import { distributedDataObject } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Memo } from '../model';
import { ShoppingItem } from '../common';

/** 分布式编辑备忘录的_plain 数据结构（分布式对象只能存储基本类型）。 */
interface EditingMemoData {
  title: string;
  content: string;
  category: string;
  isCompleted: number;
  createTime: number;
  /** 版本戳：每次写入时取 Date.now()，用于回声过滤、LWW 比较与冲突窗口检测。 */
  updateTime: number;
}

/** 购物清单的分布式数据结构。 */
interface ShoppingListData {
  items: ShoppingItem[];
}

/** 分布式编辑备忘录的完整信息（含布尔类型的 isCompleted）。 */
export interface EditingMemoInfo {
  title: string;
  content: string;
  category: string;
  isCompleted: boolean;
  createTime: number;
  updateTime: number;
}

/** Memo 序列化后的数据结构。 */
interface SerializedMemo {
  id: number;
  title: string;
  content: string;
  category: string;
  isCompleted: number;
  createTime: number;
}

/** 编辑备忘录变更回调（对端版本被采用时触发，参数为对端数据）。 */
type EditingMemoChangeCallback = (title: string, content: string, category: string) => void;

/** 编辑冲突回调（两端在冲突窗口内同时修改时触发，由用户裁决，参数为对端数据）。 */
type EditingConflictCallback = (remoteTitle: string, remoteContent: string, remoteCategory: string) => void;

/** 设备状态变更回调。 */
type DeviceStatusCallback = (sessionId: string, networkId: string, status: 'online' | 'offline') => void;

/** 购物清单变更回调。 */
type ShoppingListChangeCallback = (items: ShoppingItem[]) => void;

/** 会议纪要变更回调。 */
type MeetingMinutesChangeCallback = (title: string, content: string) => void;

/** 会议纪要的分布式数据结构。 */
interface MeetingMinutesData {
  title: string;
  content: string;
  timestamp: number;
}

/** 会议纪要的分布式数据对象。 */
interface MeetingDataObject extends distributedDataObject.DataObject {
  title: string;
  content: string;
  timestamp: number;
}

/** 编辑备忘录的分布式数据对象（扩展 DataObject 增加类型化属性访问）。 */
interface EditingDataObject extends distributedDataObject.DataObject {
  title: string;
  content: string;
  category: string;
  isCompleted: number;
  createTime: number;
  updateTime: number;
}

/** 购物清单的分布式数据对象（扩展 DataObject 增加类型化属性访问）。 */
interface ShoppingDataObject extends distributedDataObject.DataObject {
  items: ShoppingItem[];
}

/**
 * 分布式数据对象管理类（单例）。
 *
 * 职责：
 * 1. 管理编辑接续的分布式对象 —— 设备A编辑时写入数据，设备B加入同会话后读取。
 * 2. 管理购物清单的分布式对象 —— 多端实时同步勾选和添加状态。
 * 3. 提供 Memo ↔ plain object 的序列化/反序列化。
 * 4. 统一注册/注销 change 和 status 监听器。
 *
 * API 24 导入路径：@kit.ArkData（distributedDataObject 模块统一由此 Kit 导入）。
 */
export class DistributedManager {
  private static instance: DistributedManager | null = null;
  private context: Context | null = null;

  // 编辑接续相关
  private editingObject: distributedDataObject.DataObject | null = null;
  private editingSessionId: string = '';
  private editingChangeCallbacks: EditingMemoChangeCallback[] = [];
  private editingConflictCallbacks: EditingConflictCallback[] = [];
  private statusCallbacks: DeviceStatusCallback[] = [];
  /** 本端最近一次写入（或采纳）的版本戳，用于回声过滤与冲突窗口检测。 */
  private lastLocalUpdateTime: number = 0;
  /** 冲突窗口：两端版本戳差值小于该值视为"同时编辑"，交由用户裁决。 */
  private static readonly CONFLICT_WINDOW_MS: number = 2000;

  // 购物清单相关
  private shoppingObject: distributedDataObject.DataObject | null = null;
  private shoppingSessionId: string = '';
  private shoppingChangeCallbacks: ShoppingListChangeCallback[] = [];

