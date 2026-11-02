import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BookManifest,
  Bookmark,
  BookMeta,
  BookType,
  ChapterMeta,
  ImageEntry,
  PageTurnMode,
  ReaderParams,
  ReaderSettings,
  ReadingMode,
  ReadingProgress,
  SearchHit,
  TextAlignMode,
  pageTurnLabel,
  textAlignLabel
} from '../model/BookModels';
import { Annotation, AnnotationKind } from '../model/Annotation';
import { AppPaths } from '../utils/AppPaths';
import { FileUtil } from '../utils/FileUtil';
import { AnnotationStore } from '../service/AnnotationStore';
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
// 空标注列表：避免每次渲染都新建数组
const EMPTY_ANNOTATIONS: Annotation[] = [];
// 全文搜索：结果上限、片段前后各取多少字、进度文案刷新间隔（ms）、历史条数上限
const SEARCH_MAX_HITS = 200;
const SEARCH_SNIPPET_CHARS = 28;
const SEARCH_PROGRESS_INTERVAL = 150;
const SEARCH_HISTORY_LIMIT = 10;

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
  @State pageTurn: PageTurnMode = PageTurnMode.VERTICAL;
  @State fontSize: number = 18;
  @State lineHeightRatio: number = 1.7;
  @State fontFamily: string = '';
  @State textAlignMode: TextAlignMode = TextAlignMode.AUTO;
  // 系统字体列表：字体选择菜单用（首次打开时取一次）
  @State fontList: string[] = [];
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
  // 顶部设置按钮的下拉菜单：阅读设置 / 添加书签 / 全文搜索
  @State menuVisible: boolean = false;
  // 阅读设置：页脚左侧时间电量
  @State showFooterTime: boolean = true;
  // 全文搜索：关键字、进行中状态与进度、结果、逐书历史
  @State searchKeyword: string = '';
  @State searchRunning: boolean = false;
  @State searchProgress: string = '';
  @State searchResults: SearchHit[] = [];
  @State searchHistory: string[] = [];
  private searchSeq: number = 0;
  // 划线 / 想法
  @State annotations: Annotation[] = [];
  @State annotationsVersion: number = 0;
  @State noteVisible: boolean = false;
  @State noteDraft: string = '';
  @State noteQuote: string = '';
  @State noteExistingId: string = '';
  // 词典卡片：先展示选中的词，由用户决定复制还是去浏览器查
  @State dictVisible: boolean = false;
  @State dictWord: string = '';
  private noteChapter: number = 0;
  private noteStart: number = 0;
  private noteEnd: number = 0;
  private annotationIndex: Map<number, Annotation[]> = new Map();
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
    this.fontFamily = this.settings.fontFamily;
    this.textAlignMode = this.settings.textAlignMode;
    this.showFooterTime = this.settings.showFooterTime;
    // 翻页方式按书类型统一：TXT 与图片书各用一套全局配置
    this.pageTurn = this.book.type === BookType.TEXT
      ? this.settings.textPageTurn
      : this.settings.imagePageTurn;
    this.readingMode = this.pageTurn === PageTurnMode.VERTICAL
      ? ReadingMode.VERTICAL : ReadingMode.HORIZONTAL;
    this.loadFontList();
    this.manifest = LibraryStore.getManifest(this.bookId);
    this.bookmarks = LibraryStore.getBookmarks(this.bookId);
    this.searchHistory = LibraryStore.getSearchHistory(this.bookId);
    this.annotations = AnnotationStore.load(this.bookId);
    this.rebuildAnnotationIndex();
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
    this.menuVisible = false;
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
    if (this.menuVisible) {
      this.menuVisible = false;
      return true;
    }
    if (this.dictVisible) {
      this.dictVisible = false;
      return true;
    }
    if (this.noteVisible) {
      this.noteVisible = false;
      return true;
    }
    if (this.panel.length > 0) {
      this.panel = '';
      if (this.searchRunning) {
        this.cancelSearch();
      }
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

  /** 操作面板内跳章：不收起面板，用户可连续翻章后再自己关 */
  private jumpToChapterKeepPanel(index: number): void {
    if (index < 0 || index >= this.manifest.chapters.length) {
      return;
    }
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

  // ================= 划线 / 想法 =================

  /** 按章分组，渲染层按章取标注（避免每次渲染线性扫描全书标注） */
  private rebuildAnnotationIndex(): void {
    this.annotationIndex.clear();
    for (let i = 0; i < this.annotations.length; i++) {
      const item = this.annotations[i];
      let list = this.annotationIndex.get(item.chapterIndex);
      if (list === undefined) {
        list = [];
        this.annotationIndex.set(item.chapterIndex, list);
      }
      list.push(item);
    }
  }

  private annotationsOf(chapter: number): Annotation[] {
    const list = this.annotationIndex.get(chapter);
    return list !== undefined ? list : EMPTY_ANNOTATIONS;
  }

  private persistAnnotations(): void {
    this.rebuildAnnotationIndex();
    this.annotationsVersion++;
    AnnotationStore.save(this.bookId, this.annotations);
  }

  /** 划线开关：选区已有标注就取消，否则新增一条高亮 */
  private toggleHighlight(chapter: number, start: number, end: number, text: string): void {
    const existing = AnnotationStore.findAt(this.annotations, chapter, start, end);
    if (existing !== undefined) {
      if (existing.kind === AnnotationKind.NOTE) {
        // 带想法的划线不在这里删，避免误删笔记
        this.toast('该段已有想法，可在“想法”里编辑或删除');
        return;
      }
      this.annotations = AnnotationStore.removeById(this.annotations, existing.id);
      this.persistAnnotations();
      this.toast('已取消划线');
      return;
    }
    const item = Annotation.of(chapter, start, end, text, '', AnnotationKind.HIGHLIGHT);
    const next: Annotation[] = this.annotations.slice();
    next.push(item);
    AnnotationStore.sort(next);
    this.annotations = next;
    this.persistAnnotations();
    this.toast('已划线');
  }

  /** 记录 / 编辑想法：选区已有标注时进入编辑态 */
  private openNoteEditor(chapter: number, start: number, end: number, text: string): void {
    const existing = AnnotationStore.findAt(this.annotations, chapter, start, end);
    this.noteChapter = chapter;
    this.noteStart = existing !== undefined ? existing.start : start;
    this.noteEnd = existing !== undefined ? existing.end : end;
    this.noteQuote = existing !== undefined && existing.text.length > 0 ? existing.text : text;
    this.noteExistingId = existing !== undefined ? existing.id : '';
    this.noteDraft = existing !== undefined ? existing.note : '';
    this.noteVisible = true;
  }

  private saveNote(): void {
    const note = this.noteDraft.trim();
    if (this.noteExistingId.length > 0) {
      const next: Annotation[] = [];
      for (let i = 0; i < this.annotations.length; i++) {
        const item = this.annotations[i];
        if (item.id === this.noteExistingId) {
          item.note = note;
          item.start = this.noteStart;
          item.end = this.noteEnd;
          item.kind = AnnotationKind.NOTE;
          item.updatedAt = Date.now();
        }
        next.push(item);
      }
      this.annotations = next;
      this.persistAnnotations();
    } else {
      const item = Annotation.of(this.noteChapter, this.noteStart, this.noteEnd, this.noteQuote, note,
        AnnotationKind.NOTE);
      const next: Annotation[] = this.annotations.slice();
      next.push(item);
      AnnotationStore.sort(next);
      this.annotations = next;
      this.persistAnnotations();
    }
    this.noteVisible = false;
    this.toast(note.length > 0 ? '已保存想法' : '已划线');
  }

  private deleteNote(): void {
    if (this.noteExistingId.length > 0) {
      this.annotations = AnnotationStore.removeById(this.annotations, this.noteExistingId);
      this.persistAnnotations();
      this.toast('已删除');
    }
    this.noteVisible = false;
  }

  private jumpToAnnotation(annotation: Annotation): void {
    this.panel = '';
    this.openChapter(annotation.chapterIndex, annotation.start, 0, 0, true);
  }

  private deleteAnnotation(annotation: Annotation): void {
    this.annotations = AnnotationStore.removeById(this.annotations, annotation.id);
    this.persistAnnotations();
    this.toast('已删除');
  }

  /**
   * 词典：先弹卡片展示选中的词，复制或去浏览器查由用户决定。
   * 本机没有系统词典应用，也没有离线词典 API，不直接跳浏览器（会打断阅读）。
   */
  private lookupWord(word: string): void {
    const query = word.trim();
    if (query.length === 0) {
      return;
    }
    this.dictWord = query.length > 60 ? query.substring(0, 60) : query;
    this.dictVisible = true;
  }

  private copyDictWord(): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.dictWord);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.toast('已复制');
      }).catch(() => {
        this.toast('复制失败');
      });
    } catch (e) {
      const err = e as BusinessError;
      console.error(`copy failed: ${err.message}`);
      this.toast('复制失败');
    }
  }

  private openDictInBrowser(): void {
    let query = this.dictWord;
    if (query.length > 40) {
      query = query.substring(0, 40);
    }
    const url = `https://cn.bing.com/dict/search?q=${encodeURIComponent(query)}`;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.openLink(url).catch(() => {
        this.toast('没有可用的浏览器');
      });
    } catch (e) {
      this.toast('没有可用的浏览器');
    }
  }

  /**
   * 切换翻页方式：仿真 / 横滑 / 上下滑动 / 无动效。
   * 只有「上下 ↔ 左右」真正变化时才重开章节，横向三种方式只换动效。
   */
  private changePageTurn(mode: PageTurnMode): void {
    const previousMode = this.readingMode;
    this.pageTurn = mode;
    if (this.book.type === BookType.TEXT) {
      this.settings.textPageTurn = mode;
    } else {
      this.settings.imagePageTurn = mode;
    }
    LibraryStore.saveSettings(this.settings);
    this.readingMode = mode === PageTurnMode.VERTICAL ? ReadingMode.VERTICAL : ReadingMode.HORIZONTAL;
    if (previousMode !== this.readingMode) {
      // 用当前进度章重新打开，保证方向切换后定位一致
      this.openChapter(this.progressChapter, this.progressCharOffset, 0, this.progressRatio, false);
    }
  }

  private changeFontFamily(family: string): void {
    this.fontFamily = family;
    this.settings.fontFamily = family;
    LibraryStore.saveSettings(this.settings);
  }

  private changeTextAlign(mode: TextAlignMode): void {
    this.textAlignMode = mode;
    this.settings.textAlignMode = mode;
    LibraryStore.saveSettings(this.settings);
  }

  /** 页脚左侧时间与电量：关掉后页脚只留右侧章节进度 */
  private changeShowFooterTime(value: boolean): void {
    this.showFooterTime = value;
    this.settings.showFooterTime = value;
    LibraryStore.saveSettings(this.settings);
  }

  /** 面板 / 菜单配色：图片书正文是黑底，用深色面板，其余跟随阅读主题 */
  private panelColors(): ReaderThemeColors {
    return this.book.type === BookType.IMAGE ? ReaderTheme.dark() : this.palette;
  }

  // ================= 顶部设置菜单 =================

  /** 打开菜单前刷新书签状态，菜单项文案才能显示「添加书签 / 取消书签」 */
  private toggleMenu(): void {
    if (this.menuVisible) {
      this.menuVisible = false;
      return;
    }
    this.updateBookmarkState();
    this.menuVisible = true;
  }

  private openMenuPanel(name: string): void {
    this.menuVisible = false;
    this.panel = name;
  }

  // ================= 全文搜索 =================

  private startSearch(keyword: string): void {
    const query = keyword.trim();
    if (query.length === 0) {
      return;
    }
    this.searchKeyword = query;
    this.rememberSearchKeyword(query);
    this.searchSeq++;
    const seq = this.searchSeq;
    this.searchResults = [];
    this.searchProgress = '';
    this.searchRunning = true;
    this.runSearch(query, seq);
  }

  /**
   * 逐章扫全文：每章一次异步读盘（命中章节缓存则直接复用）。
   * 进度文案按时间节流刷新，避免每章都触发一次整页重建。
   */
  private async runSearch(keyword: string, seq: number): Promise<void> {
    const total = this.manifest.chapters.length;
    const hits: SearchHit[] = [];
    let lastTick = 0;
    for (let i = 0; i < total; i++) {
      if (seq !== this.searchSeq) {
        return;
      }
      const text = await this.loadChapterTextAsync(i);
      if (seq !== this.searchSeq) {
        return;
      }
      this.collectHits(hits, i, keyword, text);
      const now = Date.now();
      if (now - lastTick > SEARCH_PROGRESS_INTERVAL) {
        lastTick = now;
        this.searchProgress = `${i + 1}/${total}章`;
      }
      if (hits.length >= SEARCH_MAX_HITS) {
        break;
      }
    }
    if (seq !== this.searchSeq) {
      return;
    }
    this.searchResults = hits;
    this.searchProgress = '';
    this.searchRunning = false;
    hilog.info(DOMAIN, TAG, 'search "%{public}s" hits=%{public}d chapters=%{public}d',
      keyword, hits.length, total);
  }

  /** 单章收集命中：截取关键字前后文片段，换行压成空格，两端补省略号 */
  private collectHits(hits: SearchHit[], chapter: number, keyword: string, text: string): void {
    if (text.length === 0 || keyword.length === 0) {
      return;
    }
    const title = this.chapterTitleOf(chapter);
    const keyLength = keyword.length;
    let from = 0;
    while (hits.length < SEARCH_MAX_HITS) {
      const index = text.indexOf(keyword, from);
      if (index < 0) {
        return;
      }
      const beforeStart = index > SEARCH_SNIPPET_CHARS ? index - SEARCH_SNIPPET_CHARS : 0;
      const afterEnd = index + keyLength + SEARCH_SNIPPET_CHARS < text.length
        ? index + keyLength + SEARCH_SNIPPET_CHARS : text.length;
      let before = Reader.collapseSpace(text.substring(beforeStart, index));
      let after = Reader.collapseSpace(text.substring(index + keyLength, afterEnd));
      if (beforeStart > 0) {
        before = `…${before}`;
      }
      if (afterEnd < text.length) {
        after = `${after}…`;
      }
      hits.push(SearchHit.of(chapter, index, title, before, text.substring(index, index + keyLength), after));
      from = index + keyLength;
    }
  }

  private static collapseSpace(raw: string): string {
    return raw.split(new RegExp('\\s+')).join(' ');
  }

  /** 历史去重后置顶，最多 SEARCH_HISTORY_LIMIT 条 */
  private rememberSearchKeyword(keyword: string): void {
    const next: string[] = [];
    next.push(keyword);
    for (let i = 0; i < this.searchHistory.length; i++) {
      const item = this.searchHistory[i];
      if (item !== keyword && next.length < SEARCH_HISTORY_LIMIT) {
        next.push(item);
      }
    }
    this.searchHistory = next;
    LibraryStore.saveSearchHistory(this.bookId, next);
  }

  private clearSearchHistory(): void {
    this.searchHistory = [];
    LibraryStore.saveSearchHistory(this.bookId, []);
  }

  /** 取消进行中的搜索：序号自增让在途循环退出，并清掉半成品结果（下次打开回到历史） */
  private cancelSearch(): void {
    this.searchSeq++;
    this.searchRunning = false;
    this.searchProgress = '';
    this.searchResults = [];
    this.searchKeyword = '';
  }

  private jumpToSearchHit(hit: SearchHit): void {
    this.panel = '';
    this.openChapter(hit.chapterIndex, hit.charOffset, 0, 0, true);
  }

  private loadFontList(): void {
    try {
      const list: string[] = this.getUIContext().getFont().getSystemFontList();
      this.fontList = list;
    } catch (e) {
      this.fontList = [];
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

  private barTextColor(): string {
    return this.book.type === BookType.IMAGE ? '#FFFFFF' : this.palette.barText;
  }

  private pageBackground(): string {
    return this.book.type === BookType.IMAGE ? '#000000' : this.palette.bg;
  }

  /** 控制栏上的胶囊 / 圆钮底色：深色主题与图片书用半透明白，浅色主题用配置里的 chip 色 */
  private barChipBg(): string {
    if (this.book.type === BookType.IMAGE) {
      return '#33FFFFFF';
    }
    return this.palette.chipBg;
  }

  /** 书籍本来就在书架里，这里给出明确反馈 */
  private addToShelf(): void {
    const existing: BookMeta | undefined = LibraryStore.getBook(this.bookId);
    this.toast(existing !== undefined ? '已在书架中' : '已添加到书架');
  }

  /** 顶部圆形图标按钮：图标由系统符号绘制，按钮内不放任何文字 */
  @Builder
  barIcon(icon: Resource, action: () => void, size: number) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(size >= 44 ? 22 : 20)
        .fontColor([this.barTextColor()])
    }
    .width(size)
    .height(size)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.barChipBg())
    .borderRadius(size / 2)
    .onClick(() => {
      action();
    })
  }

  /** 顶部控制栏：返回 / 加入书架 / 设置，三个独立圆形按钮，纯图标无文字 */
  @Builder
  topBar() {
    Row() {
      this.barIcon($r('sys.symbol.chevron_left'), (): void => {
        this.goBack();
      }, 40)
      Blank()
      Row() {
        this.barIcon($r('sys.symbol.plus'), (): void => {
          this.addToShelf();
        }, 40)
      }
      .margin({ right: 10 })
      this.barIcon($r('sys.symbol.more'), (): void => {
        this.toggleMenu();
      }, 40)
    }
    .width('100%')
    .height(76)
    .padding({ left: 16, right: 16, top: 24 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
    })
  }

  /** 菜单项：整行可点，文案左对齐 */
  @Builder
  menuItem(label: string, action: () => void) {
    Text(label)
      .width('100%')
      .height(48)
      .fontSize(15)
      .fontColor(this.panelColors().panelText)
      .textAlign(TextAlign.Start)
      .padding({ left: 18, right: 18 })
      .onClick(() => {
        action();
      })
  }

  @Builder
  menuDivider() {
    Divider()
      .color(this.panelColors().divider)
      .margin({ left: 18, right: 18 })
  }

  /** 设置按钮的下拉菜单：阅读设置 / 添加书签 / 全文搜索（图片书没有全文搜索） */
  @Builder
  readerMenu() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 点空白处只收起菜单，不翻页也不关控制栏；让开顶部栏，菜单开着时按钮仍可点
      Column()
        .width('100%')
        .height('100%')
        .margin({ top: 76 })
        .onClick(() => {
          this.menuVisible = false;
        })

      Column() {
        this.menuItem('阅读设置', (): void => {
          this.openMenuPanel('settings');
        })
        this.menuDivider()
        this.menuItem(this.bookmarked ? '取消书签' : '添加书签', (): void => {
          this.menuVisible = false;
          this.toggleBookmark();
        })
        if (this.book.type === BookType.TEXT) {
          this.menuDivider()
          this.menuItem('全文搜索', (): void => {
            this.openMenuPanel('search');
          })
        }
      }
      .width(172)
      .backgroundColor(this.panelColors().panelBg)
      .borderRadius(14)
      .border({ width: 1, color: this.panelColors().divider })
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 6 })
      .padding({ top: 4, bottom: 4 })
      .margin({ top: 82, right: 28 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  bottomTab(icon: string, label: string, name: string) {
    Column() {
      Text(icon)
        .fontSize(18)
        .fontColor(this.panel === name ? this.palette.accent : this.barTextColor())
      Text(label)
        .fontSize(10)
        .margin({ top: 3 })
        .fontColor(this.panel === name ? this.palette.accent : this.barTextColor())
        .opacity(this.panel === name ? 1 : 0.75)
    }
    .layoutWeight(1)
    .height(58)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.openPanel(name);
    })
  }

  /**
   * 点控制栏的空白区（中间大块 / 底部胶囊四周留白）。
   * 面板打开时不能收起控制栏：面板浮在控制栏之上，控制栏一消失面板就悬空、底部 tab 也点不到，
   * 表现就是"点面板边缘把下方控制栏点没了"。
   */
  private tapControlsBackground(): void {
    if (this.panel.length > 0) {
      return;
    }
    this.controlsVisible = false;
  }

  /** 控制栏显隐：仅在打开时刷新进度与书签文案，减少滚动期间的无效重建 */
  private toggleControls(): void {
    if (this.controlsVisible) {
      this.controlsVisible = false;
      this.menuVisible = false;
      return;
    }
    this.updateProgressLabel();
    this.updateBookmarkState();
    this.controlsVisible = true;
  }

  private openPanel(name: string): void {
    this.menuVisible = false;
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

  /** 想法编辑面板：底部弹出，保存后立即在正文回显下划线 */
  @Builder
  noteEditor() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.noteVisible = false;
        })

      Column() {
        Row() {
          Text(this.noteExistingId.length > 0 ? '编辑想法' : '记录想法')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.panelText)
            .layoutWeight(1)
          Text('关闭')
            .fontSize(14)
            .fontColor(this.palette.accent)
            .padding({ left: 12, top: 6, bottom: 6 })
            .onClick(() => {
              this.noteVisible = false;
            })
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)

        Text(this.noteQuote)
          .width('100%')
          .fontSize(13)
          .fontColor(this.palette.panelSubText)
          .lineHeight(20)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding(10)
          .backgroundColor(this.palette.chipBg)
          .borderRadius(8)

        TextArea({ text: this.noteDraft, placeholder: '写下你的想法…' })
          .width('100%')
          .height(130)
          .fontSize(15)
          .fontColor(this.palette.panelText)
          .placeholderColor(this.palette.panelSubText)
          .backgroundColor('#00000000')
          .margin({ top: 10 })
          .onChange((value: string) => {
            this.noteDraft = value;
          })

        Row() {
          if (this.noteExistingId.length > 0) {
            Text('删除')
              .fontSize(14)
              .fontColor(this.palette.danger)
              .padding({ top: 10, bottom: 10, right: 20 })
              .onClick(() => {
                this.deleteNote();
              })
          }
          Blank()
          Button('保存')
            .type(ButtonType.Capsule)
            .backgroundColor(this.palette.accent)
            .fontColor(this.palette.accentText)
            .fontSize(14)
            .onClick(() => {
              this.saveNote();
            })
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .width('100%')
      .backgroundColor(this.palette.panelBg)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .padding({ left: 18, right: 18, bottom: 22 })
    }
    .width('100%')
    .height('100%')
  }

  /** 词典卡片：展示选中的词，复制或去浏览器查 */
  @Builder
  dictCard() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.dictVisible = false;
        })

      Column() {
        Row() {
          Text('词典')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.panelText)
            .layoutWeight(1)
          Text('关闭')
            .fontSize(14)
            .fontColor(this.palette.accent)
            .padding({ left: 12, top: 6, bottom: 6 })
            .onClick(() => {
              this.dictVisible = false;
            })
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)

        Text(this.dictWord)
          .width('100%')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.panelText)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4, bottom: 10 })

        Text('本机没有离线词典，可复制后到词典 App 里查，或用浏览器打开在线词典。')
          .width('100%')
          .fontSize(12)
          .fontColor(this.palette.panelSubText)
          .lineHeight(18)
          .margin({ bottom: 16 })

        Row() {
          Button('复制')
            .type(ButtonType.Capsule)
            .backgroundColor(this.palette.chipBg)
            .fontColor(this.palette.chipText)
            .fontSize(14)
            .onClick(() => {
              this.copyDictWord();
            })
          Blank()
          Button('浏览器查词典')
            .type(ButtonType.Capsule)
            .backgroundColor(this.palette.accent)
            .fontColor(this.palette.accentText)
            .fontSize(14)
            .onClick(() => {
              this.openDictInBrowser();
            })
        }
        .width('100%')
      }
      .width('100%')
      .backgroundColor(this.palette.panelBg)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .padding({ left: 18, right: 18, top: 0, bottom: 22 })
    }
    .width('100%')
    .height('100%')
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
          pageTurn: this.pageTurn,
          fontSize: this.fontSize,
          lineHeightRatio: this.lineHeightRatio,
          fontFamily: this.fontFamily,
          textAlignMode: this.textAlignMode,
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
          dividerColor: this.palette.divider,
          accentColor: this.palette.accent,
          accentTextColor: this.palette.accentText,
          showFooterTime: this.showFooterTime,
          controlsVisible: this.controlsVisible,
          annotationsVersion: this.annotationsVersion,
          annotationBg: this.palette.annotationBg,
          annotationLine: this.palette.annotationLine,
          annotationsOf: (index: number): Annotation[] => {
            return this.annotationsOf(index);
          },
          onToggleHighlight: (chapter: number, start: number, end: number, text: string): void => {
            this.toggleHighlight(chapter, start, end, text);
          },
          onRequestNote: (chapter: number, start: number, end: number, text: string): void => {
            this.openNoteEditor(chapter, start, end, text);
          },
          onLookup: (word: string): void => {
            this.lookupWord(word);
          },
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
          pageTurn: this.pageTurn,
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
          // 面板展开时收起顶部栏：面板从底部控制栏弹出，顶部只留阅读区域
          if (this.panel.length === 0) {
            this.topBar()
          }

          // 控制栏显示时中间区域吞掉点击与滑动：既不翻页也不滚动，点击即退出控制栏
          Column() {
          }
          .width('100%')
          .layoutWeight(1)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.tapControlsBackground();
          })

          Row() {
            this.bottomTab('☰', '目录', 'catalog')
            if (this.book.type === BookType.TEXT) {
              this.bottomTab('A', '字体', 'font')
            }
            this.bottomTab('⇅', '操作', 'actions')
            this.bottomTab('◐', '背景', 'background')
            this.bottomTab('⧉', '翻页', 'pageturn')
          }
          .width('100%')
          .height(58)
          .borderRadius(29)
          .backgroundColor(this.barChipBg())
          .padding({ left: 4, right: 4 })
          .onClick(() => {
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, bottom: 22 })
        .onClick(() => {
          // 左右 16vp / 底部 22vp 的空白不落到正文上：否则会走正文的单击逻辑把控制栏关掉
          this.tapControlsBackground();
        })
      }

      // 设置按钮的下拉菜单：盖在控制栏之上，点空白处或再点按钮收起
      if (this.menuVisible && this.panel.length === 0 && !this.loading && this.errorText.length === 0) {
        this.readerMenu()
      }

      if (this.panel.length > 0 && !this.loading && this.errorText.length === 0) {
        ReaderPanels({
          panel: this.panel,
          bookTitle: this.book.title,
          chapters: this.manifest.chapters,
          currentChapter: this.chapterIndex,
          currentOffset: this.progressCharOffset,
          bookmarks: this.bookmarks,
          annotations: this.annotations,
          isImageBook: this.book.type === BookType.IMAGE,
          pageTurn: this.pageTurn,
          fontSize: this.fontSize,
          lineHeightRatio: this.lineHeightRatio,
          fontFamily: this.fontFamily,
          fontList: this.fontList,
          textAlignMode: this.textAlignMode,
          theme: this.theme,
          colors: this.book.type === BookType.IMAGE ? ReaderTheme.dark() : this.palette,
          showFooterTime: this.showFooterTime,
          searchKeyword: this.searchKeyword,
          searchRunning: this.searchRunning,
          searchProgress: this.searchProgress,
          searchResults: this.searchResults,
          searchHistory: this.searchHistory,
          onClose: (): void => {
            this.panel = '';
            if (this.searchRunning) {
              this.cancelSearch();
            }
          },
          onToggleFooterTime: (value: boolean): void => {
            this.changeShowFooterTime(value);
          },
          onSearch: (keyword: string): void => {
            this.startSearch(keyword);
          },
          onCancelSearch: (): void => {
            this.cancelSearch();
          },
          onSelectSearchHit: (hit: SearchHit): void => {
            this.jumpToSearchHit(hit);
          },
          onClearSearchHistory: (): void => {
            this.clearSearchHistory();
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
          onSelectAnnotation: (annotation: Annotation): void => {
            this.jumpToAnnotation(annotation);
          },
          onDeleteAnnotation: (annotation: Annotation): void => {
            this.deleteAnnotation(annotation);
          },
          onFontSizeChange: (size: number): void => {
            this.changeFontSize(size);
          },
          onLineHeightChange: (ratio: number): void => {
            this.changeLineHeight(ratio);
          },
          onThemeChange: (theme: ReadingTheme): void => {
            this.changeTheme(theme);
          },
          onSwitchPanel: (name: string): void => {
            if (this.searchRunning) {
              this.cancelSearch();
            }
            this.panel = name;
          },
          onFontFamilyChange: (family: string): void => {
            this.changeFontFamily(family);
          },
          onTextAlignChange: (mode: TextAlignMode): void => {
            this.changeTextAlign(mode);
          },
          onPageTurnChange: (mode: PageTurnMode): void => {
            this.changePageTurn(mode);
          },
          onToggleBookmark: (): void => {
            this.toggleBookmark();
          },
          onJumpChapter: (index: number): void => {
            this.jumpToChapterKeepPanel(index);
          }
        })
      }

      if (this.noteVisible && !this.loading && this.errorText.length === 0) {
        this.noteEditor()
      }

      if (this.dictVisible && !this.loading && this.errorText.length === 0) {
        this.dictCard()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBackground())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
