import { Memo } from '../model';
import { MemoViewModel } from '../viewmodel';
import { RouteName } from '../common';
import { DistributedManager } from '../distributed/DistributedManager';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'RecordPage';

/** 模拟生成的会议纪要文本。 */
const SIMULATED_MINUTES_TITLE: string = 'Q3 规划会议纪要';
const SIMULATED_MINUTES_CONTENT: string =
  '会议时间：2026年Q3规划讨论\n\n' +
  '参会人员：产品、研发、设计团队\n\n' +
  '议题：\n' +
  '1. Q2 复盘：用户增长 35%，核心功能 NPS 达到 42\n' +
  '2. Q3 目标：日活提升 50%，完成分布式协同 2.0\n' +
  '3. 技术债务：清理 Phase 1 遗留的数据库迁移逻辑\n' +
  '4. 鸿蒙生态：接入 Intents Kit，实现无感场景推荐\n\n' +
  '待办项：\n' +
  '- [ ] 产品完成用户画像 v2 文档（截止 7/15）\n' +
  '- [ ] 研发启动分布式协同 2.0 技术方案评审（截止 7/20）\n' +
  '- [ ] 设计输出鸿蒙特组件设计稿（截止 7/25）\n' +
  '- [ ] 运维准备灰度发布环境（截止 7/30）\n\n' +
  '下次会议：7/20 14:00，技术方案评审。';

/**
 * 录音页面。
 *
 * 功能：
 * 1. 模拟录音界面（计时器 + 波形动画）。
 * 2. 停止录音后模拟生成会议纪要文本。
 * 3. 将纪要保存为 Memo（category='meeting'）。
 * 4. 通过 DistributedManager 推送到平板。
 * 5. 生成成功后返回主页。
 */
@Component
export struct RecordPage {
  @Consume('navPathStack') navPathStack: NavPathStack;

  private viewModel: MemoViewModel = MemoViewModel.getInstance();
  private distributedManager: DistributedManager = DistributedManager.getInstance();

  @State isRecording: boolean = false;
  @State elapsedTime: number = 0;
  @State isGenerating: boolean = false;
  @State hasGenerated: boolean = false;

  private timerId: number = -1;

  aboutToDisappear(): void {
    this.stopTimer();
  }

  /** 启动录音计时器。 */
  private startTimer(): void {
    this.elapsedTime = 0;
    this.timerId = setInterval(() => {
      this.elapsedTime++;
    }, 1000);
  }

  /** 停止计时器。 */
  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /** 格式化秒为 MM:SS。 */
  private formatTime(seconds: number): string {
    const min: number = Math.floor(seconds / 60);
    const sec: number = seconds % 60;
    const minStr: string = min < 10 ? '0' + min : min.toString();
    const secStr: string = sec < 10 ? '0' + sec : sec.toString();
    return minStr + ':' + secStr;
  }

  /** 开始录音。 */
  private startRecording(): void {
    this.isRecording = true;
    this.hasGenerated = false;
    this.startTimer();
  }

