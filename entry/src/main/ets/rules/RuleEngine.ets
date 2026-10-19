import { SceneType } from '../common';

/** 场景变更回调类型。 */
type SceneChangeListener = (scene: SceneType) => void;

/** 位置信息。 */
interface LocationInfo {
  latitude: number;
  longitude: number;
}

/**
 * 场景感知规则引擎（单例）。
 *
 * 职责：
 * 1. 根据时间、位置等规则判断当前场景。
 * 2. 支持开发者面板手动切换场景（模拟意图）。
 * 3. 场景变更时通知监听者，触发卡片刷新等操作。
 *
 * 规则示例：
 * - 9:00-10:00 → MEETING（晨会时间）
 * - 在预定义超市坐标 200 米内 → SHOPPING
 * - 其他 → DEFAULT
 */
export class RuleEngine {
  private static instance: RuleEngine | null = null;

  /** 当前自动评估出的场景。 */
  private currentScene: SceneType = SceneType.DEFAULT;
  /** 手动设置的模拟场景（非 null 时优先返回）。 */
  private mockScene: SceneType | null = null;
  /** 场景变更监听器列表。 */
  private listeners: SceneChangeListener[] = [];

  // 预定义超市坐标（模拟数据）
  private readonly SUPERMARKET_LAT: number = 30.123;
  private readonly SUPERMARKET_LNG: number = 120.456;
  private readonly SUPERMARKET_RADIUS: number = 200; // 米

  private constructor() {
  }

  /** 获取单例。 */
  static getInstance(): RuleEngine {
    if (RuleEngine.instance === null) {
      RuleEngine.instance = new RuleEngine();
    }
    return RuleEngine.instance;
  }

  /** 获取当前场景（优先返回模拟场景）。 */
  getCurrentScene(): SceneType {
    if (this.mockScene !== null) {
      return this.mockScene;
    }
    return this.currentScene;
  }

  /**
   * 根据规则评估当前场景。
   *
   * @param location 当前位置（可选）
   * @param time 当前时间（可选，默认 now）
   * @returns 评估出的场景类型
   */
  evaluateScene(location?: LocationInfo, time?: Date): SceneType {
    // 如果有模拟场景，直接返回
    if (this.mockScene !== null) {
      return this.mockScene;
    }

    const now: Date = time !== undefined ? time : new Date();
    const hour: number = now.getHours();

    // 规则 1：9:00-10:00 为会议时间
    if (hour >= 9 && hour < 10) {
      this.currentScene = SceneType.MEETING;
      return this.currentScene;
    }

    // 规则 2：在超市附近（200 米内）
    if (location !== undefined) {
      const distance: number = this.calculateDistance(
        location.latitude, location.longitude,
        this.SUPERMARKET_LAT, this.SUPERMARKET_LNG
      );
      if (distance <= this.SUPERMARKET_RADIUS) {
        this.currentScene = SceneType.SHOPPING;
        return this.currentScene;
      }
    }

    this.currentScene = SceneType.DEFAULT;
    return this.currentScene;
  }

  /**
   * 设置模拟场景（开发者面板使用）。
   * 设置后 getCurrentScene / evaluateScene 将始终返回该场景。
   */
  setMockScene(scene: SceneType): void {
    this.mockScene = scene;
    this.notifySceneChange();
  }

  /** 清除模拟场景，恢复自动评估。 */
  clearMockScene(): void {
    this.mockScene = null;
    this.evaluateScene();
    this.notifySceneChange();
  }

  /** 是否处于模拟模式。 */
  isMockMode(): boolean {
    return this.mockScene !== null;
  }

  /** 注册场景变更监听器。 */
  onSceneChange(listener: SceneChangeListener): void {
    this.listeners.push(listener);
  }

  /** 注销场景变更监听器。 */
  offSceneChange(listener: SceneChangeListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  /** 通知所有监听器场景已变更。 */
  private notifySceneChange(): void {
    const scene: SceneType = this.getCurrentScene();
    this.listeners.forEach((listener: SceneChangeListener) => {
      listener(scene);
    });
  }

  /**
   * 使用 Haversine 公式计算两点间距离（米）。
   */
  private calculateDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const R: number = 6371000; // 地球半径（米）
    const dLat: number = this.toRad(lat2 - lat1);
    const dLng: number = this.toRad(lng2 - lng1);
    const a: number = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(this.toRad(lat1)) * Math.cos(this.toRad(lat2)) *
      Math.sin(dLng / 2) * Math.sin(dLng / 2);
    const c: number = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  private toRad(deg: number): number {
    return deg * Math.PI / 180;
  }
}
