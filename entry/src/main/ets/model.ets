/**
 * 备忘录数据模型。
 * 每个字段均在类体中显式声明并赋默认值，符合 ArkTS「对象布局显式、起始状态可信」的要求。
 */
export class Memo {
  id: number = 0;
  title: string = '';
  content: string = '';
  category: string = 'default';
  isCompleted: boolean = false;
  createTime: number = Date.now();
}
