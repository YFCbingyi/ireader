import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
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
  @State controlsVisible: boolean = true;
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

  aboutToAppear(): void {
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
    this.openChapter(savedChapter, this.book.progress.charOffset, this.book.progress.pageIndex,
      this.book.progress.scrollRatio, false);
    this.loading = false;
    this.startReadingSession();
  }

  onPageShow(): void {
    this.startReadingSession();
  }

  onPageHide(): void {
    this.stopReadingSession();
    this.flushProgress();
  }

  aboutToDisappear(): void {
    this.stopReadingSession();
    this.flushProgress();
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

  private openChapter(index: number, charOffset: number, imageIndex: number, imageRatio: number,
    save: boolean): void {
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
    this.chapterIndex = target;
    this.chapterTitle = chapter.title;
    if (this.book.type === BookType.TEXT) {
      this.chapterContent = FileUtil.readText(AppPaths.abs(chapter.contentFile));
      this.chapterImages = [];
    } else {
      this.chapterContent = '';
      this.chapterImages = chapter.images;
    }
    this.startCharOffset = charOffset;
    this.startImageIndex = imageIndex;
    this.startImageRatio = imageRatio;
    this.progressChapter = target;
    this.progressCharOffset = charOffset;
    this.progressPageIndex = imageIndex;
    this.progressRatio = imageRatio;
    this.loadVersion++;
    this.updateProgressLabel();
    this.updateBookmarkState();
    if (save) {
      this.flushProgress();
    }
  }

  private previousChapter(): void {
    if (this.chapterIndex > 0) {
      this.openChapter(this.chapterIndex - 1, 0, 0, 0, true);
    }
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

  private onTextProgress(charOffset: number, ratio: number, pageIndex: number): void {
    this.progressChapter = this.chapterIndex;
    this.progressCharOffset = charOffset;
    this.progressPageIndex = pageIndex;
    this.progressRatio = ratio;
    this.updateProgressLabel();
    this.updateBookmarkState();
    this.scheduleSave();
  }

  private onImageProgress(imageIndex: number, intraRatio: number): void {
    this.progressChapter = this.chapterIndex;
    this.progressPageIndex = imageIndex;
    this.progressRatio = intraRatio;
    this.progressCharOffset = 0;
    this.updateProgressLabel();
    this.updateBookmarkState();
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
    this.progressLabel = `第 ${this.chapterIndex + 1}/${total} 章 · ${percent}%`;
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
      let text = this.chapterContent.substring(this.progressCharOffset,
        this.progressCharOffset + 40);
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
    this.readingMode = mode;
    this.book.readingMode = mode;
    this.book.updatedAt = Date.now();
    LibraryStore.saveBook(this.book);
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
          startCharOffset: this.startCharOffset,
          loadVersion: this.loadVersion,
          bgColor: this.palette.bg,
          textColor: this.palette.text,
          accentColor: this.palette.accent,
          accentTextColor: this.palette.accentText,
          onProgress: (charOffset: number, ratio: number, pageIndex: number): void => {
            this.onTextProgress(charOffset, ratio, pageIndex);
          },
          onNextChapter: (): void => {
            this.nextChapter();
          },
          onPrevChapter: (): void => {
            this.previousChapter();
          },
          onTap: (): void => {
            this.controlsVisible = !this.controlsVisible;
          }
        })
      } else {
        ImageReaderView({
          images: this.chapterImages,
          mode: this.readingMode,
          startIndex: this.startImageIndex,
          startRatio: this.startImageRatio,
          loadVersion: this.loadVersion,
          onProgress: (imageIndex: number, intraRatio: number): void => {
            this.onImageProgress(imageIndex, intraRatio);
          },
          onNextChapter: (): void => {
            this.nextChapter();
          },
          onPrevChapter: (): void => {
            this.previousChapter();
          },
          onTap: (): void => {
            this.controlsVisible = !this.controlsVisible;
          }
        })
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
          .height(62)
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.barBackground())
          .onClick(() => {
          })

          Column() {
          }
          .width('100%')
          .layoutWeight(1)
          .hitTestBehavior(HitTestMode.None)

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
          .height(56)
          .justifyContent(FlexAlign.SpaceAround)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.barBackground())
          .onClick(() => {
          })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
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
  }
}
