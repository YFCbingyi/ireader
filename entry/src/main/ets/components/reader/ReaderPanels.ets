import { Annotation } from '../../model/Annotation';
import {
  Bookmark,
  ChapterMeta,
  PageTurnMode,
  ReadingMode,
  TextAlignMode,
  pageTurnLabel,
  textAlignLabel
} from '../../model/BookModels';
import { ReaderThemeColors, ReadingTheme } from '../../model/ReaderTheme';

// 目录分档粒度：全部 / 1-30 / 31-60 ……
const CATALOG_RANGE_SIZE: number = 30;
// 底部控制栏占位（58 胶囊 + 22 安全距 + 8 卡片间距）：弹窗卡片浮在控制栏正上方
const CONTROL_BAR_SPACE: number = 88;
// 字号 9 级：14 ~ 30，步长 2
const FONT_LEVELS: number = 9;
const FONT_MIN: number = 14;
const FONT_STEP: number = 2;
// 行距 5 级
const LINE_LEVELS: number[] = [1.3, 1.5, 1.7, 1.9, 2.1];

@Component
export struct ReaderPanels {
  @Prop panel: string = '';
  @Prop bookTitle: string = '';
  @Prop chapters: ChapterMeta[] = [];
  @Prop currentChapter: number = 0;
  // 当前章内偏移：目录里「当前读到」右侧的位置数字
  @Prop currentOffset: number = 0;
  @Prop bookmarks: Bookmark[] = [];
  @Prop annotations: Annotation[] = [];
  @Prop isImageBook: boolean = false;
  @Prop readingMode: ReadingMode = ReadingMode.VERTICAL;
  @Prop pageTurn: PageTurnMode = PageTurnMode.VERTICAL;
  @Prop fontSize: number = 18;
  @Prop lineHeightRatio: number = 1.7;
  @Prop fontFamily: string = '';
  @Prop fontList: string[] = [];
  @Prop textAlignMode: TextAlignMode = TextAlignMode.AUTO;
  @Prop theme: ReadingTheme = ReadingTheme.EYE;
  @Prop colors: ReaderThemeColors = new ReaderThemeColors();

  onClose: () => void = (): void => {};
  onSelectChapter: (index: number) => void = (index: number): void => {};
  onSelectBookmark: (bookmark: Bookmark) => void = (bookmark: Bookmark): void => {};
  onDeleteBookmark: (bookmark: Bookmark) => void = (bookmark: Bookmark): void => {};
  onSelectAnnotation: (annotation: Annotation) => void = (annotation: Annotation): void => {};
  onDeleteAnnotation: (annotation: Annotation) => void = (annotation: Annotation): void => {};
  onModeChange: (mode: ReadingMode) => void = (mode: ReadingMode): void => {};
  onFontSizeChange: (size: number) => void = (size: number): void => {};
  onLineHeightChange: (ratio: number) => void = (ratio: number): void => {};
  onThemeChange: (theme: ReadingTheme) => void = (theme: ReadingTheme): void => {};
  // 目录 / 笔记共用一个抽屉，切换 tab 时由父组件改 panel
  onSwitchPanel: (name: string) => void = (name: string): void => {};
  onFontFamilyChange: (family: string) => void = (family: string): void => {};
  onTextAlignChange: (mode: TextAlignMode) => void = (mode: TextAlignMode): void => {};
  onPageTurnChange: (mode: PageTurnMode) => void = (mode: PageTurnMode): void => {};
  onToggleBookmark: () => void = (): void => {};
  // 操作面板专用：跳章后保持面板打开，由用户自己关闭
  onJumpChapter: (index: number) => void = (index: number): void => {};

  // 目录分档：0 = 全部，n = 第 n 段（每段 30 章）
  @State rangeIndex: number = 0;
  // 滑块拖动中的临时值（松手才提交，避免每次移动都触发重新分页）
  @State fontSizePreview: number = 0;
  @State lineIndexPreview: number = 0;
  @State progressPreview: number = -1;
  private catalogScroller: Scroller = new Scroller();

  private rangeStart(): number {
    if (this.rangeIndex <= 0) {
      return 0;
    }
    return (this.rangeIndex - 1) * CATALOG_RANGE_SIZE;
  }

  private rangeEnd(): number {
    if (this.rangeIndex <= 0) {
      return this.chapters.length;
    }
    return Math.min(this.rangeStart() + CATALOG_RANGE_SIZE, this.chapters.length);
  }

  private rangeLabel(): string {
    const start = this.rangeStart();
    const end = this.rangeEnd();
    if (start === 0 && end === this.chapters.length) {
      return '全部';
    }
    return `${start + 1}-${end}`;
  }

  private canSwitchRange(): boolean {
    return this.chapters.length > CATALOG_RANGE_SIZE;
  }

