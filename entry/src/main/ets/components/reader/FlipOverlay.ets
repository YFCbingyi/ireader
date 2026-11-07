import { image } from '@kit.ImageKit';

/** 卷边最大宽度占页宽比例 / 绝对值上限（vp） */
const CURL_RATIO = 0.26;
const CURL_MAX = 150;
/** 翻起纸张背面的宽度占卷边比例 */
const BACK_RATIO = 0.55;
/** 卷边阴影最深处的不透明度 */
const SHADOW_ALPHA = 0.32;

/**
 * 仿真翻页的视觉层。
 *
 * 手势与状态机在 TextReaderView 内（见 onFlipStart / onFlipUpdate / onFlipEnd），
 * 本组件只负责「给定进度 → 画一帧」：
 *   1. 底层铺目标页（下一页或上一页）的位图，静止不动；
 *   2. 上层铺当前页位图，按方向整体平移 progress * 页宽；
 *   3. 在页面被掀起的边缘画卷边阴影 + 纸张背面高光。
 *
 * 之所以用位图而不是真实组件：拖动过程中页面内容不能重排，
 * 组件截图（getComponentSnapshot）拿到的是静态位图，逐帧只做平移与描边，
 * 帧成本恒定，与页面文字量无关。
 */
@ComponentV2
export struct FlipOverlay {
  // 0 = 未翻，1 = 翻满；由状态机逐帧驱动
  @Param progress: number = 0;
  @Monitor('progress') onProgressWatch(): void {
    this.onStateChanged();
  }
  // 1 = 向后翻（下一页），-1 = 向前翻（上一页）
  @Param flipDirection: number = 1;
  @Monitor('flipDirection') onFlipDirectionWatch(): void {
    this.onStateChanged();
  }
  // 当前页截图；undefined 表示尚未就绪，此时整层保持空白
  @Param currentPage: image.PixelMap | undefined = undefined;
  @Monitor('currentPage') onCurrentPageWatch(): void {
    this.onStateChanged();
  }
  // 目标页截图（翻页后露出的那一页）
  @Param nextPage: image.PixelMap | undefined = undefined;
  @Monitor('nextPage') onNextPageWatch(): void {
    this.onStateChanged();
  }

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  onStateChanged(): void {
    this.draw();
  }

  private draw(): void {
    if (!this.ready) {
      return;
    }
    const width = this.ctx.width;
    const height = this.ctx.height;
    if (!(width > 0) || !(height > 0)) {
      return;
    }
    this.ctx.clearRect(0, 0, width, height);
    const progress = this.progress;
    if (progress <= 0) {
      return;
    }
    const current = this.currentPage;
    const target = this.nextPage;
    // 两张图齐备才绘制：只有一张时平移会露出空白底，视觉上就是闪屏
    if (current === undefined || target === undefined) {
      return;
    }
    // 目标页先铺底：翻起当前页时露出的就是它
    this.ctx.drawImage(target, 0, 0, width, height);
    const deltaX = this.flipDirection >= 0 ? -progress * width : progress * width;
    this.ctx.drawImage(current, deltaX, 0, width, height);
    // 进度过 0.5 后把「翻起的纸张背面」也画出来，避免只剩一片灰
    const curl = Math.min(width * CURL_RATIO, CURL_MAX) * Math.sin(Math.PI * Math.min(1, progress));
    this.drawCurl(deltaX, width, height, curl);
  }

  /** 在页面被掀起的边缘画阴影与纸张背面（几何近似：竖直渐变带 + 弧形高光） */
  private drawCurl(deltaX: number, width: number, height: number, curl: number): void {
    if (!(curl > 0.5)) {
      return;
    }
    const ctx = this.ctx;
    const backward = this.flipDirection < 0;
    // 页面被掀起的边缘：向后翻是当前页右边缘，向前翻是左边缘
    const edge = backward ? deltaX : deltaX + width;
    const inner = backward ? edge + curl : edge - curl;
    const left = Math.min(edge, inner);
    // 1. 边缘内侧的卷曲阴影
    ctx.save();
    ctx.beginPath();
    ctx.rect(left, 0, curl, height);
    ctx.clip();
    const shadow = backward
      ? ctx.createLinearGradient(edge, 0, inner, 0)
      : ctx.createLinearGradient(inner, 0, edge, 0);
    shadow.addColorStop(0, 'rgba(0,0,0,0)');
    shadow.addColorStop(0.62, `rgba(0,0,0,${SHADOW_ALPHA * 0.5})`);
    shadow.addColorStop(1, `rgba(0,0,0,${SHADOW_ALPHA})`);
    ctx.fillStyle = shadow;
    ctx.fillRect(left, 0, curl, height);
    ctx.restore();
    // 2. 卷边外侧的纸张背面：白色高光，宽度随进度收放
    const backWidth = curl * BACK_RATIO;
    if (!(backWidth > 0.5)) {
      return;
    }
    const backEdge = backward ? edge + backWidth : edge - backWidth;
    const backLeft = Math.min(edge, backEdge);
    ctx.save();
    const paper = backward
      ? ctx.createLinearGradient(backEdge, 0, edge, 0)
      : ctx.createLinearGradient(edge, 0, backEdge, 0);
    paper.addColorStop(0, 'rgba(255,255,255,0.06)');
    paper.addColorStop(0.65, 'rgba(255,255,255,0.42)');
    paper.addColorStop(1, 'rgba(255,255,255,0.78)');
    ctx.fillStyle = paper;
    ctx.fillRect(backLeft, 0, backWidth, height);
    // 背面与正文的交界画一条细亮线，强化「纸被掀起」的轮廓
    ctx.strokeStyle = 'rgba(255,255,255,0.85)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(edge, 0);
    ctx.quadraticCurveTo(backward ? edge + backWidth * 0.35 : edge - backWidth * 0.35, height * 0.5,
      edge, height);
    ctx.stroke();
    ctx.restore();
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
  }
}
