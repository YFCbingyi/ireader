import { ReadingMode } from '../../model/BookModels';
import { PaginationResult, TextPaginator } from '../../service/TextPaginator';

const PAGE_LEFT_RIGHT = 24;
const PAGE_TOP = 64;
const PAGE_BOTTOM = 80;

@Component
export struct TextReaderView {
  @Prop content: string = '';
  @Prop chapterTitle: string = '';
  @Prop @Watch('onConfigChanged') mode: ReadingMode = ReadingMode.VERTICAL;
  @Prop @Watch('onConfigChanged') fontSize: number = 18;
  @Prop @Watch('onConfigChanged') lineHeightRatio: number = 1.7;
  @Prop startCharOffset: number = 0;
  @Prop @Watch('onReload') loadVersion: number = 0;
  @Prop bgColor: string = '#F7F3E8';
  @Prop textColor: string = '#2B2B2B';
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

  private pageContentHeight(): number {
    return Math.max(1, this.lastHeight - PAGE_TOP - PAGE_BOTTOM - 20);
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
    const maxScroll = Math.max(1, this.contentHeightVp - this.lastHeight);
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
      const maxScroll = Math.max(0, this.contentHeightVp - this.lastHeight);
      this.verticalScroller.scrollTo({ xOffset: 0, yOffset: ratio * maxScroll });
      this.restoreTimer = -1;
    }, 100);
  }

  private reportCurrent(): void {
    this.onProgress(this.currentCharOffset, this.currentRatio, this.currentPage);
  }

  build() {
    Stack() {
      if (this.mode === ReadingMode.VERTICAL) {
        Scroll(this.verticalScroller) {
          Column() {
            Text(this.chapterTitle)
              .width('100%')
              .fontSize(this.fontSize + 6)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.textColor)
              .margin({ bottom: 18 })

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
            top: PAGE_TOP,
            bottom: PAGE_BOTTOM
          })
          .onAreaChange((oldValue: Area, newValue: Area) => {
            const height = Number(newValue.height);
            if (height > 0 && Math.abs(height - this.contentHeightVp) > 0.5) {
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
      } else {
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
            .alignItems(HorizontalAlign.Start)
            .padding({
              left: PAGE_LEFT_RIGHT,
              right: PAGE_LEFT_RIGHT,
              top: PAGE_TOP,
              bottom: PAGE_BOTTOM
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width);
      const height = Number(newValue.height);
      if (width > 0 && height > 0 && (width !== this.lastWidth || height !== this.lastHeight)) {
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