  private rangeMenu(): MenuElement[] {
    const items: MenuElement[] = [];
    items.push({
      value: '全部',
      action: (): void => {
        this.selectRange(0);
      }
    });
    for (let start = 0; start < this.chapters.length; start += CATALOG_RANGE_SIZE) {
      const rangeIdx: number = start / CATALOG_RANGE_SIZE + 1;
      const end: number = Math.min(start + CATALOG_RANGE_SIZE, this.chapters.length);
      const label: string = `${start + 1}-${end}`;
      items.push({
        value: label,
        action: (): void => {
          this.selectRange(rangeIdx);
        }
      });
    }
    return items;
  }

  private selectRange(index: number): void {
    if (this.rangeIndex === index) {
      return;
    }
    this.rangeIndex = index;
    // 换档后优先落在当前章，当前章不在该档时回到档首
    setTimeout(() => {
      if (this.panel !== 'catalog') {
        return;
      }
      const start = this.rangeStart();
      const target = this.currentChapter - start;
      if (target >= 0 && target < this.rangeEnd() - start) {
        this.catalogScroller.scrollToIndex(target, false, ScrollAlign.START);
      } else {
        this.catalogScroller.scrollToIndex(0, false, ScrollAlign.START);
      }
    }, 20);
  }

  private visibleChapters(): ChapterMeta[] {
    const start = this.rangeStart();
    const end = this.rangeEnd();
    if (start <= 0 && end >= this.chapters.length) {
      return this.chapters;
    }
    return this.chapters.slice(start, end);
  }

  /** 打开目录时把当前章节滚到可视区域中部 */
  private locateCurrentChapter(): void {
    const start = this.rangeStart();
    const target = this.currentChapter - start;
    if (target < 0 || target >= this.rangeEnd() - start) {
      return;
    }
    setTimeout(() => {
      if (this.panel === 'catalog') {
        this.catalogScroller.scrollToIndex(target, false, ScrollAlign.CENTER);
      }
    }, 30);
  }

  /** 滑轨刻度点索引 */
  private tickList(count: number): number[] {
    const list: number[] = [];
    for (let i = 0; i < count; i++) {
      list.push(i);
    }
    return list;
  }

  /** 整体进度百分比（按章等权，与阅读页页脚口径一致） */
  private progressPercent(): number {
    if (this.chapters.length <= 0) {
      return 0;
    }
    const current = this.previewChapter() + 1;
    return Math.min(100, Math.round(current / this.chapters.length * 100));
  }

  private pageTurnMenu(): MenuElement[] {
    const items: MenuElement[] = [];
    if (!this.isImageBook) {
      items.push({
        value: pageTurnLabel(PageTurnMode.SIMULATION),
        action: (): void => {
          this.onPageTurnChange(PageTurnMode.SIMULATION);
        }
      });
    }
    items.push({
      value: pageTurnLabel(PageTurnMode.SLIDE),
      action: (): void => {
        this.onPageTurnChange(PageTurnMode.SLIDE);
      }
    });
    items.push({
      value: pageTurnLabel(PageTurnMode.VERTICAL),
      action: (): void => {
        this.onPageTurnChange(PageTurnMode.VERTICAL);
      }
    });
    items.push({
      value: pageTurnLabel(PageTurnMode.NONE),
      action: (): void => {
        this.onPageTurnChange(PageTurnMode.NONE);
      }
    });
    return items;
  }

  private fontLevel(): number {
    const level = Math.round((this.fontSize - FONT_MIN) / FONT_STEP) + 1;
    if (level < 1) {
      return 1;
    }
    if (level > FONT_LEVELS) {
      return FONT_LEVELS;
    }
    return level;
  }

  private levelToSize(level: number): number {
    return FONT_MIN + (Math.round(level) - 1) * FONT_STEP;
  }

  private fontSizeLabel(): string {
    const level = this.fontSizePreview > 0 ? this.fontSizePreview : this.fontLevel();
    return `${this.levelToSize(level)}`;
  }

  private lineLevel(): number {
    let best = 1;
    let minGap = 99;
    for (let i = 0; i < LINE_LEVELS.length; i++) {
      const gap = Math.abs(LINE_LEVELS[i] - this.lineHeightRatio);
      if (gap < minGap) {
        minGap = gap;
        best = i + 1;
      }
    }
    return best;
  }

  private lineRatioOf(level: number): number {
    const index = Math.round(level) - 1;
    if (index < 0) {
      return LINE_LEVELS[0];
    }
    if (index >= LINE_LEVELS.length) {
      return LINE_LEVELS[LINE_LEVELS.length - 1];
    }
    return LINE_LEVELS[index];
  }

  private lineLabel(): string {
    const level = this.lineIndexPreview > 0 ? this.lineIndexPreview : this.lineLevel();
    return `${this.lineRatioOf(level).toFixed(1)}×`;
  }

