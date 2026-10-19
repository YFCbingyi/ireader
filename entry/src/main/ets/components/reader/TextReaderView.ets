import { hilog } from '@kit.PerformanceAnalysisKit';
import { ReadingMode } from '../../model/BookModels';
import { PaginationResult, TextPaginator } from '../../service/TextPaginator';

const DOMAIN = 0x0006;
const TAG = 'TextReaderView';

const PAGE_LEFT_RIGHT = 24;
const HEADER_HEIGHT = 38;
const FOOTER_HEIGHT = 42;
const CONTENT_PAD_COMPACT = 12;
const CONTENT_PAD_TOP_EXPANDED = 32;
const CONTENT_PAD_BOTTOM_EXPANDED = 26;
const VERTICAL_PAD_TOP = 44;
const VERTICAL_PAD_BOTTOM = 52;
const FOOTER_TEXT_SIZE = 11;

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
  @Prop content: string = '';
  @Prop chapterTitle: string = '';
  @Prop @Watch('onConfigChanged') mode: ReadingMode = ReadingMode.VERTICAL;
  @Prop @Watch('onConfigChanged') fontSize: number = 18;
  @Prop @Watch('onConfigChanged') lineHeightRatio: number = 1.7;
  @Prop @Watch('onControlsChanged') controlsVisible: boolean = false;
  @Prop startCharOffset: number = 0;
  @Prop @Watch('onReload') loadVersion: number = 0;
  @Prop chapterIndex: number = 0;
  @Prop chapterCount: number = 0;
  @Prop bgColor: string = '#F7F3E8';
  @Prop textColor: string = '#2B2B2B';
  @Prop subTextColor: string = '#8C8C8C';
  @Prop accentColor: string = '#8B5E3C';
  @Prop accentTextColor: string = '#FFF8ED';

  onProgress: (charOffset: number, ratio: number, pageIndex: number) => void =
    (charOffset: number, ratio: number, pageIndex: number): void => {};
  onNextChapter: () => void = (): void => {};
  onPrevChapter: () => void = (): void => {};
  onTap: () => void = (): void => {};

  @State pages: string[] = [];
  @State currentPage: number = 0;
  @State contentHeightVp: number = 0;

  private pageStarts: number[] = [];
  private currentCharOffset: number = 0;
  private currentRatio: number = 0;
  private pendingOffset: number = 0;
  private needsRestore: boolean = false;
  private lastWidth: number = 0;
  private lastHeight: number = 0;
  private lastReportTime: number = 0;
  private restoreTimer: number = -1;
  private verticalScroller: Scroller = new Scroller();
  private swiperController: SwiperController = new SwiperController();

  aboutToAppear(): void {
    this.reload(this.startCharOffset);
  }

  aboutToDisappear(): void {
    this.reportCurrent();
    if (this.restoreTimer !== -1) {
      clearTimeout(this.restoreTimer);
      this.restoreTimer = -1;
    }
  }

  private lineHeightValue(): number {
    return this.fontSize * this.lineHeightRatio;
  }

  private contentWidth(): number {
    return Math.max(1, this.lastWidth - PAGE_LEFT_RIGHT * 2);
  }

  private contentTopPad(): number {
    return this.controlsVisible ? CONTENT_PAD_TOP_EXPANDED : CONTENT_PAD_COMPACT;
  }

  private contentBottomPad(): number {
    return this.controlsVisible ? CONTENT_PAD_BOTTOM_EXPANDED : CONTENT_PAD_COMPACT;
  }

  private pageContentHeight(): number {
    const safety = this.lineHeightValue() * 0.5;
    return Math.max(1, this.lastHeight - HEADER_HEIGHT - FOOTER_HEIGHT
      - this.contentTopPad() - this.contentBottomPad() - safety);
  }

  private viewportHeight(): number {
    return Math.max(1, this.lastHeight - HEADER_HEIGHT - FOOTER_HEIGHT);
  }

  private footerProgress(): string {
    if (this.chapterCount <= 0) {
      return this.chapterIndex >= 0 ? `第 ${this.chapterIndex + 1} 章` : '';
    }
    const current = this.chapterIndex + 1;
    return `第 ${current}/${this.chapterCount} 章`;
  }

  private onControlsChanged(): void {
    if (this.mode !== ReadingMode.VERTICAL) {
      this.reload(this.currentCharOffset);
    }
  }

  private onReload(): void {
    this.reload(this.startCharOffset);
  }

  private onConfigChanged(): void {
    this.reload(this.currentCharOffset);
  }

  private reload(offset: number): void {
    let safeOffset = offset;
    if (safeOffset < 0) {
      safeOffset = 0;
    }
    if (safeOffset > this.content.length) {
      safeOffset = this.content.length;
    }
    this.currentCharOffset = safeOffset;
    this.pendingOffset = safeOffset;
    this.needsRestore = true;
    if (this.lastWidth <= 0 || this.lastHeight <= 0) {
      return;
    }
    if (this.mode === ReadingMode.VERTICAL) {
      this.pages = [];
      this.tryRestoreVertical();
    } else {
      this.contentHeightVp = 0;
      this.paginate();
    }
  }

  private paginate(): void {
    if (this.lastWidth <= 0 || this.lastHeight <= 0) {
      return;
    }
    const result: PaginationResult = TextPaginator.paginate(
      this.getUIContext(), this.content, this.contentWidth(), this.pageContentHeight(),
      this.fontSize, this.lineHeightValue());
    this.pageStarts = result.pageStarts;
    const newPages: string[] = [];
    for (let i = 0; i < result.ranges.length; i++) {
      newPages.push(this.content.substring(result.ranges[i].start, result.ranges[i].end));
    }
    this.pages = newPages;
    this.currentPage = this.findPage(this.pendingOffset);
    if (this.currentPage >= 0 && this.currentPage < this.pageStarts.length) {
      this.currentCharOffset = this.pageStarts[this.currentPage];
    }
    this.currentRatio = this.pages.length > 1 ? this.currentPage / (this.pages.length - 1) : 0;
    this.needsRestore = false;
    this.restorePage();
    this.reportCurrent();
    hilog.debug(DOMAIN, TAG, 'paginate pages=%{public}d height=%{public}s textArea=%{public}s',
      newPages.length, this.lastHeight.toFixed(1), this.pageContentHeight().toFixed(1));
  }

  private findPage(offset: number): number {
    if (this.pageStarts.length === 0) {
      return 0;
    }
    let page = 0;
    for (let i = 0; i < this.pageStarts.length; i++) {
      if (this.pageStarts[i] <= offset) {
        page = i;
      } else {
        break;
      }
    }
    return page;
  }

  private restorePage(): void {
    if (this.restoreTimer !== -1) {
      clearTimeout(this.restoreTimer);
    }
    this.restoreTimer = setTimeout(() => {
      this.swiperController.changeIndex(this.currentPage, false);
      this.restoreTimer = -1;
    }, 60);
  }

  private handlePageChange(index: number): void {
    this.currentPage = index;
    if (index >= 0 && index < this.pageStarts.length) {
      this.currentCharOffset = this.pageStarts[index];
    }
    this.currentRatio = this.pages.length > 1 ? index / (this.pages.length - 1) : 0;
    this.reportCurrent();
  }

  private handleVerticalScroll(yOffset: number): void {
    if (this.mode !== ReadingMode.VERTICAL) {
      return;
    }
    const maxScroll = Math.max(1, this.contentHeightVp - this.viewportHeight());
    let ratio = yOffset / maxScroll;
    if (ratio < 0) {
      ratio = 0;
    }
    if (ratio > 1) {
      ratio = 1;
    }
    this.currentRatio = ratio;
    this.currentCharOffset = Math.floor(this.content.length * ratio);
    const now = Date.now();
    if (now - this.lastReportTime > 200) {
      this.lastReportTime = now;
      this.reportCurrent();
    }
  }

  private tryRestoreVertical(): void {
    if (this.mode !== ReadingMode.VERTICAL) {
      return;
    }
    if (!this.needsRestore || this.contentHeightVp <= 0 || this.lastHeight <= 0) {
      return;
    }
    const ratio = this.content.length > 0 ? this.pendingOffset / this.content.length : 0;
    this.needsRestore = false;
    if (this.restoreTimer !== -1) {
      clearTimeout(this.restoreTimer);
    }
    this.restoreTimer = setTimeout(() => {
      const maxScroll = Math.max(0, this.contentHeightVp - this.viewportHeight());
      this.verticalScroller.scrollTo({ xOffset: 0, yOffset: ratio * maxScroll });
      this.restoreTimer = -1;
    }, 100);
  }

  private reportCurrent(): void {
    this.onProgress(this.currentCharOffset, this.currentRatio, this.currentPage);
  }

  @Builder
  header() {
    Row() {
      Text(this.chapterTitle)
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
    Scroll(this.verticalScroller) {
      Column() {
        Text(this.content)
          .width('100%')
          .fontSize(this.fontSize)
          .lineHeight(this.lineHeightValue())
          .fontColor(this.textColor)

        Button('下一章')
          .type(ButtonType.Capsule)
          .backgroundColor(this.accentColor)
          .fontColor(this.accentTextColor)
          .fontSize(14)
          .margin({ top: 32, bottom: 24 })
          .onClick(() => {
            this.onNextChapter();
          })
      }
      .width('100%')
      .padding({
        left: PAGE_LEFT_RIGHT,
        right: PAGE_LEFT_RIGHT,
        top: VERTICAL_PAD_TOP,
        bottom: VERTICAL_PAD_BOTTOM
      })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const height = Number.parseFloat(String(newValue.height));
        if (Number.isFinite(height) && height > 0 && Math.abs(height - this.contentHeightVp) > 0.5) {
          this.contentHeightVp = height;
          this.tryRestoreVertical();
        }
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .onDidScroll((xOffset: number, yOffset: number, scrollState: ScrollState) => {
      this.handleVerticalScroll(yOffset);
    })
    .onScrollStop(() => {
      this.reportCurrent();
    })
  }

  @Builder
  horizontalBody() {
    Swiper(this.swiperController) {
      ForEach(this.pages, (pageText: string, index: number) => {
        Column() {
          Text(pageText)
            .width('100%')
            .fontSize(this.fontSize)
            .lineHeight(this.lineHeightValue())
            .fontColor(this.textColor)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: PAGE_LEFT_RIGHT,
          right: PAGE_LEFT_RIGHT,
          top: this.contentTopPad(),
          bottom: this.contentBottomPad()
        })
      }, (pageText: string, index: number) => `${index}_${pageText}`)
    }
    .width('100%')
    .height('100%')
    .index(this.currentPage)
    .loop(false)
    .indicator(false)
    .onChange((index: number) => {
      this.handlePageChange(index);
    })
  }

  build() {
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
      if (width !== this.lastWidth || height !== this.lastHeight) {
        this.lastWidth = width;
        this.lastHeight = height;
        this.reload(this.currentCharOffset);
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}
