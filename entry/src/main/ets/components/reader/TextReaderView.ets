import { hilog } from '@kit.PerformanceAnalysisKit';
import { ReadingMode } from '../../model/BookModels';
import { Annotation, SegmentBuilder, TextSegment } from '../../model/Annotation';
import { TextPaginator } from '../../service/TextPaginator';

const DOMAIN = 0x0006;
const TAG = 'TextReaderView';

const PAGE_LEFT_RIGHT = 24;
const HEADER_HEIGHT = 38;
const FOOTER_HEIGHT = 42;
const CONTENT_PAD = 12;
const VERTICAL_PAD_TOP = 24;
const VERTICAL_PAD_BOTTOM = 52;
const FOOTER_TEXT_SIZE = 11;
// 章标题：正文 * 1.25 加粗，下方留白
const TITLE_SCALE = 1.25;
const TITLE_GAP = 16;
// 竖排正文分块：每块约 600 字，滚动时只渲染可视区附近的块
const CHUNK_CHARS = 600;
const CHUNK_NEWLINE_SLACK = 160;
const PAGE_CACHE_LIMIT = 6;
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
// 正文点击去抖：双击选词会连发两次 click，200ms 内的第二次忽略
const TEXT_TAP_GUARD = 200;
// 上下模式点击翻屏只滚可视高度的 90%，保留少量重叠便于衔接上下文
const TAP_SCROLL_RATIO = 0.9;
const TAP_SCROLL_DURATION = 240;
// 连续卷轴：初始窗口前后各 2 章；窗口常驻章数上限；距端部不足若干块时预加载相邻章
const WINDOW_RADIUS = 2;
const WINDOW_MAX_CHAPTERS = 8;
const LOAD_AHEAD_BLOCKS = 12;
// 长按选词菜单的自定义项 id（系统菜单项之外追加，复制/全选仍由系统提供）
const MENU_HIGHLIGHT = 'ireader_highlight';
const MENU_NOTE = 'ireader_note';
const MENU_DICT = 'ireader_dict';

/** 左右分页的一页：带所属章与章内字符偏移，key 跨章唯一 */
class PagedItem {
  key: string = '';
  chapter: number = 0;
  pageIndex: number = 0;
  text: string = '';
  start: number = 0;

  static of(chapter: number, pageIndex: number, text: string, start: number): PagedItem {
    const item = new PagedItem();
    item.key = `${chapter}_${pageIndex}`;
    item.chapter = chapter;
    item.pageIndex = pageIndex;
    item.text = text;
    item.start = start;
    return item;
  }
}

/** 章节页缓存：排版参数变化时整条失效 */
class PagedChapter {
  key: string = '';
  items: PagedItem[] = [];

  static of(key: string, items: PagedItem[]): PagedChapter {
    const chapter = new PagedChapter();
    chapter.key = key;
    chapter.items = items;
    return chapter;
  }
}

/**
 * 跨章页数据源：支持整表重置，以及尾部追加章、头部前插章、两章端回收。
 * 前插会让既有页索引整体后移，调用方必须做索引补偿。
 */
class PagedSource implements IDataSource {
  private items: PagedItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): PagedItem {
    const item = this.items[index];
    return item !== undefined ? item : PagedItem.of(0, 0, '', 0);
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  itemAt(index: number): PagedItem | undefined {
    return this.items[index];
  }

  reset(newItems: PagedItem[]): void {
    this.items = newItems;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  /** 尾部追加一章的页：不影响既有索引 */
  appendChapter(newItems: PagedItem[]): void {
    if (newItems.length === 0) {
      return;
    }
    const startIndex = this.items.length;
    for (let i = 0; i < newItems.length; i++) {
      this.items.push(newItems[i]);
    }
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < newItems.length; j++) {
        listener.onDataAdd(startIndex + j);
      }
    }
  }

  /** 头部前插一章的页：既有页索引整体后移 newItems.length */
  prependChapter(newItems: PagedItem[]): void {
    if (newItems.length === 0) {
      return;
    }
    const combined: PagedItem[] = [];
    for (let i = 0; i < newItems.length; i++) {
      combined.push(newItems[i]);
    }
    for (let i = 0; i < this.items.length; i++) {
      combined.push(this.items[i]);
    }
    this.items = combined;
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < newItems.length; j++) {
        listener.onDataAdd(j);
      }
    }
  }

  chapterCountOf(chapter: number): number {
    let count = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].chapter === chapter) {
        count++;
      }
    }
    return count;
  }

  /** 移除整个头部的某一章，返回被移除的页数 */
  removeHeadChapter(chapter: number): number {
    const count = this.chapterCountOf(chapter);
    if (count <= 0) {
      return 0;
    }
    this.items.splice(0, count);
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < count; j++) {
        listener.onDataDelete(0);
      }
    }
    return count;
  }

  /** 移除整个尾部的某一章，返回被移除的页数 */
  removeTailChapter(chapter: number): number {
    const count = this.chapterCountOf(chapter);
    if (count <= 0) {
      return 0;
    }
    const startIndex = this.items.length - count;
    this.items.splice(startIndex, count);
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < count; j++) {
        listener.onDataDelete(startIndex);
      }
    }
    return count;
  }

  /** 通知区间内的页内容变了（划线刷新），只重建这些项 */
  refreshRange(from: number, to: number): void {
    const total = this.items.length;
    if (total === 0) {
      return;
    }
    const start = from < 0 ? 0 : from;
    const end = to >= total ? total - 1 : to;
    for (let i = start; i <= end; i++) {
      for (let j = 0; j < this.listeners.length; j++) {
        this.listeners[j].onDataChange(i);
      }
    }
  }

  /** 某章在当前窗口内的起始页索引，不存在返回 -1 */
  chapterStartIndex(chapter: number): number {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].chapter === chapter) {
        return i;
      }
    }
    return -1;
  }
}

