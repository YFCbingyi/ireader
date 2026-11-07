/**
 * 拖动型翻页的公共状态机（仿真翻页与左右平移共用）。
 *
 * 这一层只做纯计算：把「水平位移 + 抬手速度」映射为「方向 + 进度 + 是否要抓目标页位图」，
 * 不持有任何 UI 状态、不触发截图与动画。视觉映射（卷曲绘制 / 平移 / 回弹）留在容器层，
 * 与文档 §3 FlipStrategy 的分工一致：
 *   onDragStart -> begin()，onDragUpdate -> update()，onDragEnd -> end()
 */

/** 位移超过页宽此比例即判定翻页完成，否则回弹 */
const COMMIT_RATIO = 0.3;
/** 抬手速度阈值（vp/s），超过则不看位移直接完成 */
const COMMIT_VELOCITY = 320;
/** 低于该位移不判定方向（手指轻微抖动不应触发截图） */
const DIRECTION_SLOP = 6;

/** update() 的输出：方向、进度、以及是否需要抓目标页位图 */
export class FlipUpdate {
  // 本次位移是否足以驱动视觉（低于 slop 时为 false，调用方直接忽略）
  active: boolean = false;
  direction: number = 1;
  progress: number = 0;
  // 方向首次确定或方向反转时为 true，调用方据此抓目标页位图
  needTarget: boolean = false;

  static of(active: boolean, direction: number, progress: number, needTarget: boolean): FlipUpdate {
    const update = new FlipUpdate();
    update.active = active;
    update.direction = direction;
    update.progress = progress;
    update.needTarget = needTarget;
    return update;
  }
}

/** end() / cancel() 的输出：是否翻满，以及翻页方向 */
export class FlipEnd {
  commit: boolean = false;
  direction: number = 1;

  static of(commit: boolean, direction: number): FlipEnd {
    const result = new FlipEnd();
    result.commit = commit;
    result.direction = direction;
    return result;
  }
}

export class FlipStateMachine {
  private dragging: boolean = false;
  private direction: number = 1;
  private progress: number = 0;
  // 已经为当前方向请求过目标页位图，避免每帧重复截图
  private targetRequested: boolean = false;

  isDragging(): boolean {
    return this.dragging;
  }

  /** 手势起点：重置方向与进度，返回是否接管本次手势 */
  begin(): boolean {
    this.dragging = true;
    this.direction = 1;
    this.progress = 0;
    this.targetRequested = false;
    return true;
  }

  /**
   * 拖动中：由水平位移与页宽算出进度。
   * 方向一旦确定（或用户反向拖动）就要求抓一次目标页位图。
   */
  update(offsetX: number, pageWidth: number): FlipUpdate {
    if (!this.dragging) {
      return FlipUpdate.of(false, this.direction, this.progress, false);
    }
    if (Math.abs(offsetX) < DIRECTION_SLOP) {
      return FlipUpdate.of(false, this.direction, this.progress, false);
    }
    // 左滑为下一页，右滑为上一页
    const direction = offsetX < 0 ? 1 : -1;
    let needTarget = false;
    if (direction !== this.direction) {
      this.direction = direction;
      this.targetRequested = false;
    }
    if (!this.targetRequested) {
      this.targetRequested = true;
      needTarget = true;
    }
    const width = pageWidth > 0 ? pageWidth : 1;
    let progress = Math.abs(offsetX) / width;
    if (progress > 1) {
      progress = 1;
    }
    this.progress = progress;
    return FlipUpdate.of(true, direction, progress, needTarget);
  }

  /** 抬手：位移过阈值或甩动速度够快则判定翻满 */
  end(velocityX: number): FlipEnd {
    this.dragging = false;
    const direction = this.direction;
    const flung = direction > 0 ? velocityX < -COMMIT_VELOCITY : velocityX > COMMIT_VELOCITY;
    const commit = this.progress >= COMMIT_RATIO || flung;
    return FlipEnd.of(commit, direction);
  }

  /** 手势被系统打断：一律回弹 */
  cancel(): FlipEnd {
    this.dragging = false;
    return FlipEnd.of(false, this.direction);
  }

  /** 动画落地后归零 */
  reset(): void {
    this.dragging = false;
    this.direction = 1;
    this.progress = 0;
    this.targetRequested = false;
  }
}
