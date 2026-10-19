import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { DistributedManager, EditingMemoInfo } from '../distributed/DistributedManager';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

/** wantParam 中存储接续 sessionId 的自定义键名。 */
const KEY_CONTINUATION_SESSION: string = 'continuation_session_id';

/** 接续恢复的备忘数据结构。 */
interface ContinuationData {
  title: string;
  content: string;
  category: string;
}

export default class EntryAbility extends UIAbility {
  /** 接续恢复的备忘数据，供页面在 onWindowStageRestore 后读取。 */
  private continuationData: ContinuationData | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }

    // 初始化 DistributedManager
    DistributedManager.getInstance().init(this.context);

    // 检测是否为接续启动
    this.checkContinuation(want);

    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  /**
   * 跨设备接续回调（源设备）。
   * 将当前编辑的备忘数据打包到 wantParam，返回 AGREE 表示同意接续。
   */
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onContinue called');

    try {
      const manager: DistributedManager = DistributedManager.getInstance();
      const editingMemo: EditingMemoInfo | null = manager.getCurrentEditingMemo();

      if (editingMemo !== null) {
        // 将编辑数据写入 wantParam
        wantParam['title'] = editingMemo.title;
        wantParam['content'] = editingMemo.content;
        wantParam['category'] = editingMemo.category;
      }

      // 如果有活跃的分布式编辑会话，将 sessionId 传入 wantParam
      const sessionId: string = manager.getEditingSessionId();
      if (sessionId.length > 0) {
        wantParam[KEY_CONTINUATION_SESSION] = sessionId;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'onContinue failed: %{public}s', JSON.stringify(err));
    }

    return AbilityConstant.OnContinueResult.AGREE;
  }

  /**
   * 热启动时接收新的 Want（目标设备接续恢复）。
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onNewWant called');
    this.checkContinuation(want);
  }

  /**
   * 迁移恢复时触发（替代 onWindowStageCreate）。
   * 在此加载页面并传递接续数据。
   */
  onWindowStageRestore(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onWindowStageRestore');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading content.');
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }

  /**
   * 检测 want 中是否包含接续参数。
   * 如果有，提取备忘数据并恢复分布式会话。
   */
  private checkContinuation(want: Want): void {
    try {
      const params: Record<string, Object> = want.parameters as Record<string, Object>;

      // 检查是否有接续标记或 sessionId
      const hasSessionId: boolean = params[KEY_CONTINUATION_SESSION] !== undefined;
      const hasTitle: boolean = params['title'] !== undefined;

      if (hasSessionId || hasTitle) {
        const title: string = params['title'] as string;
        const content: string = params['content'] as string;
        const category: string = params['category'] as string;

        const data: ContinuationData = {
          title: title !== undefined ? title : '',
          content: content !== undefined ? content : '',
          category: category !== undefined ? category : 'default',
        };
        this.continuationData = data;

        // 如果有 sessionId，恢复分布式会话
        if (hasSessionId) {
          const sessionId: string = params[KEY_CONTINUATION_SESSION] as string;
          DistributedManager.getInstance().restoreFromMigration(sessionId);
        }

        hilog.info(DOMAIN, TAG, 'Continuation data restored: title=%{public}s', title);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'checkContinuation failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 获取接续恢复的备忘数据（供页面调用）。 */
  getContinuationData(): ContinuationData | null {
    return this.continuationData;
  }
}
