import { ImageEntry, ReadingMode } from '../../model/BookModels';
import { AppPaths } from '../../utils/AppPaths';
import { ImageDataSource } from './ImageDataSource';
import { hilog } from '@kit.PerformanceAnalysisKit';

const MIN_SCALE = 0.2;
const MAX_SCALE = 3.0;
const LOG_DOMAIN = 0x0004;
const LOG_TAG = 'ImageReader';

@Component
export struct ImageReaderView {
  @Prop images: ImageEntry[] = [];
  @Prop @Watch('onConfigChanged') mode: ReadingMode = ReadingMode.VERTICAL;
  @Prop startIndex: number = 0;
  @Prop startRatio: number = 0;
  @Prop @Watch('onReload') loadVersion: number = 0;

  onProgress: (imageIndex: number, intraRatio: number) => void =
    (imageIndex: number, intraRatio: number): void => {};
  onNextChapter: () => void = (): void => {};
  onPrevChapter: () => void = (): void => {};
  onTap: () => void = (): void => {};

  @State flowScale: number = 1;
  @State viewWidth: number = 0;
  @State viewHeight: number = 0;
  @State contentWidth: number = 1;
  @State hOffset: number = 0;
  @State currentIndex: number = 0;
  @State swipeIndex: number = 0;
  @State scaleHintVisible: boolean = false;
  @State scaleHintText: string = '';

  private heights: number[] = [];
  private prefixHeights: number[] = [];
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
  private needsRestore: boolean = false;
  private dataSource: ImageDataSource = new ImageDataSource();
  private listScroller: Scroller = new Scroller();
  private swiperController: SwiperController = new SwiperController();

  aboutToAppear(): void {
    this.lastMode = this.mode;
    this.reloadAt(this.startIndex, this.startRatio);
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
  }

  private onReload(): void {
    this.reloadAt(this.startIndex, this.startRatio);
  }

  private onConfigChanged(): void {
    if (this.mode !== this.lastMode) {
      const index = this.currentIndex;
      const ratio = this.intraRatio;
      this.lastMode = this.mode;
      this.flowScale = 1;
      this.hOffset = 0;
      this.reloadAt(index, ratio);
    }
  }

  private reloadAt(indexValue: number, ratioValue: number): void {
    this.dataSource.reset(this.images);
    let index = indexValue;
    if (index < 0) {
      index = 0;
    }
    if (this.images.length > 0 && index >= this.images.length) {
      index = this.images.length - 1;
    }
    let ratio = ratioValue;
    if (ratio < 0) {
      ratio = 0;
    }
    if (ratio > 1) {
      ratio = 1;
    }
    this.currentIndex = index;
    this.swipeIndex = index;
    this.intraRatio = ratio;
    this.needsRestore = true;
    this.rebuildHeights();
    if (this.mode === ReadingMode.VERTICAL) {
      this.tryRestoreVertical();
    } else {
      this.restoreHorizontal();
    }
  }

  private itemWidth(): number {
    return Math.max(1, this.viewWidth) * this.flowScale;
  }

  private itemHeight(image: ImageEntry): number {
    const width = this.itemWidth();
    if (image.width <= 0) {
      return width;
    }
    return width * image.height / image.width;
  }

  private contentWidthValue(): number {
    const base = Math.max(1, this.viewWidth);
    return this.flowScale > 1 ? base * this.flowScale : base;
  }

  private rebuildHeights(): void {
    const width = this.itemWidth();
    const newHeights: number[] = [];
    const newPrefix: number[] = [];
    let sum = 0;
    for (let i = 0; i < this.images.length; i++) {
      const image = this.images[i];
      let height = width;
      if (image.width > 0) {
        height = width * image.height / image.width;
      }
      newHeights.push(height);
      newPrefix.push(sum);
      sum += height;
    }
    this.heights = newHeights;
    this.prefixHeights = newPrefix;
    this.contentWidth = this.contentWidthValue();
    if (this.flowScale > 1) {
      this.hOffset = -(this.contentWidth - this.viewWidth) / 2;
    } else {
      this.hOffset = 0;
    }
  }

  private tryRestoreVertical(): void {
    if (this.mode !== ReadingMode.VERTICAL || !this.needsRestore) {
      return;
    }
    if (this.viewWidth <= 0 || this.images.length === 0) {
      return;
    }
    if (this.heights.length === 0) {
      this.rebuildHeights();
    }
    this.needsRestore = false;
    this.restoreVerticalAt(this.currentIndex, this.intraRatio);
  }

  private restoreVerticalAt(index: number, ratio: number): void {
    if (this.restoreTimer !== -1) {
      clearTimeout(this.restoreTimer);
    }
    this.restoreTimer = setTimeout(() => {
      this.listScroller.scrollToIndex(index, false, ScrollAlign.START);
      const height = index >= 0 && index < this.heights.length ? this.heights[index] : 0;
      if (ratio > 0 && height > 0) {
        this.listScroller.scrollBy(0, ratio * height);
      }
      this.restoreTimer = -1;
    }, 80);
  }

