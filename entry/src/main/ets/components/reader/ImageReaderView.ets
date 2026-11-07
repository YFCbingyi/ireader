import { ImageEntry, PageTurnMode, ReadingMode } from '../../model/BookModels';
import { AppPaths } from '../../utils/AppPaths';
import { ImageDataSource, ImagePage } from './ImageDataSource';
import { hilog } from '@kit.PerformanceAnalysisKit';

const MIN_SCALE = 0.2;
const MAX_SCALE = 3.0;
const LOG_DOMAIN = 0x0004;
const LOG_TAG = 'ImageReader';
// 连续卷轴：章标题块高度、初始窗口前后章数、窗口常驻章数上限、距端部不足若干块时预加载
const TITLE_BLOCK_HEIGHT = 46;
const WINDOW_RADIUS = 2;
const WINDOW_MAX_CHAPTERS = 8;
const LOAD_AHEAD_BLOCKS = 8;
// 左右分页：初始窗口前后各 1 章；距端部不足 2 页时补章；窗口章数上限
const PAGE_WINDOW_RADIUS = 1;
const PAGE_WINDOW_MAX_CHAPTERS = 5;
const PAGE_LOAD_AHEAD = 2;

/** 连续卷轴的图片块：章标题 或 单张图片 */
class ImageBlock {
  kind: string = '';
  chapterIndex: number = 0;
  title: string = '';
  image: ImageEntry | undefined = undefined;
  imageIndex: number = 0;

  static ofTitle(chapterIndex: number, title: string): ImageBlock {
    const block = new ImageBlock();
    block.kind = 'title';
    block.chapterIndex = chapterIndex;
    block.title = title;
    return block;
  }

  static ofImage(chapterIndex: number, imageIndex: number, image: ImageEntry): ImageBlock {
    const block = new ImageBlock();
    block.kind = 'image';
    block.chapterIndex = chapterIndex;
    block.imageIndex = imageIndex;
    block.image = image;
    return block;
  }
}

/** 跨章图片块数据源：整表重置 + 两端增量追加/回收 */
class ImageBlockSource implements IDataSource {
  private blocks: ImageBlock[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.blocks.length;
  }