  // 会议纪要相关
  private meetingObject: distributedDataObject.DataObject | null = null;
  private meetingSessionId: string = '';
  private meetingChangeCallbacks: MeetingMinutesChangeCallback[] = [];

  private constructor() {
  }

  /** 获取单例。 */
  static getInstance(): DistributedManager {
    if (DistributedManager.instance === null) {
      DistributedManager.instance = new DistributedManager();
    }
    return DistributedManager.instance;
  }

  /**
   * 初始化，传入 Context。
   * 在 EntryAbility.onCreate 或页面 aboutToAppear 中调用。
   */
  init(context: Context): void {
    this.context = context;
  }

  /** 确保已初始化 context。 */
  private requireContext(): Context {
    if (this.context === null) {
      throw new Error('DistributedManager 尚未初始化，请先调用 init(context)');
    }
    return this.context;
  }

  // ==================== 编辑接续 ====================

  /**
   * 创建编辑接续的分布式对象并加入会话。
   * 设备A调用：写入当前编辑的备忘数据，其他设备加入同会话后可读取。
   *
   * 已有备忘录使用确定性 sessionId（由 createTime 派生），两台设备打开同一条
   * 备忘录时进入同一会话，从而支持协同编辑与冲突检测；新建备忘录仍用随机 ID。
   *
   * @param memo 当前正在编辑的备忘录
   * @returns sessionId 会话 ID，其他设备用此 ID 加入会话
   */
  startEditingSession(memo: Memo): string {
    const ctx: Context = this.requireContext();

    // 如果已有编辑对象，先清理
    this.stopEditingSession();

    // 生成会话 ID：已有备忘录用稳定 ID 让两端进入同一会话；新建用随机 ID
    this.editingSessionId = memo.createTime > 0
      ? `memo_sync_${memo.createTime}`
      : distributedDataObject.genSessionId();

    // 初始版本戳：作为本端写入基线，join 端首次同步时据此识别为新版本
    this.lastLocalUpdateTime = Date.now();

    // 创建源对象（plain object，基本类型字段）
    const source: EditingMemoData = {
      title: memo.title,
      content: memo.content,
      category: memo.category,
      isCompleted: memo.isCompleted ? 1 : 0,
      createTime: memo.createTime,
      updateTime: this.lastLocalUpdateTime,
    };

    try {
      this.editingObject = distributedDataObject.create(ctx, source);
      this.registerEditingListeners();
      this.editingObject.setSessionId(this.editingSessionId);
    } catch (e) {
      throw e as Error;
    }

    return this.editingSessionId;
  }