  private fontFamilyLabel(): string {
    return this.fontFamily.length > 0 ? this.fontFamily : '系统默认';
  }

  private fontMenu(): MenuElement[] {
    const items: MenuElement[] = [];
    items.push({
      value: '系统默认',
      action: (): void => {
        this.onFontFamilyChange('');
      }
    });
    const seen: string[] = [];
    for (let i = 0; i < this.fontList.length; i++) {
      const name: string = this.fontList[i];
      if (name.length === 0 || seen.indexOf(name) >= 0) {
        continue;
      }
      seen.push(name);
      items.push({
        value: name,
        action: (): void => {
          this.onFontFamilyChange(name);
        }
      });
      if (items.length >= 30) {
        break;
      }
    }
    return items;
  }

  private alignMenu(): MenuElement[] {
    const items: MenuElement[] = [];
    items.push({
      value: textAlignLabel(TextAlignMode.AUTO),
      action: (): void => {
        this.onTextAlignChange(TextAlignMode.AUTO);
      }
    });
    items.push({
      value: textAlignLabel(TextAlignMode.LEFT),
      action: (): void => {
        this.onTextAlignChange(TextAlignMode.LEFT);
      }
    });
    items.push({
      value: textAlignLabel(TextAlignMode.RIGHT),
      action: (): void => {
        this.onTextAlignChange(TextAlignMode.RIGHT);
      }
    });
    items.push({
      value: textAlignLabel(TextAlignMode.JUSTIFY),
      action: (): void => {
        this.onTextAlignChange(TextAlignMode.JUSTIFY);
      }
    });
    return items;
  }

  private swatchColor(theme: ReadingTheme): string {
    if (theme === ReadingTheme.WHITE) {
      return '#FFFFFF';
    }
    if (theme === ReadingTheme.DARK) {
      return '#121212';
    }
    if (theme === ReadingTheme.SYSTEM) {
      return '#8A8A8A';
    }
    return '#CBE3D1';
  }

  private pageTurnIcon(mode: PageTurnMode): string {
    if (mode === PageTurnMode.SIMULATION) {
      return '◭';
    }
    if (mode === PageTurnMode.SLIDE) {
      return '⇄';
    }
    if (mode === PageTurnMode.VERTICAL) {
      return '↕';
    }
    return '⊘';
  }

  private previewChapter(): number {
    return this.progressPreview >= 0 ? this.progressPreview : this.currentChapter;
  }

  private panelTitle(): string {
    if (this.panel === 'catalog') {
      return '目录';
    }
    if (this.panel === 'bookmarks') {
      return '书签';
    }
    if (this.panel === 'notes') {
      return '笔记';
    }
    return '阅读设置';
  }

  private chapterTitleOf(index: number): string {
    const chapter = this.chapters[index];
    return chapter !== undefined ? chapter.title : `第 ${index + 1} 章`;
  }

  @Builder
  modeButton(label: string, value: ReadingMode) {
    Text(label)
      .fontSize(14)
      .fontColor(this.readingMode === value ? this.colors.accentText : this.colors.chipText)
      .backgroundColor(this.readingMode === value ? this.colors.accent : this.colors.chipBg)
      .padding({ left: 18, right: 18, top: 9, bottom: 9 })
      .borderRadius(18)
      .margin({ right: 12 })
      .onClick(() => {
        this.onModeChange(value);
      })
  }

  @Builder
  themeButton(label: string, value: ReadingTheme) {
    Text(label)
      .fontSize(14)
      .fontColor(this.theme === value ? this.colors.accentText : this.colors.chipText)
      .backgroundColor(this.theme === value ? this.colors.accent : this.colors.chipBg)
      .padding({ left: 14, right: 14, top: 9, bottom: 9 })
      .borderRadius(18)
      .margin({ right: 10, bottom: 8 })
      .onClick(() => {
        this.onThemeChange(value);
      })
  }

  @Builder
  lineHeightButton(label: string, value: number, matched: boolean) {
    Text(label)
      .fontSize(14)
      .fontColor(matched ? this.colors.accentText : this.colors.chipText)
      .backgroundColor(matched ? this.colors.accent : this.colors.chipBg)
      .padding({ left: 18, right: 18, top: 9, bottom: 9 })
      .borderRadius(18)
      .margin({ right: 12 })
      .onClick(() => {
        this.onLineHeightChange(value);
      })
  }

