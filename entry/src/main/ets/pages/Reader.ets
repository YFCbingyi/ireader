import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BookManifest,
  Bookmark,
  BookMeta,
  BookType,
  ChapterMeta,
  ImageEntry,
  ReaderParams,
  ReaderSettings,
  ReadingMode,
  ReadingProgress
} from '../model/BookModels';
import { AppPaths } from '../utils/AppPaths';
import { FileUtil } from '../utils/FileUtil';
import { LibraryStore } from '../service/LibraryStore';
import { ReadingStatsStore } from '../service/ReadingStatsStore';
import { ReaderTheme, ReaderThemeColors, ReadingTheme } from '../model/ReaderTheme';
import { TextReaderView } from '../components/reader/TextReaderView';
import { ImageReaderView } from '../components/reader/ImageReaderView';
import { ReaderPanels } from '../components/reader/ReaderPanels';

// 章节全文缓存：最近 12 章、单章不超过 40 万字符
const CHAPTER_CACHE_LIMIT = 12;
const CHAPTER_CACHE_MAX_CHARS = 400000;
const DOMAIN = 0x0006;
const TAG = 'Reader';

@Entry
@Component
struct Reader {
  @State book: BookMeta = new BookMeta();
  @State manifest: BookManifest = new BookManifest();
  @State settings: ReaderSettings = new ReaderSettings();
  @State bookmarks: Bookmark[] = [];
  @State chapterIndex: number = 0;
  @State chapterTitle: string = '';
  @State chapterContent: string = '';
  @State chapterImages: ImageEntry[] = [];
  @State readingMode: ReadingMode = ReadingMode.VERTICAL;
  @State fontSize: number = 18;
  @State lineHeightRatio: number = 1.7;
  @State loading: boolean = true;
  @State errorText: string = '';
  @State controlsVisible: boolean = false;
  // 翻章/跳转期间的纯色遮挡：盖住数据源重建与定位之间的空白帧，避免闪烁
  @State turnMaskVisible: boolean = false;
  // 竖排连续卷轴的跳转目标（初始打开 / 目录 / 书签），jumpVersion 变化触发子组件重建窗口
  @State jumpVersion: number = 0;
  @State jumpChapter: number = 0;
  @State jumpOffset: number = 0;
  @State jumpIndex: number = 0;
  @State jumpRatio: number = 0;
  @State panel: string = '';
  @State loadVersion: number = 0;
  @State startCharOffset: number = 0;
  @State startImageIndex: number = 0;
  @State startImageRatio: number = 0;
  @State progressLabel: string = '';
  @State bookmarked: boolean = false;
  @State theme: ReadingTheme = ReadingTheme.EYE;
  @State palette: ReaderThemeColors = ReaderTheme.eye();
  @StorageProp('systemColorMode') @Watch('onSystemColorModeChanged') systemColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  @StorageProp('appActive') @Watch('onAppActiveChanged') appActive: boolean = true;

  private bookId: string = '';
  private progressChapter: number = 0;
  private progressCharOffset: number = 0;
  private progressPageIndex: number = 0;
  private progressRatio: number = 0;
  private saveTimer: number = -1;
  private sessionRunning: boolean = false;
  private sessionStartAt: number = 0;
  private sessionTimer: number = -1;
  private chapterTextCache: Map<string, string> = new Map();
  private cacheKeys: string[] = [];
  private readerWindow: window.Window | undefined = undefined;
  private turnMaskTimer: number = -1;
  // 章节加载序号：异步翻章期间做竞态保护，只让最后一次加载的结果生效
  private chapterLoadSeq: number = 0;