/** 连续卷轴的文本块：章标题 / 正文分块，带所属章节号 */
class ReaderBlock {
  kind: string = '';
  text: string = '';
  chapterIndex: number = 0;
  start: number = 0;
  end: number = 0;

  static of(kind: string, text: string, chapterIndex: number, start: number, end: number): ReaderBlock {
    const block = new ReaderBlock();
    block.kind = kind;
    block.text = text;
    block.chapterIndex = chapterIndex;
    block.start = start;
    block.end = end;
    return block;
  }
}

/** 跨章块数据源：支持整表重置，以及尾部追加 / 头部前插 / 两端回收的增量通知 */
class ReaderBlockSource implements IDataSource {
  private blocks: ReaderBlock[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.blocks.length;
  }

  getData(index: number): ReaderBlock {
    const block = this.blocks[index];
    return block !== undefined ? block : ReaderBlock.of('text', '', 0, 0, 0);
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 内部块数组只读视图，供组件计算锚点与进度 */
  snapshot(): ReaderBlock[] {
    return this.blocks;
  }

  reset(blocks: ReaderBlock[]): void {
    this.blocks = blocks;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  /** 尾部追加若干块 */
  append(newBlocks: ReaderBlock[]): void {
    if (newBlocks.length === 0) {
      return;
    }
    const startIndex = this.blocks.length;
    for (let i = 0; i < newBlocks.length; i++) {
      this.blocks.push(newBlocks[i]);
    }
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < newBlocks.length; j++) {
        listener.onDataAdd(startIndex + j);
      }
    }
  }

  /** 头部前插若干块（调用方需自行做滚动位置补偿） */
  prepend(newBlocks: ReaderBlock[]): void {
    if (newBlocks.length === 0) {
      return;
    }
    const combined: ReaderBlock[] = [];
    for (let i = 0; i < newBlocks.length; i++) {
      combined.push(newBlocks[i]);
    }
    for (let i = 0; i < this.blocks.length; i++) {
      combined.push(this.blocks[i]);
    }
    this.blocks = combined;
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < newBlocks.length; j++) {
        listener.onDataAdd(j);
      }
    }
  }

  /** 从头部移除 count 块 */
  removeHead(count: number): void {
    if (count <= 0 || this.blocks.length === 0) {
      return;
    }
    let removeCount = count;
    if (removeCount > this.blocks.length) {
      removeCount = this.blocks.length;
    }
    this.blocks.splice(0, removeCount);
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < removeCount; j++) {
        listener.onDataDelete(0);
      }
    }
  }

  /** 通知区间内的块内容变了（划线刷新），只重建这些项 */
  refreshRange(from: number, to: number): void {
    const total = this.blocks.length;
    if (total === 0) {
      return;
    }
    const start = from < 0 ? 0 : from;
    const end = to >= total ? total - 1 : to;
    for (let i = start; i <= end; i++) {
      for (let j = 0; j < this.listeners.length; j++) {
        this.listeners[j].onDataChange(i);
      }
    }
  }

  /** 从尾部移除 count 块 */
  removeTail(count: number): void {
    if (count <= 0 || this.blocks.length === 0) {
      return;
    }
    let removeCount = count;
    if (removeCount > this.blocks.length) {
      removeCount = this.blocks.length;
    }
    const startIndex = this.blocks.length - removeCount;
    this.blocks.splice(startIndex, removeCount);
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < removeCount; j++) {
        listener.onDataDelete(startIndex);
      }
    }
  }
}