  @Builder
  catalogPanel() {
    List({ scroller: this.catalogScroller }) {
      ForEach(this.visibleChapters(), (item: ChapterMeta, index: number) => {
        ListItem() {
          Column() {
            Row() {
              Text(item.title)
                .layoutWeight(1)
                .fontSize(14)
                .fontWeight(this.currentChapter === this.rangeStart() + index ?
                  FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.colors.panelText)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (!this.isImageBook) {
                Text(`${item.charCount}`)
                  .fontSize(11)
                  .fontColor(this.colors.panelSubText)
                  .margin({ left: 10 })
              }
            }
            .width('100%')
            .height(44)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.onSelectChapter(this.rangeStart() + index);
            })

            // 当前阅读位置：标题下方单独一行，跟随参考样式
            if (this.currentChapter === this.rangeStart() + index) {
              Row() {
                Text('♥')
                  .fontSize(11)
                  .fontColor(this.colors.accent)
                Text('当前读到')
                  .fontSize(11)
                  .fontColor(this.colors.accent)
                  .margin({ left: 6 })
                Blank()
                Text(`${this.currentOffset}`)
                  .fontSize(11)
                  .fontColor(this.colors.accent)
              }
              .width('100%')
              .height(30)
              .padding({ left: 2, right: 2 })
              .alignItems(VerticalAlign.Center)
            }

            Divider()
              .color(this.colors.divider)
              .opacity(0.7)
          }
          .width('100%')
        }
        .width('100%')
      }, (item: ChapterMeta, index: number) => `${this.rangeStart() + index}_${item.title}`)
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .onAppear(() => {
      this.locateCurrentChapter();
    })
  }

  @Builder
  bookmarksPanel() {
    if (this.bookmarks.length === 0) {
      Column() {
        Text('还没有书签')
          .fontSize(15)
          .fontColor(this.colors.panelSubText)
        Text('阅读时点击顶部“书签”即可添加')
          .fontSize(12)
          .fontColor(this.colors.panelSubText)
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      List() {
        ForEach(this.bookmarks, (item: Bookmark, index: number) => {
          ListItem() {
            Row() {
              Column() {
                Text(item.chapterTitle)
                  .fontSize(14)
                  .fontColor(this.colors.panelText)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.preview)
                  .fontSize(12)
                  .fontColor(this.colors.panelSubText)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 4 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .onClick(() => {
                this.onSelectBookmark(item);
              })

              Text('删除')
                .fontSize(13)
                .fontColor(this.colors.danger)
                .padding({ left: 12, top: 8, bottom: 8 })
                .onClick(() => {
                  this.onDeleteBookmark(item);
                })
            }
            .width('100%')
            .padding({ top: 12, bottom: 12 })
            .border({ width: { bottom: 1 }, color: this.colors.divider })
          }
          .width('100%')
        }, (item: Bookmark) => item.id)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
  }

  /** 笔记：划线 + 想法的全量列表，点击回到原文位置 */
  @Builder
  notesPanel() {
    if (this.annotations.length === 0) {
      Column() {
        Text('还没有划线和想法')
          .fontSize(15)
          .fontColor(this.colors.panelSubText)
        Text('长按正文选中文字，即可划线或记录想法')
          .fontSize(12)
          .fontColor(this.colors.panelSubText)
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      List() {
        ForEach(this.annotations, (item: Annotation) => {
          ListItem() {
            Row() {
              Column() {
                Row() {
                  Text(item.note.length > 0 ? '想法' : '划线')
                    .fontSize(11)
                    .fontColor(item.note.length > 0 ? this.colors.accentText : this.colors.chipText)
                    .backgroundColor(item.note.length > 0 ? this.colors.accent : this.colors.chipBg)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(6)
                  Text(this.chapterTitleOf(item.chapterIndex))
                    .fontSize(12)
                    .fontColor(this.colors.panelSubText)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ left: 8 })
                    .layoutWeight(1)
                }
                .width('100%')

                Text(item.text)
                  .width('100%')
                  .fontSize(14)
                  .fontColor(this.colors.panelText)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 6 })

                if (item.note.length > 0) {
                  Text(item.note)
                    .width('100%')
                    .fontSize(13)
                    .fontColor(this.colors.panelSubText)
                    .maxLines(3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .onClick(() => {
                this.onSelectAnnotation(item);
              })

              Text('删除')
                .fontSize(13)
                .fontColor(this.colors.danger)
                .padding({ left: 12, top: 8, bottom: 8 })
                .onClick(() => {
                  this.onDeleteAnnotation(item);
                })
            }
            .width('100%')
            .padding({ top: 12, bottom: 12 })
            .border({ width: { bottom: 1 }, color: this.colors.divider })
          }
          .width('100%')
        }, (item: Annotation) => `${item.id}_${item.note.length}`)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  settingsPanel() {
    Scroll() {
      Column() {
        Row() {
          Text('书签')
            .fontSize(14)
            .fontColor(this.colors.panelText)
          Blank()
          Text(`${this.bookmarks.length} 条`)
            .fontSize(12)
            .fontColor(this.colors.panelSubText)
          Text('›')
            .fontSize(14)
            .fontColor(this.colors.panelSubText)
            .margin({ left: 8 })
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)
        .border({ width: { bottom: 1 }, color: this.colors.divider })
        .onClick(() => {
          this.onSwitchPanel('bookmarks');
        })

        if (!this.isImageBook) {
          Row() {
            Text('笔记')
              .fontSize(14)
              .fontColor(this.colors.panelText)
            Blank()
            Text(`${this.annotations.length} 条`)
              .fontSize(12)
              .fontColor(this.colors.panelSubText)
            Text('›')
              .fontSize(14)
              .fontColor(this.colors.panelSubText)
              .margin({ left: 8 })
          }
          .width('100%')
          .height(48)
          .alignItems(VerticalAlign.Center)
          .border({ width: { bottom: 1 }, color: this.colors.divider })
          .onClick(() => {
            this.onSwitchPanel('notes');
          })
        }

        Row() {
          Text('添加当前页书签')
            .fontSize(14)
            .fontColor(this.colors.panelText)
          Blank()
          Text('＋')
            .fontSize(15)
            .fontColor(this.colors.panelSubText)
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)
        .border({ width: { bottom: 1 }, color: this.colors.divider })
        .onClick(() => {
          this.onToggleBookmark();
        })

        Text('阅读方向')
          .width('100%')
          .fontSize(13)
          .fontColor(this.colors.panelSubText)
          .margin({ top: 10, bottom: 10 })

        Row() {
          this.modeButton('上下', ReadingMode.VERTICAL)
          this.modeButton('左右', ReadingMode.HORIZONTAL)
        }
        .width('100%')

        if (this.isImageBook) {
          Text('上下模式：双指缩小可同屏查看多张，放大后可左右拖动。')
            .width('100%')
            .fontSize(12)
            .fontColor(this.colors.panelSubText)
            .lineHeight(20)
            .margin({ top: 18 })
        } else {
          Text('背景')
            .width('100%')
            .fontSize(13)
            .fontColor(this.colors.panelSubText)
            .margin({ top: 24, bottom: 10 })

          Flex({ wrap: FlexWrap.Wrap }) {
            this.themeButton('护眼', ReadingTheme.EYE)
            this.themeButton('白色', ReadingTheme.WHITE)
            this.themeButton('深色', ReadingTheme.DARK)
            this.themeButton('随系统', ReadingTheme.SYSTEM)
          }
          .width('100%')

          Text('字号')
            .width('100%')
            .fontSize(13)
            .fontColor(this.colors.panelSubText)
            .margin({ top: 18, bottom: 10 })

          Row() {
            Button('A-')
              .type(ButtonType.Capsule)
              .backgroundColor(this.colors.chipBg)
              .fontColor(this.colors.chipText)
              .fontSize(14)
              .onClick(() => {
                this.onFontSizeChange(this.fontSize - 2);
              })
            Text(`${this.fontSize}`)
              .width(60)
              .textAlign(TextAlign.Center)
              .fontSize(16)
              .fontColor(this.colors.panelText)
            Button('A+')
              .type(ButtonType.Capsule)
              .backgroundColor(this.colors.chipBg)
              .fontColor(this.colors.chipText)
              .fontSize(14)
              .onClick(() => {
                this.onFontSizeChange(this.fontSize + 2);
              })
          }
          .width('100%')

          Text('行距')
            .width('100%')
            .fontSize(13)
            .fontColor(this.colors.panelSubText)
            .margin({ top: 24, bottom: 10 })

          Row() {
            this.lineHeightButton('紧凑', 1.4, this.lineHeightRatio < 1.55)
            this.lineHeightButton('标准', 1.7, this.lineHeightRatio >= 1.55 && this.lineHeightRatio < 1.85)
            this.lineHeightButton('宽松', 2.0, this.lineHeightRatio >= 1.85)
          }
          .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 20 })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
  }

  /** 行距图标：三横线，紧凑 / 宽松 */
  @Builder
  lineDensityIcon(compact: boolean) {
    Column() {
      Column()
        .width(18)
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.colors.panelSubText)
        .opacity(0.75)
      Column()
        .width(18)
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.colors.panelSubText)
        .opacity(0.75)
        .margin({ top: compact ? 3 : 6 })
      Column()
        .width(18)
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.colors.panelSubText)
        .opacity(0.75)
        .margin({ top: compact ? 3 : 6 })
    }
    .width(24)
    .alignItems(HorizontalAlign.Center)
  }

  /** 滑轨上的刻度点 */
  @Builder
  trackTicks(count: number, tag: string) {
    Row() {
      ForEach(this.tickList(count), (item: number) => {
        Column()
          .width(3)
          .height(3)
          .borderRadius(2)
          .backgroundColor(this.colors.panelSubText)
          .opacity(0.38)
      }, (item: number) => `${tag}_${item}`)
    }
    .width('100%')
    .height(36)
    .padding({ left: 14, right: 14 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
  }

  /** 字体面板：字号（9 级） / 行距（5 级）两条滑轨 + 字体、对齐胶囊 */
  @Builder
  fontSheet() {
    Column() {
      Row() {
        Text('A')
          .fontSize(13)
          .fontColor(this.colors.panelSubText)
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('100%')
            .height(36)
            .borderRadius(18)
            .backgroundColor(this.colors.chipBg)
          this.trackTicks(FONT_LEVELS, 'font')
          Slider({
            value: this.fontSizePreview > 0 ? this.fontSizePreview : this.fontLevel(),
            min: 1,
            max: FONT_LEVELS,
            step: 1,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .height(36)
            .blockSize({ width: 28, height: 28 })
            .trackThickness(36)
            .trackColor('#00000000')
            .selectedColor('#00000000')
            .blockColor(this.colors.panelBg)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.fontSizePreview = 0;
                this.onFontSizeChange(this.levelToSize(value));
              } else {
                this.fontSizePreview = Math.round(value);
              }
            })
        }
        .layoutWeight(1)
        .height(36)
        .margin({ left: 10, right: 10 })
        Text('A')
          .fontSize(20)
          .fontColor(this.colors.panelSubText)
      }
      .width('100%')
      .height(52)
      .alignItems(VerticalAlign.Center)

      Row() {
        this.lineDensityIcon(true)
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('100%')
            .height(36)
            .borderRadius(18)
            .backgroundColor(this.colors.chipBg)
          this.trackTicks(LINE_LEVELS.length, 'line')
          Slider({
            value: this.lineIndexPreview > 0 ? this.lineIndexPreview : this.lineLevel(),
            min: 1,
            max: LINE_LEVELS.length,
            step: 1,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .height(36)
            .blockSize({ width: 28, height: 28 })
            .trackThickness(36)
            .trackColor('#00000000')
            .selectedColor('#00000000')
            .blockColor(this.colors.panelBg)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.lineIndexPreview = 0;
                this.onLineHeightChange(this.lineRatioOf(value));
              } else {
                this.lineIndexPreview = Math.round(value);
              }
            })
        }
        .layoutWeight(1)
        .height(36)
        .margin({ left: 10, right: 10 })
        this.lineDensityIcon(false)
      }
      .width('100%')
      .height(52)
      .alignItems(VerticalAlign.Center)

      Row() {
        Row() {
          Text(this.fontFamilyLabel())
            .layoutWeight(1)
            .fontSize(13)
            .fontColor(this.colors.panelText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('›')
            .fontSize(13)
            .fontColor(this.colors.panelSubText)
        }
        .layoutWeight(1)
        .height(40)
        .padding({ left: 16, right: 14 })
        .backgroundColor(this.colors.chipBg)
        .borderRadius(20)
        .bindMenu(this.fontMenu())

        Row() {
          Text(textAlignLabel(this.textAlignMode))
            .layoutWeight(1)
            .fontSize(13)
            .fontColor(this.colors.panelText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('˅')
            .fontSize(11)
            .fontColor(this.colors.panelSubText)
        }
        .layoutWeight(1)
        .height(40)
        .margin({ left: 10 })
        .padding({ left: 16, right: 14 })
        .backgroundColor(this.colors.chipBg)
        .borderRadius(20)
        .bindMenu(this.alignMenu())
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('calc(100% - 24vp)')
    .height(186)
    .margin({ bottom: CONTROL_BAR_SPACE })
    .backgroundColor(this.colors.bg)
    .borderRadius(24)
    .border({ width: 1, color: this.colors.divider })
    .shadow({ radius: 24, color: '#26000000', offsetX: 0, offsetY: 6 })
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  /** 操作面板：整体进度 / 笔记数 + 上一章 · 进度条 · 下一章 */
  @Builder
  actionsSheet() {
    Column() {
      Row() {
        Column() {
          Row() {
            Text(`${this.progressPercent()}`)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.colors.panelText)
            Text('%')
              .fontSize(12)
              .fontColor(this.colors.panelSubText)
              .margin({ left: 2, bottom: 3 })
          }
          .alignItems(VerticalAlign.Bottom)

          Text('整体进度')
            .fontSize(11)
            .fontColor(this.colors.panelSubText)
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column() {
          Row() {
            Text(this.isImageBook ? `${this.bookmarks.length}` : `${this.annotations.length}`)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.colors.panelText)
            Text('条')
              .fontSize(12)
              .fontColor(this.colors.panelSubText)
              .margin({ left: 2, bottom: 3 })
          }
          .alignItems(VerticalAlign.Bottom)

          Text(this.isImageBook ? '我的书签 ›' : '我的笔记 ›')
            .fontSize(11)
            .fontColor(this.colors.panelSubText)
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          this.onSwitchPanel(this.isImageBook ? 'bookmarks' : 'notes');
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row() {
        Row() {
          Text('‹')
            .fontSize(20)
            .fontColor(this.currentChapter > 0 ? this.colors.panelText : this.colors.divider)
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          if (this.currentChapter > 0) {
            this.onJumpChapter(this.currentChapter - 1);
          }
        })

        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('100%')
            .height(30)
            .borderRadius(15)
            .backgroundColor(this.colors.chipBg)

          Slider({
            value: this.previewChapter(),
            min: 0,
            max: Math.max(0, this.chapters.length - 1),
            step: 1,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .height(30)
            .blockSize({ width: 26, height: 26 })
            .trackThickness(30)
            .trackColor('#00000000')
            .selectedColor('#00000000')
            .blockColor(this.colors.panelBg)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.progressPreview = -1;
                this.onJumpChapter(Math.round(value));
              } else {
                this.progressPreview = Math.round(value);
              }
            })
        }
        .layoutWeight(1)
        .height(30)
        .margin({ left: 6, right: 6 })

        Row() {
          Text('›')
            .fontSize(20)
            .fontColor(this.currentChapter < this.chapters.length - 1 ?
              this.colors.panelText : this.colors.divider)
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          if (this.currentChapter < this.chapters.length - 1) {
            this.onJumpChapter(this.currentChapter + 1);
          }
        })
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)

      Text(`第 ${this.previewChapter() + 1} 章 · ${this.chapterTitleOf(this.previewChapter())}`)
        .width('100%')
        .fontSize(11)
        .fontColor(this.colors.panelSubText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .margin({ top: 2 })
    }
    .width('calc(100% - 24vp)')
    .height(158)
    .margin({ bottom: CONTROL_BAR_SPACE })
    .backgroundColor(this.colors.bg)
    .borderRadius(24)
    .border({ width: 1, color: this.colors.divider })
    .shadow({ radius: 24, color: '#26000000', offsetX: 0, offsetY: 6 })
    .padding({ left: 18, right: 18, top: 14, bottom: 12 })
  }

  @Builder
  themeSwatchItem(value: ReadingTheme, label: string) {
    Column() {
      Stack() {
        Column()
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.swatchColor(value))
          .border({ width: 1, color: this.colors.divider })
        if (this.theme === value) {
          Column()
            .width(40)
            .height(40)
            .borderRadius(20)
            .border({ width: 2, color: this.colors.accent })
        }
      }
      .width(40)
      .height(40)

      Text(label)
        .fontSize(10)
        .margin({ top: 5 })
        .fontColor(this.theme === value ? this.colors.accent : this.colors.panelSubText)
    }
    .layoutWeight(1)
    .onClick(() => {
      this.onThemeChange(value);
    })
  }

  /** 背景面板：一排圆形色块 */
  @Builder
  backgroundSheet() {
    Column() {
      Row() {
        this.themeSwatchItem(ReadingTheme.EYE, '护眼')
        this.themeSwatchItem(ReadingTheme.WHITE, '白色')
        this.themeSwatchItem(ReadingTheme.DARK, '深色')
        this.themeSwatchItem(ReadingTheme.SYSTEM, '跟随系统')
      }
      .width('100%')
    }
    .width('calc(100% - 24vp)')
    .height(100)
    .margin({ bottom: CONTROL_BAR_SPACE })
    .backgroundColor(this.colors.bg)
    .borderRadius(24)
    .border({ width: 1, color: this.colors.divider })
    .shadow({ radius: 24, color: '#26000000', offsetX: 0, offsetY: 6 })
    .padding({ left: 16, right: 16 })
    .justifyContent(FlexAlign.Center)
  }

  /** 翻页设置面板：只有翻页方式一项 */
  @Builder
  pageTurnSheet() {
    Column() {
      Row() {
        Text('翻页方式')
          .fontSize(14)
          .fontColor(this.colors.panelText)
        Blank()
        Row() {
          Text(pageTurnLabel(this.pageTurn))
            .fontSize(13)
            .fontColor(this.colors.panelText)
          Text('▾')
            .fontSize(11)
            .fontColor(this.colors.panelSubText)
            .margin({ left: 5 })
        }
        .height(32)
        .padding({ left: 14, right: 12 })
        .backgroundColor(this.colors.chipBg)
        .borderRadius(16)
        .bindMenu(this.pageTurnMenu())
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)
    }
    .width('calc(100% - 24vp)')
    .height(84)
    .margin({ bottom: CONTROL_BAR_SPACE })
    .backgroundColor(this.colors.bg)
    .borderRadius(24)
    .border({ width: 1, color: this.colors.divider })
    .shadow({ radius: 24, color: '#26000000', offsetX: 0, offsetY: 6 })
    .padding({ left: 18, right: 18 })
    .justifyContent(FlexAlign.Center)
  }

  /** 目录 / 笔记分段控件（选中项为悬浮胶囊） */
  @Builder
  segmentTab(label: string, name: string) {
    Text(label)
      .layoutWeight(1)
      .height(32)
      .textAlign(TextAlign.Center)
      .fontSize(14)
      .fontWeight(this.panel === name ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.panel === name ? this.colors.panelText : this.colors.panelSubText)
      .backgroundColor(this.panel === name ? this.colors.bg : '#00000000')
      .borderRadius(16)
      .onClick(() => {
        if (this.panel !== name) {
          this.onSwitchPanel(name);
        }
      })
  }

  /** 目录 / 笔记卡片：书名 + 分段切换 + 分档 + 列表 */
  @Builder
  catalogSheet() {
    Column() {
      Row() {
        Text(this.bookTitle.length > 0 ? this.bookTitle : this.panelTitle())
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.colors.panelText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Row() {
          Text('✕')
            .fontSize(13)
            .fontColor(this.colors.panelSubText)
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.colors.chipBg)
        .borderRadius(15)
        .onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
      .height(50)
      .alignItems(VerticalAlign.Center)

      Row() {
        this.segmentTab('目录', 'catalog')
        if (!this.isImageBook) {
          this.segmentTab('笔记', 'notes')
        }
      }
      .width('100%')
      .height(38)
      .padding(3)
      .backgroundColor(this.colors.chipBg)
      .borderRadius(19)
      .margin({ bottom: 8 })

      if (this.panel === 'catalog') {
        Row() {
          Text(`共 ${this.chapters.length} 章`)
            .fontSize(12)
            .fontColor(this.colors.panelSubText)
          Blank()
          if (this.canSwitchRange()) {
            Row() {
              Text(this.rangeLabel())
                .fontSize(12)
                .fontColor(this.colors.panelText)
              Text('▾')
                .fontSize(11)
                .fontColor(this.colors.panelSubText)
                .margin({ left: 5 })
            }
            .height(28)
            .padding({ left: 12, right: 10 })
            .backgroundColor(this.colors.bg)
            .borderRadius(14)
            .border({ width: 1, color: this.colors.divider })
            .bindMenu(this.rangeMenu())
          }
        }
        .width('100%')
        .height(40)
        .alignItems(VerticalAlign.Center)

        this.catalogPanel()
      } else {
        this.notesPanel()
      }
    }
    .width('calc(100% - 24vp)')
    .height('58%')
    .margin({ bottom: CONTROL_BAR_SPACE })
    .backgroundColor(this.colors.bg)
    .borderRadius(24)
    .border({ width: 1, color: this.colors.divider })
    .shadow({ radius: 24, color: '#26000000', offsetX: 0, offsetY: 6 })
    .padding({ left: 16, right: 16, top: 4, bottom: 16 })
  }

  /** 书签 / 设置抽屉：沿用简单的标题栏 */
  @Builder
  plainSheet() {
    Column() {
      Row() {
        Text(this.panelTitle())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.colors.panelText)
          .layoutWeight(1)
        Text('关闭')
          .fontSize(14)
          .fontColor(this.colors.accent)
          .padding({ left: 12, right: 4, top: 8, bottom: 8 })
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .height(52)
      .alignItems(VerticalAlign.Center)

      Divider()
        .color(this.colors.divider)

      if (this.panel === 'bookmarks') {
        this.bookmarksPanel()
      } else {
        this.settingsPanel()
      }
    }
    .width('calc(100% - 24vp)')
    .height('58%')
    .margin({ bottom: CONTROL_BAR_SPACE })
    .backgroundColor(this.colors.bg)
    .borderRadius(20)
    .border({ width: 1, color: this.colors.divider })
    .shadow({ radius: 24, color: '#26000000', offsetX: 0, offsetY: 6 })
    .padding({ left: 18, right: 18, bottom: 18 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 上半屏遮罩负责点击关闭；底部留出控制栏，保证弹窗期间仍能切换 tab
      Column() {
        Column()
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#66000000')
          .onClick(() => {
            this.onClose();
          })
        Column()
          .width('100%')
          .height(CONTROL_BAR_SPACE)
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.panel === 'catalog' || this.panel === 'notes') {
        this.catalogSheet()
      } else if (this.panel === 'font') {
        this.fontSheet()
      } else if (this.panel === 'actions') {
        this.actionsSheet()
      } else if (this.panel === 'background') {
        this.backgroundSheet()
      } else if (this.panel === 'pageturn') {
        this.pageTurnSheet()
      } else {
        this.plainSheet()
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