  async aboutToAppear(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPaths.init(context.filesDir);
    LibraryStore.init();
    const raw = this.getUIContext().getRouter().getParams();
    const params = raw as ReaderParams;
    if (params !== undefined && params !== null && params.bookId !== undefined) {
      this.bookId = params.bookId;
    }
    if (this.bookId.length === 0) {
      this.errorText = '未找到书籍';
      this.loading = false;
      return;
    }
    const found = LibraryStore.getBook(this.bookId);
    if (found === undefined) {
      this.errorText = '书籍不存在或已被删除';
      this.loading = false;
      return;
    }
    this.book = found;
    this.settings = LibraryStore.getSettings();
    this.theme = this.settings.theme;
    this.applyTheme();
    this.fontSize = this.settings.fontSize;
    this.lineHeightRatio = this.settings.lineHeightRatio;
    this.readingMode = this.book.readingMode;
    this.manifest = LibraryStore.getManifest(this.bookId);
    this.bookmarks = LibraryStore.getBookmarks(this.bookId);
    if (this.manifest.chapters.length === 0) {
      this.errorText = '书籍内容为空';
      this.loading = false;
      return;
    }

    let savedChapter = this.book.progress.chapterIndex;
    if (savedChapter < 0) {
      savedChapter = 0;
    }
    if (savedChapter >= this.manifest.chapters.length) {
      savedChapter = this.manifest.chapters.length - 1;
    }
    await this.openChapter(savedChapter, this.book.progress.charOffset, this.book.progress.pageIndex,
      this.book.progress.scrollRatio, false);
    this.loading = false;
    this.startReadingSession();
  }

  onPageShow(): void {
    this.startReadingSession();
    this.enterImmersive();
  }

  onPageHide(): void {
    this.stopReadingSession();
    this.flushProgress();
    this.exitImmersive();
  }

  aboutToDisappear(): void {
    this.stopReadingSession();
    this.flushProgress();
    this.clearTurnMaskTimer();
    this.exitImmersive();
  }

