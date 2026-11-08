import { hilog } from '@kit.PerformanceAnalysisKit';
import { batteryInfo } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { PageTurnMode, ReadingMode, TextAlignMode } from '../../model/BookModels';
import { Annotation, SegmentBuilder, TextSegment } from '../../model/Annotation';
import { TextPaginator } from '../../service/TextPaginator';
import { PagedItem, PageWindow } from '../../reader/PageWindow';
import { BlockWindow, ReaderBlock } from '../../reader/BlockWindow';
import { FlipEnd, FlipStateMachine, FlipUpdate } from '../../reader/FlipStateMachine';
import { LayoutConfig } from '../../reader/LayoutConfig';
import { LengthMetricsUnit } from '@kit.ArkUI';

const DOMAIN = 0x0006;
const TAG = 'TextReaderView';

// 版式参照华为阅读：左右留白更宽，页眉小标题距顶更远，正文上下留白更大
const PAGE_LEFT_RIGHT = 30;
const HEADER_HEIGHT = 58;
const FOOTER_HEIGHT = 36;
const CONTENT_PAD = 16;
const VERTICAL_PAD_TOP = 8;
const VERTICAL_PAD_BOTTOM = 52;
const FOOTER_TEXT_SIZE = 11;
// 章标题：正文 * 1.25 加粗，下方留白
const TITLE_SCALE = 1.25;
const TITLE_GAP = 16;
// 左右分页：距端部不足 2 页时补章；窗口章数上限
const PAGE_WINDOW_MAX_CHAPTERS = 5;
const PAGE_LOAD_AHEAD = 2;
// 分页分片：每片最多推进多少页，片间让出主线程，长章节打开时界面不白屏卡死
const PAGINATE_SLICE_PAGES = 20;
// 首屏出字后预热相邻章分页缓存的延迟（避开首帧布局）
const PAGE_PREFETCH_NEXT_DELAY = 220;
const PAGE_PREFETCH_PREV_DELAY = 560;
// 点击分区：两侧 30% 翻页（左右模式翻页 / 上下模式翻屏），中间 40% 唤起控制栏
const TAP_SIDE_RATIO = 0.3;
// 选区锁时长（按下起算）：Text 开了 copyOption 后系统自带"双击选词"，
// 快速连点翻页正好构成双击。每次触摸按下都锁 400ms 并续锁：
// 双击第二下永远落在锁定期内不触发选择；长按需按住 500ms+，
// 按下 400ms 后锁已解除，长按选词不受影响
const SELECTION_LOCK_AFTER_DOWN = 400;
// 上下模式点击翻屏只滚可视高度的 90%，保留少量重叠便于衔接上下文
const TAP_SCROLL_RATIO = 0.9;
const TAP_SCROLL_DURATION = 240;
/**
 * 抬手抑制阈值（vp）：本次触摸位移超过该值就算拖动（翻页 / 下拉书签 / 滚动）。
 * 拖动之后的抬手不能被当成点击 —— 否则慢速翻页时抬手点会被"点击左右/中间区域"
 * 再判一次：落在两侧多翻一页（松手后倒退或前进两页），落在中间直接唤起控制栏
 * （表现为「每次翻页都弹出上下状态栏」）。
 */
const TAP_MOVE_SLOP = 8;
// 连续卷轴：初始窗口前后各 2 章；窗口常驻章数上限；距端部不足若干块时预加载相邻章
const WINDOW_RADIUS = 2;
const WINDOW_MAX_CHAPTERS = 8;
const LOAD_AHEAD_BLOCKS = 12;
// 长按选词菜单的自定义项 id（系统菜单项之外追加，复制/全选仍由系统提供）
const MENU_HIGHLIGHT = 'ireader_highlight';
const MENU_NOTE = 'ireader_note';
const MENU_DICT = 'ireader_dict';
// 回弹 / 补间时长（ms）
const FLIP_SETTLE_DURATION = 260;
// 点击翻页的整页卷曲时长（ms）
const FLIP_AUTO_DURATION = 460;
// 卷曲补间用的缓动（AnimateParam 不支持 onFrame，动画帧由组件自己驱动）
function easeOutCubic(t: number): number {
  return 1 - Math.pow(1 - t, 3);
}