  private restoreHorizontal(): void {
    if (this.restoreTimer !== -1) {
      clearTimeout(this.restoreTimer);
    }
    this.restoreTimer = setTimeout(() => {
      this.swiperController.changeIndex(this.swipeIndex, false);
      this.restoreTimer = -1;
    }, 60);
  }

  private updateProgressFromScroll(): void {
    if (this.mode !== ReadingMode.VERTICAL || this.isPinching) {
      return;
    }
    if (this.images.length === 0 || this.heights.length === 0) {
      return;
    }
    if (this.currentIndex < 0 || this.currentIndex >= this.heights.length) {
      return;
    }
    const offset = this.listScroller.currentOffset().yOffset;
    const base = this.prefixHeights[this.currentIndex];
    const height = this.heights[this.currentIndex];
    let ratio = height > 0 ? (offset - base) / height : 0;
    if (ratio < 0) {
      ratio = 0;
    }
    if (ratio > 1) {
      ratio = 1;
    }
    this.intraRatio = ratio;
    const now = Date.now();
    if (now - this.lastReportTime > 200) {
      this.lastReportTime = now;
      this.reportProgress();
    }
  }

  private reportProgress(): void {
    if (this.images.length === 0) {
      return;
    }
    let index = this.currentIndex;
    if (index < 0) {
      index = 0;
    }
    if (index >= this.images.length) {
      index = this.images.length - 1;
    }
    this.onProgress(index, this.intraRatio);
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
    if (this.mode !== ReadingMode.VERTICAL) {
      return;
    }
    this.isPinching = true;
    this.baseFlowScale = this.flowScale;
    this.anchorIndex = this.currentIndex;
    this.anchorRatio = this.intraRatio;
    hilog.info(LOG_DOMAIN, LOG_TAG, 'pinch start scale=%{public}s index=%{public}d ratio=%{public}s',
      this.flowScale.toFixed(3), this.currentIndex, this.intraRatio.toFixed(3));
  }

  private handlePinchUpdate(scaleValue: number): void {
    if (this.mode !== ReadingMode.VERTICAL) {
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
    if (this.mode !== ReadingMode.VERTICAL) {
      return;
    }
    this.isPinching = false;
    this.rebuildHeights();
    this.currentIndex = this.anchorIndex;
    this.intraRatio = this.anchorRatio;
    this.restoreVerticalAt(this.anchorIndex, this.anchorRatio);
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
            LazyForEach(this.dataSource, (item: ImageEntry, index: number) => {
              ListItem() {
                Row() {
                  Image(AppPaths.uri(item.file))
                    .width(this.itemWidth())
                    .height(this.itemHeight(item))
                    .objectFit(ImageFit.Contain)
                    .autoResize(true)
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
              }
              .width('100%')
            }, (item: ImageEntry) => item.file)

            ListItem() {
              Button('下一章')
                .type(ButtonType.Capsule)
                .backgroundColor('#8B5E3C')
                .fontColor('#FFF8ED')
                .fontSize(14)
                .margin({ top: 40, bottom: 100 })
                .onClick(() => {
                  this.onNextChapter();
                })
            }
            .width('100%')
          }
          .width(this.contentWidth)
          .height('100%')
          .scrollBar(BarState.Off)
          .cachedCount(3)
          .translate({ x: this.hOffset, y: 0 })
          .onScrollIndex((start: number, end: number) => {
            if (this.isPinching) {
              return;
            }
            const maxIndex = Math.max(0, this.images.length - 1);
            this.currentIndex = Math.min(start, maxIndex);
            this.updateProgressFromScroll();
          })
          .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
            this.updateProgressFromScroll();
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
                this.baseHOffset = this.hOffset;
              })
              .onActionUpdate((event: GestureEvent) => {
                this.applyHOffset(this.baseHOffset + event.offsetX);
              })
          )
        )
      } else {
        Swiper(this.swiperController) {
          LazyForEach(this.dataSource, (item: ImageEntry) => {
            Stack() {
              Image(AppPaths.uri(item.file))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
                .autoResize(true)
            }
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Black)
          }, (item: ImageEntry) => item.file)
        }
        .width('100%')
        .height('100%')
        .index(this.swipeIndex)
        .loop(false)
        .indicator(false)
        .onChange((index: number) => {
          this.swipeIndex = index;
          this.currentIndex = index;
          this.intraRatio = 0;
          this.onProgress(index, 0);
        })
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
        this.rebuildHeights();
        if (this.mode === ReadingMode.VERTICAL) {
          this.tryRestoreVertical();
        }
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}
