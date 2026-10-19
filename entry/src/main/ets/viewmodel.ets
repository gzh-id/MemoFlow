import { Memo } from './model';
import { RdbHelper } from './database';

/**
 * 备忘录 ViewModel（单例）。
 *
 * 职责：
 * 1. 持有应用上下文，负责初始化 RdbHelper（数据库）。
 * 2. 对 UI 层暴露异步业务方法，内部直接委托 RdbHelper。
 * 3. 首次启动时自动生成测试数据，便于开发调试。
 */
export class MemoViewModel {
  private static instance: MemoViewModel | null = null;
  private initialized: boolean = false;

  private constructor() {
  }

  /** 获取 ViewModel 单例。 */
  static getInstance(): MemoViewModel {
    if (MemoViewModel.instance === null) {
      MemoViewModel.instance = new MemoViewModel();
    }
    return MemoViewModel.instance;
  }

  /**
   * 初始化数据库。应在 UI 组件 aboutToAppear 中调用。
   *
   * @param context 应用上下文（Stage 模型 Context）
   */
  async init(context: Context): Promise<void> {
    if (this.initialized) {
      return;
    }
    await RdbHelper.getInstance(context);
    await this.generateTestDataIfNeeded();
    this.initialized = true;
  }

  /** 新增备忘录，返回新行 rowId。 */
  async addMemo(memo: Memo): Promise<number> {
    return await RdbHelper.insertMemo(memo);
  }

  /** 更新备忘录，返回受影响行数。 */
  async updateMemo(memo: Memo): Promise<number> {
    return await RdbHelper.updateMemo(memo);
  }

  /** 按 id 删除备忘录，返回删除行数。 */
  async deleteMemo(id: number): Promise<number> {
    return await RdbHelper.deleteMemo(id);
  }

  /** 查询全部备忘录（按创建时间降序）。 */
  async loadAllMemos(): Promise<Memo[]> {
    return await RdbHelper.queryAllMemos();
  }

  /** 按关键词搜索标题或内容。 */
  async searchMemos(keyword: string): Promise<Memo[]> {
    return await RdbHelper.searchMemos(keyword);
  }

  /** 按分类查询备忘录。 */
  async getMemosByCategory(category: string): Promise<Memo[]> {
    return await RdbHelper.getMemosByCategory(category);
  }

  /** 按 id 查询单条备忘录。 */
  async getMemoById(id: number): Promise<Memo | null> {
    return await RdbHelper.getMemoById(id);
  }

  /**
   * 首次启动时生成测试数据。
   * 判断依据：数据库表为空（count === 0）。
   */
  async generateTestDataIfNeeded(): Promise<void> {
    const count: number = await RdbHelper.getMemoCount();
    if (count > 0) {
      return;
    }

    const now: number = Date.now();
    const testMemos: Memo[] = [
      this.createMemo('欢迎使用 MemoFlow', '这是一款基于 HarmonyOS NEXT 的备忘录应用，支持分类管理、搜索和快捷编辑。', 'default', false, now - 86400000),
      this.createMemo('团队周会', '讨论 Q3 进度，确认下阶段任务分配。准备演示原型。', 'work', true, now - 43200000),
      this.createMemo('购物清单', '牛奶、鸡蛋、面包、水果、咖啡豆', 'personal', false, now - 21600000),
      this.createMemo('ArkTS 学习笔记', '@State 观察第一层属性变化；@Observed + @ObjectLink 处理嵌套对象；LazyForEach 需实现 IDataSource。', 'study', false, now - 10800000),
      this.createMemo('数据库设计要点', 'isCompleted 存储为 INTEGER (0/1)，读取时转为 boolean；createTime 使用毫秒时间戳；SQL 一律参数化执行。', 'study', false, now - 3600000),
      this.createMemo('健身计划', '周一：胸+三头，周三：背+二头，周五：腿+肩，周日：有氧 30min', 'personal', false, now - 1800000),
      this.createMemo('项目里程碑', 'Phase 1：数据模型 + 数据库 ✓\nPhase 2：ViewModel + UI 页面\nPhase 3：功能联调与优化', 'work', false, now),
    ];

    for (const memo of testMemos) {
      await RdbHelper.insertMemo(memo);
    }
  }

  /** 构造一条 Memo 对象的辅助方法。 */
  private createMemo(title: string, content: string, category: string, isCompleted: boolean, createTime: number): Memo {
    const memo: Memo = new Memo();
    memo.title = title;
    memo.content = content;
    memo.category = category;
    memo.isCompleted = isCompleted;
    memo.createTime = createTime;
    return memo;
  }
}