  /** 停止录音并生成会议纪要。 */
  private async stopAndGenerate(): Promise<void> {
    this.isRecording = false;
    this.stopTimer();
    this.isGenerating = true;

    try {
      // 创建 Memo 保存会议纪要
      const memo: Memo = new Memo();
      memo.title = SIMULATED_MINUTES_TITLE;
      memo.content = SIMULATED_MINUTES_CONTENT;
      memo.category = 'meeting';
      memo.isCompleted = false;
      memo.createTime = Date.now();

      await this.viewModel.addMemo(memo);
      hilog.info(DOMAIN, TAG, 'Meeting minutes saved as memo');

      // 通过分布式对象推送到平板
      try {
        this.distributedManager.pushMeetingMinutes(memo.title, memo.content);
        hilog.info(DOMAIN, TAG, 'Meeting minutes pushed to distributed session');
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'Failed to push minutes: %{public}s', JSON.stringify(e));
      }

      this.isGenerating = false;
      this.hasGenerated = true;

      // 显示成功提示后返回
      try {
        this.getUIContext().getPromptAction().showToast({
          message: '会议纪要已生成并推送',
          duration: 2000
        });
      } catch (e) {
        // showToast 失败忽略
      }

      // 延迟返回，让 Toast 显示
      setTimeout(() => {
        this.navPathStack.pop();
      }, 1500);

    } catch (e) {
      this.isGenerating = false;
      hilog.error(DOMAIN, TAG, 'Failed to generate minutes: %{public}s', JSON.stringify(e));

      try {
        this.getUIContext().getPromptAction().showToast({
          message: '生成失败，请重试',
          duration: 2000
        });
      } catch (toastErr) {
        // 忽略
      }
    }
  }

  build() {
    NavDestination() {
      Column({ space: 24 }) {
        // 顶部标题
        Text('会议录音')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ top: 20 })

        // 录音状态区域
        Column({ space: 16 }) {
          if (this.isGenerating) {
            // 生成中状态
            Column({ space: 12 }) {
              LoadingProgress()
                .width(60)
                .height(60)
                .color('#007DFF')
              Text('正在生成会议纪要...')
                .fontSize(14)
                .fontColor('#999999')
            }
            .width('100%')
            .padding(40)
            .justifyContent(FlexAlign.Center)
          } else if (this.hasGenerated) {
            // 生成完成
            Column({ space: 12 }) {
              Text('✓')
                .fontSize(48)
                .fontColor('#4CAF50')
              Text('纪要已生成')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#4CAF50')
            }
            .width('100%')
            .padding(40)
            .justifyContent(FlexAlign.Center)
          } else if (this.isRecording) {
            // 录音中
            Column({ space: 16 }) {
              // 录音波形动画
              Row({ space: 4 }) {
                ForEach([0, 1, 2, 3, 4, 5, 6, 7], (index: number) => {
                  Column()
                    .width(4)
                    .height(20 + Math.abs(Math.sin((this.elapsedTime + index) * 0.8)) * 40)
                    .backgroundColor('#FF6B6B')
                    .borderRadius(2)
                    .animation({ duration: 300, curve: Curve.EaseInOut })
                }, (index: number) => index.toString())
              }
              .height(80)
              .alignItems(VerticalAlign.Center)

              Text(this.formatTime(this.elapsedTime))
                .fontSize(36)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FF6B6B')
                .fontFamily('monospace')

              Text('录音中...')
                .fontSize(13)
                .fontColor('#999999')
            }
            .width('100%')
            .padding(40)
            .justifyContent(FlexAlign.Center)
          } else {
            // 待开始录音
            Column({ space: 16 }) {
              Text('🎙')
                .fontSize(64)
                .fontColor('#CCCCCC')
              Text('点击下方按钮开始录音')
                .fontSize(14)
                .fontColor('#999999')
              Text('录音结束后将自动生成会议纪要')
                .fontSize(12)
                .fontColor('#BBBBBB')
            }
            .width('100%')
            .padding(40)
            .justifyContent(FlexAlign.Center)
          }
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)

        // 操作按钮区
        if (!this.isGenerating && !this.hasGenerated) {
          if (this.isRecording) {
            // 停止按钮
            Button('停止录音')
              .width(160)
              .height(48)
              .fontSize(16)
              .fontColor(Color.White)
              .backgroundColor('#FF4444')
              .borderRadius(24)
              .onClick(() => {
                this.stopAndGenerate();
              })
          } else {
            // 开始按钮
            Button('开始录音')
              .width(160)
              .height(48)
              .fontSize(16)
              .fontColor(Color.White)
              .backgroundColor('#FF6B6B')
              .borderRadius(24)
              .onClick(() => {
                this.startRecording();
              })
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FAFAFA')
      .alignItems(HorizontalAlign.Center)
    }
    .title('会议纪要')
    .onShown(() => {
      // 页面重新显示时重置状态
    })
  }
}
