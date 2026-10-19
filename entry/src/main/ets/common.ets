import { Memo } from './model';

/** 路由名称常量。 */
export class RouteName {
  static readonly MAIN_PAGE: string = 'MainPage';
  static readonly EDIT_PAGE: string = 'EditPage';
  static readonly SHOPPING_PAGE: string = 'ShoppingPage';
  static readonly RECORD_PAGE: string = 'RecordPage';
}

/** 场景类型枚举。 */
export enum SceneType {
  DEFAULT = 'DEFAULT',
  SHOPPING = 'SHOPPING',
  MEETING = 'MEETING',
}

/** 分类项。 */
export class CategoryItem {
  value: string = '';
  label: string = '';

  constructor(value: string, label: string) {
    this.value = value;
    this.label = label;
  }
}

/** 全部分类（含「全部」筛选选项）。 */
export const CATEGORIES: CategoryItem[] = [
  new CategoryItem('all', '全部'),
  new CategoryItem('default', '默认'),
  new CategoryItem('work', '工作'),
  new CategoryItem('personal', '个人'),
  new CategoryItem('study', '学习'),
  new CategoryItem('shopping', '购物'),
];

/** 编辑页导航参数。editId === 0 表示新建，> 0 表示编辑已有备忘录。 */
export class EditPageParam {
  editId: number = 0;
  isContinuation: boolean = false;
  continuationTitle: string = '';
  continuationContent: string = '';
  continuationCategory: string = 'default';

  constructor(editId: number = 0) {
    this.editId = editId;
  }
}

/** 购物清单项。 */
export class ShoppingItem {
  name: string = '';
  checked: boolean = false;

  constructor(name: string = '', checked: boolean = false) {
    this.name = name;
    this.checked = checked;
  }
}

/**
 * LazyForEach 数据源，封装 Memo 列表并实现 IDataSource。
 * 通过 DataChangeListener 通知 LazyForEach 局部刷新。
 */
export class MemoDataSource implements IDataSource {
  private list: Memo[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.list.length;
  }

  getData(index: number): Memo {
    return this.list[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  /** 整体替换数据，触发 onDataReloaded。 */
  setData(list: Memo[]): void {
    this.list = list;
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }

  /** 获取内部列表引用（用于按索引删除等操作）。 */
  getList(): Memo[] {
    return this.list;
  }
}

/**
 * 格式化时间戳为可读字符串。
 * 今天 → HH:mm；昨天 → 昨天 HH:mm；更早 → MM-DD HH:mm。
 */
export function formatTime(timestamp: number): string {
  const date: Date = new Date(timestamp);
  const now: Date = new Date();
  const hour: number = date.getHours();
  const minute: number = date.getMinutes();
  const hourStr: string = hour < 10 ? '0' + hour : hour.toString();
  const minuteStr: string = minute < 10 ? '0' + minute : minute.toString();

  const isToday: boolean = date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() && date.getDate() === now.getDate();
  if (isToday) {
    return hourStr + ':' + minuteStr;
  }

  const yesterday: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  const isYesterday: boolean = date.getFullYear() === yesterday.getFullYear() &&
    date.getMonth() === yesterday.getMonth() && date.getDate() === yesterday.getDate();
  if (isYesterday) {
    return '昨天 ' + hourStr + ':' + minuteStr;
  }

  const month: number = date.getMonth() + 1;
  const day: number = date.getDate();
  const monthStr: string = month < 10 ? '0' + month : month.toString();
  const dayStr: string = day < 10 ? '0' + day : day.toString();
  return monthStr + '-' + dayStr + ' ' + hourStr + ':' + minuteStr;
}
