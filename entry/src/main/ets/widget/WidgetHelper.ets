import { formBindingData, formProvider } from '@kit.FormKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RdbHelper } from '../database';
import { Memo } from '../model';
import { SceneType } from '../common';

const DOMAIN: number = 0x0001;
const TAG: string = 'WidgetHelper';
const FORM_ID_FILE: string = 'form_ids.txt';

/** 卡片数据结构（扁平化，仅基本类型，避免卡片序列化问题）。 */
export interface CardFormData {
  dimension: number;
  sceneType: string;
  todoCount: number;
  topMemoTitle: string;
  topMemoCategory: string;
  shoppingTitle: string;
  item1Name: string;
  item1Checked: number;
  item2Name: string;
  item2Checked: number;
  item3Name: string;
  item3Checked: number;
}

/** formId 与尺寸的映射条目。 */
interface FormIdEntry {
  formId: string;
  dimension: number;
}

/**
 * 卡片工具类。
 *
 * 职责：
 * 1. 构建卡片数据（从 RDB 查询，组装为扁平化结构）。
 * 2. 管理 formId 文件存储（跨进程共享 formId 与尺寸映射）。
 * 3. 提供主应用主动刷新卡片的接口。
 *
 * 卡片扩展进程和主应用进程共享同一份数据库和文件沙箱，
 * 因此 formId 文件可以被两个进程读写。
 */
export class WidgetHelper {

  // ==================== 卡片数据构建 ====================

  /** 创建占位数据（onAddForm 同步返回时使用）。 */
  static createPlaceholderData(dimension: number): CardFormData {
    const data: CardFormData = {
      dimension: dimension,
      sceneType: SceneType.DEFAULT,
      todoCount: 0,
      topMemoTitle: '加载中...',
      topMemoCategory: 'default',
      shoppingTitle: '购物清单',
      item1Name: '',
      item1Checked: 0,
      item2Name: '',
      item2Checked: 0,
      item3Name: '',
      item3Checked: 0,
    };
    return data;
  }