  private async enterImmersive(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win = await window.getLastWindow(context);
      this.readerWindow = win;
      await win.setWindowLayoutFullScreen(true);
      await win.setWindowSystemBarEnable([]);
    } catch (e) {
      const err = e as BusinessError;
      console.error(`enter immersive failed: ${err.message}`);
    }
  }

  private async exitImmersive(): Promise<void> {
    const win = this.readerWindow;
    if (win === undefined) {
      return;
    }
    this.readerWindow = undefined;
    try {
      // 只恢复系统栏可见，保持窗口全屏布局，避免返回首页后背景无法铺满整屏
      await win.setWindowSystemBarEnable(['status', 'navigation']);
    } catch (e) {
      const err = e as BusinessError;
      console.error(`exit immersive failed: ${err.message}`);
    }
  }

  onBackPress(): boolean {
    if (this.panel.length > 0) {
      this.panel = '';
      return true;
    }
    this.stopReadingSession();
    this.flushProgress();
    return false;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      const err = e as BusinessError;
      console.error(`toast failed: ${err.message}`);
    }
  }

  private clearSaveTimer(): void {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
  }

  /** 翻章/跳转期间盖一层纯色遮挡，内容定位完成或超时后再揭开 */
  private showTurnMask(): void {
    this.clearTurnMaskTimer();
    this.turnMaskVisible = true;
    this.turnMaskTimer = setTimeout(() => {
      this.turnMaskVisible = false;
      this.turnMaskTimer = -1;
    }, 400);
  }

  private clearTurnMaskTimer(): void {
    if (this.turnMaskTimer !== -1) {
      clearTimeout(this.turnMaskTimer);
      this.turnMaskTimer = -1;
    }
  }

  private onReaderReady(): void {
    this.clearTurnMaskTimer();
    this.turnMaskVisible = false;
  }

  private startReadingSession(): void {
    if (this.sessionRunning || this.bookId.length === 0 || this.errorText.length > 0) {
      return;
    }
    this.sessionRunning = true;
    this.sessionStartAt = Date.now();
    this.sessionTimer = setInterval(() => {
      this.flushReadingSession();
    }, 30000);
  }

  private flushReadingSession(): void {
    if (!this.sessionRunning) {
      return;
    }
    const now = Date.now();
    const elapsed = Math.floor((now - this.sessionStartAt) / 1000);
    this.sessionStartAt = now;
    if (elapsed > 0) {
      ReadingStatsStore.addSeconds(elapsed);
    }
  }

  private stopReadingSession(): void {
    if (!this.sessionRunning) {
      return;
    }
    this.flushReadingSession();
    this.sessionRunning = false;
    if (this.sessionTimer !== -1) {
      clearInterval(this.sessionTimer);
      this.sessionTimer = -1;
    }
  }

  private onAppActiveChanged(): void {
    if (this.appActive) {
      this.startReadingSession();
    } else {
      this.stopReadingSession();
    }
  }

  private async openChapter(index: number, charOffset: number, imageIndex: number, imageRatio: number,
    save: boolean): Promise<void> {
    let target = index;
    if (target < 0) {
      target = 0;
    }
    if (target >= this.manifest.chapters.length) {
      target = this.manifest.chapters.length - 1;
    }
    if (target < 0) {
      return;
    }
    const chapter: ChapterMeta = this.manifest.chapters[target];
    this.chapterLoadSeq++;
    const seq = this.chapterLoadSeq;
    this.chapterIndex = target;
    this.chapterTitle = chapter.title;
    // 左右翻页需要重分页，短暂遮挡避免空白帧；竖排连续卷轴不重建页面，保持平滑
    if (!this.loading && this.readingMode === ReadingMode.HORIZONTAL) {
      this.showTurnMask();
    }
    if (this.book.type === BookType.TEXT) {
      this.chapterImages = [];
      if (this.readingMode === ReadingMode.VERTICAL) {
        // 竖排：正文由子组件按章异步加载窗口，这里立即下发跳转，避免等待整章读盘
        this.applyJump(target, charOffset, imageIndex, imageRatio, save);
        setTimeout(() => {
          this.prefetchAround(target);
        }, 120);
        return;
      }
      const applied = await this.loadTextChapter(target, seq);
      if (!applied) {
        return;
      }
    } else {
      this.chapterContent = '';
      this.chapterImages = chapter.images;
      if (this.readingMode === ReadingMode.VERTICAL) {
        this.applyJump(target, charOffset, imageIndex, imageRatio, save);
        return;
      }
    }
    // 期间又发起了新的切章，本次结果作废
    if (seq !== this.chapterLoadSeq) {
      return;
    }
    this.applyJump(target, charOffset, imageIndex, imageRatio, save);
    this.prefetchAround(target);
  }

  /** 更新跳转目标与进度，并通知子组件（竖排重建窗口 / 左右重新分页） */
  private applyJump(target: number, charOffset: number, imageIndex: number, imageRatio: number,
    save: boolean): void {
    this.startCharOffset = charOffset;
    this.startImageIndex = imageIndex;
    this.startImageRatio = imageRatio;
    this.progressChapter = target;
    this.progressCharOffset = charOffset;
    this.progressPageIndex = imageIndex;
    this.progressRatio = imageRatio;
    this.jumpChapter = target;
    this.jumpOffset = charOffset;
    this.jumpIndex = imageIndex;
    this.jumpRatio = imageRatio;
    this.jumpVersion++;
    this.loadVersion++;
    this.updateProgressLabel();
    this.updateBookmarkState();
    if (save) {
      // 切章不阻塞本帧：进度已在内存字段，改为防抖异步写盘（离开/隐藏页面仍有 flush 兜底）
      this.scheduleSave();
    }
  }

  /** 异步加载文本章正文，返回是否仍是当前章节（竞态保护） */
  private async loadTextChapter(index: number, seq: number): Promise<boolean> {
    const t0 = Date.now();
    const content = await this.loadChapterTextAsync(index);
    // 期间又发起了新的切章，本次结果作废，避免旧内容覆盖新章
    if (seq !== this.chapterLoadSeq) {
      return false;
    }
    this.chapterContent = content;
    hilog.debug(DOMAIN, TAG, 'loadTextChapter %{public}d io=%{public}dms',
      index, Date.now() - t0);
    return true;
  }

  /**
   * 切章后立即异步预取前后章节文本（读盘不阻塞主线程）。
   * 左右模式的分页窗口也走同一份章节缓存，预取能显著减少翻到章末时的等待。
   */
  private prefetchAround(index: number): void {
    this.prefetchChapterText(index + 1);
    this.prefetchChapterText(index - 1);
    this.prefetchChapterText(index + 2);
    this.prefetchChapterText(index - 2);
  }

  /** 异步预读单章全文（命中缓存则跳过），读完后回填章节缓存 */
  private async prefetchChapterText(index: number): Promise<void> {
    const chapter = this.manifest.chapters[index];
    if (chapter === undefined) {
      return;
    }
    const key = `${this.bookId}#${index}`;
    if (this.chapterTextCache.get(key) !== undefined) {
      return;
    }
    const text = await FileUtil.readTextAsync(AppPaths.abs(chapter.contentFile));
    if (text.length === 0) {
      return;
    }
    // 异步期间可能已被同步路径（openChapter）缓存，避免重复入队
    if (this.chapterTextCache.get(key) !== undefined) {
      return;
    }
    if (text.length <= CHAPTER_CACHE_MAX_CHARS) {
      this.putChapterText(key, text);
    }
  }

  private chapterTitleOf(index: number): string {
    const chapter = this.manifest.chapters[index];
    return chapter !== undefined ? chapter.title : '';
  }

  /** 只读缓存，不触发读盘 */
  private peekChapterText(index: number): string {
    const cached = this.chapterTextCache.get(`${this.bookId}#${index}`);
    return cached !== undefined ? cached : '';
  }

  /**
   * 异步读取章节全文，带最近若干章的内存缓存。
   * 连续阅读时相邻章节通常已缓存，切章不再同步读盘。
   */
  private async loadChapterTextAsync(index: number): Promise<string> {
    const chapter = this.manifest.chapters[index];
    if (chapter === undefined) {
      return '';
    }
    const key = `${this.bookId}#${index}`;
    const cached = this.chapterTextCache.get(key);
    if (cached !== undefined) {
      return cached;
    }
    const text = await FileUtil.readTextAsync(AppPaths.abs(chapter.contentFile));
    if (text.length <= CHAPTER_CACHE_MAX_CHARS) {
      this.putChapterText(key, text);
    }
    return text;
  }

  private putChapterText(key: string, text: string): void {
    if (this.chapterTextCache.size >= CHAPTER_CACHE_LIMIT && this.cacheKeys.length > 0) {
      const oldest = this.cacheKeys.shift();
      if (oldest !== undefined) {
        this.chapterTextCache.delete(oldest);
      }
    }
    this.chapterTextCache.set(key, text);
    this.cacheKeys.push(key);
  }

  /** 上一章：落到上一章末尾（文本为末字，图片为最后一张） */
  private previousChapter(): void {
    if (this.chapterIndex <= 0) {
      return;
    }
    const target = this.chapterIndex - 1;
    const chapter = this.manifest.chapters[target];
    let charOffset = 0;
    let imageIndex = 0;
    if (chapter !== undefined) {
      if (this.book.type === BookType.TEXT) {
        charOffset = Math.max(0, chapter.charCount);
      } else {
        imageIndex = Math.max(0, chapter.images.length - 1);
      }
    }
    this.openChapter(target, charOffset, imageIndex, 0, true);
  }

  private nextChapter(): void {
    if (this.chapterIndex < this.manifest.chapters.length - 1) {
      this.openChapter(this.chapterIndex + 1, 0, 0, 0, true);
    }
  }

  private jumpToChapter(index: number): void {
    this.panel = '';
    this.openChapter(index, 0, 0, 0, true);
  }

  private onTextProgress(chapterIndex: number, charOffset: number, ratio: number): void {
    // 连续卷轴下可见章号由子组件上报，进度 / 书签 / 目录高亮都以此为准
    this.progressChapter = chapterIndex;
    this.progressCharOffset = charOffset;
    this.progressPageIndex = 0;
    this.progressRatio = ratio;
    if (this.chapterIndex !== chapterIndex) {
      this.chapterIndex = chapterIndex;
      this.chapterTitle = this.chapterTitleOf(chapterIndex);
    }
    // 控制栏未显示时无需刷新可见文案，避免滚动过程中反复触发重建
    if (this.controlsVisible) {
      this.updateProgressLabel();
      this.updateBookmarkState();
    }
    this.scheduleSave();
  }

  private onImageProgress(chapterIndex: number, imageIndex: number, intraRatio: number): void {
    this.progressChapter = chapterIndex;
    this.progressPageIndex = imageIndex;
    this.progressRatio = intraRatio;
    this.progressCharOffset = 0;
    if (this.chapterIndex !== chapterIndex) {
      this.chapterIndex = chapterIndex;
      this.chapterTitle = this.chapterTitleOf(chapterIndex);
    }
    if (this.controlsVisible) {
      this.updateProgressLabel();
      this.updateBookmarkState();
    }
    this.scheduleSave();
  }

  private computePercent(): number {
    const chapterCount = Math.max(1, this.manifest.chapters.length);
    let chapter = this.manifest.chapters[this.progressChapter];
    if (chapter === undefined) {
      chapter = this.manifest.chapters[0];
    }
    let percent = 0;
    if (this.book.type === BookType.TEXT) {
      const charCount = chapter !== undefined ? Math.max(1, chapter.charCount) : 1;
      let offset = this.progressCharOffset;
      if (offset < 0) {
        offset = 0;
      }
      if (offset > charCount) {
        offset = charCount;
      }
      percent = (this.progressChapter + offset / charCount) / chapterCount;
    } else {
      const imageCount = chapter !== undefined ? Math.max(1, chapter.images.length) : 1;
      let index = this.progressPageIndex;
      if (index < 0) {
        index = 0;
      }
      let ratio = this.progressRatio;
      if (ratio < 0) {
        ratio = 0;
      }
      if (ratio > 1) {
        ratio = 1;
      }
      percent = (this.progressChapter + (index + ratio) / imageCount) / chapterCount;
    }
    if (percent < 0) {
      percent = 0;
    }
    if (percent > 1) {
      percent = 1;
    }
    return percent;
  }

  private updateProgressLabel(): void {
    const total = Math.max(1, this.manifest.chapters.length);
    const percent = Math.round(this.computePercent() * 100);
    this.progressLabel = `第 ${this.progressChapter + 1}/${total} 章 · ${percent}%`;
  }

  private scheduleSave(): void {
    this.clearSaveTimer();
    this.saveTimer = setTimeout(() => {
      this.flushProgress();
    }, 800);
  }

  private flushProgress(): void {
    if (this.bookId.length === 0 || this.errorText.length > 0) {
      return;
    }
    this.clearSaveTimer();
    if (this.book.progress === undefined) {
      this.book.progress = new ReadingProgress();
    }
    this.book.progress.chapterIndex = this.progressChapter;
    this.book.progress.charOffset = this.progressCharOffset;
    this.book.progress.pageIndex = this.progressPageIndex;
    this.book.progress.scrollRatio = this.progressRatio;
    this.book.progress.percent = this.computePercent();
    this.book.progress.updatedAt = Date.now();
    this.book.updatedAt = Date.now();
    LibraryStore.saveBook(this.book);
  }

  private makePreview(chapter: ChapterMeta): string {
    if (this.book.type === BookType.TEXT) {
      // 连续卷轴下可见章可能不是打开的目标章，按进度章缓存取预览文本
      const full = this.peekChapterText(this.progressChapter);
      let text = full.substring(this.progressCharOffset, this.progressCharOffset + 40);
      text = text.split(new RegExp('\\s+')).join(' ').trim();
      return text.length > 0 ? text : chapter.title;
    }
    return `第 ${this.progressPageIndex + 1} 页`;
  }

  private updateBookmarkState(): void {
    let found = false;
    for (let i = 0; i < this.bookmarks.length; i++) {
      const bookmark = this.bookmarks[i];
      if (bookmark.chapterIndex !== this.chapterIndex) {
        continue;
      }
      if (this.book.type === BookType.TEXT) {
        if (Math.abs(bookmark.charOffset - this.progressCharOffset) < 50) {
          found = true;
          break;
        }
      } else {
        if (bookmark.pageIndex === this.progressPageIndex) {
          found = true;
          break;
        }
      }
    }
    this.bookmarked = found;
  }

  private toggleBookmark(): void {
    if (this.manifest.chapters.length === 0) {
      return;
    }
    const chapter = this.manifest.chapters[this.chapterIndex];
    let existing = -1;
    for (let i = 0; i < this.bookmarks.length; i++) {
      const bookmark = this.bookmarks[i];
      if (bookmark.chapterIndex !== this.chapterIndex) {
        continue;
      }
      if (this.book.type === BookType.TEXT) {
        if (Math.abs(bookmark.charOffset - this.progressCharOffset) < 50) {
          existing = i;
          break;
        }
      } else {
        if (bookmark.pageIndex === this.progressPageIndex) {
          existing = i;
          break;
        }
      }
    }
    if (existing >= 0) {
      this.bookmarks.splice(existing, 1);
      LibraryStore.saveBookmarks(this.bookId, this.bookmarks);
      this.updateBookmarkState();
      this.toast('已删除书签');
      return;
    }
    const bookmark = Bookmark.of(this.bookId, this.chapterIndex, chapter.title);
    bookmark.charOffset = this.progressCharOffset;
    bookmark.pageIndex = this.progressPageIndex;
    bookmark.scrollRatio = this.progressRatio;
    bookmark.preview = this.makePreview(chapter);
    this.bookmarks.splice(0, 0, bookmark);
    if (this.bookmarks.length > 200) {
      this.bookmarks = this.bookmarks.slice(0, 200);
    }
    LibraryStore.saveBookmarks(this.bookId, this.bookmarks);
    this.updateBookmarkState();
    this.toast('已添加书签');
  }

  private jumpToBookmark(bookmark: Bookmark): void {
    this.panel = '';
    this.openChapter(bookmark.chapterIndex, bookmark.charOffset, bookmark.pageIndex,
      bookmark.scrollRatio, true);
  }

  private deleteBookmark(bookmark: Bookmark): void {
    const remain: Bookmark[] = [];
    for (let i = 0; i < this.bookmarks.length; i++) {
      if (this.bookmarks[i].id !== bookmark.id) {
        remain.push(this.bookmarks[i]);
      }
    }
    this.bookmarks = remain;
    LibraryStore.saveBookmarks(this.bookId, this.bookmarks);
    this.updateBookmarkState();
  }

  private changeMode(mode: ReadingMode): void {
    const previous = this.readingMode;
    this.readingMode = mode;
    this.book.readingMode = mode;
    this.book.updatedAt = Date.now();
    LibraryStore.saveBook(this.book);
    if (previous !== mode) {
      // 用当前进度章重新打开，保证两种模式切换后定位一致
      this.openChapter(this.progressChapter, this.progressCharOffset, 0, this.progressRatio, false);
    }
  }

  private changeFontSize(size: number): void {
    let next = size;
    if (next < 14) {
      next = 14;
    }
    if (next > 30) {
      next = 30;
    }
    this.fontSize = next;
    this.settings.fontSize = next;
    LibraryStore.saveSettings(this.settings);
  }

  private changeLineHeight(ratio: number): void {
    this.lineHeightRatio = ratio;
    this.settings.lineHeightRatio = ratio;
    LibraryStore.saveSettings(this.settings);
  }

  private isSystemDark(): boolean {
    return this.systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private applyTheme(): void {
    this.palette = ReaderTheme.resolve(this.theme, this.isSystemDark());
  }

  private onSystemColorModeChanged(): void {
    if (this.theme === ReadingTheme.SYSTEM) {
      this.applyTheme();
    }
  }

  private changeTheme(theme: ReadingTheme): void {
    this.theme = theme;
    this.settings.theme = theme;
    LibraryStore.saveSettings(this.settings);
    this.applyTheme();
  }

  private barBackground(): string {
    return this.book.type === BookType.IMAGE ? '#B3000000' : this.palette.barBg;
  }

  private barTextColor(): string {
    return this.book.type === BookType.IMAGE ? '#FFFFFF' : this.palette.barText;
  }

  private pageBackground(): string {
    return this.book.type === BookType.IMAGE ? '#000000' : this.palette.bg;
  }

  /** 控制栏显隐：仅在打开时刷新进度与书签文案，减少滚动期间的无效重建 */
  private toggleControls(): void {
    if (this.controlsVisible) {
      this.controlsVisible = false;
      return;
    }
    this.updateProgressLabel();
    this.updateBookmarkState();
    this.controlsVisible = true;
  }

  private openPanel(name: string): void {
    if (this.panel === name) {
      this.panel = '';
    } else {
      this.panel = name;
    }
  }

  private goBack(): void {
    this.flushProgress();
    this.getUIContext().getRouter().back();
  }

  @Builder
  loadingView() {
    Column() {
      LoadingProgress()
        .width(44)
        .height(44)
        .color(this.palette.accent)
      Text('正在加载…')
        .fontSize(14)
        .fontColor(this.palette.subText)
        .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.pageBackground())
  }

  @Builder
  errorView() {
    Column() {
      Text(this.errorText)
        .fontSize(16)
        .fontColor(this.palette.text)
      Button('返回书架')
        .type(ButtonType.Capsule)
        .backgroundColor(this.palette.accent)
        .fontColor(this.palette.accentText)
        .fontSize(14)
        .margin({ top: 18 })
        .onClick(() => {
          this.getUIContext().getRouter().back();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.pageBackground())
  }

  build() {
    Stack() {
      if (this.loading) {
        this.loadingView()
      } else if (this.errorText.length > 0) {
        this.errorView()
      } else if (this.book.type === BookType.TEXT) {
        TextReaderView({
          content: this.chapterContent,
          chapterTitle: this.chapterTitle,
          mode: this.readingMode,
          fontSize: this.fontSize,
          lineHeightRatio: this.lineHeightRatio,
          chapterIndex: this.chapterIndex,
          chapterCount: this.manifest.chapters.length,
          startCharOffset: this.startCharOffset,
          loadVersion: this.loadVersion,
          jumpVersion: this.jumpVersion,
          jumpChapter: this.jumpChapter,
          jumpOffset: this.jumpOffset,
          chapterTitleOf: (index: number): string => {
            return this.chapterTitleOf(index);
          },
          chapterTextProvider: (index: number): Promise<string> => {
            return this.loadChapterTextAsync(index);
          },
          bgColor: this.palette.bg,
          textColor: this.palette.text,
          subTextColor: this.palette.subText,
          accentColor: this.palette.accent,
          accentTextColor: this.palette.accentText,
          controlsVisible: this.controlsVisible,
          onProgress: (chapterIndex: number, charOffset: number, ratio: number): void => {
            this.onTextProgress(chapterIndex, charOffset, ratio);
          },
          onTap: (): void => {
            this.toggleControls();
          },
          onReady: (): void => {
            this.onReaderReady();
          }
        })
      } else {
        ImageReaderView({
          images: this.chapterImages,
          mode: this.readingMode,
          chapterCount: this.manifest.chapters.length,
          startIndex: this.startImageIndex,
          startRatio: this.startImageRatio,
          loadVersion: this.loadVersion,
          jumpVersion: this.jumpVersion,
          jumpChapter: this.jumpChapter,
          jumpIndex: this.jumpIndex,
          jumpRatio: this.jumpRatio,
          chapterTitleOf: (index: number): string => {
            return this.chapterTitleOf(index);
          },
          chapterImagesOf: (index: number): ImageEntry[] => {
            const chapter: ChapterMeta | undefined = this.manifest.chapters[index];
            return chapter !== undefined ? chapter.images : [];
          },
          controlsVisible: this.controlsVisible,
          onProgress: (chapterIndex: number, imageIndex: number, intraRatio: number): void => {
            this.onImageProgress(chapterIndex, imageIndex, intraRatio);
          },
          onTap: (): void => {
            this.toggleControls();
          },
          onReady: (): void => {
            this.onReaderReady();
          }
        })
      }

      if (this.turnMaskVisible && !this.loading && this.errorText.length === 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.pageBackground())
          .hitTestBehavior(HitTestMode.Block)
      }

      if (this.controlsVisible && !this.loading && this.errorText.length === 0) {
        Column() {
          Row() {
            Text('‹ 返回')
              .fontSize(15)
              .fontColor(this.barTextColor())
              .padding({ right: 12, top: 8, bottom: 8 })
              .onClick(() => {
                this.goBack();
              })
            Column() {
              Text(this.book.title)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.barTextColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${this.chapterTitle} · ${this.progressLabel}`)
                .fontSize(11)
                .fontColor(this.barTextColor())
                .opacity(0.7)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text(this.bookmarked ? '已书签' : '书签')
              .fontSize(14)
              .fontColor(this.bookmarked ? '#D4A017' : this.barTextColor())
              .padding({ left: 12, top: 8, bottom: 8 })
              .onClick(() => {
                this.toggleBookmark();
              })
          }
          .width('100%')
          .height(96)
          .padding({ left: 16, right: 16, top: 28 })
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.barBackground())
          .onClick(() => {
          })

          // 控制栏显示时中间区域吞掉点击与滑动：既不翻页也不滚动，点击即退出控制栏
          Column() {
          }
          .width('100%')
          .layoutWeight(1)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.controlsVisible = false;
          })

          Row() {
            Text('上一章')
              .fontSize(13)
              .fontColor(this.barTextColor())
              .opacity(this.chapterIndex > 0 ? 1 : 0.35)
              .padding({ top: 10, bottom: 10 })
              .onClick(() => {
                this.previousChapter();
              })
            Text('目录')
              .fontSize(13)
              .fontColor(this.barTextColor())
              .padding({ top: 10, bottom: 10 })
              .onClick(() => {
                this.openPanel('catalog');
              })
            Text('书签')
              .fontSize(13)
              .fontColor(this.barTextColor())
              .padding({ top: 10, bottom: 10 })
              .onClick(() => {
                this.openPanel('bookmarks');
              })
            Text('设置')
              .fontSize(13)
              .fontColor(this.barTextColor())
              .padding({ top: 10, bottom: 10 })
              .onClick(() => {
                this.openPanel('settings');
              })
            Text('下一章')
              .fontSize(13)
              .fontColor(this.barTextColor())
              .opacity(this.chapterIndex < this.manifest.chapters.length - 1 ? 1 : 0.35)
              .padding({ top: 10, bottom: 10 })
              .onClick(() => {
                this.nextChapter();
              })
          }
          .width('100%')
          .height(88)
          .padding({ bottom: 26 })
          .justifyContent(FlexAlign.SpaceAround)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.barBackground())
          .onClick(() => {
          })
        }
        .width('100%')
        .height('100%')
      }

      if (this.panel.length > 0 && !this.loading && this.errorText.length === 0) {
        ReaderPanels({
          panel: this.panel,
          chapters: this.manifest.chapters,
          currentChapter: this.chapterIndex,
          bookmarks: this.bookmarks,
          isImageBook: this.book.type === BookType.IMAGE,
          readingMode: this.readingMode,
          fontSize: this.fontSize,
          lineHeightRatio: this.lineHeightRatio,
          theme: this.theme,
          colors: this.book.type === BookType.IMAGE ? ReaderTheme.eye() : this.palette,
          onClose: (): void => {
            this.panel = '';
          },
          onSelectChapter: (index: number): void => {
            this.jumpToChapter(index);
          },
          onSelectBookmark: (bookmark: Bookmark): void => {
            this.jumpToBookmark(bookmark);
          },
          onDeleteBookmark: (bookmark: Bookmark): void => {
            this.deleteBookmark(bookmark);
          },
          onModeChange: (mode: ReadingMode): void => {
            this.changeMode(mode);
          },
          onFontSizeChange: (size: number): void => {
            this.changeFontSize(size);
          },
          onLineHeightChange: (ratio: number): void => {
            this.changeLineHeight(ratio);
          },
          onThemeChange: (theme: ReadingTheme): void => {
            this.changeTheme(theme);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBackground())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