@Component
struct ReaderFooter {
  @Prop progressText: string = '';
  @Prop subTextColor: string = '#8C8C8C';
  @State clock: string = '';

  private timer: number = -1;

  aboutToAppear(): void {
    this.clock = ReaderFooter.formatNow();
    this.timer = setInterval(() => {
      this.clock = ReaderFooter.formatNow();
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

  build() {
    Row() {
      Text(this.clock)
        .fontSize(FOOTER_TEXT_SIZE)
        .fontColor(this.subTextColor)
      Blank()
      Text(this.progressText)
        .fontSize(FOOTER_TEXT_SIZE)
        .fontColor(this.subTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(FOOTER_HEIGHT)
    .padding({ left: PAGE_LEFT_RIGHT, right: PAGE_LEFT_RIGHT, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct TextReaderView {
  // 当前章正文：左右模式的书签预览与父组件文案仍使用；分页改由 chapterTextProvider 按章取文
  @Prop content: string = '';
  @Prop chapterTitle: string = '';
  @Prop startCharOffset: number = 0;
  @Prop @Watch('onReload') loadVersion: number = 0;
  @Prop chapterIndex: number = 0;

  @Prop @Watch('onModeChanged') mode: ReadingMode = ReadingMode.VERTICAL;
  @Prop @Watch('onConfigChanged') fontSize: number = 18;
  @Prop @Watch('onConfigChanged') lineHeightRatio: number = 1.7;
  @Prop chapterCount: number = 0;
  @Prop bgColor: string = '#F7F3E8';
  @Prop textColor: string = '#2B2B2B';
  @Prop subTextColor: string = '#8C8C8C';
  @Prop accentColor: string = '#8B5E3C';
  @Prop accentTextColor: string = '#FFF8ED';
  // 控制栏显示时锁定翻页与滑动，避免误触
  @Prop controlsVisible: boolean = false;

  // 划线 / 想法：按章取标注（父组件注入，内部按章分组缓存）；版本号变化时重建可见块刷新样式
  @Prop @Watch('onAnnotationsChanged') annotationsVersion: number = 0;
  @Prop annotationBg: string = '#40E8B339';
  @Prop annotationLine: string = '#C08A22';
  annotationsOf: (chapterIndex: number) => Annotation[] = (chapterIndex: number): Annotation[] => [];
  onToggleHighlight: (chapter: number, start: number, end: number, text: string) => void =
    (chapter: number, start: number, end: number, text: string): void => {};
  onRequestNote: (chapter: number, start: number, end: number, text: string) => void =
    (chapter: number, start: number, end: number, text: string): void => {};
  onLookup: (word: string) => void = (word: string): void => {};

  // 竖排连续卷轴：跳转目标（初始打开 / 目录 / 书签共用），jumpVersion 变化时重建窗口并定位
  @Prop @Watch('onJump') jumpVersion: number = 0;
  @Prop jumpChapter: number = 0;
  @Prop jumpOffset: number = 0;

  // 按章取标题 / 取全文（父组件注入，复用其章节缓存与异步读盘）
  chapterTitleOf: (index: number) => string = (index: number): string => '';
  chapterTextProvider: (index: number) => Promise<string> =
    (index: number): Promise<string> => Promise.resolve('');

  onProgress: (chapterIndex: number, charOffset: number, ratio: number) => void =
    (chapterIndex: number, charOffset: number, ratio: number): void => {};
  onTap: () => void = (): void => {};
  // 定位动作完成后回调，父组件据此揭开翻章遮挡
  onReady: () => void = (): void => {};

  // 左右模式：当前页索引与当前页所属章（页眉、页脚、目录高亮都以此为准）
  @State currentPage: number = 0;
  @State pagedChapter: number = 0;

  private pageSource: PagedSource = new PagedSource();
  // 章级页缓存（章号 -> 该章页数组），排版参数变化时整条失效
  private pageCache: Map<number, PagedChapter> = new Map();
  private pageCacheKeys: number[] = [];
  // 当前页窗口的章范围
  private pageWindowStart: number = -1;
  private pageWindowEnd: number = -1;
  private loadingPageChapters: Set<number> = new Set();
  // 页窗口重建序号，避免异步分页结果错位
  private pageSeq: number = 0;
  // 排版代次：字号 / 行距 / 视口尺寸变化时递增，用于作废进行中的增量分页
  private layoutEpoch: number = 0;
  private chapterLengths: Map<number, number> = new Map();
  private pagedReady: boolean = false;
  // 数据源重建 / 索引补偿期间抑制 onChange 的进度误报（结构变化会让 Swiper 先跳到 0 或旧索引）
  private pageSyncLock: boolean = false;
  private pageSyncTimer: number = -1;

  // 连续卷轴：可见章号（页脚显示）
  @State currentChapter: number = 0;

  private blockSource: ReaderBlockSource = new ReaderBlockSource();
  private windowStart: number = 0;
  private windowEnd: number = -1;
  // 窗口内各章全文与块数
  private chapterTexts: Map<number, string> = new Map();
  private chapterBlockCounts: Map<number, number> = new Map();
  private loadingChapters: Set<number> = new Set();
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
  // 正文点击去抖时间戳（双击选词连发的第二次 click）
  private lastTextTapAt: number = 0;
  private restoreTimer: number = -1;
  private readyTimer: number = -1;
  // 竖排定位：数据源变化后，在 List 完成布局（onScrollIndex 首次回调）时滚动到目标块
  private pendingScrollIndex: number = -1;
  private pendingScrollAlign: ScrollAlign = ScrollAlign.START;
  private verticalScroller: Scroller = new Scroller();
  private swiperController: SwiperController = new SwiperController();

  aboutToAppear(): void {
    if (this.mode === ReadingMode.HORIZONTAL) {
      this.reload(this.startCharOffset);
    }
    // 竖排等 onAreaChange 拿到尺寸后再初始化窗口
  }

  aboutToDisappear(): void {
    this.reportCurrent();
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
    const title = this.chapterTitleOf(this.pagedChapter);
    return title.length > 0 ? title : this.chapterTitle;
  }

  private onReload(): void {
    if (this.mode !== ReadingMode.HORIZONTAL) {
      return;
    }
    // 延迟一帧，确保同一批下发的 chapterIndex / startCharOffset 等 @Prop 已全部更新
    setTimeout(() => {
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
    // 延迟一帧再读目标，确保 jumpChapter / jumpOffset 等 @Prop 已全部更新到位
    setTimeout(() => {
      this.initWindow(this.jumpChapter, this.jumpOffset);
    }, 0);
  }

  /** 字号 / 行距变化：清空页缓存后按当前锚点重建页窗口并做无动画定位 */
  private onConfigChanged(): void {
    this.pageCache.clear();
    this.pageCacheKeys = [];
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
    this.loadingChapters.clear();
    this.chapterTexts.clear();
    this.chapterBlockCounts.clear();
    let start = centerChapter - WINDOW_RADIUS;
    if (start < 0) {
      start = 0;
    }
    let end = centerChapter + WINDOW_RADIUS;
    if (end > this.chapterCount - 1) {
      end = this.chapterCount - 1;
    }
    this.windowStart = start;
    this.windowEnd = end;
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
    const blocks: ReaderBlock[] = [];
    for (let i = 0; i < indexes.length; i++) {
      const chapter = indexes[i];
      const text = i < texts.length ? texts[i] : '';
      this.chapterTexts.set(chapter, text);
      const chapterBlocks = this.buildChapterBlocks(chapter, text);
      this.chapterBlockCounts.set(chapter, chapterBlocks.length);
      for (let j = 0; j < chapterBlocks.length; j++) {
        blocks.push(chapterBlocks[j]);
      }
    }
    this.blockSource.reset(blocks);
    this.currentChapter = centerChapter;
    this.currentCharOffset = charOffset;
    const index = this.findBlockIndex(centerChapter, charOffset);
    this.pendingScrollIndex = index >= 0 ? index : 0;
    this.pendingScrollAlign = ScrollAlign.START;
    this.firstVisibleIndex = this.pendingScrollIndex;
    this.lastVisibleStart = this.pendingScrollIndex;
    this.lastVisibleEnd = this.pendingScrollIndex;
    this.updateRatio(centerChapter, charOffset);
    // 双保险：数据源重置后若 List 可见索引未变、onScrollIndex 不触发，下一帧主动定位
    setTimeout(() => {
      this.consumePendingScroll();
    }, 0);
    hilog.info(DOMAIN, TAG, 'initWindow center=%{public}d window=[%{public}d,%{public}d] blocks=%{public}d',
      centerChapter, this.windowStart, this.windowEnd, blocks.length);
  }

  /** 把一章切成 [章标题块] + [正文分块] */
  private buildChapterBlocks(chapter: number, text: string): ReaderBlock[] {
    const blocks: ReaderBlock[] = [];
    const title = this.chapterTitleOf(chapter);
    if (title.length > 0) {
      blocks.push(ReaderBlock.of('title', title, chapter, 0, 0));
    }
    let cursor = 0;
    while (cursor < text.length) {
      let end = Math.min(text.length, cursor + CHUNK_CHARS);
      if (end < text.length) {
        // 尽量在换行处断开，避免把一段切两半
        const newline = text.indexOf('\n', end);
        if (newline > 0 && newline - end < CHUNK_NEWLINE_SLACK) {
          end = newline + 1;
        }
      }
      blocks.push(ReaderBlock.of('text', text.substring(cursor, end), chapter, cursor, end));
      cursor = end;
    }
    return blocks;
  }

  /**
   * 在块列表里找到「某章、某偏移」所在的块索引。
   *
   * 注意：不能一遇到标题块就返回。标题块的 start/end 都是 0，若在此直接 return，
   * 任何一次锚点补偿（前插 / 头部回收 / 打开书恢复进度）都会落到该章标题，
   * 表现为"滚到章末又跳回章首"。
   *
   * - offset <= 0 视为章首，返回标题块（无标题则返回该章第一块正文）
   * - offset > 0 返回最后一个 start <= offset 的正文块（偏移超过章末时即最后一块，
   *   "上一章"按钮定位到章末依赖这一点）
   */
  private findBlockIndex(chapter: number, offset: number): number {
    const blocks = this.blockSource.snapshot();
    let titleIndex = -1;
    let firstTextIndex = -1;
    let matchedTextIndex = -1;
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      if (block.chapterIndex !== chapter) {
        continue;
      }
      if (block.kind === 'title') {
        if (titleIndex < 0) {
          titleIndex = i;
        }
        continue;
      }
      if (firstTextIndex < 0) {
        firstTextIndex = i;
      }
      if (block.start <= offset) {
        matchedTextIndex = i;
      }
    }
    if (offset <= 0) {
      return titleIndex >= 0 ? titleIndex : firstTextIndex;
    }
    if (matchedTextIndex >= 0) {
      return matchedTextIndex;
    }
    return titleIndex >= 0 ? titleIndex : firstTextIndex;
  }

  /** 请求加载某一章（追加或前插），带去重与序号校验 */
  private requestChapter(chapter: number, prepend: boolean): void {
    if (chapter < 0 || chapter >= this.chapterCount) {
      return;
    }
    if (this.chapterTexts.has(chapter) || this.loadingChapters.has(chapter)) {
      return;
    }
    this.loadingChapters.add(chapter);
    const seq = this.windowSeq;
    this.chapterTextProvider(chapter).then((text: string) => {
      this.loadingChapters.delete(chapter);
      if (seq !== this.windowSeq) {
        return;
      }
      if (prepend) {
        this.onChapterPrepend(chapter, text);
      } else {
        this.onChapterAppend(chapter, text);
      }
    }).catch(() => {
      this.loadingChapters.delete(chapter);
    });
  }

  private onChapterAppend(chapter: number, text: string): void {
    if (chapter !== this.windowEnd + 1) {
      return;
    }
    this.chapterTexts.set(chapter, text);
    const blocks = this.buildChapterBlocks(chapter, text);
    this.chapterBlockCounts.set(chapter, blocks.length);
    this.blockSource.append(blocks);
    this.windowEnd = chapter;
    hilog.debug(DOMAIN, TAG, 'append chapter %{public}d blocks=%{public}d', chapter, blocks.length);
  }

  private onChapterPrepend(chapter: number, text: string): void {
    if (chapter !== this.windowStart - 1) {
      return;
    }
    // 前插会把内容整体下移，先记录锚点，稍后补偿滚动位置
    this.captureAnchor();
    this.chapterTexts.set(chapter, text);
    const blocks = this.buildChapterBlocks(chapter, text);
    this.chapterBlockCounts.set(chapter, blocks.length);
    this.blockSource.prepend(blocks);
    this.windowStart = chapter;
    // 前插把内容整体下移，必须立即补偿，否则会先闪一帧下移后的画面
    setTimeout(() => {
      this.applyAnchorCompensation();
    }, 0);
    hilog.debug(DOMAIN, TAG, 'prepend chapter %{public}d blocks=%{public}d', chapter, blocks.length);
  }

  /** 记录当前首个可见块作为锚点 */
  private captureAnchor(): void {
    const blocks = this.blockSource.snapshot();
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
    if (end >= this.blockSource.totalCount() - LOAD_AHEAD_BLOCKS
      && this.windowEnd < this.chapterCount - 1) {
      this.requestChapter(this.windowEnd + 1, false);
    }
    if (start <= LOAD_AHEAD_BLOCKS && this.windowStart > 0) {
      this.requestChapter(this.windowStart - 1, true);
    }
  }

  /** 窗口章数超过上限时，回收离当前可见章更远的一端 */
  private maybeTrim(): void {
    const chapters = this.windowEnd - this.windowStart + 1;
    if (chapters <= WINDOW_MAX_CHAPTERS) {
      return;
    }
    const distanceHead = this.currentChapter - this.windowStart;
    const distanceTail = this.windowEnd - this.currentChapter;
    if (distanceTail >= distanceHead) {
      // 回收尾部：不影响可见区
      const tailCount = this.chapterBlockCounts.get(this.windowEnd);
      const count = tailCount !== undefined ? tailCount : 0;
      this.chapterTexts.delete(this.windowEnd);
      this.chapterBlockCounts.delete(this.windowEnd);
      this.blockSource.removeTail(count);
      this.windowEnd--;
    } else {
      // 回收头部：先记录锚点，删除后立即补偿，避免中间渲染一帧错位内容
      this.captureAnchor();
      const headCount = this.chapterBlockCounts.get(this.windowStart);
      const count = headCount !== undefined ? headCount : 0;
      this.chapterTexts.delete(this.windowStart);
      this.chapterBlockCounts.delete(this.windowStart);
      this.blockSource.removeHead(count);
      this.windowStart++;
      setTimeout(() => {
        this.applyAnchorCompensation();
      }, 0);
    }
  }

  /** 更新整体比例（保留两位精度，供父组件算百分比） */
  private updateRatio(chapter: number, offset: number): void {
    const text = this.chapterTexts.get(chapter);
    const length = text !== undefined ? text.length : 0;
    const intra = length > 0 ? offset / length : 0;
    const total = this.chapterCount > 0 ? this.chapterCount : 1;
    this.currentRatio = (chapter + intra) / total;
  }

  /**
   * 按视口中心块判定当前章并更新进度。
   * 目录高亮与进度归属都以此为准；补偿定位仍用首可见块，避免定位偏半屏。
   */
  private updateProgressFromCenter(start: number, end: number): void {
    const total = this.blockSource.totalCount();
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
    const blocks = this.blockSource.snapshot();
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
    const index = this.findBlockIndex(this.anchorChapter, this.anchorOffset);
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
    this.pageWindowStart = center;
    this.pageWindowEnd = center;
    this.loadingPageChapters.clear();
    this.beginPageSync();
    this.pageSource.reset(items);
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
      setTimeout(() => {
        if (seq !== this.pageSeq) {
          return;
        }
        this.pagesOfChapterAsync(next).catch(() => {
        });
      }, PAGE_PREFETCH_NEXT_DELAY);
    }
    const prev = center - 1;
    if (prev >= 0) {
      setTimeout(() => {
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
    const width = this.contentWidth();
    const height = this.pageContentHeight();
    const title = this.chapterTitleOf(chapter);
    const titleExtra = this.titleBlockHeightOf(title);
    const key = `${Math.round(width)}x${Math.round(height)}|${this.fontSize}|${this.lineHeightRatio}|${Math.round(titleExtra)}`;
    const cached = this.pageCache.get(chapter);
    if (cached !== undefined && cached.key === key) {
      this.touchPageCache(chapter);
      return cached.items;
    }
    const epoch = this.layoutEpoch;
    const t0 = Date.now();
    const text = await this.chapterTextAsync(chapter);
    if (epoch !== this.layoutEpoch) {
      return [];
    }
    this.chapterLengths.set(chapter, text.length);
    const session = TextPaginator.createSession(this.getUIContext(), text, width, height,
      this.fontSize, this.lineHeightValue(), titleExtra);
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
      items.push(PagedItem.of(chapter, i, text.substring(range.start, range.end), range.start));
    }
    if (items.length === 0) {
      items.push(PagedItem.of(chapter, 0, '', 0));
    }
    this.putPageCache(chapter, key, items);
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

  private putPageCache(chapter: number, key: string, items: PagedItem[]): void {
    if (this.pageCache.size >= PAGE_CACHE_LIMIT && this.pageCacheKeys.length > 0) {
      const oldest = this.pageCacheKeys.shift();
      if (oldest !== undefined) {
        this.pageCache.delete(oldest);
      }
    }
    this.pageCache.set(chapter, PagedChapter.of(key, items));
    this.pageCacheKeys.push(chapter);
  }

  /** 命中缓存时把章号移到队尾，实现 LRU 淘汰顺序 */
  private touchPageCache(chapter: number): void {
    const index = this.pageCacheKeys.indexOf(chapter);
    if (index >= 0) {
      this.pageCacheKeys.splice(index, 1);
      this.pageCacheKeys.push(chapter);
    }
  }

  /** 在当前窗口内找到「某章、某偏移」对应的页索引，找不到返回 -1 */
  private findPageIndex(chapter: number, offset: number): number {
    const total = this.pageSource.totalCount();
    let target = -1;
    for (let i = 0; i < total; i++) {
      const item = this.pageSource.itemAt(i);
      if (item === undefined || item.chapter !== chapter) {
        continue;
      }
      if (target < 0) {
        target = i;
      }
      if (item.start <= offset) {
        target = i;
      } else {
        break;
      }
    }
    return target;
  }

  /** Swiper 换页：更新锚点与进度，并按需补章 / 回收远端章 */
  private handlePageChange(index: number): void {
    const total = this.pageSource.totalCount();
    if (index < 0 || index >= total) {
      return;
    }
    // 数据源重建 / 索引补偿期间，Swiper 会先落到临时索引，不能当成用户翻页
    if (this.pageSyncLock) {
      this.currentPage = index;
      return;
    }
    const item = this.pageSource.itemAt(index);
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
    const length = this.chapterLengths.get(chapter);
    const safeLength = length !== undefined && length > 0 ? length : 1;
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
    const total = this.pageSource.totalCount();
    if (index >= total - PAGE_LOAD_AHEAD && this.pageWindowEnd < this.chapterCount - 1) {
      this.appendNextChapter(this.pageWindowEnd + 1);
    }
    if (index <= PAGE_LOAD_AHEAD - 1 && this.pageWindowStart > 0) {
      this.prependPrevChapter(this.pageWindowStart - 1);
    }
    this.trimPageWindow(this.pagedChapter);
  }

  /** 尾部补章：不动既有索引 */
  private async appendNextChapter(chapter: number): Promise<void> {
    if (chapter < 0 || chapter >= this.chapterCount || chapter !== this.pageWindowEnd + 1) {
      return;
    }
    if (this.loadingPageChapters.has(chapter)) {
      return;
    }
    this.loadingPageChapters.add(chapter);
    const items = await this.pagesOfChapterAsync(chapter);
    this.loadingPageChapters.delete(chapter);
    // 异步期间窗口可能已被重建，校验后再插入；分页被作废时返回空数组
    if (chapter !== this.pageWindowEnd + 1 || items.length === 0) {
      return;
    }
    this.pageSource.appendChapter(items);
    this.pageWindowEnd = chapter;
    hilog.debug(DOMAIN, TAG, 'append chapter %{public}d pages=%{public}d', chapter, items.length);
    this.trimPageWindow(this.pagedChapter);
  }

  /** 头部补章：前插后必须无动画补偿当前页索引 */
  private async prependPrevChapter(chapter: number): Promise<void> {
    if (chapter < 0 || chapter >= this.chapterCount || chapter !== this.pageWindowStart - 1) {
      return;
    }
    if (this.loadingPageChapters.has(chapter)) {
      return;
    }
    this.loadingPageChapters.add(chapter);
    const items = await this.pagesOfChapterAsync(chapter);
    this.loadingPageChapters.delete(chapter);
    if (chapter !== this.pageWindowStart - 1 || items.length === 0) {
      return;
    }
    const before = this.currentPage;
    this.beginPageSync();
    this.pageSource.prependChapter(items);
    this.pageWindowStart = chapter;
    this.currentPage = before + items.length;
    this.swiperController.changeIndex(this.currentPage, false);
    hilog.debug(DOMAIN, TAG, 'prepend chapter %{public}d pages=%{public}d', chapter, items.length);
    this.trimPageWindow(this.pagedChapter);
  }

  /** 窗口章数超过上限时回收离当前页更远的一端，并补偿索引 */
  private trimPageWindow(chapter: number): void {
    const chapters = this.pageWindowEnd - this.pageWindowStart + 1;
    if (chapters <= PAGE_WINDOW_MAX_CHAPTERS) {
      return;
    }
    const distanceHead = chapter - this.pageWindowStart;
    const distanceTail = this.pageWindowEnd - chapter;
    if (distanceTail >= distanceHead) {
      this.pageSource.removeTailChapter(this.pageWindowEnd);
      this.pageWindowEnd--;
    } else {
      this.beginPageSync();
      const removed = this.pageSource.removeHeadChapter(this.pageWindowStart);
      this.pageWindowStart++;
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
      this.blockSource.refreshRange(this.lastVisibleStart - 1, this.lastVisibleEnd + 1);
    } else {
      this.pageSource.refreshRange(this.currentPage - 1, this.currentPage + 1);
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
      .copyOption(CopyOptions.LocalDevice)
      .editMenuOptions(this.selectionMenu(chapter, baseStart, content))
      .onClick((event: ClickEvent) => {
        this.handleTextTap(event);
      })
    } else {
      Text(content)
        .width('100%')
        .fontSize(this.fontSize)
        .lineHeight(this.lineHeightValue())
        .fontColor(this.textColor)
        .copyOption(CopyOptions.LocalDevice)
        .editMenuOptions(this.selectionMenu(chapter, baseStart, content))
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
    this.applyTap(event.x, event.y);
  }

  /**
   * 正文上的单击：可选中文本后，文字会吃掉根容器上的 onClick，
   * 所以每块正文自己也挂一份，坐标用窗口坐标（点击点相对自身的 x/y 不能用）。
   * 双击选词会连发两次 click，这里做 200ms 去抖，避免"开了控制栏又马上关掉/连翻两页"。
   */
  private handleTextTap(event: ClickEvent): void {
    const now = Date.now();
    if (now - this.lastTextTapAt < TEXT_TAP_GUARD) {
      return;
    }
    this.lastTextTapAt = now;
    this.applyTap(event.windowX, event.windowY);
  }

  private applyTap(x: number, y: number): void {
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

  /**
   * 左右模式点击翻页。已在窗口端部时先补相邻章，补完后等补偿锁释放再翻，
   * 否则本次翻页会被 beginPageSync 的 48ms 锁吞掉。
   */
  private async turnPage(delta: number): Promise<void> {
    const total = this.pageSource.totalCount();
    if (total === 0) {
      return;
    }
    let target = this.currentPage + delta;
    let needSync = false;
    if (target < 0) {
      if (this.pageWindowStart <= 0) {
        return;
      }
      await this.prependPrevChapter(this.pageWindowStart - 1);
      target = this.currentPage - 1;
      needSync = true;
    } else if (target >= total) {
      if (this.pageWindowEnd >= this.chapterCount - 1) {
        return;
      }
      await this.appendNextChapter(this.pageWindowEnd + 1);
      target = this.currentPage + 1;
      needSync = true;
    }
    const max = this.pageSource.totalCount();
    if (target < 0 || target >= max) {
      return;
    }
    if (needSync) {
      setTimeout(() => {
        this.swiperController.changeIndex(target, true);
      }, 60);
      return;
    }
    this.swiperController.changeIndex(target, true);
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
      Text(this.headerTitle())
        .width('100%')
        .fontSize(12)
        .fontColor(this.subTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .height(HEADER_HEIGHT)
    .padding({ left: PAGE_LEFT_RIGHT, right: PAGE_LEFT_RIGHT, top: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  verticalBody() {
    List({ scroller: this.verticalScroller }) {
      LazyForEach(this.blockSource, (block: ReaderBlock, index: number) => {
        ListItem() {
          if (block.kind === 'title') {
            Text(block.text)
              .width('100%')
              .fontSize(this.titleFontSize())
              .fontWeight(FontWeight.Bold)
              .lineHeight(this.titleLineHeight())
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
      LazyForEach(this.pageSource, (item: PagedItem, index: number) => {
        Column() {
          // 每章第 0 页顶部渲染该章标题（分页时已扣减这部分高度）
          if (item.pageIndex === 0 && this.chapterTitleOf(item.chapter).length > 0) {
            Text(this.chapterTitleOf(item.chapter))
              .width('100%')
              .fontSize(this.titleFontSize())
              .fontWeight(FontWeight.Bold)
              .lineHeight(this.titleLineHeight())
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
      }, (item: PagedItem) => `${item.key}_${item.text.length}_${this.annotationsVersion}`)
    }
    .width('100%')
    .height('100%')
    .index(this.currentPage)
    .loop(false)
    .indicator(false)
    .cachedCount(1)
    .disableSwipe(this.controlsVisible)
    .onChange((index: number) => {
      this.handlePageChange(index);
    })
  }

  build() {
    Column() {
      // 竖排连续卷轴不再固定显示章名，左右分页保留页眉
      if (this.mode === ReadingMode.HORIZONTAL) {
        this.header()
      }

      Stack() {
        if (this.mode === ReadingMode.VERTICAL) {
          this.verticalBody()
        } else {
          this.horizontalBody()
        }
      }
      .width('100%')
      .layoutWeight(1)

      ReaderFooter({
        progressText: this.footerProgress(),
        subTextColor: this.subTextColor
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
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
    .onClick((event: ClickEvent) => {
      this.handleTap(event);
    })
  }
}