function easeInOutCubic(t: number): number {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

// 折纸几何（参照华为阅读的仿真翻页）：整张纸绕折线翻折，是平面折叠，没有圆柱卷轴。
// 折线过手指点，倾角由起手点高度决定：
//   起手靠上 → 折线向右下倾，只折起右上角（看到一个书角）
//   起手居中 → 折线竖直，右边缘整条被折起（上下各一个书角）
//   起手靠下 → 折线向左下倾，只折起右下角
// 折线与竖直方向的最大夹角（弧度，约 26°）
const FOLD_MAX_ANGLE = 0.46;
// 纸张背面白化强度。必须接近不透明，否则底下的目标页会透上来，
// 与镜像反字叠成"两页文字重影"
const FOLD_BACK_ALPHA = 0.972;
// 折痕阴影强度与扩散宽度（占页宽比例）
const FOLD_SHADOW_ALPHA = 0.24;
const FOLD_SHADOW_SPREAD = 0.07;
// 整页（含页眉页脚）截图用的组件 id：仿真翻页要连页眉章节名、页脚时间进度一起翻
const FLIP_PAGE_ID = 'reader_flip_page_full';

@ComponentV2
struct ReaderFooter {
  @Param progressText: string = '';
  // 右侧章节进度：如 4/65章
  @Param chapterText: string = '';
  @Param badgeBg: string = '#00000000';
  @Param subTextColor: string = '#8C8C8C';
  // 页脚左侧时间与电量：由阅读设置控制，关闭时左侧留空
  @Param showClock: boolean = true;
  @Local clock: string = '';
  @Local battery: number = -1;

  private timer: number = -1;

  aboutToAppear(): void {
    this.clock = ReaderFooter.formatNow();
    this.battery = ReaderFooter.readBattery();
    this.timer = setInterval(() => {
      this.clock = ReaderFooter.formatNow();
      this.battery = ReaderFooter.readBattery();
    }, 30000);
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private static formatNow(): string {
    const now = new Date();
    const hours = now.getHours();
    const minutes = now.getMinutes();
    const hh = hours < 10 ? `0${hours}` : `${hours}`;
    const mm = minutes < 10 ? `0${minutes}` : `${minutes}`;
    return `${hh}:${mm}`;
  }

  private static readBattery(): number {
    try {
      const soc = batteryInfo.batterySOC;
      if (!Number.isFinite(soc) || soc < 0) {
        return -1;
      }
      return Math.round(soc);
    } catch (e) {
      return -1;
    }
  }

  build() {
    Row() {
      if (this.showClock) {
        Text(this.clock)
          .fontSize(FOOTER_TEXT_SIZE)
          .fontColor(this.subTextColor)
        if (this.battery >= 0) {
          Text(`${this.battery}`)
            .fontSize(9)
            .fontColor(this.subTextColor)
            .backgroundColor(this.badgeBg)
            .borderRadius(4)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .margin({ left: 6 })
        }
      }
      Blank()
      Text(this.chapterText.length > 0 ? this.chapterText : this.progressText)
        .fontSize(FOOTER_TEXT_SIZE)
        .fontColor(this.subTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(FOOTER_HEIGHT)
    .padding({ left: PAGE_LEFT_RIGHT, right: PAGE_LEFT_RIGHT, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }
}

@ComponentV2
export struct TextReaderView {
  // 当前章正文：左右模式的书签预览与父组件文案仍使用；分页改由 chapterTextProvider 按章取文
  @Param content: string = '';
  @Param chapterTitle: string = '';
  @Param startCharOffset: number = 0;
  @Param loadVersion: number = 0;
  @Monitor('loadVersion') onLoadVersionWatch(): void {
    this.onReload();
  }
  @Param chapterIndex: number = 0;

  @Param mode: ReadingMode = ReadingMode.VERTICAL;
  @Monitor('mode') onModeWatch(): void {
    this.onModeChanged();
  }
  @Param pageTurn: PageTurnMode = PageTurnMode.SLIDE;
  @Param fontSize: number = 18;
  @Monitor('fontSize') onFontSizeWatch(): void {
    this.onConfigChanged();
  }
  @Param lineHeightRatio: number = 1.7;
  @Monitor('lineHeightRatio') onLineHeightRatioWatch(): void {
    this.onConfigChanged();
  }
  @Param fontFamily: string = '';
  @Monitor('fontFamily') onFontFamilyWatch(): void {
    this.onConfigChanged();
  }
  @Param textAlignMode: TextAlignMode = TextAlignMode.AUTO;
  @Param chapterCount: number = 0;
  @Param bgColor: string = '#F7F3E8';
  @Param textColor: string = '#2B2B2B';
  @Param subTextColor: string = '#8C8C8C';
  @Param dividerColor: string = '#EFE7D8';
  @Param accentColor: string = '#8B5E3C';
  @Param accentTextColor: string = '#FFF8ED';
  // 页脚左侧显示时间与电量（阅读设置开关）
  @Param showFooterTime: boolean = true;
  // 控制栏显示时锁定翻页与滑动，避免误触
  @Param controlsVisible: boolean = false;

  // 划线 / 想法：按章取标注（父组件注入，内部按章分组缓存）；版本号变化时重建可见块刷新样式
  @Param annotationsVersion: number = 0;
  @Monitor('annotationsVersion') onAnnotationsVersionWatch(): void {
    this.onAnnotationsChanged();
  }
  @Param annotationBg: string = '#40E8B339';
  @Param annotationLine: string = '#C08A22';
  @Event annotationsOf: (chapterIndex: number) => Annotation[] = (chapterIndex: number): Annotation[] => [];
  @Event onToggleHighlight: (chapter: number, start: number, end: number, text: string) => void =
    (chapter: number, start: number, end: number, text: string): void => {};
  @Event onRequestNote: (chapter: number, start: number, end: number, text: string) => void =
    (chapter: number, start: number, end: number, text: string): void => {};
  @Event onLookup: (word: string) => void = (word: string): void => {};

  // 竖排连续卷轴：跳转目标（初始打开 / 目录 / 书签共用），jumpVersion 变化时重建窗口并定位
  @Param jumpVersion: number = 0;
  @Monitor('jumpVersion') onJumpVersionWatch(): void {
    this.onJump();
  }
  @Param jumpChapter: number = 0;
  @Param jumpOffset: number = 0;

  // 按章取标题 / 取全文（父组件注入，复用其章节缓存与异步读盘）
  @Event chapterTitleOf: (index: number) => string = (index: number): string => '';
  @Event chapterTextProvider: (index: number) => Promise<string> =
    (index: number): Promise<string> => Promise.resolve('');

  @Event onProgress: (chapterIndex: number, charOffset: number, ratio: number) => void =
    (chapterIndex: number, charOffset: number, ratio: number): void => {};
  @Event onTap: () => void = (): void => {};
  // 定位动作完成后回调，父组件据此揭开翻章遮挡
  @Event onReady: () => void = (): void => {};

  // 左右模式：当前页索引与当前页所属章（页眉、页脚、目录高亮都以此为准）
  @Local currentPage: number = 0;
  @Local pagedChapter: number = 0;

  // 页窗口（Engine 层）：页序列 + 章级缓存 + 章范围
  private pageWindow: PageWindow = new PageWindow();
  // 页窗口重建序号，避免异步分页结果错位
  private pageSeq: number = 0;
  // 排版代次：字号 / 行距 / 视口尺寸变化时递增，用于作废进行中的增量分页
  private layoutEpoch: number = 0;
  private pagedReady: boolean = false;
  // 数据源重建 / 索引补偿期间抑制 onChange 的进度误报（结构变化会让 Swiper 先跳到 0 或旧索引）
  private pageSyncLock: boolean = false;
  private pageSyncTimer: number = -1;

  // 连续卷轴：可见章号（页脚显示）
  @Local currentChapter: number = 0;
  // 竖排：章标题块在屏幕内时收起顶部小标题，避免与大标题重复
  @Local headerSuppressed: boolean = false;

  // 块窗口（Engine 层）：块序列 + 章范围 + 章全文/块数
  private blockWindow: BlockWindow = new BlockWindow();
  // 窗口初始化/跳转序号，避免异步加载结果错位
  private windowSeq: number = 0;
  private verticalReady: boolean = false;

  private currentCharOffset: number = 0;
  private currentRatio: number = 0;
  private firstVisibleIndex: number = 0;
  // 竖排最近一次可见块区间：进度按中心块判定，补偿仍按首块
  private lastVisibleStart: number = 0;
  private lastVisibleEnd: number = 0;
  // 前插/头部回收后的锚点补偿：重新定位到该章该偏移的块，避免视觉跳变
  private anchorChapter: number = -1;
  private anchorOffset: number = 0;
  private lastWidth: number = 0;
  private lastHeight: number = 0;
  private lastReportTime: number = 0;
  // 程序性翻页的逻辑目标页：翻页动画最长 520ms，期间 Swiper 的 onChange 尚未回传新索引，
  // 快速连点时若仍以 currentPage 为基准，每次都算出同一个目标页导致只翻一页。
  // 动画落地（onChange 回传目标页）前，连点以该逻辑页为基准逐次累加
  private turnTargetPage: number = -1;
  private turnTargetAt: number = 0;
  // 触摸按下后的选区锁：锁定期内禁用文本选择（防双击选词），松手自解
  @Local selectionLocked: boolean = false;
  private selectionUnlockTimer: number = -1;
  // 本次触摸的按下点（窗口坐标）与"拖动过"标记：据此过滤掉拖动之后的误点击（见 TAP_MOVE_SLOP）
  private touchDownX: number = 0;
  private touchDownY: number = 0;
  private tapSuppressed: boolean = false;
  private restoreTimer: number = -1;
  private readyTimer: number = -1;
  // 竖排定位：数据源变化后，在 List 完成布局（onScrollIndex 首次回调）时滚动到目标块
  private pendingScrollIndex: number = -1;
  private pendingScrollAlign: ScrollAlign = ScrollAlign.START;
  private verticalScroller: Scroller = new Scroller();
  private swiperController: SwiperController = new SwiperController();
  // 一次性延时任务句柄：页面销毁时统一取消，避免回调操作已释放的 Scroller / SwiperController
  private pendingTimers: number[] = [];

  // ===== 仿真翻页（卷曲）=====
  // 进度与方向是视觉层的唯一输入；位图为空时视觉层整层不绘制，直接看真实页面
  @Local flipProgress: number = 0;
  @Local flipDirection: number = 1;
  // 位图刻意不进状态系统：@Local 会给对象套观察代理，而 PixelMap 是 Native 对象，
  // 被代理后 CanvasRenderingContext2D.drawImage 会静默失败（表现就是"卷曲完全没效果"）。
  // 因此位图走普通字段传递，另用一个计数驱动视觉层重绘。
  private flipPageImage: image.PixelMap | undefined = undefined;
  private flipTargetImage: image.PixelMap | undefined = undefined;
  // 卷曲直接画在本组件的 Canvas 上，不再走子组件：animateTo 的 onFrame 要在父组件里逐帧绘制，
  // 而 V2 的 @Monitor 在动画插值期间不会逐帧回调（只在赋值瞬间回调一次），
  // 隔着子组件传 @Param 会退化成「整段动画只画一帧」——现象是两页轻微重影后静止。
  // 单位必须与 PixelMap 一致（px）：drawImage 的源矩形取自位图像素坐标，
  // 而 CanvasRenderingContext2D 默认按 vp 计量，混用会把源区域缩到左上角一小块再拉伸
  private flipCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  // 位图实际像素尺寸：与画布尺寸可能差像素级，绘制时按比例换算源矩形
  private flipPageWidth: number = 0;
  private flipPageHeight: number = 0;
  private flipTargetWidth: number = 0;
  private flipTargetHeight: number = 0;
  // 起手点在整页中的高度（px）：决定折线倾角，进而决定折起哪个书角
  private flipAnchorY: number = 0;
  private flipCanvasReady: boolean = false;
  // 卷曲补间的帧定时器（-1 表示未运行）
  private flipTimerId: number = -1;
  // 手势状态机（Strategy 层）：只算方向与进度，不碰 UI
  private flipMachine: FlipStateMachine = new FlipStateMachine();
  // 补间动画进行中：期间拒绝新手势，避免两张位图交叉
  private flipBusy: boolean = false;
  // 目标页位图请求在途，防止每帧重复发起截图
  private flipTargetPending: boolean = false;

  /** 登记一次性延时任务，便于销毁时取消（替代散落的裸 setTimeout） */
  private scheduleOnce(task: () => void, delay: number): void {
    const timer = setTimeout(() => {
      const index = this.pendingTimers.indexOf(timer);
      if (index >= 0) {
        this.pendingTimers.splice(index, 1);
      }
      task();
    }, delay);
    this.pendingTimers.push(timer);
  }

  private clearPendingTimers(): void {
    for (let i = 0; i < this.pendingTimers.length; i++) {
      clearTimeout(this.pendingTimers[i]);
    }
    this.pendingTimers = [];
  }

  aboutToAppear(): void {
    if (this.mode === ReadingMode.HORIZONTAL) {
      this.reload(this.startCharOffset);
    }
    // 竖排等 onAreaChange 拿到尺寸后再初始化窗口
  }

  aboutToDisappear(): void {
    this.reportCurrent();
    // 仿真翻页的位图必须显式释放，否则每翻几页就漏两张
    this.stopFlipTimer();
    this.releaseFlipImages();
    // 作废进行中的异步窗口 / 分页 / 预取，否则销毁后仍会继续读盘与 measureTextSize
    this.windowSeq++;
    this.pageSeq++;
    this.layoutEpoch++;
    this.clearPendingTimers();
    if (this.selectionUnlockTimer !== -1) {
      clearTimeout(this.selectionUnlockTimer);
      this.selectionUnlockTimer = -1;
    }
    if (this.readyTimer !== -1) {
      clearTimeout(this.readyTimer);
      this.readyTimer = -1;
    }
    if (this.restoreTimer !== -1) {
      clearTimeout(this.restoreTimer);
      this.restoreTimer = -1;
    }
    if (this.pageSyncTimer !== -1) {
      clearTimeout(this.pageSyncTimer);
      this.pageSyncTimer = -1;
    }
  }

  private lineHeightValue(): number {
    return this.fontSize * this.lineHeightRatio;
  }

  private titleFontSize(): number {
    return Math.round(this.fontSize * TITLE_SCALE);
  }

  /** 对齐方式：自动对齐在中文下等同左对齐（跟随书写方向） */
  private textAlignValue(): TextAlign {
    if (this.textAlignMode === TextAlignMode.RIGHT) {
      return TextAlign.End;
    }
    if (this.textAlignMode === TextAlignMode.JUSTIFY) {
      return TextAlign.JUSTIFY;
    }
    return TextAlign.Start;
  }

  /** 翻页动画时长：无动效瞬时切换，仿真放慢让纸页感更明显 */
  private turnDuration(): number {
    if (this.pageTurn === PageTurnMode.NONE) {
      return 0;
    }
    if (this.pageTurn === PageTurnMode.SIMULATION) {
      return 520;
    }
    return 300;
  }

  private turnCurve(): Curve {
    return this.pageTurn === PageTurnMode.SIMULATION ? Curve.EaseInOut : Curve.EaseOut;
  }

  /** 仿真模式给页面加一层投影，滑动时两页之间有纸页层叠的明暗分界 */
  private pageShadow(): ShadowOptions {
    if (this.pageTurn === PageTurnMode.SIMULATION) {
      const options: ShadowOptions = {
        radius: 14,
        color: '#33000000',
        offsetX: -8,
        offsetY: 0
      };
      return options;
    }
    const none: ShadowOptions = {
      radius: 0,
      color: '#00000000'
    };
    return none;
  }

  private titleLineHeight(): number {
    return Math.round(this.fontSize * TITLE_SCALE * this.lineHeightRatio * 10) / 10;
  }

  /** 左右模式首页标题占用的估算高度（vp） */
  private titleBlockHeightOf(title: string): number {
    return title.length > 0 ? this.titleLineHeight() + TITLE_GAP : 0;
  }

  private contentWidth(): number {
    return Math.max(1, this.lastWidth - PAGE_LEFT_RIGHT * 2);
  }

  private pageContentHeight(): number {
    const safety = this.lineHeightValue() * 0.5;
    return Math.max(1, this.lastHeight - HEADER_HEIGHT - FOOTER_HEIGHT
      - CONTENT_PAD * 2 - safety);
  }

  /** 页脚只保留章序与章节进度百分比，不再显示页号 */
  private footerProgress(): string {
    let ratio = this.currentRatio;
    if (!Number.isFinite(ratio)) {
      ratio = 0;
    }
    if (ratio < 0) {
      ratio = 0;
    }
    if (ratio > 1) {
      ratio = 1;
    }
    const percent = Math.round(ratio * 100);
    if (this.chapterCount <= 0) {
      return this.currentChapter >= 0 ? `第 ${this.currentChapter + 1} 章 · ${percent}%` : `${percent}%`;
    }
    const current = this.currentChapter + 1;
    return `第 ${current}/${this.chapterCount} 章 · ${percent}%`;
  }

  /** 页眉章名：以当前页所属章为准，取不到时回退父组件下发的章名 */
  private headerTitle(): string {
    if (this.mode === ReadingMode.VERTICAL) {
      const chapter = this.currentChapter >= 0 ? this.currentChapter : this.chapterIndex;
      const title = this.chapterTitleOf(chapter);
      return title.length > 0 ? title : this.chapterTitle;
    }
    const title = this.chapterTitleOf(this.pagedChapter);
    return title.length > 0 ? title : this.chapterTitle;
  }

  /**
   * 顶部小标题显隐：章节首页已有大标题，不再重复小标题；
   * 竖排时章标题块滚进视野也收起，滚过去后再出现。
   */
  private headerVisible(): boolean {
    if (this.mode === ReadingMode.HORIZONTAL) {
      const item = this.pageWindow.source.itemAt(this.currentPage);
      if (item === undefined) {
        return true;
      }
      return item.pageIndex > 0;
    }
    return !this.headerSuppressed;
  }

  /** 页脚右侧：当前章/总章数，如 4/65章 */
  private footerChapter(): string {
    if (this.chapterCount <= 0) {
      return '';
    }
    const chapter = this.mode === ReadingMode.HORIZONTAL ? this.pagedChapter : this.currentChapter;
    const current = chapter + 1;
    if (current < 1) {
      return '';
    }
    return `${current}/${this.chapterCount}章`;
  }

  private onReload(): void {
    if (this.mode !== ReadingMode.HORIZONTAL) {
      return;
    }
    // 延迟一帧，确保同一批下发的 chapterIndex / startCharOffset 等 @Param 已全部更新
    this.scheduleOnce((): void => {
      this.reload(this.startCharOffset);
    }, 0);
  }

  /** 阅读方向切换：竖排重建窗口，左右以当前锚点重建页窗口 */
  private onModeChanged(): void {
    if (this.mode === ReadingMode.VERTICAL) {
      this.initWindow(this.currentChapter, this.currentCharOffset);
    } else {
      this.reload(this.currentCharOffset);
    }
  }

  /** 跳转（初始打开 / 目录 / 书签）：竖排重建窗口并定位到目标章 */
  private onJump(): void {
    if (this.mode !== ReadingMode.VERTICAL) {
      return;
    }
    // 延迟一帧再读目标，确保 jumpChapter / jumpOffset 等 @Param 已全部更新到位
    this.scheduleOnce((): void => {
      this.initWindow(this.jumpChapter, this.jumpOffset);
    }, 0);
  }

  /** 字号 / 行距变化：清空页缓存后按当前锚点重建页窗口并做无动画定位 */
  private onConfigChanged(): void {
    this.pageWindow.cacheClear();
    // 排版参数变了，进行中的分页结果全部作废
    this.layoutEpoch++;
    if (this.mode === ReadingMode.VERTICAL) {
      this.initWindow(this.currentChapter, this.currentCharOffset);
    } else {
      this.reload(this.currentCharOffset);
    }
  }

  /** 左右模式：以当前章 + 章内偏移重建跨章页窗口（连续卷轴不使用） */
  private reload(offset: number): void {
    let safeOffset = offset;
    if (safeOffset < 0) {
      safeOffset = 0;
    }
    // 左右模式下章号来自父组件的当前章
    this.currentChapter = this.chapterIndex;
    this.currentCharOffset = safeOffset;
    if (this.lastWidth <= 0 || this.lastHeight <= 0) {
      return;
    }
    this.initPageWindow(this.chapterIndex, safeOffset);
  }

  // ================= 连续卷轴 =================

  /** 重建窗口：以 centerChapter 为中心加载前后若干章，并定位到章内 charOffset */
  private async initWindow(centerChapter: number, charOffset: number): Promise<void> {
    if (this.chapterCount <= 0) {
      return;
    }
    this.windowSeq++;
    const seq = this.windowSeq;
    this.verticalReady = true;
    this.anchorChapter = -1;
    let start = centerChapter - WINDOW_RADIUS;
    if (start < 0) {
      start = 0;
    }
    let end = centerChapter + WINDOW_RADIUS;
    if (end > this.chapterCount - 1) {
      end = this.chapterCount - 1;
    }
    const indexes: number[] = [];
    const promises: Promise<string>[] = [];
    for (let i = start; i <= end; i++) {
      indexes.push(i);
      promises.push(this.chapterTextProvider(i));
    }
    const texts: string[] = await Promise.all(promises);
    if (seq !== this.windowSeq) {
      return;
    }
    this.blockWindow.reset(centerChapter, indexes, texts, (chapter: number): string => this.chapterTitleOf(chapter));
    this.currentChapter = centerChapter;
    this.currentCharOffset = charOffset;
    const index = this.blockWindow.findBlockIndex(centerChapter, charOffset);
    this.pendingScrollIndex = index >= 0 ? index : 0;
    this.pendingScrollAlign = ScrollAlign.START;
    this.firstVisibleIndex = this.pendingScrollIndex;
    this.lastVisibleStart = this.pendingScrollIndex;
    this.lastVisibleEnd = this.pendingScrollIndex;
    this.updateRatio(centerChapter, charOffset);
    // 双保险：数据源重置后若 List 可见索引未变、onScrollIndex 不触发，下一帧主动定位。
    // 必须等一帧布局（16ms）：setTimeout(0) 早于新数据项的挂载，scrollToIndex 会落在旧列表上
    // 被 clamp 到末尾，表现为「跳章后停在了更靠后的位置」。
    this.scheduleOnce((): void => {
      this.consumePendingScroll();
    }, 16);
    hilog.info(DOMAIN, TAG, 'initWindow center=%{public}d window=[%{public}d,%{public}d] blocks=%{public}d',
      centerChapter, this.blockWindow.startChapter, this.blockWindow.endChapter, this.blockWindow.totalCount());
  }

  /** 请求加载某一章（追加或前插），带去重与序号校验 */
  private requestChapter(chapter: number, prepend: boolean): void {
    if (chapter < 0 || chapter >= this.chapterCount) {
      return;
    }
    if (this.blockWindow.hasChapter(chapter) || this.blockWindow.isLoading(chapter)) {
      return;
    }
    this.blockWindow.markLoading(chapter);
    const seq = this.windowSeq;
    this.chapterTextProvider(chapter).then((text: string) => {
      this.blockWindow.clearLoading(chapter);
      if (seq !== this.windowSeq) {
        return;
      }
      if (prepend) {
        this.onChapterPrepend(chapter, text);
      } else {
        this.onChapterAppend(chapter, text);
      }
    }).catch(() => {
      this.blockWindow.clearLoading(chapter);
    });
  }

  private onChapterAppend(chapter: number, text: string): void {
    if (chapter !== this.blockWindow.endChapter + 1) {
      return;
    }
    this.blockWindow.append(chapter, text, this.chapterTitleOf(chapter));
    hilog.debug(DOMAIN, TAG, 'append chapter %{public}d blocks=%{public}d', chapter,
      this.blockWindow.blockCount(chapter));
  }

  private onChapterPrepend(chapter: number, text: string): void {
    if (chapter !== this.blockWindow.startChapter - 1) {
      return;
    }
    // 前插会把内容整体下移，先记录锚点，稍后补偿滚动位置
    this.captureAnchor();
    this.blockWindow.prepend(chapter, text, this.chapterTitleOf(chapter));
    // 前插把内容整体下移，必须立即补偿，否则会先闪一帧下移后的画面
    this.scheduleOnce((): void => {
      this.applyAnchorCompensation();
    }, 0);
    hilog.debug(DOMAIN, TAG, 'prepend chapter %{public}d blocks=%{public}d', chapter,
      this.blockWindow.blockCount(chapter));
  }

  /** 记录当前首个可见块作为锚点 */
  private captureAnchor(): void {
    const blocks = this.blockWindow.source.snapshot();
    const index = this.firstVisibleIndex;
    if (index < 0 || index >= blocks.length) {
      return;
    }
    const block = blocks[index];
    if (block === undefined) {
      return;
    }
    this.anchorChapter = block.chapterIndex;
    this.anchorOffset = block.kind === 'text' ? block.start : 0;
  }

  /** 滚动到窗口尾部/头部附近时预加载相邻章 */
  private maybeLoadMore(start: number, end: number): void {
    if (end >= this.blockWindow.source.totalCount() - LOAD_AHEAD_BLOCKS
      && this.blockWindow.endChapter < this.chapterCount - 1) {
      this.requestChapter(this.blockWindow.endChapter + 1, false);
    }
    if (start <= LOAD_AHEAD_BLOCKS && this.blockWindow.startChapter > 0) {
      this.requestChapter(this.blockWindow.startChapter - 1, true);
    }
  }

  /** 窗口章数超过上限时，回收离当前可见章更远的一端 */
  private maybeTrim(): void {
    const chapters = this.blockWindow.chapterCount();
    if (chapters <= WINDOW_MAX_CHAPTERS) {
      return;
    }
    const distanceHead = this.currentChapter - this.blockWindow.startChapter;
    const distanceTail = this.blockWindow.endChapter - this.currentChapter;
    if (distanceTail >= distanceHead) {
      // 回收尾部：不影响可见区
      this.blockWindow.removeTail();
    } else {
      // 回收头部：先记录锚点，删除后立即补偿，避免中间渲染一帧错位内容
      this.captureAnchor();
      this.blockWindow.removeHead();
      this.scheduleOnce((): void => {
        this.applyAnchorCompensation();
      }, 0);
    }
  }

  /** 更新整体比例（保留两位精度，供父组件算百分比） */
  private updateRatio(chapter: number, offset: number): void {
    const length = this.blockWindow.chapterText(chapter).length;
    const intra = length > 0 ? offset / length : 0;
    const total = this.chapterCount > 0 ? this.chapterCount : 1;
    this.currentRatio = (chapter + intra) / total;
  }

  /**
   * 按视口中心块判定当前章并更新进度。
   * 目录高亮与进度归属都以此为准；补偿定位仍用首可见块，避免定位偏半屏。
   */
  private updateProgressFromCenter(start: number, end: number): void {
    const total = this.blockWindow.source.totalCount();
    if (total <= 0) {
      return;
    }
    let center = Math.floor((start + end) / 2);
    if (center < 0) {
      center = 0;
    }
    if (center >= total) {
      center = total - 1;
    }
    this.updateProgressFromBlocks(center);
  }

  /** 根据某个块更新当前章 / 章内偏移，并降频上报 */
  private updateProgressFromBlocks(index: number): void {
    const blocks = this.blockWindow.source.snapshot();
    const block = blocks[index];
    if (block === undefined) {
      return;
    }
    const chapter = block.chapterIndex;
    const offset = block.kind === 'text' ? block.start : 0;
    this.currentChapter = chapter;
    this.currentCharOffset = offset;
    this.updateRatio(chapter, offset);
    const now = Date.now();
    if (now - this.lastReportTime > 400) {
      this.lastReportTime = now;
      this.reportCurrent();
    }
  }

  /**
   * 按已记录的锚点做无动画重定位。
   * 前插 / 头部回收都会让既有块索引整体位移，必须立即回到原锚点，
   * 否则会先渲染一帧错位内容再被 onScrollIndex 纠正。
   */
  private applyAnchorCompensation(): void {
    if (this.anchorChapter < 0) {
      return;
    }
    const index = this.blockWindow.findBlockIndex(this.anchorChapter, this.anchorOffset);
    this.anchorChapter = -1;
    if (index < 0) {
      return;
    }
    this.firstVisibleIndex = index;
    this.lastVisibleStart = index;
    this.lastVisibleEnd = index;
    this.verticalScroller.scrollToIndex(index, false, ScrollAlign.START);
    this.updateProgressFromBlocks(index);
  }

  /** 消费待定定位：滚到目标块并更新进度（onScrollIndex 与 initWindow 的下一帧补偿共用） */
  private consumePendingScroll(): void {
    if (this.pendingScrollIndex < 0) {
      return;
    }
    const target = this.pendingScrollIndex;
    const align = this.pendingScrollAlign;
    this.pendingScrollIndex = -1;
    this.firstVisibleIndex = target;
    this.lastVisibleStart = target;
    this.lastVisibleEnd = target;
    this.verticalScroller.scrollToIndex(target, false, align);
    this.updateProgressFromBlocks(target);
    this.signalReady();
  }

  /** 竖排滚动回调：先处理定位补偿，再更新进度、按需加载与回收 */
  private handleVerticalScroll(start: number, end: number): void {
    if (this.mode !== ReadingMode.VERTICAL) {
      return;
    }
    this.firstVisibleIndex = start;
    this.lastVisibleStart = start;
    this.lastVisibleEnd = end;
    // 章标题块滚进视野时收起顶部小标题，滚过去后再出现
    const titleOnScreen = this.blockWindow.hasKindBetween(start, end, 'title');
    if (titleOnScreen !== this.headerSuppressed) {
      this.headerSuppressed = titleOnScreen;
    }
    if (this.pendingScrollIndex >= 0) {
      this.consumePendingScroll();
      return;
    }
    if (this.anchorChapter >= 0) {
      this.applyAnchorCompensation();
      return;
    }
    this.updateProgressFromCenter(start, end);
    this.maybeLoadMore(start, end);
    this.maybeTrim();
  }

  /** 定位动作发出后再等一帧，确保新内容已渲染，再通知父组件揭开遮挡 */
  private signalReady(): void {
    if (this.readyTimer !== -1) {
      clearTimeout(this.readyTimer);
    }
    this.readyTimer = setTimeout(() => {
      this.readyTimer = -1;
      this.onReady();
    }, 0);
  }

  // ================= 左右分页：跨章页窗口 =================

  /**
   * 标记一次程序性数据源变更：期间 onChange 只同步索引，不上报进度、不触发窗口维护。
   * 覆盖两个渲染帧，避免结构变化引起的临时索引被当成用户翻页。
   */
  private beginPageSync(): void {
    this.pageSyncLock = true;
    if (this.pageSyncTimer !== -1) {
      clearTimeout(this.pageSyncTimer);
    }
    this.pageSyncTimer = setTimeout(() => {
      this.pageSyncTimer = -1;
      this.pageSyncLock = false;
    }, 48);
  }

  /**
   * 以 targetChapter + charOffset 为中心重建页窗口，并做无动画定位。
   *
   * 只先排当前章：长章节（几万字、上百页）不必等前后章一起排完就能出首屏，
   * 前后章交给 ensurePageWindow 在翻到端部时按需补，或由 prefetchNeighborPages 预热缓存。
   */
  private async initPageWindow(targetChapter: number, charOffset: number): Promise<void> {
    if (this.lastWidth <= 0 || this.lastHeight <= 0 || this.chapterCount <= 0) {
      return;
    }
    this.pageSeq++;
    const seq = this.pageSeq;
    // 新窗口开始：进行中的分页（旧窗口 / 旧参数）全部作废
    this.layoutEpoch++;
    let center = targetChapter;
    if (center < 0) {
      center = 0;
    }
    if (center >= this.chapterCount) {
      center = this.chapterCount - 1;
    }
    const t0 = Date.now();
    const items = await this.pagesOfChapterAsync(center);
    if (seq !== this.pageSeq || items.length === 0) {
      return;
    }
    this.pageWindow.reset(center, items);
    this.beginPageSync();
    this.turnTargetPage = -1;
    this.pagedReady = true;
    const index = this.findPageIndex(center, charOffset);
    this.currentPage = index >= 0 ? index : 0;
    this.pagedChapter = center;
    this.currentChapter = center;
    this.currentCharOffset = charOffset;
    this.updatePagedRatio(center, charOffset);
    this.restorePage();
    this.reportCurrent();
    hilog.info(DOMAIN, TAG, 'initPageWindow center=%{public}d pages=%{public}d cost=%{public}dms',
      center, items.length, Date.now() - t0);
    this.prefetchNeighborPages(center, seq);
  }

  /** 首屏出字后预热前后章的分页缓存，翻到章末时不必现场排版 */
  private prefetchNeighborPages(center: number, seq: number): void {
    const next = center + 1;
    if (next < this.chapterCount) {
      this.scheduleOnce((): void => {
        if (seq !== this.pageSeq) {
          return;
        }
        this.pagesOfChapterAsync(next).catch(() => {
        });
      }, PAGE_PREFETCH_NEXT_DELAY);
    }
    const prev = center - 1;
    if (prev >= 0) {
      this.scheduleOnce((): void => {
        if (seq !== this.pageSeq) {
          return;
        }
        this.pagesOfChapterAsync(prev).catch(() => {
        });
      }, PAGE_PREFETCH_PREV_DELAY);
    }
  }

  /**
   * 取某章的页（命中缓存直接复用）；排版参数变化后自动重算并写回缓存。
   *
   * 分页按片推进并让出主线程（见 PAGINATE_SLICE_PAGES），
   * 排版代次（layoutEpoch）变化时中途放弃，返回空数组由调用方忽略。
   */
  private async pagesOfChapterAsync(chapter: number): Promise<PagedItem[]> {
    const title = this.chapterTitleOf(chapter);
    const config = LayoutConfig.of(this.fontSize, this.lineHeightValue(), this.contentWidth(),
      this.pageContentHeight(), this.titleBlockHeightOf(title), this.fontFamily);
    const key = config.key();
    const cached = this.pageWindow.cacheGet(chapter, key);
    if (cached !== undefined) {
      return cached;
    }
    const epoch = this.layoutEpoch;
    const t0 = Date.now();
    const text = await this.chapterTextAsync(chapter);
    if (epoch !== this.layoutEpoch) {
      return [];
    }
    this.pageWindow.setChapterLength(chapter, text.length);
    const session = TextPaginator.createSession(this.getUIContext(), text, config);
    while (!session.isFinished()) {
      session.step(PAGINATE_SLICE_PAGES);
      if (session.isFinished()) {
        break;
      }
      await TextReaderView.yieldToUi();
      if (epoch !== this.layoutEpoch) {
        return [];
      }
    }
    const result = session.result();
    const items: PagedItem[] = [];
    for (let i = 0; i < result.ranges.length; i++) {
      const range = result.ranges[i];
      // pageStarts 与 ranges[i].start 恒等，这里取 pageStarts 作为「页首偏移」的权威值，
      // PageWindow 的二分查找与锚点定位都依赖它单调递增
      const start = i < result.pageStarts.length ? result.pageStarts[i] : range.start;
      items.push(PagedItem.of(chapter, i, text.substring(start, range.end), start));
    }
    if (items.length === 0) {
      items.push(PagedItem.of(chapter, 0, '', 0));
    }
    this.pageWindow.cachePut(chapter, key, items);
    hilog.info(DOMAIN, TAG, 'paginate chapter=%{public}d pages=%{public}d chars=%{public}d cost=%{public}dms',
      chapter, items.length, text.length, Date.now() - t0);
    return items;
  }

  /** 让出主线程一拍，供分片分页之间插入（保持渲染与触摸响应） */
  private static yieldToUi(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, 0);
    });
  }

  private chapterTextAsync(chapter: number): Promise<string> {
    if (chapter < 0 || chapter >= this.chapterCount) {
      return Promise.resolve('');
    }
    return this.chapterTextProvider(chapter);
  }

  /** 在当前窗口内找到「某章、某偏移」对应的页索引，找不到返回 -1 */
  private findPageIndex(chapter: number, offset: number): number {
    return this.pageWindow.findPageIndex(chapter, offset);
  }

  /** Swiper 换页：更新锚点与进度，并按需补章 / 回收远端章 */
  private handlePageChange(index: number): void {
    const total = this.pageWindow.source.totalCount();
    if (index < 0 || index >= total) {
      return;
    }
    // Swiper 动画落地到逻辑目标页：连点累加结束，翻页基准回归 currentPage
    if (index === this.turnTargetPage) {
      this.turnTargetPage = -1;
    }
    // 数据源重建 / 索引补偿期间，Swiper 会先落到临时索引，不能当成用户翻页
    if (this.pageSyncLock) {
      this.currentPage = index;
      return;
    }
    const item = this.pageWindow.source.itemAt(index);
    if (item === undefined) {
      return;
    }
    const changed = index !== this.currentPage || item.chapter !== this.pagedChapter
      || item.start !== this.currentCharOffset;
    this.currentPage = index;
    this.pagedChapter = item.chapter;
    this.currentChapter = item.chapter;
    this.currentCharOffset = item.start;
    this.updatePagedRatio(item.chapter, item.start);
    if (changed) {
      this.reportCurrent();
    }
    this.ensurePageWindow(index);
  }

  /** 与竖排同一套百分比：按章等权 + 章内字符比例，不依赖全书总页数 */
  private updatePagedRatio(chapter: number, offset: number): void {
    const cachedLength = this.pageWindow.chapterLength(chapter);
    const safeLength = cachedLength > 0 ? cachedLength : 1;
    let intra = offset / safeLength;
    if (intra < 0) {
      intra = 0;
    }
    if (intra > 1) {
      intra = 1;
    }
    const total = this.chapterCount > 0 ? this.chapterCount : 1;
    this.currentRatio = (chapter + intra) / total;
  }

  /** 距窗口两端不足若干页时补相邻章，章数超上限后回收远端章 */
  private ensurePageWindow(index: number): void {
    if (!this.pagedReady) {
      return;
    }
    const total = this.pageWindow.source.totalCount();
    if (index >= total - PAGE_LOAD_AHEAD && this.pageWindow.endChapter < this.chapterCount - 1) {
      this.appendNextChapter(this.pageWindow.endChapter + 1);
    }
    if (index <= PAGE_LOAD_AHEAD - 1 && this.pageWindow.startChapter > 0) {
      this.prependPrevChapter(this.pageWindow.startChapter - 1);
    }
    this.trimPageWindow(this.pagedChapter);
  }

  /** 尾部补章：不动既有索引 */
  private async appendNextChapter(chapter: number): Promise<void> {
    if (chapter < 0 || chapter >= this.chapterCount || chapter !== this.pageWindow.endChapter + 1) {
      return;
    }
    if (this.pageWindow.isLoading(chapter)) {
      return;
    }
    this.pageWindow.markLoading(chapter);
    const items = await this.pagesOfChapterAsync(chapter);
    this.pageWindow.clearLoading(chapter);
    // 异步期间窗口可能已被重建，校验后再插入；分页被作废时返回空数组
    if (chapter !== this.pageWindow.endChapter + 1 || items.length === 0) {
      return;
    }
    this.pageWindow.appendChapter(chapter, items);
    hilog.debug(DOMAIN, TAG, 'append chapter %{public}d pages=%{public}d', chapter, items.length);
    this.trimPageWindow(this.pagedChapter);
  }

  /** 头部补章：前插后必须无动画补偿当前页索引 */
  private async prependPrevChapter(chapter: number): Promise<void> {
    if (chapter < 0 || chapter >= this.chapterCount || chapter !== this.pageWindow.startChapter - 1) {
      return;
    }
    if (this.pageWindow.isLoading(chapter)) {
      return;
    }
    this.pageWindow.markLoading(chapter);
    const items = await this.pagesOfChapterAsync(chapter);
    this.pageWindow.clearLoading(chapter);
    if (chapter !== this.pageWindow.startChapter - 1 || items.length === 0) {
      return;
    }
    const before = this.currentPage;
    this.beginPageSync();
    const inserted = this.pageWindow.prependChapter(chapter, items);
    this.currentPage = before + inserted;
    this.swiperController.changeIndex(this.currentPage, false);
    hilog.debug(DOMAIN, TAG, 'prepend chapter %{public}d pages=%{public}d', chapter, items.length);
    this.trimPageWindow(this.pagedChapter);
  }

  /** 窗口章数超过上限时回收离当前页更远的一端，并补偿索引 */
  private trimPageWindow(chapter: number): void {
    if (this.pageWindow.chapterCount() <= PAGE_WINDOW_MAX_CHAPTERS) {
      return;
    }
    const distanceHead = chapter - this.pageWindow.startChapter;
    const distanceTail = this.pageWindow.endChapter - chapter;
    if (distanceTail >= distanceHead) {
      this.pageWindow.trimTail();
    } else {
      this.beginPageSync();
      const removed = this.pageWindow.trimHead();
      if (removed > 0) {
        this.currentPage = Math.max(0, this.currentPage - removed);
        this.swiperController.changeIndex(this.currentPage, false);
      }
    }
  }

  private restorePage(): void {
    if (this.restoreTimer !== -1) {
      clearTimeout(this.restoreTimer);
    }
    this.restoreTimer = setTimeout(() => {
      this.swiperController.changeIndex(this.currentPage, false);
      this.restoreTimer = -1;
      this.signalReady();
    }, 0);
  }

  private reportCurrent(): void {
    this.onProgress(this.currentChapter, this.currentCharOffset, this.currentRatio);
  }

  // ================= 长按选词：复制 / 划线 / 想法 / 词典 =================

  /**
   * 标注变化：只刷新可视区附近的项。
   * LazyForEach 不会因为外部普通状态变化重跑 item builder，
   * 必须显式 onDataChange 才能让划线即时显示（否则要退出重进）。
   */
  private onAnnotationsChanged(): void {
    if (this.mode === ReadingMode.VERTICAL) {
      this.blockWindow.source.refreshRange(this.lastVisibleStart - 1, this.lastVisibleEnd + 1);
    } else {
      this.pageWindow.source.refreshRange(this.currentPage - 1, this.currentPage + 1);
    }
  }

  /** 该块内是否有标注（没有则走纯文本快路径，不切 Span） */
  private hasAnnotation(chapter: number, baseStart: number, length: number): boolean {
    if (length <= 0) {
      return false;
    }
    const list = this.annotationsOf(chapter);
    const baseEnd = baseStart + length;
    for (let i = 0; i < list.length; i++) {
      if (list[i].intersects(baseStart, baseEnd)) {
        return true;
      }
    }
    return false;
  }

  private static menuItem(id: string, label: string): TextMenuItem {
    const item: TextMenuItem = {
      content: label,
      id: TextMenuItemId.of(id)
    };
    return item;
  }

  /**
   * 选词菜单：系统默认项（复制 / 全选）保留，追加三项自定义动作。
   * onMenuItemClick 直接带回选中区间，省掉自己维护选区状态的麻烦。
   */
  private selectionMenu(chapter: number, baseStart: number, content: string): EditMenuOptions {
    const options: EditMenuOptions = {
      onCreateMenu: (items: Array<TextMenuItem>): Array<TextMenuItem> => {
        const result: Array<TextMenuItem> = [];
        for (let i = 0; i < items.length; i++) {
          result.push(items[i]);
        }
        result.push(TextReaderView.menuItem(MENU_HIGHLIGHT, '划线'));
        result.push(TextReaderView.menuItem(MENU_NOTE, '想法'));
        result.push(TextReaderView.menuItem(MENU_DICT, '词典'));
        return result;
      },
      onMenuItemClick: (item: TextMenuItem, range: TextRange): boolean => {
        return this.handleMenuItem(item, range, chapter, baseStart, content);
      }
    };
    return options;
  }

  private handleMenuItem(item: TextMenuItem, range: TextRange, chapter: number, baseStart: number,
    content: string): boolean {
    const rawStart = range.start !== undefined ? range.start : 0;
    const rawEnd = range.end !== undefined ? range.end : 0;
    if (rawEnd <= rawStart || rawStart < 0 || rawEnd > content.length) {
      return false;
    }
    const text = content.substring(rawStart, rawEnd);
    if (text.length === 0) {
      return false;
    }
    const start = baseStart + rawStart;
    const end = baseStart + rawEnd;
    if (item.id.equals(TextMenuItemId.of(MENU_HIGHLIGHT))) {
      this.onToggleHighlight(chapter, start, end, text);
      return true;
    }
    if (item.id.equals(TextMenuItemId.of(MENU_NOTE))) {
      this.onRequestNote(chapter, start, end, text);
      return true;
    }
    if (item.id.equals(TextMenuItemId.of(MENU_DICT))) {
      this.onLookup(text);
      return true;
    }
    return false;
  }

  /**
   * 正文块：可长按选词。无标注时直接用纯文本（快路径），
   * 有标注时切成 Span 片段分别加底色 / 下划线。
   * 注意 ForEach 的 key 里必须带上 annotationsVersion 的上下游依赖，
   * 标注变化时由 LazyForEach key 变化触发重建。
   */
  @Builder
  bodyText(content: string, baseStart: number, chapter: number) {
    if (this.hasAnnotation(chapter, baseStart, content.length)) {
      Text() {
        ForEach(SegmentBuilder.build(content, baseStart, this.annotationsOf(chapter)),
          (seg: TextSegment) => {
            Span(seg.text)
              .fontColor(this.textColor)
              .decoration({
                type: seg.underline ? TextDecorationType.Underline : TextDecorationType.None,
                color: this.annotationLine
              })
              .textBackgroundStyle({
                color: seg.highlight ? this.annotationBg : '#00000000',
                radius: 3
              })
          }, (seg: TextSegment) => seg.key)
      }
      .width('100%')
      .fontSize(this.fontSize)
      .lineHeight(this.lineHeightValue())
      .fontColor(this.textColor)
      .fontFamily(this.fontFamily)
      .textAlign(this.textAlignValue())
      .copyOption(this.selectionLocked ? CopyOptions.None : CopyOptions.LocalDevice)
      .editMenuOptions(this.selectionMenu(chapter, baseStart, content))
      .onTouch((event: TouchEvent) => {
        this.onBodyTouch(event);
      })
      .onClick((event: ClickEvent) => {
        this.handleTextTap(event);
      })
    } else {
      Text(content)
        .width('100%')
        .fontSize(this.fontSize)
        .lineHeight(this.lineHeightValue())
        .fontColor(this.textColor)
        .fontFamily(this.fontFamily)
        .textAlign(this.textAlignValue())
        .copyOption(this.selectionLocked ? CopyOptions.None : CopyOptions.LocalDevice)
        .editMenuOptions(this.selectionMenu(chapter, baseStart, content))
        .onTouch((event: TouchEvent) => {
          this.onBodyTouch(event);
        })
        .onClick((event: ClickEvent) => {
          this.handleTextTap(event);
        })
    }
  }

  // ================= 点击分区：两侧翻页 / 中间唤起控制栏 =================

  /**
   * 根容器单击：按当前模式分区。
   * - 左右模式：左侧 30% 上一页，右侧 30% 下一页，中间唤起控制栏。
   * - 上下模式：上侧 30% 上翻一屏，下侧 30% 下翻一屏，中间唤起控制栏。
   */
  private handleTap(event: ClickEvent): void {
    // 与 onTouch 记录的按下点统一用窗口坐标
    this.applyTap(event.windowX, event.windowY);
  }

  /**
   * 记录本次触摸的按下点与是否发生过拖动。
   * 根容器与正文各挂一份：正文的 onTouch 先到，父级也会收到冒泡，任一处置位即生效。
   * 坐标统一用窗口坐标，避免正文（相对自身）与根容器（相对容器）两套原点混算。
   */
  private trackTouchMove(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      const down: TouchObject | undefined = event.touches[0];
      if (down === undefined) {
        return;
      }
      this.touchDownX = down.windowX;
      this.touchDownY = down.windowY;
      return;
    }
    if (event.type !== TouchType.Move) {
      return;
    }
    const touch: TouchObject | undefined = event.touches[0];
    if (touch === undefined) {
      return;
    }
    if (Math.abs(touch.windowX - this.touchDownX) > TAP_MOVE_SLOP ||
      Math.abs(touch.windowY - this.touchDownY) > TAP_MOVE_SLOP) {
      this.tapSuppressed = true;
    }
  }

  /**
   * 拖动之后的抬手不是点击：只有"点击点离按下点很远"才丢弃。
   *
   * 不能只靠一个布尔标记：拖动后通常不会派发 onClick，标记会残留到下一次点击，
   * 表现就是"翻完页点中间弹不出控制栏"。而每次点击的 Down 都会刷新按下点，
   * 因此"离按下点很近"就说明这是一次独立的新点击，必须正常处理。
   */
  private consumeTapAfterDrag(x: number, y: number): boolean {
    if (!this.tapSuppressed) {
      return false;
    }
    this.tapSuppressed = false;
    return Math.abs(x - this.touchDownX) > TAP_MOVE_SLOP ||
      Math.abs(y - this.touchDownY) > TAP_MOVE_SLOP;
  }

  /**
   * 正文上的单击：可选中文本后，文字会吃掉根容器上的 onClick，
   * 所以每块正文自己也挂一份，坐标用窗口坐标（点击点相对自身的 x/y 不能用）。
   * 不做去抖：快速连点时每一击都应翻一页，双击选词已由触摸侧选区锁拦截。
   */
  private handleTextTap(event: ClickEvent): void {
    this.applyTap(event.windowX, event.windowY);
  }

  /**
   * 正文触摸：按下即锁定选区，400ms 后自动解除（快速连点时每次按下续锁）。
   * 挂在 onTouch 而不是 click 上：click 有 200ms 去抖会被吞掉导致续不上锁，
   * 而双击选词的第二下永远不会落在锁定期外 —— 双击触发不了选择；
   * 长按需要按住 500ms 以上，系统判定长按时锁已解除，长按选词不受影响。
   */
  private onBodyTouch(event: TouchEvent): void {
    // 正文也要记位移：翻页 / 下拉都在正文上起手，抬手点绝不能当成点击
    this.trackTouchMove(event);
    if (event.type !== TouchType.Down) {
      return;
    }
    this.selectionLocked = true;
    if (this.selectionUnlockTimer !== -1) {
      clearTimeout(this.selectionUnlockTimer);
    }
    this.selectionUnlockTimer = setTimeout(() => {
      this.selectionUnlockTimer = -1;
      this.selectionLocked = false;
    }, SELECTION_LOCK_AFTER_DOWN);
  }

  private applyTap(x: number, y: number): void {
    // 拖动翻页 / 下拉书签 / 滚动之后的抬手不是点击：否则会在刚翻完的页上再判一次分区
    if (this.consumeTapAfterDrag(x, y)) {
      return;
    }
    if (this.controlsVisible) {
      this.onTap();
      return;
    }
    if (this.mode === ReadingMode.HORIZONTAL) {
      const width = this.lastWidth > 0 ? this.lastWidth : 1;
      const ratio = x / width;
      if (ratio < TAP_SIDE_RATIO) {
        this.turnPage(-1);
        return;
      }
      if (ratio > 1 - TAP_SIDE_RATIO) {
        this.turnPage(1);
        return;
      }
      this.onTap();
      return;
    }
    const height = this.lastHeight > 0 ? this.lastHeight : 1;
    const ratio = y / height;
    if (ratio < TAP_SIDE_RATIO) {
      this.scrollScreen(-1);
      return;
    }
    if (ratio > 1 - TAP_SIDE_RATIO) {
      this.scrollScreen(1);
      return;
    }
    this.onTap();
  }

  // ================= 仿真翻页：手势 + 卷曲 =================

  /** 页组件 id：截图按 id 抓取，跨章窗口前插导致索引变化时按当前值实时取 */
  private pageComponentId(index: number): string {
    return `reader_page_${index}`;
  }

  private releaseImage(target: image.PixelMap | undefined): void {
    if (target === undefined) {
      return;
    }
    try {
      target.release();
    } catch (e) {
      // 位图可能已被系统回收，释放失败不影响后续
    }
  }

  private releaseFlipImages(): void {
    this.releaseImage(this.flipPageImage);
    this.releaseImage(this.flipTargetImage);
    this.flipPageImage = undefined;
    this.flipTargetImage = undefined;
    this.flipTargetPending = false;
  }

  /**
   * 抓当前整页位图（含页眉章节名与页脚时间/进度）。
   * 翻页层要盖住整个页面，所以抓的是整页容器而不是 Swiper 里那一页正文。
   */
  private captureFlipPage(allowRetry: boolean = true): void {
    this.getUIContext().getComponentSnapshot().get(FLIP_PAGE_ID)
      .then((pixelMap: image.PixelMap) => {
        this.releaseImage(this.flipPageImage);
        this.flipPageImage = pixelMap;
        const info = pixelMap.getImageInfoSync();
        this.flipPageWidth = info.size.width;
        this.flipPageHeight = info.size.height;
        this.drawFlipAt(this.flipProgress);
      })
      .catch((error: Error) => {
        hilog.warn(DOMAIN, TAG, 'capture page failed: %{public}s', JSON.stringify(error));
        // 跨章重建数据源时页节点可能还没挂上，补抓一次；手势已结束就不再补
        if (allowRetry) {
          this.scheduleOnce((): void => {
            if (this.flipMachine.isDragging() || this.flipBusy) {
              this.captureFlipPage(false);
            }
          }, 80);
        }
      });
  }

  /** 抓目标页位图；在途期间不重复发起（拖动每帧都会走到这里） */
  private captureFlipTarget(index: number, allowRetry: boolean = true): void {
    if (this.flipTargetPending || index < 0 || index >= this.pageWindow.source.totalCount()) {
      return;
    }
    this.flipTargetPending = true;
    this.getUIContext().getComponentSnapshot().get(this.pageComponentId(index))
      .then((pixelMap: image.PixelMap) => {
        this.flipTargetPending = false;
        this.releaseImage(this.flipTargetImage);
        this.flipTargetImage = pixelMap;
        const info = pixelMap.getImageInfoSync();
        this.flipTargetWidth = info.size.width;
        this.flipTargetHeight = info.size.height;
        this.drawFlipAt(this.flipProgress);
      })
      .catch((error: Error) => {
        this.flipTargetPending = false;
        hilog.warn(DOMAIN, TAG, 'capture target %{public}d failed: %{public}s', index, JSON.stringify(error));
        if (allowRetry) {
          this.scheduleOnce((): void => {
            if (this.flipMachine.isDragging() || this.flipBusy) {
              this.captureFlipTarget(index, false);
            }
          }, 80);
        }
      });
  }

  /**
   * 手势起点：状态机接管，只抓当前页；方向与目标页等首次位移再定。
   * anchorY 是起手点在正文区里的 y（vp，相对正文区顶部），换算成整页坐标后决定折线倾角。
   */
  private onFlipStart(anchorY: number = -1): void {
    if (!this.canSimulationFlip()) {
      return;
    }
    const bodyTop = vp2px(HEADER_HEIGHT);
    const bodyHeight = vp2px(this.lastHeight - HEADER_HEIGHT - FOOTER_HEIGHT);
    this.flipAnchorY = anchorY >= 0 ? bodyTop + vp2px(anchorY) : bodyTop + bodyHeight * 0.5;
    this.flipMachine.begin();
    this.flipProgress = 0;
    this.flipDirection = 1;
    this.flipTargetPending = false;
    this.releaseImage(this.flipTargetImage);
    this.flipTargetImage = undefined;
    this.captureFlipPage();
  }

  /**
   * 拖动中：位移交给状态机换算方向与进度。
   * 方向首次确定（或反转）时才抓目标页；位图没到之前视觉层不绘制，
   * 用户看到的是真实页面，所以首帧不会闪白，只是卷曲效果晚一两帧出现。
   */
  private onFlipUpdate(offsetX: number): void {
    if (!this.flipMachine.isDragging()) {
      // onActionStart 可能落在数据源重建的锁定窗口里被拒；拖动既已成立就补接一次，
      // 否则整个手势全程无效（用户感知为仿真翻页完全没反应）
      if (!this.canSimulationFlip()) {
        return;
      }
      this.onFlipStart();
    }
    const update: FlipUpdate = this.flipMachine.update(offsetX, this.lastWidth);
    if (!update.active) {
      return;
    }
    this.flipDirection = update.direction;
    if (update.needTarget) {
      this.captureFlipTarget(update.direction > 0 ? this.currentPage + 1 : this.currentPage - 1);
    }
    this.flipProgress = update.progress;
    this.drawFlipAt(update.progress);
  }

  /** 抬手：状态机按位移与速度判定翻满 / 回弹，补间结束后再真正切索引 */
  private onFlipEnd(velocityX: number): void {
    if (!this.flipMachine.isDragging()) {
      return;
    }
    const result: FlipEnd = this.flipMachine.end(velocityX);
    this.animateFlip(result.commit ? 1 : 0, FLIP_SETTLE_DURATION, easeOutCubic, (): void => {
      this.settleFlip(result.commit, result.direction);
    });
  }

  private onFlipCancel(): void {
    if (!this.flipMachine.isDragging()) {
      return;
    }
    this.flipMachine.cancel();
    this.animateFlip(0, FLIP_SETTLE_DURATION, easeOutCubic, (): void => {
      this.settleFlip(false, 1);
    });
  }

  /**
   * 画一帧折纸翻页（平面折叠，不是圆柱卷轴）。
   *
   * 整张纸沿一条折线翻折，折起的一侧绕折线做镜像贴在页面上，形成一个纸角：
   *   折线过"手指点" C = (手指 x, 起手点 y)，与竖直方向夹角 φ 由起手点高度决定：
   *     起手靠上 → 折线横向倾角大，只折起右上角（看到一个书角）
   *     起手居中 → 折线竖直，整条右边缘折起（上下各一个书角）
   *     起手靠下 → 只折起右下角
   *   起手点越靠上/下，另一个角的"完整度"越小，中途是连续过渡的。
   *
   * 折起的一侧 D = 矩形 ∩ 折线外侧半平面：那一侧的画面绕折线镜像后铺纸白当纸背，
   * 原来位置的画面则已经折走，露出下层目标页。所以整页（含页眉章节名、页脚时间进度）
   * 都跟着折起来，而不是只有中间正文在动。
   *
   * 向前翻只是把几何整体镜像（side = -1），不镜像画面本身，页眉页脚文字不会反写。
   */
  private drawFlipAt(progress: number): void {
    if (!this.flipCanvasReady) {
      return;
    }
    const ctx = this.flipCtx;
    const width = ctx.width;
    const height = ctx.height;
    if (!(width > 0) || !(height > 0)) {
      return;
    }
    ctx.clearRect(0, 0, width, height);
    if (progress <= 0.002) {
      return;
    }
    const page = this.flipPageImage;
    const target = this.flipTargetImage;
    if (page === undefined || target === undefined) {
      return;
    }
    const ratio = Math.min(1, progress);
    const bodyTop = vp2px(HEADER_HEIGHT);
    const side = this.flipDirection >= 0 ? 1 : -1;
    const anchor = Math.max(0, Math.min(height, this.flipAnchorY));
    // 起手点越靠上，折线越"平"，折起的就是上面的角
    const phi = (0.5 - anchor / height) * 2 * FOLD_MAX_ANGLE;
    const cx = side > 0 ? width * (1 - ratio) : width * ratio;
    const nx = side * Math.cos(phi);
    const ny = -Math.sin(phi);

    // 1) 目标页：整屏纸色打底，正文位图贴在页眉下方（目标页位图只含正文区）
    ctx.fillStyle = this.bgColor;
    ctx.fillRect(0, 0, width, height);
    if (this.flipTargetWidth > 0 && this.flipTargetHeight > 0) {
      ctx.drawImage(target, 0, 0, this.flipTargetWidth, this.flipTargetHeight,
        0, bodyTop, this.flipTargetWidth, this.flipTargetHeight);
    }

    // 2) 当前页正面：只画还没折起的一侧，折走的那侧露出目标页
    const keep = this.foldRegion(width, height, cx, anchor, -nx, -ny);
    if (keep.length >= 6) {
      ctx.save();
      this.pathPolygon(ctx, keep);
      ctx.clip();
      if (this.flipPageWidth > 0 && this.flipPageHeight > 0) {
        ctx.drawImage(page, 0, 0, this.flipPageWidth, this.flipPageHeight, 0, 0, width, height);
      }
      ctx.restore();
    }

    // 3) 折起的纸角
    this.drawFold(ctx, page, width, height, cx, anchor, phi, side);
  }

  /**
   * 折起部分：把折线外侧 D 内的画面绕折线镜像，铺上纸白当纸背，描一道纸边亮线。
   * 折线过 (cx, cy)；side = 1 折右侧，side = -1 折左侧。
   */
  private drawFold(ctx: CanvasRenderingContext2D, page: image.PixelMap, width: number,
    height: number, cx: number, cy: number, phi: number, side: number): void {
    const nx = side * Math.cos(phi);
    const ny = -Math.sin(phi);
    const dirX = side * Math.sin(phi);
    const dirY = Math.cos(phi);
    const polygon = this.foldRegion(width, height, cx, cy, nx, ny);
    if (polygon.length < 6) {
      return;
    }
    // 关于过 (cx, cy)、方向 (dirX, dirY) 的直线的反射矩阵
    const cos2 = dirX * dirX - dirY * dirY;
    const sin2 = 2 * dirX * dirY;
    const tx = cx - (cos2 * cx + sin2 * cy);
    const ty = cy - (sin2 * cx - cos2 * cy);

    // 纸角投影：先把纸角的形状带模糊地投下去，纸角才"立"得起来；
    // 这一层随后被不透明的纸背盖住，只留下外缘的柔和阴影
    ctx.save();
    ctx.transform(cos2, sin2, sin2, -cos2, tx, ty);
    ctx.shadowColor = 'rgba(16,13,8,0.28)';
    ctx.shadowBlur = Math.max(6, width * 0.016);
    ctx.shadowOffsetX = width * 0.005;
    ctx.shadowOffsetY = height * 0.005;
    ctx.fillStyle = 'rgba(16,13,8,0.5)';
    this.pathPolygon(ctx, polygon);
    ctx.fill();
    ctx.restore();

    ctx.save();
    ctx.beginPath();
    ctx.rect(0, 0, width, height);
    ctx.clip();
    ctx.transform(cos2, sin2, sin2, -cos2, tx, ty);
    this.pathPolygon(ctx, polygon);
    ctx.clip();
    if (this.flipPageWidth > 0 && this.flipPageHeight > 0) {
      ctx.drawImage(page, 0, 0, this.flipPageWidth, this.flipPageHeight, 0, 0, width, height);
    }
    // 纸背：接近不透明的纸白（比正面略暖一点，才看得出是背面），只透出极淡的反字
    ctx.fillStyle = `rgba(251,247,238,${FOLD_BACK_ALPHA})`;
    this.pathPolygon(ctx, polygon);
    ctx.fill();
    // 纸边亮线，让翻起的纸有厚度感
    ctx.strokeStyle = 'rgba(255,255,255,0.95)';
    ctx.lineWidth = Math.max(1, width * 0.0025);
    this.pathPolygon(ctx, polygon);
    ctx.stroke();
    ctx.restore();

    // 折痕阴影落在未折起的一侧，模拟纸角翘起后遮光
    this.drawFoldShadow(ctx, width, height, cx, cy, nx, ny);
  }

  /** 页面矩形被「相对折线外侧」半平面裁出的多边形（x,y 交错） */
  private foldRegion(width: number, height: number, cx: number, cy: number,
    nx: number, ny: number): number[] {
    const corners: number[] = [0, 0, width, 0, width, height, 0, height];
    const result: number[] = [];
    const count = corners.length / 2;
    for (let i = 0; i < count; i++) {
      const ax = corners[i * 2];
      const ay = corners[i * 2 + 1];
      const next = (i + 1) % count;
      const bx = corners[next * 2];
      const by = corners[next * 2 + 1];
      const sideA = (ax - cx) * nx + (ay - cy) * ny;
      const sideB = (bx - cx) * nx + (by - cy) * ny;
      if (sideA >= 0) {
        result.push(ax);
        result.push(ay);
      }
      if ((sideA > 0 && sideB < 0) || (sideA < 0 && sideB > 0)) {
        const k = sideA / (sideA - sideB);
        result.push(ax + (bx - ax) * k);
        result.push(ay + (by - ay) * k);
      }
    }
    return result;
  }

  private pathPolygon(ctx: CanvasRenderingContext2D, polygon: number[]): void {
    ctx.beginPath();
    for (let i = 0; i + 1 < polygon.length; i += 2) {
      if (i === 0) {
        ctx.moveTo(polygon[0], polygon[1]);
      } else {
        ctx.lineTo(polygon[i], polygon[i + 1]);
      }
    }
    ctx.closePath();
  }

  /** 折痕阴影：贴着折线、沿法向反方向衰减，只画在未折起的一侧 */
  private drawFoldShadow(ctx: CanvasRenderingContext2D, width: number, height: number,
    cx: number, cy: number, nx: number, ny: number): void {
    const keep = this.foldRegion(width, height, cx, cy, -nx, -ny);
    if (keep.length < 6) {
      return;
    }
    const spread = Math.max(6, width * FOLD_SHADOW_SPREAD);
    ctx.save();
    this.pathPolygon(ctx, keep);
    ctx.clip();
    const gradient = ctx.createLinearGradient(cx, cy, cx - nx * spread, cy - ny * spread);
    gradient.addColorStop(0, `rgba(24,20,12,${FOLD_SHADOW_ALPHA})`);
    gradient.addColorStop(0.45, `rgba(24,20,12,${FOLD_SHADOW_ALPHA * 0.35})`);
    gradient.addColorStop(1, 'rgba(24,20,12,0)');
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, width, height);
    ctx.restore();
  }

  /**
   * 卷曲补间：用 animateTo 的 onFrame 逐帧驱动绘制。
   * 闭包里仍写一次 flipProgress（保证动画有状态变更、onFrame 按帧回调），
   * 但画面完全由 onFrame 里的 drawFlipAt 决定，不依赖 @Monitor。
   */
  private animateFlip(to: number, duration: number, easing: (t: number) => number,
    done: () => void): void {
    const from = this.flipProgress;
    this.flipBusy = true;
    this.stopFlipTimer();
    const startTime = Date.now();
    let frames = 0;
    this.flipTimerId = setInterval((): void => {
      const elapsed = Date.now() - startTime;
      const ratio = elapsed >= duration ? 1 : elapsed / duration;
      this.drawFlipAt(from + (to - from) * easing(ratio));
      frames++;
      if (ratio >= 1) {
        this.stopFlipTimer();
        this.flipProgress = to;
        this.drawFlipAt(to);
        const spent = Date.now() - startTime;
        hilog.info(DOMAIN, TAG, 'flip done %{public}dms %{public}d frames ~%{public}d fps',
          spent, frames, Math.round(frames * 1000 / (spent > 0 ? spent : 1)));
        done();
      }
    }, 16);
  }

  private stopFlipTimer(): void {
    if (this.flipTimerId >= 0) {
      clearInterval(this.flipTimerId);
      this.flipTimerId = -1;
    }
  }


  /** 卷曲补间落地：清位图后按需切页（silent 切换，不再重播动画） */
  private settleFlip(commit: boolean, direction: number): void {
    this.flipBusy = false;
    this.flipProgress = 0;
    this.flipMachine.reset();
    this.releaseFlipImages();
    this.drawFlipAt(0);
    if (commit) {
      this.turnPage(direction, true);
    }
  }

  /**
   * 点击翻页的整页翻折：先抓两张位图再起补间。
   * 位图没就绪也照常推进（结束后照常切页），只是这一段看不到折纸效果。
   */
  private playFlipTo(target: number): void {
    const direction = target >= this.currentPage ? 1 : -1;
    this.flipBusy = true;
    this.flipDirection = direction;
    this.flipProgress = 0;
    // 点击翻页没有起手点，按页面中部折，得到"上下两个书角"的整页翻折
    this.flipAnchorY = vp2px(HEADER_HEIGHT + (this.lastHeight - HEADER_HEIGHT - FOOTER_HEIGHT) * 0.5);
    this.captureFlipPage();
    this.captureFlipTarget(target);
    this.scheduleOnce((): void => {
      this.animateFlip(1, FLIP_AUTO_DURATION, easeInOutCubic, (): void => {
        this.flipBusy = false;
        this.flipProgress = 0;
        this.flipMachine.reset();
        this.releaseFlipImages();
        this.drawFlipAt(0);
        this.swiperController.changeIndex(target, false);
        this.turnTargetPage = target;
        this.turnTargetAt = Date.now();
      });
    }, 90);
  }

  /** 仿真翻页的可用条件：横向分页、仿真模式、控制栏收起、无选区操作、无动画在跑 */
  private canSimulationFlip(): boolean {
    if (this.mode !== ReadingMode.HORIZONTAL) {
      return false;
    }
    if (this.pageTurn !== PageTurnMode.SIMULATION) {
      return false;
    }
    // 注意：这里不能看 selectionLocked —— 手指按下时正文的 onTouch 会先锁 400ms，
    // 而 PanGesture 的 onActionStart 正好落在这段时间内，一旦否决就再也接不上手势
    if (this.controlsVisible || this.flipBusy) {
      return false;
    }
    return !this.pageDragLocked();
  }

  /** 数据源重建窗口期不接手势，避免抓到错位页的位图 */
  private pageDragLocked(): boolean {
    return !this.pagedReady || this.pageSyncLock;
  }

  /**
   * 左右模式点击翻页。已在窗口端部时先补相邻章，补完后等补偿锁释放再翻，
   * 否则本次翻页会被 beginPageSync 的 48ms 锁吞掉。
   * 基准页用 turnTargetPage（动画未落地时是上一击的逻辑目标），
   * 保证快速连点时每一击各翻一页，不因 currentPage 迟迟不更新而重复翻同一页。
   * silent 为 true 表示调用方已播完自己的视觉（如手势卷曲），这里只切索引。
   */
  private async turnPage(delta: number, silent: boolean = false): Promise<void> {
    const total = this.pageWindow.source.totalCount();
    if (total === 0) {
      return;
    }
    const now = Date.now();
    const ttl = this.turnDuration() + 80;
    const base = this.turnTargetPage >= 0 && now - this.turnTargetAt < ttl
      ? this.turnTargetPage
      : this.currentPage;
    let target = base + delta;
    let needSync = false;
    if (target < 0) {
      if (this.pageWindow.startChapter <= 0 || base !== this.currentPage) {
        return;
      }
      await this.prependPrevChapter(this.pageWindow.startChapter - 1);
      target = this.currentPage - 1;
      needSync = true;
    } else if (target >= total) {
      if (this.pageWindow.endChapter >= this.chapterCount - 1 || base !== this.currentPage) {
        return;
      }
      await this.appendNextChapter(this.pageWindow.endChapter + 1);
      target = this.currentPage + 1;
      needSync = true;
    }
    const max = this.pageWindow.source.totalCount();
    if (target < 0 || target >= max) {
      return;
    }
    this.turnTargetPage = target;
    this.turnTargetAt = now;
    if (silent) {
      // 手势卷曲已播完，这里只落索引，不能再播一次动画
      this.swiperController.changeIndex(target, false);
      return;
    }
    if (this.pageTurn === PageTurnMode.SIMULATION) {
      // 卷曲动画进行中不排队：直接落索引，避免两张位图交叉叠画
      if (this.flipBusy) {
        this.swiperController.changeIndex(target, false);
        return;
      }
      this.playFlipTo(target);
      return;
    }
    const animated = this.pageTurn !== PageTurnMode.NONE;
    if (needSync) {
      this.scheduleOnce((): void => {
        this.swiperController.changeIndex(target, animated);
      }, 60);
    } else {
      this.swiperController.changeIndex(target, animated);
    }
  }

  /** 上下模式点击翻屏：按可视高度滚动一屏，跨章自然滚过章标题 */
  private scrollScreen(direction: number): void {
    if (this.lastHeight <= 0) {
      return;
    }
    const delta = this.lastHeight * TAP_SCROLL_RATIO * direction;
    this.getUIContext().animateTo({
      duration: TAP_SCROLL_DURATION,
      curve: Curve.EaseOut
    }, () => {
      this.verticalScroller.scrollBy(0, delta);
    });
  }

  @Builder
  header() {
    Row() {
      // 章节首页有大标题时不重复显示小标题，位置高度保持不变，避免正文跳动
      if (this.headerVisible()) {
        Text(this.headerTitle())
          .width('100%')
          .fontSize(12)
          .fontColor(this.subTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
      }
    }
    .width('100%')
    .height(HEADER_HEIGHT)
    .padding({ left: PAGE_LEFT_RIGHT, right: PAGE_LEFT_RIGHT, top: 30 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  verticalBody() {
    List({ scroller: this.verticalScroller }) {
      LazyForEach(this.blockWindow.source, (block: ReaderBlock, index: number) => {
        ListItem() {
          if (block.kind === 'title') {
            Text(block.text)
              .width('100%')
              .fontSize(this.titleFontSize())
              .fontWeight(FontWeight.Bold)
              .lineHeight(this.titleLineHeight())
              .fontFamily(this.fontFamily)
              .fontColor(this.textColor)
              .padding({ top: index === 0 ? 0 : TITLE_GAP * 2, bottom: TITLE_GAP })
          } else {
            this.bodyText(block.text, block.start, block.chapterIndex)
          }
        }
        .width('100%')
      }, (block: ReaderBlock, index: number) =>
        `${block.chapterIndex}_${block.kind}_${block.start}_${block.text.length}_${this.annotationsVersion}`)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: PAGE_LEFT_RIGHT,
      right: PAGE_LEFT_RIGHT,
      top: VERTICAL_PAD_TOP,
      bottom: VERTICAL_PAD_BOTTOM
    })
    .cachedCount(4)
    .scrollBar(BarState.Off)
    .enableScrollInteraction(!this.controlsVisible)
    .onScrollIndex((start: number, end: number) => {
      this.handleVerticalScroll(start, end);
    })
    .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
      this.updateProgressFromCenter(this.lastVisibleStart, this.lastVisibleEnd);
    })
    .onScrollStop(() => {
      this.reportCurrent();
    })
  }

  @Builder
  horizontalBody() {
    Swiper(this.swiperController) {
      LazyForEach(this.pageWindow.source, (item: PagedItem, index: number) => {
        Column() {
          // 每章第 0 页顶部渲染该章标题（分页时已扣减这部分高度）
          if (item.pageIndex === 0 && this.chapterTitleOf(item.chapter).length > 0) {
            Text(this.chapterTitleOf(item.chapter))
              .width('100%')
              .fontSize(this.titleFontSize())
              .fontWeight(FontWeight.Bold)
              .lineHeight(this.titleLineHeight())
              .fontFamily(this.fontFamily)
              .fontColor(this.textColor)
              .margin({ bottom: TITLE_GAP })
          }
          this.bodyText(item.text, item.start, item.chapter)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: PAGE_LEFT_RIGHT,
          right: PAGE_LEFT_RIGHT,
          top: CONTENT_PAD,
          bottom: CONTENT_PAD
        })
        .shadow(this.pageShadow())
        // 背景色必须画在页组件自己身上：仿真翻页按 id 截该组件，
        // 背景若留在父级 Stack 上，截出来的位图是透明的，两层叠加就变成"文字重影"
        .backgroundColor(this.bgColor)
        // 仿真翻页按 id 抓当前页 / 目标页位图（见 captureFlipPage）
        .id(this.pageComponentId(index))
      }, (item: PagedItem) => `${item.key}_${item.text.length}_${this.annotationsVersion}`)
    }
    .width('100%')
    .height('100%')
    .index(this.currentPage)
    .loop(false)
    .indicator(false)
    .cachedCount(1)
    .duration(this.turnDuration())
    .curve(this.turnCurve())
    // 仿真模式下滑动由 PanGesture 接管（跟手卷曲），Swiper 只负责索引切换
    .disableSwipe(this.controlsVisible || this.pageTurn === PageTurnMode.SIMULATION)
    .onChange((index: number) => {
      this.handlePageChange(index);
    })
  }

  build() {
    Stack() {
      Column() {
        this.header()

        Stack() {
          if (this.mode === ReadingMode.VERTICAL) {
            this.verticalBody()
          } else {
            this.horizontalBody()
          }
        }
        .width('100%')
        .layoutWeight(1)
        // parallelGesture 不抢子组件手势：Swiper 滑动（横滑模式）与长按选词仍按原逻辑工作
        .parallelGesture(
          PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
            .onActionStart((event: GestureEvent) => {
              const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
              this.onFlipStart(finger !== undefined ? finger.localY : -1);
            })
            .onActionUpdate((event: GestureEvent) => {
              this.onFlipUpdate(event.offsetX);
            })
            .onActionEnd((event: GestureEvent) => {
              this.onFlipEnd(event.velocityX);
            })
            .onActionCancel(() => {
              this.onFlipCancel();
            })
        )

        ReaderFooter({
          progressText: this.footerProgress(),
          chapterText: this.footerChapter(),
          badgeBg: this.dividerColor,
          subTextColor: this.subTextColor,
          showClock: this.showFooterTime
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.bgColor)
      // 仿真翻页按这个 id 抓整页位图（含页眉章节名与页脚时间/进度）
      .id(FLIP_PAGE_ID)
      .onAreaChange((oldValue: Area, newValue: Area) => {
      const width = Number.parseFloat(String(newValue.width));
      const height = Number.parseFloat(String(newValue.height));
      if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
        hilog.warn(DOMAIN, TAG, 'invalid area: %{public}s x %{public}s',
          String(newValue.width), String(newValue.height));
        return;
      }
      const firstLayout = this.lastWidth <= 0 || this.lastHeight <= 0;
      if (width !== this.lastWidth || height !== this.lastHeight) {
        this.lastWidth = width;
        this.lastHeight = height;
        if (this.mode === ReadingMode.VERTICAL) {
          if (firstLayout || !this.verticalReady) {
            this.initWindow(this.jumpChapter, this.jumpOffset);
          } else {
            this.initWindow(this.currentChapter, this.currentCharOffset);
          }
        } else {
          this.reload(this.currentCharOffset);
        }
      }
    })
    .onTouch((event: TouchEvent) => {
      this.trackTouchMove(event);
    })
    .onClick((event: ClickEvent) => {
      this.handleTap(event);
    })

      // 仿真翻页层：盖住整个页面（页眉页脚一起翻），不拦截触摸
      if (this.mode === ReadingMode.HORIZONTAL && this.pageTurn === PageTurnMode.SIMULATION) {
        Canvas(this.flipCtx)
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.None)
          .onReady(() => {
            this.flipCanvasReady = true;
            this.drawFlipAt(this.flipProgress);
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
  }
}