  /**
   * 从数据库查询数据并构建卡片数据。
   * 卡片进程独立于主应用，需自行初始化 RdbHelper。
   */
  static async buildCardData(context: Context, dimension: number, sceneType: SceneType): Promise<CardFormData> {
    try {
      await RdbHelper.getInstance(context);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to init RDB: %{public}s', JSON.stringify(e));
      return WidgetHelper.createPlaceholderData(dimension);
    }

    let todoCount: number = 0;
    let topMemoTitle: string = '暂无备忘';
    let topMemoCategory: string = 'default';
    let item1Name: string = '';
    let item1Checked: number = 0;
    let item2Name: string = '';
    let item2Checked: number = 0;
    let item3Name: string = '';
    let item3Checked: number = 0;

    try {
      // 查询所有备忘录
      const allMemos: Memo[] = await RdbHelper.queryAllMemos();

      // 统计未完成待办数
      const uncompleted: Memo[] = allMemos.filter((m: Memo) => !m.isCompleted);
      todoCount = uncompleted.length;

      // 最高优先级备忘（取第一条未完成的）
      if (uncompleted.length > 0) {
        topMemoTitle = uncompleted[0].title;
        topMemoCategory = uncompleted[0].category;
      } else if (allMemos.length > 0) {
        topMemoTitle = allMemos[0].title;
        topMemoCategory = allMemos[0].category;
      }

      // 查询购物清单（category='shopping'）
      const shoppingMemos: Memo[] = await RdbHelper.getMemosByCategory('shopping');
      if (shoppingMemos.length > 0) {
        item1Name = shoppingMemos[0].title;
        item1Checked = shoppingMemos[0].isCompleted ? 1 : 0;
      }
      if (shoppingMemos.length > 1) {
        item2Name = shoppingMemos[1].title;
        item2Checked = shoppingMemos[1].isCompleted ? 1 : 0;
      }
      if (shoppingMemos.length > 2) {
        item3Name = shoppingMemos[2].title;
        item3Checked = shoppingMemos[2].isCompleted ? 1 : 0;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to query data: %{public}s', JSON.stringify(e));
    }

    const data: CardFormData = {
      dimension: dimension,
      sceneType: sceneType,
      todoCount: todoCount,
      topMemoTitle: topMemoTitle,
      topMemoCategory: topMemoCategory,
      shoppingTitle: '购物清单',
      item1Name: item1Name,
      item1Checked: item1Checked,
      item2Name: item2Name,
      item2Checked: item2Checked,
      item3Name: item3Name,
      item3Checked: item3Checked,
    };

    return data;
  }

  // ==================== FormId 文件存储 ====================

  /** 保存 formId 和尺寸到文件。 */
  static saveFormIdWithDimension(context: Context, formId: string, dimension: number): void {
    try {
      const entries: FormIdEntry[] = WidgetHelper.readFormIds(context);
      const filtered: FormIdEntry[] = entries.filter((e: FormIdEntry) => e.formId !== formId);
      const entry: FormIdEntry = {
        formId: formId,
        dimension: dimension,
      };
      filtered.push(entry);
      WidgetHelper.writeFormIds(context, filtered);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveFormId failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 从文件中移除 formId。 */
  static removeFormId(context: Context, formId: string): void {
    try {
      const entries: FormIdEntry[] = WidgetHelper.readFormIds(context);
      const filtered: FormIdEntry[] = entries.filter((e: FormIdEntry) => e.formId !== formId);
      WidgetHelper.writeFormIds(context, filtered);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'removeFormId failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 根据 formId 查找尺寸。 */
  static getDimensionByFormId(context: Context, formId: string): number {
    const entries: FormIdEntry[] = WidgetHelper.readFormIds(context);
    for (const entry of entries) {
      if (entry.formId === formId) {
        return entry.dimension;
      }
    }
    return 2; // 默认 2x2
  }

  /** 读取所有 formId 条目。 */
  static readFormIds(context: Context): FormIdEntry[] {
    try {
      const filePath: string = context.filesDir + '/' + FORM_ID_FILE;

      // 检查文件是否存在
      let fileExists: boolean = false;
      try {
        fs.accessSync(filePath);
        fileExists = true;
      } catch (e) {
        fileExists = false;
      }

      if (!fileExists) {
        return [];
      }

      const text: string = fs.readTextSync(filePath);
      return WidgetHelper.parseEntries(text);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'readFormIds failed: %{public}s', JSON.stringify(e));
      return [];
    }
  }

  /** 写入 formId 文件。 */
  private static writeFormIds(context: Context, entries: FormIdEntry[]): void {
    const filePath: string = context.filesDir + '/' + FORM_ID_FILE;
    const text: string = WidgetHelper.serializeEntries(entries);

    // 删除旧文件（如果存在）
    try {
      fs.unlinkSync(filePath);
    } catch (e) {
      // 文件可能不存在，忽略
    }

    try {
      const file: fs.File = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.writeSync(file.fd, text);
      fs.closeSync(file);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'writeFormIds failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 序列化 formId 条目为字符串。格式：formId1:dim1,formId2:dim2 */
  private static serializeEntries(entries: FormIdEntry[]): string {
    if (entries.length === 0) {
      return '';
    }
    const parts: string[] = [];
    for (const entry of entries) {
      parts.push(entry.formId + ':' + entry.dimension.toString());
    }
    return parts.join(',');
  }

  /** 反序列化 formId 条目。 */
  private static parseEntries(text: string): FormIdEntry[] {
    if (text.length === 0) {
      return [];
    }
    const parts: string[] = text.split(',');
    const entries: FormIdEntry[] = [];
    for (const part of parts) {
      const kv: string[] = part.split(':');
      if (kv.length === 2) {
        const entry: FormIdEntry = {
          formId: kv[0],
          dimension: parseInt(kv[1]),
        };
        entries.push(entry);
      }
    }
    return entries;
  }

  // ==================== 卡片主动刷新 ====================

  /**
   * 主动刷新所有已添加的卡片。
   * 在场景切换时由主应用调用。
   */
  static async triggerFormUpdate(context: Context, sceneType: SceneType): Promise<void> {
    try {
      const entries: FormIdEntry[] = WidgetHelper.readFormIds(context);
      if (entries.length === 0) {
        hilog.info(DOMAIN, TAG, 'No formIds found, skip update');
        return;
      }

      for (const entry of entries) {
        try {
          const data: CardFormData = await WidgetHelper.buildCardData(context, entry.dimension, sceneType);
          const formBinding: formBindingData.FormBindingData = formBindingData.createFormBindingData(data);
          await formProvider.updateForm(entry.formId, formBinding);
          hilog.info(DOMAIN, TAG, 'Updated form: %{public}s', entry.formId);
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'updateForm failed for %{public}s: %{public}s', entry.formId, JSON.stringify(e));
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'triggerFormUpdate failed: %{public}s', JSON.stringify(e));
    }
  }
}
