import { Annotation } from '../../model/Annotation';
import {
  Bookmark,
  ChapterMeta,
  PageTurnMode,
  SearchHit,
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
// 阅读设置抽屉高度：按内容（标题 52 + 4 行 + 底部留白）收口，避免大片空白
const SETTINGS_SHEET_HEIGHT: number = 284;
// 笔记筛选：0 全部 / 1 书签 / 2 想法 / 3 划线
const NOTE_KIND_BOOKMARK: number = 1;
const NOTE_KIND_THOUGHT: number = 2;
const NOTE_KIND_HIGHLIGHT: number = 3;

/** 笔记条目：书签 / 划线 / 想法按时间混排，靠类型标识区分（参照华为阅读） */
class NoteItem {
  key: string = '';
  kind: number = NOTE_KIND_BOOKMARK;
  chapterTitle: string = '';
  text: string = '';
  note: string = '';
  createdAt: number = 0;
  bookmark: Bookmark | undefined = undefined;
  annotation: Annotation | undefined = undefined;
}

@ComponentV2
export struct ReaderPanels {
  @Param panel: string = '';
  @Param bookTitle: string = '';
  // 目录用的章节表可能上千条，@Param 会在父组件每次刷新时深拷贝整表；
  // 本组件只读不改：@Param 单向传入即可，不需要双向绑定
  @Param chapters: ChapterMeta[] = [];
  @Param currentChapter: number = 0;
  // 当前章内偏移：目录里「当前读到」右侧的位置数字
  @Param currentOffset: number = 0;
  @Param bookmarks: Bookmark[] = [];
  @Param annotations: Annotation[] = [];
  @Param isImageBook: boolean = false;
  @Param pageTurn: PageTurnMode = PageTurnMode.VERTICAL;
  @Param fontSize: number = 18;
  @Param lineHeightRatio: number = 1.7;
  @Param fontFamily: string = '';
  @Param fontList: string[] = [];
  @Param textAlignMode: TextAlignMode = TextAlignMode.AUTO;
  @Param theme: ReadingTheme = ReadingTheme.EYE;
  @Param colors: ReaderThemeColors = new ReaderThemeColors();
  // 阅读设置：页脚时间电量开关
  @Param showFooterTime: boolean = true;
  // 全文搜索：关键字、进行中状态与进度、结果、逐书历史
  @Param searchKeyword: string = '';
  @Param searchRunning: boolean = false;
  @Param searchProgress: string = '';
  @Param searchResults: SearchHit[] = [];
  @Param searchHistory: string[] = [];

  @Event onClose: () => void = (): void => {};
  // 点面板外的正文区遮罩：连控制栏一起收起，直接回到可翻页的阅读状态
  @Event onDismissToReading: () => void = (): void => {};
  @Event onSelectChapter: (index: number) => void = (index: number): void => {};
  @Event onSelectBookmark: (bookmark: Bookmark) => void = (bookmark: Bookmark): void => {};
  @Event onDeleteBookmark: (bookmark: Bookmark) => void = (bookmark: Bookmark): void => {};
  @Event onSelectAnnotation: (annotation: Annotation) => void = (annotation: Annotation): void => {};
  @Event onDeleteAnnotation: (annotation: Annotation) => void = (annotation: Annotation): void => {};
  @Event onFontSizeChange: (size: number) => void = (size: number): void => {};
  @Event onLineHeightChange: (ratio: number) => void = (ratio: number): void => {};
  @Event onThemeChange: (theme: ReadingTheme) => void = (theme: ReadingTheme): void => {};
  // 目录 / 笔记共用一个抽屉，切换 tab 时由父组件改 panel
  @Event onSwitchPanel: (name: string) => void = (name: string): void => {};
  @Event onFontFamilyChange: (family: string) => void = (family: string): void => {};
  @Event onTextAlignChange: (mode: TextAlignMode) => void = (mode: TextAlignMode): void => {};
  @Event onPageTurnChange: (mode: PageTurnMode) => void = (mode: PageTurnMode): void => {};
  @Event onToggleBookmark: () => void = (): void => {};
  // 操作面板专用：跳章后保持面板打开，由用户自己关闭
  @Event onJumpChapter: (index: number) => void = (index: number): void => {};
  // 阅读设置：页脚时间电量
  @Event onToggleFooterTime: (value: boolean) => void = (value: boolean): void => {};
  // 全文搜索
  @Event onSearch: (keyword: string) => void = (keyword: string): void => {};
  @Event onCancelSearch: () => void = (): void => {};
  @Event onSelectSearchHit: (hit: SearchHit) => void = (hit: SearchHit): void => {};
  @Event onClearSearchHistory: () => void = (): void => {};

  // 目录分档：0 = 全部，n = 第 n 段（每段 30 章）
  @Local rangeIndex: number = 0;
  // 笔记筛选（全部 / 书签 / 想法 / 划线）
  @Local noteFilter: number = 0;
  // 滑块拖动中的临时值（松手才提交，避免每次移动都触发重新分页）
  @Local fontSizePreview: number = 0;
  @Local lineIndexPreview: number = 0;
  @Local progressPreview: number = -1;
  // 搜索框内容（回车或点「搜索」才提交给父组件，避免每输入一个字就全库扫）
  @Local searchInput: string = '';
  private catalogScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // 重新打开面板时沿用上次的关键字
    this.searchInput = this.searchKeyword;
  }

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

  /**
   * 目录当前档位的绝对章号列表。
   *
   * 列表项一律用「绝对章号」作为数据源，而不是「全量数组 + 档首偏移 + 相对 index」：
   * 后者一旦 ForEach 的 index 与数据源错位（分档切换后 key 复用、列表重建时机等），
   * 点击算出来的章号就会整体偏移 —— 表现为「点了目录里的某章，跳到更后面」。
   */
  private visibleIndexes(): number[] {
    const start = this.rangeStart();
    const end = this.rangeEnd();
    const list: number[] = [];
    for (let i = start; i < end; i++) {
      list.push(i);
    }
    return list;
  }

  private chapterCharCount(index: number): number {
    const chapter = this.chapters[index];
    return chapter !== undefined ? chapter.charCount : 0;
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

  /** 翻页菜单：图片书只提供「横滑 / 上下滑动」，没有仿真，也没有「无动效」 */
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
    if (!this.isImageBook) {
      items.push({
        value: pageTurnLabel(PageTurnMode.NONE),
        action: (): void => {
          this.onPageTurnChange(PageTurnMode.NONE);
        }
      });
    }
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
    if (this.panel === 'search') {
      return '全文搜索';
    }
    return '阅读设置';
  }

  private chapterTitleOf(index: number): string {
    const chapter = this.chapters[index];
    return chapter !== undefined ? chapter.title : `第 ${index + 1} 章`;
  }

  @Builder
  catalogPanel() {
    List({ scroller: this.catalogScroller }) {
      ForEach(this.visibleIndexes(), (abs: number) => {
        ListItem() {
          Column() {
            Row() {
              Text(this.chapterTitleOf(abs))
                .layoutWeight(1)
                .fontSize(14)
                .fontWeight(this.currentChapter === abs ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.colors.panelText)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (!this.isImageBook) {
                Text(`${this.chapterCharCount(abs)}`)
                  .fontSize(11)
                  .fontColor(this.colors.panelSubText)
                  .margin({ left: 10 })
              }
            }
            .width('100%')
            .height(44)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.onSelectChapter(abs);
            })

            // 当前阅读位置：标题下方单独一行，跟随参考样式
            if (this.currentChapter === abs) {
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
      }, (abs: number) => `${abs}_${this.chapterTitleOf(abs)}`)
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
        Text('阅读时点右上角「···」→ 添加书签，即可记录当前位置')
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

  /** 笔记全量：书签 + 划线 + 想法合成一条时间线 */
  private noteItems(): NoteItem[] {
    const list: NoteItem[] = [];
    for (let i = 0; i < this.bookmarks.length; i++) {
      const bm: Bookmark = this.bookmarks[i];
      const item = new NoteItem();
      item.key = `b_${bm.id}`;
      item.kind = NOTE_KIND_BOOKMARK;
      item.chapterTitle = bm.chapterTitle;
      item.text = bm.preview;
      item.createdAt = bm.createdAt;
      item.bookmark = bm;
      list.push(item);
    }
    for (let i = 0; i < this.annotations.length; i++) {
      const ann: Annotation = this.annotations[i];
      const item = new NoteItem();
      item.key = `a_${ann.id}_${ann.note.length}`;
      item.kind = ann.note.length > 0 ? NOTE_KIND_THOUGHT : NOTE_KIND_HIGHLIGHT;
      item.chapterTitle = this.chapterTitleOf(ann.chapterIndex);
      item.text = ann.text;
      item.note = ann.note;
      item.createdAt = ann.createdAt > 0 ? ann.createdAt : ann.updatedAt;
      item.annotation = ann;
      list.push(item);
    }
    list.sort((a: NoteItem, b: NoteItem): number => b.createdAt - a.createdAt);
    return list;
  }

  private visibleNoteItems(): NoteItem[] {
    const all: NoteItem[] = this.noteItems();
    if (this.noteFilter === 0) {
      return all;
    }
    const result: NoteItem[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].kind === this.noteFilter) {
        result.push(all[i]);
      }
    }
    return result;
  }

  private noteFilterLabel(): string {
    if (this.noteFilter === NOTE_KIND_BOOKMARK) {
      return '书签';
    }
    if (this.noteFilter === NOTE_KIND_THOUGHT) {
      return '想法';
    }
    if (this.noteFilter === NOTE_KIND_HIGHLIGHT) {
      return '划线';
    }
    return '全部';
  }

  private noteFilterMenu(): MenuElement[] {
    const labels: string[] = ['全部', '书签', '想法', '划线'];
    const items: MenuElement[] = [];
    for (let i = 0; i < labels.length; i++) {
      const index: number = i;
      items.push({
        value: this.noteFilter === index ? `${labels[index]} ✓` : labels[index],
        action: (): void => {
          this.noteFilter = index;
        }
      });
    }
    return items;
  }

  private noteKindLabel(kind: number): string {
    if (kind === NOTE_KIND_BOOKMARK) {
      return '书签';
    }
    if (kind === NOTE_KIND_THOUGHT) {
      return '想法';
    }
    return '划线';
  }

  private noteBadgeBg(kind: number): string {
    return kind === NOTE_KIND_THOUGHT ? this.colors.accent : this.colors.chipBg;
  }

  private noteBadgeColor(kind: number): string {
    if (kind === NOTE_KIND_BOOKMARK) {
      return this.colors.annotationLine;
    }
    if (kind === NOTE_KIND_THOUGHT) {
      return this.colors.accentText;
    }
    return this.colors.chipText;
  }

  private openNoteItem(item: NoteItem): void {
    const bm: Bookmark | undefined = item.bookmark;
    if (bm !== undefined) {
      this.onSelectBookmark(bm);
      return;
    }
    const ann: Annotation | undefined = item.annotation;
    if (ann !== undefined) {
      this.onSelectAnnotation(ann);
    }
  }

  private deleteNoteItem(item: NoteItem): void {
    const bm: Bookmark | undefined = item.bookmark;
    if (bm !== undefined) {
      this.onDeleteBookmark(bm);
      return;
    }
    const ann: Annotation | undefined = item.annotation;
    if (ann !== undefined) {
      this.onDeleteAnnotation(ann);
    }
  }

  /** 笔记筛选条：全部 ▾（全部 / 书签 / 想法 / 划线），与目录分档同一套胶囊样式 */
  @Builder
  noteFilterBar() {
    Row() {
      Row() {
        Text(this.noteFilterLabel())
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
      .bindMenu(this.noteFilterMenu())

      Blank()
      Text(`共 ${this.noteItems().length} 条`)
        .fontSize(12)
        .fontColor(this.colors.panelSubText)
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
  }

  /** 笔记一行：左侧类型标识区分书签 / 划线 / 想法，点击回原文，右侧删除 */
  @Builder
  noteRow(item: NoteItem) {
    Row() {
      Column() {
        Row() {
          Text(this.noteKindLabel(item.kind))
            .fontSize(11)
            .fontColor(this.noteBadgeColor(item.kind))
            .backgroundColor(this.noteBadgeBg(item.kind))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
          Text(item.chapterTitle)
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
        this.openNoteItem(item);
      })

      Text('删除')
        .fontSize(13)
        .fontColor(this.colors.danger)
        .padding({ left: 12, top: 8, bottom: 8 })
        .onClick(() => {
          this.deleteNoteItem(item);
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: 1 }, color: this.colors.divider })
  }

  /** 笔记：书签 + 划线 + 想法混排，点击回到原文位置 */
  @Builder
  notesPanel() {
    if (this.visibleNoteItems().length === 0) {
      Column() {
        Text(this.noteFilter === 0 ? '还没有笔记' : '这一类还没有内容')
          .fontSize(15)
          .fontColor(this.colors.panelSubText)
        Text('长按正文可划线或写想法；右上角「···」可添加书签')
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
        ForEach(this.visibleNoteItems(), (item: NoteItem) => {
          ListItem() {
            this.noteRow(item)
          }
          .width('100%')
        }, (item: NoteItem) => item.key)
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
          Text('笔记（书签 / 划线 / 想法）')
            .fontSize(14)
            .fontColor(this.colors.panelText)
          Blank()
          Text(`${this.bookmarks.length + this.annotations.length} 条`)
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

        if (!this.isImageBook) {
          Row() {
            Text('页脚显示时间与电量')
              .fontSize(14)
              .fontColor(this.colors.panelText)
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.showFooterTime })
              .selectedColor(this.colors.accent)
              .switchPointColor('#FFFFFF')
              .onChange((isOn: boolean) => {
                this.onToggleFooterTime(isOn);
              })
          }
          .width('100%')
          .height(48)
          .alignItems(VerticalAlign.Center)
          .border({ width: { bottom: 1 }, color: this.colors.divider })
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
            Text(`${this.bookmarks.length + this.annotations.length}`)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.colors.panelText)
            Text('条')
              .fontSize(12)
              .fontColor(this.colors.panelSubText)
              .margin({ left: 2, bottom: 3 })
          }
          .alignItems(VerticalAlign.Bottom)

          Text('我的笔记 ›')
            .fontSize(11)
            .fontColor(this.colors.panelSubText)
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          this.onSwitchPanel('notes');
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
        this.segmentTab('笔记', 'notes')
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
        this.noteFilterBar()
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

  /** 提交搜索：空关键字忽略（输入框内容由子组件自己维护） */
  private submitSearch(keyword: string): void {
    const text: string = keyword.trim();
    if (text.length === 0) {
      return;
    }
    this.searchInput = text;
    this.onSearch(text);
  }

  /** 单条搜索结果：章名 + 前后文片段（关键字用强调色标出） */
  @Builder
  searchResultItem(item: SearchHit) {
    Column() {
      Text(item.chapterTitle)
        .width('100%')
        .fontSize(13)
        .fontColor(this.colors.panelText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 6 })
      Text() {
        Span(item.before)
          .fontColor(this.colors.panelSubText)
        Span(item.match)
          .fontColor(this.colors.danger)
        Span(item.after)
          .fontColor(this.colors.panelSubText)
      }
      .width('100%')
      .fontSize(13)
      .lineHeight(20)
      .maxLines(3)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor(this.colors.chipBg)
      .borderRadius(10)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      this.onSelectSearchHit(item);
    })
  }

  /** 搜索历史条目 */
  @Builder
  historyChip(keyword: string) {
    Text(keyword)
      .fontSize(13)
      .fontColor(this.colors.chipText)
      .backgroundColor(this.colors.chipBg)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .margin({ right: 8, bottom: 8 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .onClick(() => {
        this.submitSearch(keyword);
      })
  }

  /** 全文搜索：输入框 + 搜索历史 / 进行中进度 / 结果列表 */
  @Builder
  searchSheet() {
    Column() {
      Row() {
        Text('全文搜索')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.colors.panelText)
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

      Search({ value: this.searchInput, placeholder: '搜索本书内容' })
        .width('100%')
        .height(40)
        .backgroundColor(this.colors.chipBg)
        .fontColor(this.colors.panelText)
        .placeholderColor(this.colors.panelSubText)
        .placeholderFont({ size: 14 })
        .textFont({ size: 14 })
        .caretStyle({ color: this.colors.accent })
        .searchButton('搜索')
        .onChange((value: string) => {
          this.searchInput = value;
        })
        .onSubmit((value: string) => {
          this.submitSearch(value);
        })

      if (this.searchRunning) {
        Column() {
          LoadingProgress()
            .width(30)
            .height(30)
            .color(this.colors.accent)
          Text(this.searchProgress.length > 0 ? `正在搜索 ${this.searchProgress}` : '正在搜索…')
            .fontSize(12)
            .fontColor(this.colors.panelSubText)
            .margin({ top: 10 })
          Text('取消')
            .fontSize(13)
            .fontColor(this.colors.accent)
            .padding(10)
            .onClick(() => {
              this.onCancelSearch();
            })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.searchResults.length > 0) {
        Row() {
          Text(`找到 ${this.searchResults.length} 处`)
            .fontSize(12)
            .fontColor(this.colors.panelSubText)
          Blank()
          Text(this.searchKeyword)
            .fontSize(12)
            .fontColor(this.colors.accent)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '60%' })
        }
        .width('100%')
        .height(34)
        .alignItems(VerticalAlign.Center)

        List() {
          ForEach(this.searchResults, (item: SearchHit) => {
            ListItem() {
              this.searchResultItem(item)
            }
            .width('100%')
          }, (item: SearchHit) => `${item.chapterIndex}_${item.charOffset}`)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: this.colors.divider, startMargin: 0, endMargin: 0 })
        .scrollBar(BarState.Off)
      } else if (this.searchKeyword.length > 0) {
        Column() {
          Text('没有找到相关内容')
            .fontSize(14)
            .fontColor(this.colors.panelSubText)
          Text(`关键字：${this.searchKeyword}`)
            .fontSize(12)
            .fontColor(this.colors.panelSubText)
            .margin({ top: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Row() {
          Text('搜索历史')
            .fontSize(14)
            .fontColor(this.colors.panelText)
          Blank()
          if (this.searchHistory.length > 0) {
            Text('清空')
              .fontSize(13)
              .fontColor(this.colors.panelSubText)
              .padding({ left: 10, top: 6, bottom: 6 })
              .onClick(() => {
                this.onClearSearchHistory();
              })
          }
        }
        .width('100%')
        .height(40)
        .alignItems(VerticalAlign.Center)

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.searchHistory, (item: string) => {
            this.historyChip(item)
          }, (item: string) => item)
        }
        .width('100%')

        if (this.searchHistory.length === 0) {
          Text('在全书范围内查找关键字，点击结果可跳转到原文位置')
            .width('100%')
            .fontSize(12)
            .fontColor(this.colors.panelSubText)
            .lineHeight(18)
        }
        Blank()
      }
    }
    .width('calc(100% - 24vp)')
    .height('72%')
    .margin({ bottom: CONTROL_BAR_SPACE })
    .backgroundColor(this.colors.bg)
    .borderRadius(20)
    .border({ width: 1, color: this.colors.divider })
    .shadow({ radius: 24, color: '#26000000', offsetX: 0, offsetY: 6 })
    .padding({ left: 18, right: 18, bottom: 18 })
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
    .height(this.panel === 'bookmarks' ? '58%' : SETTINGS_SHEET_HEIGHT)
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
            this.onDismissToReading();
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
      } else if (this.panel === 'search') {
        this.searchSheet()
      } else {
        this.plainSheet()
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