  getData(index: number): ImageBlock {
    const block = this.blocks[index];
    return block !== undefined ? block : ImageBlock.ofTitle(0, '');
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

  snapshot(): ImageBlock[] {
    return this.blocks;
  }

  reset(blocks: ImageBlock[]): void {
    this.blocks = blocks;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  append(newBlocks: ImageBlock[]): void {
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

  prepend(newBlocks: ImageBlock[]): void {
    if (newBlocks.length === 0) {
      return;
    }
    const combined: ImageBlock[] = [];
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

@ComponentV2
export struct ImageReaderView {
  // 左右模式：当前章图片（连续卷轴不使用）
  @Param images: ImageEntry[] = [];
  @Param startIndex: number = 0;
  @Param startRatio: number = 0;
  @Param loadVersion: number = 0;
  @Monitor('loadVersion') onLoadVersionWatch(): void {
    this.onReload();
  }

  @Param mode: ReadingMode = ReadingMode.VERTICAL;
  @Monitor('mode') onModeWatch(): void {
    this.onConfigChanged();
  }
  @Param pageTurn: PageTurnMode = PageTurnMode.SLIDE;
  @Param chapterCount: number = 0;
  // 控制栏显示时锁定翻页、滑动与缩放，避免误触
  @Param controlsVisible: boolean = false;

  // 竖排连续卷轴：跳转目标（初始 / 目录 / 书签），jumpVersion 变化时重建窗口并定位
  @Param jumpVersion: number = 0;
  @Monitor('jumpVersion') onJumpVersionWatch(): void {
    this.onJump();
  }
  @Param jumpChapter: number = 0;
  @Param jumpIndex: number = 0;
  @Param jumpRatio: number = 0;

  // 按章取标题 / 图片（图片已在 manifest 内存中，同步返回）
  @Event chapterTitleOf: (index: number) => string = (index: number): string => '';
  @Event chapterImagesOf: (index: number) => ImageEntry[] = (index: number): ImageEntry[] => [];

  @Event onProgress: (chapterIndex: number, imageIndex: number, intraRatio: number) => void =
    (chapterIndex: number, imageIndex: number, intraRatio: number): void => {};
  @Event onTap: () => void = (): void => {};
  // 定位动作完成后回调，父组件据此揭开翻章遮挡
  @Event onReady: () => void = (): void => {};

  @Local flowScale: number = 1;
  @Local viewWidth: number = 0;
  @Local viewHeight: number = 0;
  @Local contentWidth: number = 1;
  @Local hOffset: number = 0;
  @Local currentIndex: number = 0;
  @Local swipeIndex: number = 0;
  // 左右模式页眉显示的章名（随页所属章更新）
  @Local pagedChapterTitle: string = '';
  @Local scaleHintVisible: boolean = false;
  @Local scaleHintText: string = '';

  // 竖排连续滚动：可见章与图片序号
  private currentChapter: number = 0;
  private currentImageIndex: number = 0;
  private intraRatio: number = 0;
  private lastMode: ReadingMode = ReadingMode.VERTICAL;
  private baseFlowScale: number = 1;
  private baseHOffset: number = 0;
  private anchorIndex: number = 0;
  private anchorRatio: number = 0;
  private isPinching: boolean = false;
  private lastReportTime: number = 0;
  private scaleHintTimer: number = -1;
  private restoreTimer: number = -1;

  private dataSource: ImageDataSource = new ImageDataSource();
  // 竖排连续卷轴数据
  private blockSource: ImageBlockSource = new ImageBlockSource();
  private blockHeights: number[] = [];
  private blockPrefix: number[] = [];
  private windowStart: number = 0;
  private windowEnd: number = -1;
  private chapterImages: Map<number, ImageEntry[]> = new Map();
  private chapterBlockCounts: Map<number, number> = new Map();
  private windowSeq: number = 0;
  private verticalReady: boolean = false;
  private firstVisibleBlock: number = 0;
  private pendingBlockIndex: number = -1;
  private pendingBlockRatio: number = 0;
  // 前插/头部回收后的锚点补偿
  private anchorBlockChapter: number = -1;
  private anchorBlockIndex: number = 0;
  private anchorBlockRatio: number = 0;

  private listScroller: Scroller = new Scroller();
  private swiperController: SwiperController = new SwiperController();
  // 左右模式页窗口：章范围、就绪标志、重建序号、程序性变更锁
  private pageWindowStart: number = -1;
  private pageWindowEnd: number = -1;
  private pagedReady: boolean = false;
  private pageSeq: number = 0;
  private pageSyncLock: boolean = false;
  private pageSyncTimer: number = -1;

  aboutToAppear(): void {
    this.lastMode = this.mode;
    if (this.mode === ReadingMode.HORIZONTAL) {
      this.reloadAt(this.jumpChapter, this.startIndex, this.startRatio);
    }
  }

  aboutToDisappear(): void {
    this.reportProgress();
    if (this.scaleHintTimer !== -1) {
      clearTimeout(this.scaleHintTimer);
      this.scaleHintTimer = -1;
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

  private onReload(): void {
    if (this.mode !== ReadingMode.HORIZONTAL) {
      return;
    }
    // 延迟一帧，确保同一批下发的 jumpChapter / startIndex 等 @Param 已全部更新
    setTimeout(() => {
      this.reloadAt(this.jumpChapter, this.startIndex, this.startRatio);
    }, 0);
  }

  private onConfigChanged(): void {
    if (this.mode !== this.lastMode) {
      const index = this.currentImageIndex;
      const ratio = this.intraRatio;
      this.lastMode = this.mode;
      this.flowScale = 1;
      this.hOffset = 0;
      if (this.mode === ReadingMode.VERTICAL) {
        this.initWindow(this.currentChapter, index, ratio);
      } else {
        this.reloadAt(this.currentChapter, index, ratio);
      }
    }
  }

  private onJump(): void {
    if (this.mode !== ReadingMode.VERTICAL) {
      return;
    }
    // 延迟一帧再读目标，确保 jumpChapter / jumpIndex / jumpRatio 等 @Param 已更新到位
    setTimeout(() => {
      this.initWindow(this.jumpChapter, this.jumpIndex, this.jumpRatio);
    }, 0);
  }

  /**
   * 标记一次程序性数据源变更：期间 onChange 只同步索引，不上报进度、不触发窗口维护。
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
   * 左右模式：以 centerChapter 为中心重建跨章图片页窗口（当前章 ±1），
   * 定位到章内第 imageIndex 张。不插章标题页，标题只出现在页眉。
   */
  private reloadAt(centerChapter: number, imageIndexValue: number, ratioValue: number): void {
    if (this.chapterCount <= 0) {
      return;
    }
    this.pageSeq++;
    let center = centerChapter;
    if (center < 0) {
      center = 0;
    }
    if (center >= this.chapterCount) {
      center = this.chapterCount - 1;
    }
    let start = center - PAGE_WINDOW_RADIUS;
    if (start < 0) {
      start = 0;
    }
    let end = center + PAGE_WINDOW_RADIUS;
    if (end > this.chapterCount - 1) {
      end = this.chapterCount - 1;
    }
    const pages: ImagePage[] = [];
    for (let c = start; c <= end; c++) {
      const chapterPages = this.pagesOfChapter(c);
      for (let i = 0; i < chapterPages.length; i++) {
        pages.push(chapterPages[i]);
      }
    }
    this.pageWindowStart = start;
    this.pageWindowEnd = end;
    this.beginPageSync();
    this.dataSource.reset(pages);
    this.pagedReady = true;
    let ratio = ratioValue;
    if (ratio < 0) {
      ratio = 0;
    }
    if (ratio > 1) {
      ratio = 1;
    }
    this.currentChapter = center;
    this.currentIndex = imageIndexValue;
    this.currentImageIndex = imageIndexValue;
    this.intraRatio = ratio;
    const index = this.findPageIndex(center, imageIndexValue);
    this.swipeIndex = index >= 0 ? index : 0;
    this.pagedChapterTitle = this.chapterTitleOf(center);
    this.restoreHorizontal();
    this.reportProgress();
    hilog.info(LOG_DOMAIN, LOG_TAG, 'reloadAt center=%{public}d window=[%{public}d,%{public}d] pages=%{public}d',
      center, start, end, pages.length);
  }

  /** 某章的全部图片页（图片已在 manifest 内存中，无需读盘） */
  private pagesOfChapter(chapter: number): ImagePage[] {
    const images = this.chapterImagesOf(chapter);
    this.chapterImages.set(chapter, images);
    const pages: ImagePage[] = [];
    for (let i = 0; i < images.length; i++) {
      pages.push(ImagePage.of(chapter, i, images[i]));
    }
    return pages;
  }

  /** 在当前窗口内找到「某章、第 imageIndex 张」对应的页索引 */
  private findPageIndex(chapter: number, imageIndexValue: number): number {
    const total = this.dataSource.totalCount();
    let target = -1;
    for (let i = 0; i < total; i++) {
      const page = this.dataSource.getData(i);
      if (page.chapter !== chapter) {
        continue;
      }
      if (target < 0) {
        target = i;
      }
      if (page.imageIndex >= imageIndexValue) {
        target = i;
        break;
      }
    }
    return target;
  }

  /** Swiper 换页：更新章与图序号，并按需补章 / 回收远端章 */
  private handlePageChange(index: number): void {
    const total = this.dataSource.totalCount();
    if (index < 0 || index >= total) {
      return;
    }
    if (this.pageSyncLock) {
      this.swipeIndex = index;
      return;
    }
    const page = this.dataSource.getData(index);
    const changed = index !== this.swipeIndex || page.chapter !== this.currentChapter
      || page.imageIndex !== this.currentImageIndex;
    this.swipeIndex = index;
    this.currentChapter = page.chapter;
    this.currentIndex = page.imageIndex;
    this.currentImageIndex = page.imageIndex;
    this.intraRatio = 0;
    if (changed) {
      this.pagedChapterTitle = this.chapterTitleOf(page.chapter);
      this.onProgress(page.chapter, page.imageIndex, 0);
    }
    this.ensurePageWindow(index);
  }

  /** 距窗口两端不足若干页时补相邻章，章数超上限后回收远端章 */
  private ensurePageWindow(index: number): void {
    if (!this.pagedReady) {
      return;
    }
    const total = this.dataSource.totalCount();
    if (index >= total - PAGE_LOAD_AHEAD && this.pageWindowEnd < this.chapterCount - 1) {
      this.appendChapterPages(this.pageWindowEnd + 1);
    }
    if (index <= PAGE_LOAD_AHEAD - 1 && this.pageWindowStart > 0) {
      this.prependChapterPages(this.pageWindowStart - 1);
    }
    this.trimPageWindow(this.currentChapter);
  }

  /** 尾部补章：跳过空章，不影响既有索引 */
  private appendChapterPages(chapter: number): void {
    let next = chapter;
    while (next >= 0 && next < this.chapterCount) {
      if (next !== this.pageWindowEnd + 1) {
        return;
      }
      const pages = this.pagesOfChapter(next);
      this.pageWindowEnd = next;
      if (pages.length > 0) {
        this.dataSource.appendChapter(pages);
        break;
      }
      next++;
    }
    this.trimPageWindow(this.currentChapter);
  }

  /** 头部补章：跳过空章；有实际前插时补偿当前页索引 */
  private prependChapterPages(chapter: number): void {
    let prev = chapter;
    while (prev >= 0) {
      if (prev !== this.pageWindowStart - 1) {
        return;
      }
      const pages = this.pagesOfChapter(prev);
      this.pageWindowStart = prev;
      if (pages.length > 0) {
        const before = this.swipeIndex;
        this.beginPageSync();
        this.dataSource.prependChapter(pages);
        this.swipeIndex = before + pages.length;
        this.swiperController.changeIndex(this.swipeIndex, false);
        break;
      }
      prev--;
    }
    this.trimPageWindow(this.currentChapter);
  }

  /** 窗口章数超过上限时回收离当前章更远的一端，并补偿索引 */
  private trimPageWindow(chapter: number): void {
    const chapters = this.pageWindowEnd - this.pageWindowStart + 1;
    if (chapters <= PAGE_WINDOW_MAX_CHAPTERS) {
      return;
    }
    const distanceHead = chapter - this.pageWindowStart;
    const distanceTail = this.pageWindowEnd - chapter;
    if (distanceTail >= distanceHead) {
      this.dataSource.removeTailChapter(this.pageWindowEnd);
      this.pageWindowEnd--;
    } else {
      this.beginPageSync();
      const removed = this.dataSource.removeHeadChapter(this.pageWindowStart);
      this.pageWindowStart++;
      if (removed > 0) {
        this.swipeIndex = Math.max(0, this.swipeIndex - removed);
        this.swiperController.changeIndex(this.swipeIndex, false);
      }
    }
  }

  // ================= 连续卷轴 =================

  /** 以 centerChapter 为中心加载前后若干章，并定位到章内第 imageIndex 张 */
  private initWindow(centerChapter: number, imageIndex: number, ratio: number): void {
    if (this.chapterCount <= 0) {
      return;
    }
    this.windowSeq++;
    this.verticalReady = true;
    this.anchorBlockChapter = -1;
    this.chapterImages.clear();
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
    const blocks: ImageBlock[] = [];
    for (let chapter = start; chapter <= end; chapter++) {
      const chapterBlocks = this.buildChapterBlocks(chapter);
      this.chapterBlockCounts.set(chapter, chapterBlocks.length);
      for (let i = 0; i < chapterBlocks.length; i++) {
        blocks.push(chapterBlocks[i]);
      }
    }
    this.blockSource.reset(blocks);
    this.rebuildBlockHeights();
    this.currentChapter = centerChapter;
    this.currentImageIndex = imageIndex;
    this.intraRatio = ratio;
    const index = this.findBlockIndex(centerChapter, imageIndex);
    this.pendingBlockIndex = index >= 0 ? index : 0;
    this.pendingBlockRatio = ratio;
    this.firstVisibleBlock = this.pendingBlockIndex;
    // 双保险：数据源重置后若 List 可见索引未变、onScrollIndex 不触发，下一帧主动定位
    setTimeout(() => {
      this.consumePendingBlock();
    }, 0);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'initWindow center=%{public}d window=[%{public}d,%{public}d] blocks=%{public}d',
      centerChapter, this.windowStart, this.windowEnd, blocks.length);
  }

  private buildChapterBlocks(chapter: number): ImageBlock[] {
    const blocks: ImageBlock[] = [];
    const images = this.chapterImagesOf(chapter);
    this.chapterImages.set(chapter, images);
    const title = this.chapterTitleOf(chapter);
    if (title.length > 0) {
      blocks.push(ImageBlock.ofTitle(chapter, title));
    }
    for (let i = 0; i < images.length; i++) {
      blocks.push(ImageBlock.ofImage(chapter, i, images[i]));
    }
    return blocks;
  }

  /**
   * 找到「某章、第 imageIndex 张」对应的块索引。
   *
   * 注意：不能一遇到标题块就返回，否则前插 / 头部回收 / 恢复进度时都会落到章首。
   * imageIndex <= 0 才视为章首（返回标题块）；超出本章图片数时落到最后一张。
   */
  private findBlockIndex(chapter: number, imageIndex: number): number {
    const blocks = this.blockSource.snapshot();
    let titleIndex = -1;
    let firstImageIndex = -1;
    let lastImageIndex = -1;
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
      if (firstImageIndex < 0) {
        firstImageIndex = i;
      }
      lastImageIndex = i;
      if (block.imageIndex >= imageIndex) {
        return i;
      }
    }
    if (imageIndex > 0 && lastImageIndex >= 0) {
      return lastImageIndex;
    }
    return titleIndex >= 0 ? titleIndex : firstImageIndex;
  }

  private rebuildBlockHeights(): void {
    const blocks = this.blockSource.snapshot();
    const width = this.itemWidth();
    const heights: number[] = [];
    const prefix: number[] = [];
    let sum = 0;
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      let height = TITLE_BLOCK_HEIGHT;
      if (block.kind === 'image' && block.image !== undefined) {
        const image = block.image;
        height = image.width > 0 ? width * image.height / image.width : width;
      }
      heights.push(height);
      prefix.push(sum);
      sum += height;
    }
    this.blockHeights = heights;
    this.blockPrefix = prefix;
    this.contentWidth = this.contentWidthValue();
    if (this.flowScale > 1) {
      this.hOffset = -(this.contentWidth - this.viewWidth) / 2;
    } else {
      this.hOffset = 0;
    }
  }

  private itemWidth(): number {
    return Math.max(1, this.viewWidth) * this.flowScale;
  }

  /** 图片块按原始宽高比换算显示高度 */
  private blockImageHeight(block: ImageBlock): number {
    if (block.image === undefined) {
      return this.itemWidth();
    }
    const width = this.itemWidth();
    return block.image.width > 0 ? width * block.image.height / block.image.width : width;
  }

  private contentWidthValue(): number {
    const base = Math.max(1, this.viewWidth);
    return this.flowScale > 1 ? base * this.flowScale : base;
  }

  /** 消费待定定位（onScrollIndex 与 initWindow 的下一帧补偿共用） */
  private consumePendingBlock(): void {
    if (this.pendingBlockIndex < 0) {
      return;
    }
    const target = this.pendingBlockIndex;
    const ratio = this.pendingBlockRatio;
    this.pendingBlockIndex = -1;
    this.pendingBlockRatio = 0;
    this.firstVisibleBlock = target;
    this.scrollToBlock(target, ratio);
    this.updateBlockProgress(target);
    this.onReady();
  }

  /** 竖排滚动回调：定位补偿 + 进度 + 按需加载/回收 */
  private handleBlockScroll(start: number, end: number): void {
    if (this.mode !== ReadingMode.VERTICAL) {
      return;
    }
    this.firstVisibleBlock = start;
    if (this.pendingBlockIndex >= 0) {
      this.consumePendingBlock();
      return;
    }
    if (this.anchorBlockChapter >= 0) {
      const index = this.findBlockIndex(this.anchorBlockChapter, this.anchorBlockIndex);
      this.anchorBlockChapter = -1;
      if (index >= 0) {
        this.firstVisibleBlock = index;
        this.scrollToBlock(index, this.anchorBlockRatio);
        this.updateBlockProgress(index);
        return;
      }
    }
    this.updateBlockProgress(start);
    this.maybeLoadMore(start, end);
    this.maybeTrim();
  }

  private scrollToBlock(index: number, ratio: number): void {
    this.listScroller.scrollToIndex(index, false, ScrollAlign.START);
    if (ratio > 0) {
      const height = index >= 0 && index < this.blockHeights.length ? this.blockHeights[index] : 0;
      if (height > 0) {
        this.listScroller.scrollBy(0, ratio * height);
      }
    }
  }

  /** 根据块索引更新当前章 / 图片序号 / 章内比例 */
  private updateBlockProgress(index: number): void {
    if (this.isPinching) {
      return;
    }
    const blocks = this.blockSource.snapshot();
    if (index < 0 || index >= blocks.length) {
      return;
    }
    const block = blocks[index];
    if (block.kind === 'image') {
      this.currentChapter = block.chapterIndex;
      this.currentImageIndex = block.imageIndex;
      const height = index < this.blockHeights.length ? this.blockHeights[index] : 0;
      const base = index < this.blockPrefix.length ? this.blockPrefix[index] : 0;
      if (height > 0) {
        const offset = this.listScroller.currentOffset().yOffset;
        let ratio = (offset - base) / height;
        if (ratio < 0) {
          ratio = 0;
        }
        if (ratio > 1) {
          ratio = 1;
        }
        this.intraRatio = ratio;
      } else {
        this.intraRatio = 0;
      }
    } else {
      this.currentChapter = block.chapterIndex;
      this.currentImageIndex = 0;
      this.intraRatio = 0;
    }
    const now = Date.now();
    if (now - this.lastReportTime > 400) {
      this.lastReportTime = now;
      this.reportProgress();
    }
  }

  private maybeLoadMore(start: number, end: number): void {
    if (end >= this.blockSource.totalCount() - LOAD_AHEAD_BLOCKS && this.windowEnd < this.chapterCount - 1) {
      this.appendChapter(this.windowEnd + 1);
    }
    if (start <= LOAD_AHEAD_BLOCKS && this.windowStart > 0) {
      this.prependChapter(this.windowStart - 1);
    }
  }

  private appendChapter(chapter: number): void {
    if (chapter < 0 || chapter >= this.chapterCount || this.chapterImages.has(chapter)) {
      return;
    }
    const blocks = this.buildChapterBlocks(chapter);
    this.chapterBlockCounts.set(chapter, blocks.length);
    this.blockSource.append(blocks);
    this.windowEnd = chapter;
    this.rebuildBlockHeights();
  }

  private prependChapter(chapter: number): void {
    if (chapter < 0 || chapter >= this.chapterCount || this.chapterImages.has(chapter)) {
      return;
    }
    this.captureAnchor();
    const blocks = this.buildChapterBlocks(chapter);
    this.chapterBlockCounts.set(chapter, blocks.length);
    this.blockSource.prepend(blocks);
    this.windowStart = chapter;
    this.rebuildBlockHeights();
  }

  private captureAnchor(): void {
    const blocks = this.blockSource.snapshot();
    const index = this.firstVisibleBlock;
    if (index < 0 || index >= blocks.length) {
      return;
    }
    const block = blocks[index];
    if (block === undefined) {
      return;
    }
    this.anchorBlockChapter = block.chapterIndex;
    this.anchorBlockIndex = block.kind === 'image' ? block.imageIndex : 0;
    const height = index < this.blockHeights.length ? this.blockHeights[index] : 0;
    const base = index < this.blockPrefix.length ? this.blockPrefix[index] : 0;
    if (height > 0) {
      const offset = this.listScroller.currentOffset().yOffset;
      let ratio = (offset - base) / height;
      if (ratio < 0) {
        ratio = 0;
      }
      if (ratio > 1) {
        ratio = 1;
      }
      this.anchorBlockRatio = ratio;
    } else {
      this.anchorBlockRatio = 0;
    }
  }

  private maybeTrim(): void {
    const chapters = this.windowEnd - this.windowStart + 1;
    if (chapters <= WINDOW_MAX_CHAPTERS) {
      return;
    }
    const distanceHead = this.currentChapter - this.windowStart;
    const distanceTail = this.windowEnd - this.currentChapter;
    if (distanceTail >= distanceHead) {
      const tailCount = this.chapterBlockCounts.get(this.windowEnd);
      const count = tailCount !== undefined ? tailCount : 0;
      this.chapterImages.delete(this.windowEnd);
      this.chapterBlockCounts.delete(this.windowEnd);
      this.blockSource.removeTail(count);
      this.windowEnd--;
    } else {
      this.captureAnchor();
      const headCount = this.chapterBlockCounts.get(this.windowStart);
      const count = headCount !== undefined ? headCount : 0;
      this.chapterImages.delete(this.windowStart);
      this.chapterBlockCounts.delete(this.windowStart);
      this.blockSource.removeHead(count);
      this.windowStart++;
    }
    this.rebuildBlockHeights();
  }

  private restoreHorizontal(): void {
    if (this.restoreTimer !== -1) {
      clearTimeout(this.restoreTimer);
    }
    this.restoreTimer = setTimeout(() => {
      this.swiperController.changeIndex(this.swipeIndex, false);
      this.restoreTimer = -1;
      this.onReady();
    }, 60);
  }

  private reportProgress(): void {
    this.onProgress(this.currentChapter, this.currentImageIndex, this.intraRatio);
  }

  private showScaleHint(): void {
    this.scaleHintText = `${this.flowScale.toFixed(2)}x`;
    this.scaleHintVisible = true;
    if (this.scaleHintTimer !== -1) {
      clearTimeout(this.scaleHintTimer);
    }
    this.scaleHintTimer = setTimeout(() => {
      this.scaleHintVisible = false;
      this.scaleHintTimer = -1;
    }, 1200);
  }

  private handlePinchStart(): void {
    if (this.mode !== ReadingMode.VERTICAL || this.controlsVisible) {
      return;
    }
    this.isPinching = true;
    this.baseFlowScale = this.flowScale;
    this.anchorIndex = this.currentImageIndex;
    this.anchorRatio = this.intraRatio;
    hilog.info(LOG_DOMAIN, LOG_TAG, 'pinch start scale=%{public}s index=%{public}d ratio=%{public}s',
      this.flowScale.toFixed(3), this.currentImageIndex, this.intraRatio.toFixed(3));
  }

  private handlePinchUpdate(scaleValue: number): void {
    if (this.mode !== ReadingMode.VERTICAL || this.controlsVisible) {
      return;
    }
    let next = this.baseFlowScale * scaleValue;
    if (next < MIN_SCALE) {
      next = MIN_SCALE;
    }
    if (next > MAX_SCALE) {
      next = MAX_SCALE;
    }
    this.flowScale = next;
    this.contentWidth = this.contentWidthValue();
    if (next > 1) {
      this.hOffset = -(this.contentWidth - this.viewWidth) / 2;
    } else {
      this.hOffset = 0;
    }
    this.showScaleHint();
  }

  private handlePinchEnd(): void {
    if (this.mode !== ReadingMode.VERTICAL || this.controlsVisible) {
      return;
    }
    this.isPinching = false;
    this.rebuildBlockHeights();
    this.currentImageIndex = this.anchorIndex;
    this.intraRatio = this.anchorRatio;
    const index = this.findBlockIndex(this.currentChapter, this.anchorIndex);
    this.pendingBlockIndex = index >= 0 ? index : 0;
    this.pendingBlockRatio = this.anchorRatio;
    this.firstVisibleBlock = this.pendingBlockIndex;
    this.reportProgress();
    hilog.info(LOG_DOMAIN, LOG_TAG, 'pinch end scale=%{public}s index=%{public}d ratio=%{public}s',
      this.flowScale.toFixed(3), this.anchorIndex, this.anchorRatio.toFixed(3));
  }

  private applyHOffset(value: number): void {
    if (this.flowScale <= 1) {
      this.hOffset = 0;
      return;
    }
    const max = Math.max(0, this.contentWidth - this.viewWidth);
    let next = value;
    if (next > 0) {
      next = 0;
    }
    if (next < -max) {
      next = -max;
    }
    this.hOffset = next;
  }

  build() {
    Stack() {
      if (this.mode === ReadingMode.VERTICAL) {
        Stack({ alignContent: Alignment.TopStart }) {
          List({ scroller: this.listScroller }) {
            LazyForEach(this.blockSource, (block: ImageBlock, index: number) => {
              ListItem() {
                if (block.kind === 'title') {
                  Column() {
                    Text(block.title)
                      .width('100%')
                      .fontSize(20)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                      .textAlign(TextAlign.Center)
                      .padding({ left: 24, right: 24 })
                  }
                  .width('100%')
                  .height(TITLE_BLOCK_HEIGHT)
                  .justifyContent(FlexAlign.Center)
                } else if (block.image !== undefined) {
                  Row() {
                    Image(AppPaths.uri(block.image.file))
                      .width(this.itemWidth())
                      .height(this.blockImageHeight(block))
                      .objectFit(ImageFit.Contain)
                      .autoResize(true)
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                }
              }
              .width('100%')
            }, (block: ImageBlock, index: number) =>
              `${block.chapterIndex}_${block.kind}_${block.imageIndex}`)
          }
          .width(this.contentWidth)
          .height('100%')
          .scrollBar(BarState.Off)
          .cachedCount(3)
          .enableScrollInteraction(!this.controlsVisible)
          .translate({ x: this.hOffset, y: 0 })
          .onScrollIndex((start: number, end: number) => {
            this.handleBlockScroll(start, end);
          })
          .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
            this.updateBlockProgress(this.firstVisibleBlock);
          })
          .onScrollStop(() => {
            this.reportProgress();
          })

          if (this.scaleHintVisible) {
            Column() {
              Blank()
              Text(this.scaleHintText)
                .fontSize(13)
                .fontColor('#FFFFFF')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor('#80000000')
                .borderRadius(14)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.End)
            .alignItems(HorizontalAlign.Center)
            .padding({ bottom: 110 })
            .hitTestBehavior(HitTestMode.None)
          }
        }
        .width('100%')
        .height('100%')
        .clip(true)
        .parallelGesture(
          GestureGroup(GestureMode.Parallel,
            PinchGesture({ fingers: 2 })
              .onActionStart(() => {
                this.handlePinchStart();
              })
              .onActionUpdate((event: GestureEvent) => {
                this.handlePinchUpdate(event.scale);
              })
              .onActionEnd(() => {
                this.handlePinchEnd();
              }),
            PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
              .onActionStart(() => {
                if (this.controlsVisible) {
                  return;
                }
                this.baseHOffset = this.hOffset;
              })
              .onActionUpdate((event: GestureEvent) => {
                if (this.controlsVisible) {
                  return;
                }
                this.applyHOffset(this.baseHOffset + event.offsetX);
              })
          )
        )
      } else {
        Stack({ alignContent: Alignment.Top }) {
          Swiper(this.swiperController) {
            LazyForEach(this.dataSource, (page: ImagePage) => {
              Stack() {
                Image(AppPaths.uri(page.image.file))
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Contain)
                  .autoResize(true)
              }
              .width('100%')
              .height('100%')
              .backgroundColor(Color.Black)
            }, (page: ImagePage) => page.key)
          }
          .width('100%')
          .height('100%')
          .index(this.swipeIndex)
          .loop(false)
          .indicator(false)
          .duration(this.pageTurn === PageTurnMode.NONE ? 0 : 300)
          .disableSwipe(this.controlsVisible)
          .onChange((index: number) => {
            this.handlePageChange(index);
          })

          // 页眉：只显示当前页所属章名，章节第一页不额外插标题页
          if (this.pagedChapterTitle.length > 0) {
            Text(this.pagedChapterTitle)
              .width('100%')
              .fontSize(12)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Start)
              .padding({ left: 24, right: 24, top: 12 })
              .hitTestBehavior(HitTestMode.None)
          }
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width);
      const height = Number(newValue.height);
      if (width > 0 && height > 0 && (width !== this.viewWidth || height !== this.viewHeight)) {
        this.viewWidth = width;
        this.viewHeight = height;
        if (this.mode === ReadingMode.VERTICAL) {
          if (this.verticalReady && this.blockSource.totalCount() > 0) {
            // 尺寸变化（旋转/分屏）：按当前块重新定位，不重建窗口
            this.rebuildBlockHeights();
            const index = this.findBlockIndex(this.currentChapter, this.currentImageIndex);
            this.pendingBlockIndex = index >= 0 ? index : 0;
            this.pendingBlockRatio = this.intraRatio;
            this.firstVisibleBlock = this.pendingBlockIndex;
          } else {
            this.initWindow(this.jumpChapter, this.jumpIndex, this.jumpRatio);
          }
        }
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}