  /**
   * 注册编辑会话的 change / status 监听（start 与 join 共用）。
   * 仅在变更字段包含 updateTime 时处理：每批写入以 updateTime 收尾，
   * 避免读到其他字段已变但版本戳未同步的中间状态。
   */
  private registerEditingListeners(): void {
    if (this.editingObject === null) {
      return;
    }
    try {
      this.editingObject.on('change', (session: string, fields: Array<string>) => {
        if (fields.indexOf('updateTime') >= 0) {
          this.handleEditingChange();
        }
      });
      this.editingObject.on('status', (session: string, networkId: string, status: 'online' | 'offline') => {
        this.notifyStatusChange(session, networkId, status);
      });
    } catch (e) {
      hilog.error(0x0001, 'DistributedManager',
        'registerEditingListeners failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 加入已有的编辑会话（设备B调用）。
   * 创建一个空的分布式对象并设置相同的 sessionId，数据会自动同步。
   *
   * @param sessionId 设备A生成的会话 ID
   */
  joinEditingSession(sessionId: string): void {
    const ctx: Context = this.requireContext();

    // 如果已加入某个会话，先退出
    this.stopEditingSession();

    // 创建源对象，初始值为空（目标端初始值需为空，才能接收源端数据）
    const source: EditingMemoData = {
      title: '',
      content: '',
      category: '',
      isCompleted: 0,
      createTime: 0,
      updateTime: 0,
    };

    try {
      this.editingObject = distributedDataObject.create(ctx, source);
      this.editingSessionId = sessionId;

      // 注册数据变更与状态监听，加入会话后数据自动同步
      this.registerEditingListeners();
      this.editingObject.setSessionId(sessionId);
    } catch (e) {
      throw e as Error;
    }
  }

  /**
   * 更新当前编辑的备忘数据到分布式对象。
   * 设备A编辑时调用，数据自动同步到同会话的其他设备。
   *
   * 每次写入刷新版本戳 updateTime 并记录为本端基线；createTime 作为会话
   * 身份标识不更新（避免接续端以新 createTime 覆盖导致会话身份漂移）。
   */
  updateEditingMemo(memo: Memo): void {
    if (this.editingObject === null) {
      return;
    }
    try {
      const obj: EditingDataObject = this.editingObject as EditingDataObject;
      obj.title = memo.title;
      obj.content = memo.content;
      obj.category = memo.category;
      obj.isCompleted = memo.isCompleted ? 1 : 0;
      // 版本戳最后写入：对端以 updateTime 变更作为一批修改的收尾信号
      this.lastLocalUpdateTime = Date.now();
      obj.updateTime = this.lastLocalUpdateTime;
    } catch (e) {
      // 同步到对端失败仅记日志，不阻断本地编辑
      hilog.warn(0x0001, 'DistributedManager', 'updateEditingMemo sync failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 获取分布式对象中当前的编辑备忘数据。
   * 设备B调用：读取设备A同步过来的备忘数据。
   */
  getCurrentEditingMemo(): EditingMemoInfo | null {
    if (this.editingObject === null) {
      return null;
    }
    try {
      const obj: EditingDataObject = this.editingObject as EditingDataObject;
      const title: string = obj.title;
      const content: string = obj.content;
      const category: string = obj.category;
      const isCompleted: number = obj.isCompleted;
      const createTime: number = obj.createTime;
      const updateTime: number = obj.updateTime;
      const info: EditingMemoInfo = {
        title: title,
        content: content,
        category: category,
        isCompleted: isCompleted !== 0,
        createTime: createTime,
        updateTime: updateTime,
      };
      return info;
    } catch (e) {
      return null;
    }
  }

  /** 获取当前编辑会话 ID。 */
  getEditingSessionId(): string {
    return this.editingSessionId;
  }

  /** 停止编辑会话，清理分布式对象和监听器。 */
  stopEditingSession(): void {
    if (this.editingObject !== null) {
      try {
        this.editingObject.off('change');
        this.editingObject.off('status');
        this.editingObject.setSessionId('');
      } catch (e) {
        // 清理失败忽略
      }
      this.editingObject = null;
    }
    this.editingSessionId = '';
    this.lastLocalUpdateTime = 0;
  }

  /**
   * 注册编辑备忘数据变更监听器。
   * 当分布式对象数据变化时，通过回调通知外部。
   */
  onEditingMemoChange(callback: EditingMemoChangeCallback): void {
    this.editingChangeCallbacks.push(callback);
  }

  /** 注销编辑备忘数据变更监听器。 */
  offEditingMemoChange(callback: EditingMemoChangeCallback): void {
    const pos: number = this.editingChangeCallbacks.indexOf(callback);
    if (pos >= 0) {
      this.editingChangeCallbacks.splice(pos, 1);
    }
  }

  /** 注册编辑冲突监听器：两端同时修改同一条备忘录时触发，由 UI 弹窗请用户裁决。 */
  onEditingConflict(callback: EditingConflictCallback): void {
    this.editingConflictCallbacks.push(callback);
  }

  /** 注销编辑冲突监听器。 */
  offEditingConflict(callback: EditingConflictCallback): void {
    const pos: number = this.editingConflictCallbacks.indexOf(callback);
    if (pos >= 0) {
      this.editingConflictCallbacks.splice(pos, 1);
    }
  }

  /**
   * 用户裁决"采用对方"后调用：将对端版本戳记为本端基线。
   * 否则对端版本戳与本端基线仍处冲突窗口内，后续对端每次修改都会被重复判为冲突。
   */
  acceptRemoteEditing(): void {
    const data: EditingMemoInfo | null = this.getCurrentEditingMemo();
    if (data !== null) {
      this.lastLocalUpdateTime = data.updateTime;
    }
  }

  /**
   * 注册设备状态变更监听器。
   * 当其他设备加入/退出会话时通知。
   */
  onDeviceStatusChange(callback: DeviceStatusCallback): void {
    this.statusCallbacks.push(callback);
  }

  /** 注销设备状态变更监听器。 */
  offDeviceStatusChange(callback: DeviceStatusCallback): void {
    const pos: number = this.statusCallbacks.indexOf(callback);
    if (pos >= 0) {
      this.statusCallbacks.splice(pos, 1);
    }
  }

  /**
   * 处理编辑对象的远端变更（LWW + 冲突窗口检测）。
   *
   * 判定顺序：
   * 1. 回声过滤：版本戳等于本端基线，说明是本端写入被同步回来，忽略。
   * 2. 冲突窗口：本端刚写过且两端版本戳差值小于窗口，视为"同时编辑"，交用户裁决。
   * 3. LWW：对端版本明显更新则采用对端值并刷新基线；本端更新则忽略对端旧值。
   */
  private handleEditingChange(): void {
    const data: EditingMemoInfo | null = this.getCurrentEditingMemo();
    if (data === null) {
      return;
    }

    // 回声过滤：自己的写回到达，无需处理
    if (data.updateTime === this.lastLocalUpdateTime) {
      return;
    }

    // 冲突窗口检测：本端有未裁决的并发修改时，不静默覆盖，交给用户选择
    if (this.lastLocalUpdateTime !== 0 &&
      Math.abs(data.updateTime - this.lastLocalUpdateTime) < DistributedManager.CONFLICT_WINDOW_MS) {
      hilog.info(0x0001, 'DistributedManager', 'editing conflict detected, local: %{public}d, remote: %{public}d',
        this.lastLocalUpdateTime, data.updateTime);
      this.editingConflictCallbacks.forEach((callback: EditingConflictCallback) => {
        callback(data.title, data.content, data.category);
      });
      return;
    }

    // LWW：本端版本更新（对端是过期写入），忽略
    if (data.updateTime < this.lastLocalUpdateTime) {
      return;
    }

    // LWW：对端版本更新，采用对端值并刷新基线
    this.lastLocalUpdateTime = data.updateTime;
    this.editingChangeCallbacks.forEach((callback: EditingMemoChangeCallback) => {
      callback(data.title, data.content, data.category);
    });
  }

  /** 通知所有设备状态变更回调。 */
  private notifyStatusChange(session: string, networkId: string, status: 'online' | 'offline'): void {
    this.statusCallbacks.forEach((callback: DeviceStatusCallback) => {
      callback(session, networkId, status);
    });
  }

  // ==================== 购物清单实时同步 ====================

  /**
   * 创建或加入购物清单的分布式会话。
   * 两台设备使用相同的 sessionId，数据自动同步。
   *
   * @param sessionId 会话 ID，传入空字符串则生成新 ID
   * @param initialItems 初始购物清单数据（首次创建时使用）
   * @returns 实际使用的 sessionId
   */
  startShoppingSync(sessionId: string, initialItems: ShoppingItem[]): string {
    const ctx: Context = this.requireContext();

    // 如果已有购物对象，先清理
    this.stopShoppingSync();

    // 生成或使用传入的会话 ID
    this.shoppingSessionId = sessionId.length > 0 ? sessionId : distributedDataObject.genSessionId();

    // 创建源对象
    const source: ShoppingListData = {
      items: initialItems,
    };

    try {
      this.shoppingObject = distributedDataObject.create(ctx, source);

      // 注册数据变更监听
      this.shoppingObject.on('change', (session: string, fields: Array<string>) => {
        this.notifyShoppingListChange();
      });

      // 加入会话
      this.shoppingObject.setSessionId(this.shoppingSessionId);
    } catch (e) {
      throw e as Error;
    }

    return this.shoppingSessionId;
  }

  /**
   * 更新购物清单数据到分布式对象。
   * 注意：分布式对象的复杂类型只能修改根属性，因此每次替换整个 items 数组。
   *
   * @param items 最新的购物清单数组
   */
  updateShoppingItems(items: ShoppingItem[]): void {
    if (this.shoppingObject === null) {
      return;
    }
    try {
      const obj: ShoppingDataObject = this.shoppingObject as ShoppingDataObject;
      obj.items = items;
    } catch (e) {
      // 同步到对端失败仅记日志，不阻断本地操作
      hilog.warn(0x0001, 'DistributedManager', 'updateShoppingItems sync failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 获取分布式对象中当前的购物清单数据。
   */
  getCurrentShoppingItems(): ShoppingItem[] {
    if (this.shoppingObject === null) {
      return [];
    }
    try {
      const obj: ShoppingDataObject = this.shoppingObject as ShoppingDataObject;
      const items: ShoppingItem[] = obj.items;
      if (items instanceof Array) {
        return items;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /** 获取购物清单会话 ID。 */
  getShoppingSessionId(): string {
    return this.shoppingSessionId;
  }

  /** 停止购物清单同步，清理分布式对象和监听器。 */
  stopShoppingSync(): void {
    if (this.shoppingObject !== null) {
      try {
        this.shoppingObject.off('change');
        this.shoppingObject.setSessionId('');
      } catch (e) {
        // 清理失败忽略
      }
      this.shoppingObject = null;
    }
    this.shoppingSessionId = '';
  }

  /**
   * 注册购物清单数据变更监听器。
   * 当其他设备修改了购物清单时，通过回调通知本地 UI 刷新。
   */
  onShoppingListChange(callback: ShoppingListChangeCallback): void {
    this.shoppingChangeCallbacks.push(callback);
  }

  /** 注销购物清单数据变更监听器。 */
  offShoppingListChange(callback: ShoppingListChangeCallback): void {
    const pos: number = this.shoppingChangeCallbacks.indexOf(callback);
    if (pos >= 0) {
      this.shoppingChangeCallbacks.splice(pos, 1);
    }
  }

  /** 通知所有购物清单变更回调。 */
  private notifyShoppingListChange(): void {
    const items: ShoppingItem[] = this.getCurrentShoppingItems();
    this.shoppingChangeCallbacks.forEach((callback: ShoppingListChangeCallback) => {
      callback(items);
    });
  }

  // ==================== 会议纪要分布式推送 ====================

  /**
   * 推送会议纪要到其他设备。
   * 创建分布式对象并写入会议纪要数据，其他设备加入同会话后自动接收。
   *
   * @param title 纪要标题
   * @param content 纪要内容
   * @returns sessionId 会话 ID
   */
  pushMeetingMinutes(title: string, content: string): string {
    const ctx: Context = this.requireContext();

    // 停止之前的会议纪要会话
    this.stopMeetingSync();

    this.meetingSessionId = distributedDataObject.genSessionId();

    const source: MeetingMinutesData = {
      title: title,
      content: content,
      timestamp: Date.now(),
    };

    try {
      this.meetingObject = distributedDataObject.create(ctx, source);
      this.meetingObject.setSessionId(this.meetingSessionId);
    } catch (e) {
      throw e as Error;
    }

    return this.meetingSessionId;
  }

  /**
   * 加入会议纪要监听会话。
   * 目标设备调用：加入后会议纪要数据自动同步，变更时触发回调。
   *
   * @param sessionId 推送方生成的会话 ID
   */
  joinMeetingSync(sessionId: string): void {
    const ctx: Context = this.requireContext();
    this.stopMeetingSync();

    const source: MeetingMinutesData = {
      title: '',
      content: '',
      timestamp: 0,
    };

    try {
      this.meetingObject = distributedDataObject.create(ctx, source);
      this.meetingSessionId = sessionId;

      this.meetingObject.on('change', (session: string, fields: Array<string>) => {
        this.notifyMeetingMinutesChange();
      });

      this.meetingObject.setSessionId(sessionId);
    } catch (e) {
      throw e as Error;
    }
  }

  /**
   * 启动会议纪要监听（自动生成会话，等待其他设备推送）。
   * 两台设备使用相同会话 ID 后数据自动同步。
   *
   * @param sessionId 会话 ID，空字符串则生成新 ID
   * @returns 实际使用的 sessionId
   */
  startMeetingListener(sessionId: string = ''): string {
    const ctx: Context = this.requireContext();
    this.stopMeetingSync();

    this.meetingSessionId = sessionId.length > 0 ? sessionId : distributedDataObject.genSessionId();

    const source: MeetingMinutesData = {
      title: '',
      content: '',
      timestamp: 0,
    };

    try {
      this.meetingObject = distributedDataObject.create(ctx, source);

      this.meetingObject.on('change', (session: string, fields: Array<string>) => {
        this.notifyMeetingMinutesChange();
      });

      this.meetingObject.setSessionId(this.meetingSessionId);
    } catch (e) {
      throw e as Error;
    }

    return this.meetingSessionId;
  }

  /** 获取当前会议纪要数据。 */
  getCurrentMeetingMinutes(): MeetingMinutesData | null {
    if (this.meetingObject === null) {
      return null;
    }
    try {
      const obj: MeetingDataObject = this.meetingObject as MeetingDataObject;
      const data: MeetingMinutesData = {
        title: obj.title,
        content: obj.content,
        timestamp: obj.timestamp,
      };
      return data;
    } catch (e) {
      return null;
    }
  }

  /** 获取会议纪要会话 ID。 */
  getMeetingSessionId(): string {
    return this.meetingSessionId;
  }

  /** 停止会议纪要同步，清理分布式对象和监听器。 */
  stopMeetingSync(): void {
    if (this.meetingObject !== null) {
      try {
        this.meetingObject.off('change');
        this.meetingObject.setSessionId('');
      } catch (e) {
        // 清理失败忽略
      }
      this.meetingObject = null;
    }
    this.meetingSessionId = '';
  }

  /** 注册会议纪要变更监听器。 */
  onMeetingMinutesChange(callback: MeetingMinutesChangeCallback): void {
    this.meetingChangeCallbacks.push(callback);
  }

  /** 注销会议纪要变更监听器。 */
  offMeetingMinutesChange(callback: MeetingMinutesChangeCallback): void {
    const pos: number = this.meetingChangeCallbacks.indexOf(callback);
    if (pos >= 0) {
      this.meetingChangeCallbacks.splice(pos, 1);
    }
  }

  /** 通知所有会议纪要变更回调。 */
  private notifyMeetingMinutesChange(): void {
    const data: MeetingMinutesData | null = this.getCurrentMeetingMinutes();
    if (data === null || data.title.length === 0) {
      return;
    }
    this.meetingChangeCallbacks.forEach((callback: MeetingMinutesChangeCallback) => {
      callback(data.title, data.content);
    });
  }

  // ==================== 序列化工具 ====================

  /** 将 Memo 序列化为 plain object（分布式对象不能直接存 class 实例）。 */
  static serializeMemo(memo: Memo): SerializedMemo {
    const result: SerializedMemo = {
      id: memo.id,
      title: memo.title,
      content: memo.content,
      category: memo.category,
      isCompleted: memo.isCompleted ? 1 : 0,
      createTime: memo.createTime,
    };
    return result;
  }

  /** 将 plain object 反序列化为 Memo 实例。 */
  static deserializeMemo(data: SerializedMemo): Memo {
    const memo: Memo = new Memo();
    memo.id = data.id;
    memo.title = data.title;
    memo.content = data.content;
    memo.category = data.category;
    memo.isCompleted = data.isCompleted !== 0;
    memo.createTime = data.createTime;
    return memo;
  }

  // ==================== 跨设备迁移支持 ====================

  /**
   * 为跨设备迁移准备分布式对象。
   * 在 EntryAbility.onContinue 中调用：创建对象、写入数据、生成 sessionId。
   *
   * @param memo 当前编辑的备忘录
   * @returns sessionId 用于放入 wantParam
   */
  prepareForMigration(memo: Memo): string {
    const sessionId: string = this.startEditingSession(memo);
    return sessionId;
  }

  /**
   * 从迁移数据中恢复。
   * 在 EntryAbility.onCreate/onNewWant 中调用：加入会话、注册监听、等待数据同步。
   *
   * @param sessionId 从 want.parameters 中获取的会话 ID
   */
  restoreFromMigration(sessionId: string): void {
    this.joinEditingSession(sessionId);
  }
}
