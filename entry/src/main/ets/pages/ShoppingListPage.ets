import { ShoppingItem } from '../common';
import { DistributedManager } from '../distributed/DistributedManager';

/**
 * 购物清单页面。
 *
 * 功能：
 * 1. 展示购物清单列表，每项含勾选框和商品名称，点击勾选框切换状态。
 * 2. 底部输入栏添加新购物项，支持回车键快速添加。
 * 3. 支持删除单个购物项。
 * 4. 通过 DistributedManager 的分布式数据对象实现多端实时同步。
 *
 * 架构：Navigation + NavDestination，通过 @Consume('navPathStack') 获取导航栈。
 * 状态管理：V1（@State / @Consume / @Component）。
 */
@Component
export struct ShoppingListPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State items: ShoppingItem[] = [];
  @State newItemName: string = '';

  private distributedManager: DistributedManager = DistributedManager.getInstance();

  // 分布式数据变更回调：其他设备修改购物清单时触发，刷新本地列表
  private shoppingListCallback: (items: ShoppingItem[]) => void = (items: ShoppingItem[]) => {
    this.items = [...items];
  };

  aboutToAppear(): void {
    this.initShoppingList();
  }

  aboutToDisappear(): void {
    // 先注销监听，再停止同步，避免清理过程中收到回调
    try {
      this.distributedManager.offShoppingListChange(this.shoppingListCallback);
    } catch (e) {
      // 注销监听失败忽略
    }
    try {
      this.distributedManager.stopShoppingSync();
    } catch (e) {
      // 停止同步失败忽略
    }
  }

  /**
   * 初始化购物清单：启动分布式同步、注册监听、加载当前数据。
   * 传入空 sessionId 由系统自动生成，初始列表为空。
   */
  private async initShoppingList(): Promise<void> {
    try {
      // 启动购物清单同步（空 session ID 自动生成，初始为空列表）
      this.distributedManager.startShoppingSync('', []);
      // 注册数据变更监听，其他设备修改时回调
      this.distributedManager.onShoppingListChange(this.shoppingListCallback);
      // 加载当前购物项
      this.items = [...this.distributedManager.getCurrentShoppingItems()];
    } catch (e) {
      // 初始化失败，提示用户
      try {
        this.getUIContext().getPromptAction().showToast({ message: '购物同步初始化失败' });
      } catch (err) {
        // showToast 调用失败忽略
      }
    }
  }

  /**
   * 切换指定购物项的勾选状态。
   * 使用 [...this.items] 创建新数组触发 @State 刷新，同时更新分布式对象。
   */
  private toggleItem(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    const newItems: ShoppingItem[] = [...this.items];
    newItems[index] = new ShoppingItem(newItems[index].name, !newItems[index].checked);
    this.items = newItems;
    try {
      this.distributedManager.updateShoppingItems(this.items);
    } catch (e) {
      // 更新分布式对象失败，本地状态已更新
    }
  }

  /**
   * 添加新购物项。
   * 空名称校验提示，添加后清空输入框并同步到分布式对象。
   */
  private addItem(): void {
    const name: string = this.newItemName.trim();
    if (name.length === 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '请输入商品名称' });
      } catch (e) {
        // showToast 调用失败忽略
      }
      return;
    }
    this.items = [...this.items, new ShoppingItem(name, false)];
    try {
      this.distributedManager.updateShoppingItems(this.items);
    } catch (e) {
      // 更新分布式对象失败，本地状态已更新
    }
    this.newItemName = '';
  }

  /**
   * 删除指定购物项。
   * 使用 filter 创建新数组触发 @State 刷新，同时更新分布式对象。
   */
  private deleteItem(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    const newItems: ShoppingItem[] = this.items.filter((_: ShoppingItem, i: number) => i !== index);
    this.items = newItems;
    try {
      this.distributedManager.updateShoppingItems(this.items);
    } catch (e) {
      // 更新分布式对象失败，本地状态已更新
    }
  }

  /** 获取购物项文字颜色：已勾选灰色，未勾选深色。 */
  private getItemFontColor(checked: boolean): string {
    if (checked) {
      return '#999999';
    }
    return '#333333';
  }

  /** 获取购物项文字装饰类型：已勾选删除线，未勾选无装饰。 */
  private getItemDecorationType(checked: boolean): TextDecorationType {
    if (checked) {
      return TextDecorationType.LineThrough;
    }
    return TextDecorationType.None;
  }

  build() {
    NavDestination() {
      Column() {
        // 购物清单列表 / 空状态（互斥显示，避免空列表渲染问题）
        if (this.items.length === 0) {
          Column({ space: 8 }) {
            Text('暂无购物项')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor('#999999')
            Text('在下方输入并添加购物项')
              .fontSize(13)
              .fontColor('#CCCCCC')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          // 购物清单列表
          List({ space: 8 }) {
            ForEach(this.items, (item: ShoppingItem, index: number) => {
              ListItem() {
                Row({ space: 12 }) {
                  // 勾选框
                  Checkbox()
                    .select(item.checked)
                    .selectedColor('#007DFF')
                    .onChange((value: boolean) => {
                      this.toggleItem(index);
                    })

                  // 商品名称（已勾选时显示删除线 + 灰色文字）
                  Text(item.name)
                    .fontSize(16)
                    .fontColor(this.getItemFontColor(item.checked))
                    .decoration({ type: this.getItemDecorationType(item.checked) })
                    .layoutWeight(1)

                  // 删除按钮
                  Text('删除')
                    .fontSize(13)
                    .fontColor('#FF4444')
                    .onClick(() => {
                      this.deleteItem(index);
                    })
                }
                .padding(12)
                .backgroundColor(Color.White)
                .borderRadius(8)
              }
            }, (item: ShoppingItem, index: number) => index.toString() + item.name)
          }
          .padding({ left: 12, right: 12, top: 8 })
          .layoutWeight(1)
        }

        // 底部输入区域
        Row({ space: 8 }) {
          TextInput({ placeholder: '添加购物项...', text: this.newItemName })
            .height(40)
            .backgroundColor('#F5F5F5')
            .borderRadius(20)
            .padding({ left: 16, right: 16 })
            .layoutWeight(1)
            .onChange((value: string) => {
              this.newItemName = value;
            })
            .onSubmit(() => {
              this.addItem();
            })

          Button('添加', { type: ButtonType.Normal })
            .height(40)
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor('#007DFF')
            .borderRadius(20)
            .padding({ left: 20, right: 20 })
            .onClick(() => {
              this.addItem();
            })
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 12 })
        .backgroundColor(Color.White)
      }
      .width('100%')
      .height('100%')
    }
    .title('购物清单')
  }
}
