import { Memo } from '../model';
import { MemoViewModel } from '../viewmodel';
import { CATEGORIES, CategoryItem, MemoDataSource, RouteName, EditPageParam, formatTime, SceneType } from '../common';
import { DistributedManager } from '../distributed/DistributedManager';
import { RuleEngine } from '../rules/RuleEngine';
import { WidgetHelper } from '../widget/WidgetHelper';
import { notificationManager } from '@kit.NotificationKit';
import { abilityAccessCtrl, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 主页面：备忘录列表。
 *
 * 功能：
 * 1. 顶部搜索栏，实时按关键词搜索标题/内容。
 * 2. 分类筛选标签（全部 / 默认 / 工作 / 个人 / 学习 / 购物）。
 * 3. LazyForEach 懒加载列表，cachedCount = 5。
 * 4. 左滑显示删除按钮，确认后删除。
 * 5. 右下角 FAB 新建备忘录。
 * 6. 点击列表项跳转编辑页。
 * 7. 从编辑页返回时自动刷新（onShown）。
 * 8. 监听分布式编辑会话，发现其他设备正在编辑时弹出接续提示。
 * 9. 顶部购物清单入口按钮。
 */
@Component
export struct MainPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State currentCategory: string = 'all';
  @State searchKeyword: string = '';
  @State isEmpty: boolean = true;
  @State hasContinuationOffer: boolean = false;

  private viewModel: MemoViewModel = MemoViewModel.getInstance();
  private dataSource: MemoDataSource = new MemoDataSource();
  private distributedManager: DistributedManager = DistributedManager.getInstance();
  private isInitialized: boolean = false;
  // 搜索防抖定时器：避免每次按键都触发数据库查询
  private searchTimerId: number = -1;
  // 页面可见性：仅可见时才弹"发现对端编辑"的接续提示
  private isPageVisible: boolean = false;

  // 接续数据缓存
  private continuationTitle: string = '';
  private continuationContent: string = '';
  private continuationCategory: string = 'default';

  // 分布式编辑监听回调
  private editingMemoCallback: (title: string, content: string, category: string) => void = (title: string, content: string, category: string) => {
    this.handleRemoteEditing(title, content, category);
  };

  // 场景感知
  private ruleEngine: RuleEngine = RuleEngine.getInstance();
  private appContext: Context | null = null;
  private sceneChangeCallback: (scene: SceneType) => void = (scene: SceneType) => {
    this.handleSceneChange(scene);
  };

  // 会议纪要监听
  private meetingMinutesCallback: (title: string, content: string) => void = (title: string, content: string) => {
    this.handleMeetingMinutesReceived(title, content);
  };

  aboutToAppear(): void {
    this.initAndLoad();
  }

  aboutToDisappear(): void {
    if (this.searchTimerId !== -1) {
      clearTimeout(this.searchTimerId);
      this.searchTimerId = -1;
    }
    this.distributedManager.offEditingMemoChange(this.editingMemoCallback);
    this.ruleEngine.offSceneChange(this.sceneChangeCallback);
    this.distributedManager.offMeetingMinutesChange(this.meetingMinutesCallback);
  }

  private async initAndLoad(): Promise<void> {
    const context: Context = this.getUIContext().getHostContext() as Context;
    this.appContext = context;
    await this.viewModel.init(context);
    this.isInitialized = true;

    // 分布式功能依赖 user_grant 权限，需先完成运行时授权再注册监听
    await this.requestDistributedPermission();

    // 注册分布式编辑监听
    this.distributedManager.onEditingMemoChange(this.editingMemoCallback);

    // 注册场景变更监听（场景切换时自动刷新卡片）
    this.ruleEngine.onSceneChange(this.sceneChangeCallback);

    // 注册会议纪要监听（其他设备推送时接收通知）
    this.distributedManager.onMeetingMinutesChange(this.meetingMinutesCallback);

    await this.loadMemos();
  }

  /** 申请分布式数据同步权限（user_grant，仅 module.json5 声明不够，需运行时弹框授权）。 */
  private async requestDistributedPermission(): Promise<void> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const permissions: Permissions[] = ['ohos.permission.DISTRIBUTED_DATASYNC'];
    try {
      const context: Context = this.getUIContext().getHostContext() as Context;
      const result: PermissionRequestResult =
        await atManager.requestPermissionsFromUser(context, permissions);
      const granted: boolean = result.authResults.every((code: number) => code === 0);
      hilog.info(0x0001, 'MainPage', 'DISTRIBUTED_DATASYNC granted: %{public}s', granted.toString());
      if (!granted) {
        this.showPermissionGuideDialog();
      }
    } catch (e) {
      hilog.error(0x0001, 'MainPage', 'request DISTRIBUTED_DATASYNC failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 权限被拒时引导用户去系统设置开启，否则跨设备协作不可用。 */
  private showPermissionGuideDialog(): void {
    this.getUIContext().showAlertDialog({
      title: '需要多设备协同权限',
      message: '跨设备接续、购物清单同步等协作功能依赖「多设备协同」权限，当前未授权将不可用。可前往 设置 > 应用和服务 > 应用管理 > MemoFlow > 权限 手动开启。',
      primaryButton: {
        value: '知道了',
        action: () => {
        }
      }
    });
  }

  /** 处理远程设备编辑数据变更。 */
  private handleRemoteEditing(title: string, content: string, category: string): void {
    // 如果已经有接续提示在显示，不再重复弹出
    if (this.hasContinuationOffer) {
      return;
    }

    // 页面不可见（用户正在编辑页）时不弹接续发现框：
    // 协同编辑中对端的持续同步也会走到这里，此时由编辑页的冲突检测接管
    if (!this.isPageVisible) {
      return;
    }

    // 只有当标题不为空时才认为是有效的编辑数据
    if (title.length === 0) {
      return;
    }

    this.continuationTitle = title;
    this.continuationContent = content;
    this.continuationCategory = category;
    this.hasContinuationOffer = true;

    // 弹出接续确认对话框
    this.showContinuationDialog(title);
  }

  /** 显示接续确认对话框。 */
  private showContinuationDialog(title: string): void {
    this.getUIContext().showAlertDialog({
      title: '发现正在编辑的备忘录',
      message: '另一台设备正在编辑「' + title + '」，是否接续编辑？',
      primaryButton: {
        value: '取消',
        action: () => {
          this.hasContinuationOffer = false;
        }
      },
      secondaryButton: {
        value: '接续',
        fontColor: '#007DFF',
        action: () => {
          this.acceptContinuation();
        }
      }
    });
  }

  /** 接受接续，跳转编辑页并携带分布式数据。 */
  private acceptContinuation(): void {
    this.hasContinuationOffer = false;
    const param: EditPageParam = new EditPageParam(0);
    param.isContinuation = true;
    param.continuationTitle = this.continuationTitle;
    param.continuationContent = this.continuationContent;
    param.continuationCategory = this.continuationCategory;
    this.navPathStack.pushPathByName(RouteName.EDIT_PAGE, param);
  }

  /** 场景模拟选择处理：切换场景并显示提示。 */
  private handleSceneSelection(scene: SceneType, label: string): void {
    this.ruleEngine.setMockScene(scene);
    try {
      this.getUIContext().getPromptAction().showToast({
        message: '已切换到' + label,
        duration: 2000
      });
    } catch (e) {
      // showToast 失败不影响场景切换
    }
  }

  /** 场景变更回调：自动刷新服务卡片。 */
  private async handleSceneChange(scene: SceneType): Promise<void> {
    if (this.appContext !== null) {
      await WidgetHelper.triggerFormUpdate(this.appContext, scene);
    }
  }

  /** 根据搜索关键词和分类筛选加载备忘录列表。 */
  private async loadMemos(): Promise<void> {
    try {
      let memos: Memo[] = [];
      if (this.searchKeyword.length > 0) {
        memos = await this.viewModel.searchMemos(this.searchKeyword);
      } else if (this.currentCategory === 'all') {
        memos = await this.viewModel.loadAllMemos();
      } else {
        memos = await this.viewModel.getMemosByCategory(this.currentCategory);
      }
      this.dataSource.setData(memos);
      this.isEmpty = memos.length === 0;
    } catch (e) {
      hilog.error(0x0001, 'MainPage', 'loadMemos failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 弹出确认删除对话框。 */
  private confirmDelete(id: number): void {
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
          this.doDelete(id);
        }
      }
    });
  }

  private async doDelete(id: number): Promise<void> {
    try {
      await this.viewModel.deleteMemo(id);
      await this.loadMemos();
    } catch (e) {
      hilog.error(0x0001, 'MainPage', 'doDelete failed: %{public}s', JSON.stringify(e));
      try {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败' });
      } catch (toastErr) {
        // showToast 失败忽略
      }
    }
  }

  private getCategoryLabel(category: string): string {
    for (const cat of CATEGORIES) {
      if (cat.value === category) {
        return cat.label;
      }
    }
    return category;
  }

  private getCategoryColor(category: string): string {
    switch (category) {
      case 'work':
        return '#FF6B6B';
      case 'personal':
        return '#4ECDC4';
      case 'study':
        return '#45B7D1';
      case 'shopping':
        return '#FFA726';
      default:
        return '#95A5A6';
    }
  }

  /** 跳转编辑页：editId > 0 编辑已有，0 新建。 */
  private navigateToEdit(editId: number): void {
    this.navPathStack.pushPathByName(RouteName.EDIT_PAGE, new EditPageParam(editId));
  }

  /** 跳转购物清单页。 */
  private navigateToShopping(): void {
    this.navPathStack.pushPathByName(RouteName.SHOPPING_PAGE, null);
  }

  /** 跳转录音页。 */
  private navigateToRecord(): void {
    this.navPathStack.pushPathByName(RouteName.RECORD_PAGE, null);
  }

  /** 处理收到的分布式会议纪要：保存并发送本地通知。 */
  private async handleMeetingMinutesReceived(title: string, content: string): Promise<void> {
    if (title.length === 0) {
      return;
    }

    hilog.info(0x0001, 'MainPage', 'Meeting minutes received: %{public}s', title);

    // 保存为 Memo
    try {
      const memo: Memo = new Memo();
      memo.title = title;
      memo.content = content;
      memo.category = 'meeting';
      memo.isCompleted = false;
      memo.createTime = Date.now();
      await this.viewModel.addMemo(memo);
      // 保存成功后立即刷新列表，保证主页可见时新纪要即时出现
      await this.loadMemos();
    } catch (e) {
      hilog.error(0x0001, 'MainPage', 'Save meeting memo failed: %{public}s', JSON.stringify(e));
    }

    // 发送本地通知
    try {
      const request: notificationManager.NotificationRequest = {
        id: Date.now(),
        content: {
          contentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: '新会议纪要已生成',
            text: title,
            additionalText: '点击查看详情',
          } as notificationManager.NotificationBasicContent,
        } as notificationManager.NotificationContent,
        notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION,
      };
      await notificationManager.publish(request);
      hilog.info(0x0001, 'MainPage', 'Notification published');
    } catch (e) {
      hilog.error(0x0001, 'MainPage', 'Publish notification failed: %{public}s', JSON.stringify(e));
    }
  }

  @Builder
  MemoItem(item: Memo) {
    Row({ space: 12 }) {
      // 完成状态指示器
      if (item.isCompleted) {
        Text('✓')
          .fontSize(16)
          .fontColor('#4CAF50')
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .borderRadius(12)
          .backgroundColor('#E8F5E9')
      } else {
        Text('')
          .width(24)
          .height(24)
          .borderRadius(12)
          .border({ width: 1.5, color: '#CCCCCC' })
      }

      // 标题 + 内容预览 + 标签行
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (item.content.length > 0) {
          Text(item.content)
            .fontSize(13)
            .fontColor('#999999')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        Row({ space: 8 }) {
          Text(this.getCategoryLabel(item.category))
            .fontSize(11)
            .fontColor(Color.White)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(8)
            .backgroundColor(this.getCategoryColor(item.category))

          Text(formatTime(item.createTime))
            .fontSize(11)
            .fontColor('#BBBBBB')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(12)
  }

  @Builder
  SwipeDeleteButton(item: Memo) {
    Button('删除', { type: ButtonType.Normal })
      .width(80)
      .height('100%')
      .backgroundColor('#FF4444')
      .fontColor(Color.White)
      .fontSize(14)
      .borderRadius(8)
      .onClick(() => {
        this.confirmDelete(item.id);
      })
  }

  @Builder
  EmptyState() {
    Column({ space: 12 }) {
      Text('暂无备忘录')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#999999')
      Text('点击右下角 + 添加新备忘录')
        .fontSize(13)
        .fontColor('#CCCCCC')
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          // 搜索栏 + 购物清单入口
          Row() {
            TextInput({ placeholder: '搜索备忘录...' })
              .height(40)
              .backgroundColor('#F5F5F5')
              .borderRadius(20)
              .padding({ left: 16, right: 16 })
              .layoutWeight(1)
              .onChange((value: string) => {
                this.searchKeyword = value;
                // 300ms 防抖：停止输入后才执行查询
                if (this.searchTimerId !== -1) {
                  clearTimeout(this.searchTimerId);
                }
                this.searchTimerId = setTimeout(() => {
                  this.loadMemos();
                }, 300);
              })
            // 场景模拟入口
            Text('场景')
              .fontSize(13)
              .fontColor('#FF6B6B')
              .padding({ left: 12, right: 4 })
              .bindMenu([
                { value: '默认场景', action: () => { this.handleSceneSelection(SceneType.DEFAULT, '默认场景'); } },
                { value: '在超市', action: () => { this.handleSceneSelection(SceneType.SHOPPING, '超市场景'); } },
                { value: '在开会', action: () => { this.handleSceneSelection(SceneType.MEETING, '会议场景'); } }
              ])
            // 录音入口
            Text('录音')
              .fontSize(13)
              .fontColor('#9C27B0')
              .padding({ left: 12, right: 4 })
              .onClick(() => {
                this.navigateToRecord();
              })
            // 购物清单入口
            Text('购物清单')
              .fontSize(13)
              .fontColor('#007DFF')
              .padding({ left: 12, right: 4 })
              .onClick(() => {
                this.navigateToShopping();
              })
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })

          // 分类筛选标签
          Scroll() {
            Row({ space: 8 }) {
              ForEach(CATEGORIES, (cat: CategoryItem) => {
                Text(cat.label)
                  .fontSize(14)
                  .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                  .borderRadius(16)
                  .backgroundColor(this.currentCategory === cat.value ? '#007DFF' : '#F0F0F0')
                  .fontColor(this.currentCategory === cat.value ? Color.White : '#333333')
                  .onClick(() => {
                    this.currentCategory = cat.value;
                    this.loadMemos();
                  })
              }, (cat: CategoryItem) => cat.value)
            }
            .padding({ left: 12, right: 12 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .height(44)

          // 列表 / 空状态
          if (this.isEmpty) {
            this.EmptyState()
          } else {
            List({ space: 8 }) {
              LazyForEach(this.dataSource, (item: Memo) => {
                ListItem() {
                  this.MemoItem(item)
                }
                .swipeAction({
                  end: {
                    builder: () => {
                      this.SwipeDeleteButton(item)
                    }
                  }
                })
                .onClick(() => {
                  this.navigateToEdit(item.id);
                })
              }, (item: Memo) => item.id.toString())
            }
            .cachedCount(5)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height('100%')

        // 悬浮新建按钮
        Button('+', { type: ButtonType.Circle })
          .width(56)
          .height(56)
          .fontSize(28)
          .fontColor(Color.White)
          .backgroundColor('#007DFF')
          .shadow({ radius: 8, color: '#33000000', offsetX: 0, offsetY: 4 })
          .margin({ right: 20, bottom: 20 })
          .onClick(() => {
            this.navigateToEdit(0);
          })
      }
      .width('100%')
      .height('100%')
    }
    .title('MemoFlow')
    .onShown(() => {
      this.isPageVisible = true;
      if (this.isInitialized) {
        this.loadMemos();
      }
    })
    .onHidden(() => {
      this.isPageVisible = false;
    })
  }
}
