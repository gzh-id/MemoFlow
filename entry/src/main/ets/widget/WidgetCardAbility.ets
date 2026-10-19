import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WidgetHelper, CardFormData } from './WidgetHelper';
import { RuleEngine } from '../rules/RuleEngine';
import { SceneType } from '../common';

const DOMAIN: number = 0x0001;
const TAG: string = 'WidgetCardAbility';

/** want.parameters 中卡片尺寸的键名。 */
const DIMENSION_KEY: string = 'ohos.extra.param.key.form_dimension';

/**
 * 服务卡片 FormExtensionAbility。
 *
 * 运行在独立进程中，不能访问主应用的 ViewModel。
 * 通过 RdbHelper 直接查询数据库获取数据。
 *
 * 生命周期：
 * 1. onAddForm — 用户添加卡片时回调，同步返回占位数据。
 * 2. onCastToNormalForm — 临时卡片转正后回调，保存 formId 并加载真实数据。
 * 3. onUpdateForm — 定时刷新回调，加载最新数据并更新卡片。
 * 4. onFormEvent — 卡片交互事件回调。
 * 5. onRemoveForm — 卡片被删除时回调，清理 formId。
 */
export default class WidgetCardAbility extends FormExtensionAbility {
  /** 最近一次 onAddForm 获取的尺寸，用于 onCastToNormalForm 时保存。 */
  private static lastDimension: number = 2;

  /**
   * 添加卡片时回调。
   * 从 want 中获取尺寸，同步返回占位数据。
   * 真实数据将在 onCastToNormalForm 后异步推送。
   */
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, 'onAddForm called');

    let dimension: number = 2;
    try {
      const params: Record<string, Object> = want.parameters as Record<string, Object>;
      const dimValue: Object | undefined = params[DIMENSION_KEY];
      if (dimValue !== undefined) {
        dimension = dimValue as number;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to get dimension: %{public}s', JSON.stringify(e));
    }

    WidgetCardAbility.lastDimension = dimension;
    hilog.info(DOMAIN, TAG, 'onAddForm dimension: %{public}d', dimension);

    const placeholder: CardFormData = WidgetHelper.createPlaceholderData(dimension);
    return formBindingData.createFormBindingData(placeholder);
  }

  /**
   * 临时卡片转普通卡片时回调。
   * 保存 formId 并立即加载真实数据更新卡片。
   */
  onCastToNormalForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onCastToNormalForm: %{public}s', formId);
    WidgetHelper.saveFormIdWithDimension(this.context, formId, WidgetCardAbility.lastDimension);
    this.updateFormById(formId, WidgetCardAbility.lastDimension);
  }

  /**
   * 卡片定时刷新时回调。
   */
  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onUpdateForm: %{public}s', formId);
    const dimension: number = WidgetHelper.getDimensionByFormId(this.context, formId);
    this.updateFormById(formId, dimension);
  }

  /**
   * 卡片触发事件时回调（如点击消息事件）。
   */
  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, 'onFormEvent: %{public}s, message: %{public}s', formId, message);
    const dimension: number = WidgetHelper.getDimensionByFormId(this.context, formId);
    this.updateFormById(formId, dimension);
  }

  /**
   * 卡片被删除时回调，清理 formId。
   */
  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm: %{public}s', formId);
    WidgetHelper.removeFormId(this.context, formId);
  }

  /**
   * 异步加载数据并通过 formProvider 更新指定卡片。
   */
  private async updateFormById(formId: string, dimension: number): Promise<void> {
    try {
      const scene: SceneType = RuleEngine.getInstance().getCurrentScene();
      const data: CardFormData = await WidgetHelper.buildCardData(this.context, dimension, scene);
      const formBinding: formBindingData.FormBindingData = formBindingData.createFormBindingData(data);
      await formProvider.updateForm(formId, formBinding);
      hilog.info(DOMAIN, TAG, 'Form updated successfully: %{public}s', formId);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'updateFormById failed: %{public}s', JSON.stringify(e));
    }
  }
}
