import { relationalStore } from '@kit.ArkData';
import { Memo } from './model';

/**
 * 关系型数据库帮助类（单例）。
 *
 * 说明：
 * 1. 导入使用官方当前推荐的 @kit.ArkData（relationalStore 模块统一由此 Kit 导入）。
 *    不存在 @kit.DataRelationalStoreKit 这一 Kit。
 * 2. 当前 relationalStore API 不提供 RdbOpenCallback / onCreate 框架回调。
 *    官方建表模式为：getRdbStore 后通过 store.version === 0 判定数据库首次创建，
 *    再执行建表 SQL 并设置版本号。这里将建表逻辑封装在 onCreate 方法中以贴合该意图。
 * 3. 所有数据库操作均用 try-catch 包裹，捕获底层异常并向调用方抛出 BusinessError。
 */
const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'MemoStore.db',
  securityLevel: relationalStore.SecurityLevel.S1,
};

const TABLE_NAME: string = 'memo_table';

// 建表 SQL：id 整型主键自增；title/content/category 文本；
// isCompleted 用整数 0/1 表示布尔值；createTime 整型时间戳。
const SQL_CREATE_TABLE: string =
  'CREATE TABLE IF NOT EXISTS ' + TABLE_NAME + ' (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'title TEXT, ' +
  'content TEXT, ' +
  'category TEXT, ' +
  'isCompleted INTEGER, ' +
  'createTime INTEGER)';

// 分类筛选索引：加速 getMemosByCategory 的 WHERE category = ? 查询。
const SQL_CREATE_CATEGORY_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_memo_category ON ' + TABLE_NAME + '(category)';

export class RdbHelper {
  private static rdbStore: relationalStore.RdbStore | null = null;

  private constructor() {
  }

