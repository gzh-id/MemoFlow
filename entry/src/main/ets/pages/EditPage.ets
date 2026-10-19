import { Memo } from '../model';
import { MemoViewModel } from '../viewmodel';
import { CATEGORIES, CategoryItem } from '../common';
import { DistributedManager } from '../distributed/DistributedManager';

/**
 * 编辑/新建/接续页面。
 *
 * editId === 0 → 新建备忘录；editId > 0 → 编辑已有备忘录。
 * isContinuation === true → 接续编辑，预填分布式对象同步的数据，保存为新备忘。
 *
 * 功能：
 * 1. 标题输入（必填，空值校验提示）。
 * 2. 多行内容输入（TextArea）。
 * 3. 分类下拉选择（Select，排除「全部」）。
 * 4. 完成状态开关（Toggle Switch）。
 * 5. 保存按钮 → 新增或更新，成功后返回。
 * 6. 删除按钮（仅编辑模式）→ 确认对话框 → 删除后返回。
 * 7. 编辑时启动分布式会话，其他设备可发现并接续。
 * 8. 接续模式预填数据，editId 为 0（新建）。
 */
@Component
export struct EditPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State title: string = '';
  @State content: string = '';
  @State category: string = 'default';
  @State isCompleted: boolean = false;

  editId: number = 0;
  isContinuation: boolean = false;
  continuationTitle: string = '';
  continuationContent: string = '';
  continuationCategory: string = 'default';

  private viewModel: MemoViewModel = MemoViewModel.getInstance();
  private distributedManager: DistributedManager = DistributedManager.getInstance();
  private createTime: number = Date.now();
  private editCategories: CategoryItem[] = [];
  private selectOptions: SelectOption[] = [];

  // 对端版本被采用（LWW）时刷新本地输入框
  private remoteChangeCallback: (title: string, content: string, category: string) => void =
    (title: string, content: string, category: string) => {
      this.title = title;
      this.content = content;
      this.category = category;
    };

  // 两端同时编辑触发冲突时，弹窗请用户裁决
  private conflictCallback: (remoteTitle: string, remoteContent: string, remoteCategory: string) => void =
    (remoteTitle: string, remoteContent: string, remoteCategory: string) => {
      this.showConflictDialog(remoteTitle, remoteContent, remoteCategory);
    };

  aboutToAppear(): void {
    this.distributedManager.onEditingMemoChange(this.remoteChangeCallback);
    this.distributedManager.onEditingConflict(this.conflictCallback);
    this.initData();
  }

  aboutToDisappear(): void {
    this.distributedManager.offEditingMemoChange(this.remoteChangeCallback);
    this.distributedManager.offEditingConflict(this.conflictCallback);
    // 离开页面时停止分布式编辑会话
    this.distributedManager.stopEditingSession();
  }

  /**
   * 冲突裁决弹窗。
   * 「采用对方」：用对端数据覆盖本地，并将对端版本戳记为本端基线；
   * 「保留我的」：以本地数据 + 新版本戳重新推送，对端按 LWW 自动采用。
   */
  private showConflictDialog(remoteTitle: string, remoteContent: string, remoteCategory: string): void {
    this.getUIContext().showAlertDialog({
      title: '编辑冲突',
      message: '检测到另一台设备正在同时编辑此备忘录，请选择保留哪个版本。',
      primaryButton: {
        value: '采用对方',
        action: () => {
          this.title = remoteTitle;
          this.content = remoteContent;
          this.category = remoteCategory;
          this.distributedManager.acceptRemoteEditing();
        }
      },
      secondaryButton: {
        value: '保留我的',
        action: () => {
          this.updateDistributedEditing();
        }
      }
    });
  }

  private async initData(): Promise<void> {
    // 构建分类选项（排除「全部」），同步执行确保 build 前就绪
    for (const cat of CATEGORIES) {
      if (cat.value !== 'all') {
        this.editCategories.push(cat);
        this.selectOptions.push({ value: cat.label });
      }
    }

    if (this.isContinuation) {
      // 接续模式：使用分布式对象同步的数据预填表单
      this.title = this.continuationTitle;
      this.content = this.continuationContent;
      this.category = this.continuationCategory;
      this.editId = 0; // 接续保存为新备忘
      return;
    }

    // 编辑模式：加载已有备忘录数据
    if (this.editId > 0) {
      const memo: Memo | null = await this.viewModel.getMemoById(this.editId);
      if (memo !== null) {
        this.title = memo.title;
        this.content = memo.content;
        this.category = memo.category;
        this.isCompleted = memo.isCompleted;
        this.createTime = memo.createTime;

        // 启动分布式编辑会话，其他设备可发现
        this.startEditingSession(memo);
      }
    } else {
      // 新建模式：启动空编辑会话
      const memo: Memo = new Memo();
      this.startEditingSession(memo);
    }
  }

  /** 启动分布式编辑会话。 */
  private startEditingSession(memo: Memo): void {
    try {
      this.distributedManager.startEditingSession(memo);
    } catch (e) {
      // 启动分布式会话失败，不影响本地编辑
    }
  }

  /** 更新分布式对象中的编辑数据（用户输入时调用）。 */
  private updateDistributedEditing(): void {
    try {
      const memo: Memo = new Memo();
      memo.title = this.title;
      memo.content = this.content;
      memo.category = this.category;
      memo.isCompleted = this.isCompleted;
      memo.createTime = this.editId > 0 ? this.createTime : Date.now();
      this.distributedManager.updateEditingMemo(memo);
    } catch (e) {
      // 更新失败忽略
    }
  }

  private getSelectedIndex(): number {
    const categories: CategoryItem[] = this.editCategories;
    const currentCategory: string = this.category;
    for (let i = 0; i < categories.length; i++) {
      if (categories[i].value === currentCategory) {
        return i;
      }
    }
    return 0;
  }

  private getCategoryLabel(value: string): string {
    const categories: CategoryItem[] = this.editCategories;
    for (const cat of categories) {
      if (cat.value === value) {
        return cat.label;
      }
    }
    return value;
  }

  /** 获取页面标题。 */
  private getPageTitle(): string {
    if (this.isContinuation) {
      return '接续编辑';
    }
    return this.editId > 0 ? '编辑备忘录' : '新建备忘录';
  }

  /** 校验并保存备忘录。 */
  private async saveMemo(): Promise<void> {
    if (this.title.trim().length === 0) {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: '请输入标题'
        });
      } catch (e) {
        // showToast 调用失败时忽略
      }
      return;
    }

    try {
      const memo: Memo = new Memo();
      memo.id = this.editId;
      memo.title = this.title.trim();
      memo.content = this.content;
      memo.category = this.category;
      memo.isCompleted = this.isCompleted;
      memo.createTime = this.editId > 0 ? this.createTime : Date.now();

      if (this.editId > 0) {
        await this.viewModel.updateMemo(memo);
      } else {
        await this.viewModel.addMemo(memo);
      }

      this.navPathStack.pop();
    } catch (e) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
      } catch (toastErr) {
        // showToast 失败忽略
      }
    }
  }

  /** 弹出删除确认对话框。 */
  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: '确认删除',
      message: '确定要删除这条备忘录吗？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Color.Red,
        action: () => {
          this.doDelete();
        }
      }
    });
  }

  private async doDelete(): Promise<void> {
    try {
      await this.viewModel.deleteMemo(this.editId);
      this.navPathStack.pop();
    } catch (e) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败' });
      } catch (toastErr) {
        // showToast 失败忽略
      }
    }
  }

  build() {
    NavDestination() {
      Column({ space: 16 }) {
        // 标题输入
        TextInput({ placeholder: '标题', text: this.title })
          .height(48)
          .fontSize(16)
          .backgroundColor('#F9F9F9')
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.title = value;
            this.updateDistributedEditing();
          })

        // 内容输入（多行）
        TextArea({ placeholder: '输入内容...', text: this.content })
          .height(200)
          .fontSize(15)
          .backgroundColor('#F9F9F9')
          .borderRadius(8)
          .padding(12)
          .onChange((value: string) => {
            this.content = value;
            this.updateDistributedEditing();
          })

        // 分类选择 + 完成状态
        Row({ space: 24 }) {
          // 分类下拉
          Column({ space: 6 }) {
            Text('分类')
              .fontSize(13)
              .fontColor('#666666')
            Select(this.selectOptions)
              .selected(this.getSelectedIndex())
              .value(this.getCategoryLabel(this.category))
              .width(120)
              .onSelect((index: number, text: string) => {
                this.category = this.editCategories[index].value;
                this.updateDistributedEditing();
              })
          }
          .alignItems(HorizontalAlign.Start)

          // 完成状态开关
          Column({ space: 6 }) {
            Text('已完成')
              .fontSize(13)
              .fontColor('#666666')
            Toggle({ type: ToggleType.Switch, isOn: this.isCompleted })
              .onChange((isOn: boolean) => {
                this.isCompleted = isOn;
                this.updateDistributedEditing();
              })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')

        // 保存按钮
        Button('保存', { type: ButtonType.Normal })
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor('#007DFF')
          .borderRadius(8)
          .onClick(() => {
            this.saveMemo();
          })

        // 删除按钮（仅编辑已有备忘时显示，接续和新建不显示）
        if (this.editId > 0 && !this.isContinuation) {
          Button('删除备忘录', { type: ButtonType.Normal })
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor('#FF4444')
            .backgroundColor(Color.White)
            .borderRadius(8)
            .border({ width: 1, color: '#FF4444' })
            .onClick(() => {
              this.confirmDelete();
            })
        }
      }
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .title(this.getPageTitle())
  }
}