  /**
   * 获取 RdbStore 单例。
   * 首次调用时创建/打开数据库，并在数据库首次创建时执行建表。
   *
   * @param context 应用上下文（Stage 模型 Context）
   * @returns RdbStore 实例
   */
  static async getInstance(context: Context): Promise<relationalStore.RdbStore> {
    if (RdbHelper.rdbStore !== null) {
      return RdbHelper.rdbStore;
    }

    try {
      // 创建或打开数据库；若文件不存在则自动创建。
      const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);

      // version 默认为 0 表示数据库首次创建；低版本库按需执行升级。
      const currentVersion: number = store.version;
      if (currentVersion === 0) {
        await RdbHelper.onCreate(store);
      }
      if (currentVersion < 2) {
        // v2：新增分类索引（IF NOT EXISTS，幂等可重复执行）
        await RdbHelper.upgradeToV2(store);
      }
      store.version = 2;

      RdbHelper.rdbStore = store;
      return store;
    } catch (e) {
      throw e as Error;
    }
  }

  /**
   * 数据库首次创建时的初始化逻辑：执行建表 SQL。
   * 使用 executeSql 参数化执行接口（DDL 无需绑定参数，仅传 SQL 字符串）。
   */
  private static async onCreate(db: relationalStore.RdbStore): Promise<void> {
    try {
      await db.executeSql(SQL_CREATE_TABLE);
    } catch (e) {
      throw e as Error;
    }
  }

  /**
   * v1 → v2 升级：为 category 列创建索引。
   * 使用 IF NOT EXISTS，对已建索引的库重复执行无副作用。
   */
  private static async upgradeToV2(db: relationalStore.RdbStore): Promise<void> {
    try {
      await db.executeSql(SQL_CREATE_CATEGORY_INDEX);
    } catch (e) {
      throw e as Error;
    }
  }

  /**
   * 获取已初始化的 RdbStore；若尚未调用 getInstance(context) 则抛错。
   */
  private static async requireStore(): Promise<relationalStore.RdbStore> {
    if (RdbHelper.rdbStore === null) {
      throw new Error('RdbHelper 尚未初始化，请先调用 getInstance(context)');
    }
    return RdbHelper.rdbStore;
  }

  /** 新增备忘录，返回新行 rowId（失败为 -1）。 */
  static async insertMemo(memo: Memo): Promise<number> {
    try {
      const store: relationalStore.RdbStore = await RdbHelper.requireStore();
      const valueBucket: relationalStore.ValuesBucket = {
        title: memo.title,
        content: memo.content,
        category: memo.category,
        isCompleted: memo.isCompleted ? 1 : 0,
        createTime: memo.createTime,
      };
      return await store.insert(TABLE_NAME, valueBucket);
    } catch (e) {
      throw e as Error;
    }
  }

  /** 按 id 更新备忘录，返回受影响行数。 */
  static async updateMemo(memo: Memo): Promise<number> {
    try {
      const store: relationalStore.RdbStore = await RdbHelper.requireStore();
      const valueBucket: relationalStore.ValuesBucket = {
        title: memo.title,
        content: memo.content,
        category: memo.category,
        isCompleted: memo.isCompleted ? 1 : 0,
        createTime: memo.createTime,
      };
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', memo.id);
      return await store.update(valueBucket, predicates);
    } catch (e) {
      throw e as Error;
    }
  }

  /** 按 id 删除备忘录，返回删除行数。 */
  static async deleteMemo(id: number): Promise<number> {
    try {
      const store: relationalStore.RdbStore = await RdbHelper.requireStore();
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', id);
      return await store.delete(predicates);
    } catch (e) {
      throw e as Error;
    }
  }

  /** 查询全部备忘录（按 createTime 降序）。 */
  static async queryAllMemos(): Promise<Memo[]> {
    try {
      const store: relationalStore.RdbStore = await RdbHelper.requireStore();
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.orderByDesc('createTime');
      const resultSet: relationalStore.ResultSet = await store.query(predicates);
      return RdbHelper.mapToList(resultSet);
    } catch (e) {
      throw e as Error;
    }
  }

  /** 按关键词搜索标题或内容（参数化占位符 ?，禁止把值拼接进 SQL）。 */
  static async searchMemos(keyword: string): Promise<Memo[]> {
    try {
      const store: relationalStore.RdbStore = await RdbHelper.requireStore();
      const pattern: string = '%' + keyword + '%';
      const sql: string = 'SELECT * FROM ' + TABLE_NAME +
        ' WHERE title LIKE ? OR content LIKE ? ORDER BY createTime DESC';
      const resultSet: relationalStore.ResultSet = await store.querySql(sql, [pattern, pattern]);
      return RdbHelper.mapToList(resultSet);
    } catch (e) {
      throw e as Error;
    }
  }

  /** 按分类查询备忘录（按 createTime 降序）。 */
  static async getMemosByCategory(category: string): Promise<Memo[]> {
    try {
      const store: relationalStore.RdbStore = await RdbHelper.requireStore();
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.equalTo('category', category);
      predicates.orderByDesc('createTime');
      const resultSet: relationalStore.ResultSet = await store.query(predicates);
      return RdbHelper.mapToList(resultSet);
    } catch (e) {
      throw e as Error;
    }
  }

  /** 按 id 查询单条备忘录，未找到返回 null。 */
  static async getMemoById(id: number): Promise<Memo | null> {
    try {
      const store: relationalStore.RdbStore = await RdbHelper.requireStore();
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', id);
      const resultSet: relationalStore.ResultSet = await store.query(predicates);
      const list: Memo[] = RdbHelper.mapToList(resultSet);
      return list.length > 0 ? list[0] : null;
    } catch (e) {
      throw e as Error;
    }
  }

  /** 查询备忘录总数。 */
  static async getMemoCount(): Promise<number> {
    try {
      const store: relationalStore.RdbStore = await RdbHelper.requireStore();
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
      const resultSet: relationalStore.ResultSet = await store.query(predicates);
      const count: number = resultSet.rowCount;
      try {
        resultSet.close();
      } catch (e) {
        // 关闭 ResultSet 失败不影响查询结果
      }
      return count;
    } catch (e) {
      throw e as Error;
    }
  }

  /** 遍历 ResultSet 构建 Memo 列表，isCompleted 由 0/1 转为 boolean。 */
  private static mapToList(resultSet: relationalStore.ResultSet): Memo[] {
    const list: Memo[] = [];
    try {
      if (resultSet.rowCount <= 0) {
        return list;
      }
      resultSet.goToFirstRow();
      do {
        const memo: Memo = new Memo();
        memo.id = resultSet.getLong(resultSet.getColumnIndex('id'));
        memo.title = resultSet.getString(resultSet.getColumnIndex('title'));
        memo.content = resultSet.getString(resultSet.getColumnIndex('content'));
        memo.category = resultSet.getString(resultSet.getColumnIndex('category'));
        memo.isCompleted = resultSet.getLong(resultSet.getColumnIndex('isCompleted')) !== 0;
        memo.createTime = resultSet.getLong(resultSet.getColumnIndex('createTime'));
        list.push(memo);
      } while (resultSet.goToNextRow());
    } catch (e) {
      // 读取行数据失败时返回已收集的部分结果
    } finally {
      try {
        resultSet.close();
      } catch (e) {
        // 关闭失败忽略
      }
    }
    return list;
  }
}
