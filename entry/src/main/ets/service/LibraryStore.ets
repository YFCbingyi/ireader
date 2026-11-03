import {
  BookMeta,
  Bookmark,
  BookManifest,
  PageTurnMode,
  ReaderSettings,
  ReadingMode,
  ReadingProgress,
  TextAlignMode
} from '../model/BookModels';
import { ReadingTheme } from '../model/ReaderTheme';
import { AppPaths } from '../utils/AppPaths';
import { FileUtil } from '../utils/FileUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0002;
const TAG = 'LibraryStore';
// 全文搜索历史条数上限
const SEARCH_HISTORY_LIMIT = 10;

export class LibraryStore {
  static init(): void {
    FileUtil.ensureDir(`${AppPaths.getFilesDir()}/books`);
    FileUtil.ensureDir(`${AppPaths.getFilesDir()}/bookmarks`);
    FileUtil.ensureDir(`${AppPaths.getFilesDir()}/search`);
  }

  private static libraryPath(): string {
    return `${AppPaths.getFilesDir()}/library.json`;
  }

  private static settingsPath(): string {
    return `${AppPaths.getFilesDir()}/settings.json`;
  }

  private static bookmarksPath(bookId: string): string {
    return `${AppPaths.getFilesDir()}/bookmarks/${bookId}.json`;
  }

  private static manifestPath(bookId: string): string {
    return `${AppPaths.bookDir(bookId)}/manifest.json`;
  }

  private static searchHistoryPath(bookId: string): string {
    return `${AppPaths.getFilesDir()}/search/${bookId}.json`;
  }

  /** 全文搜索历史：逐书保存，最新在前，最多 SEARCH_HISTORY_LIMIT 条 */
  static getSearchHistory(bookId: string): string[] {
    const raw = FileUtil.readText(LibraryStore.searchHistoryPath(bookId));
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as string[];
      const result: string[] = [];
      for (let i = 0; i < parsed.length; i++) {
        const item = parsed[i];
        if (typeof item === 'string' && item.length > 0 && result.indexOf(item) < 0) {
          result.push(item);
        }
        if (result.length >= SEARCH_HISTORY_LIMIT) {
          break;
        }
      }
      return result;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'parse search history failed: %{public}s', bookId);
      return [];
    }
  }

  static saveSearchHistory(bookId: string, keywords: string[]): void {
    FileUtil.writeTextAtomic(LibraryStore.searchHistoryPath(bookId), JSON.stringify(keywords));
  }

  static getBooks(): BookMeta[] {
    const books = LibraryStore.loadBooks();
    return books === undefined ? [] : books;
  }

  /**
   * 读全表。返回 undefined 表示「文件存在但解析失败」，与「文件不存在/空文件」区分开：
   * 前者绝不能拿去整表覆盖写回，否则会把其余书静默抹掉。
   */
  private static loadBooks(): BookMeta[] | undefined {
    const raw = FileUtil.readText(LibraryStore.libraryPath());
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as BookMeta[];
      const result: BookMeta[] = [];
      for (let i = 0; i < parsed.length; i++) {
        const item = parsed[i];
        if (item !== undefined && item.id !== undefined && item.id.length > 0) {
          if (item.progress === undefined) {
            item.progress = new ReadingProgress();
          }
          // 旧版本没有分组字段，补空串（未分组）
          if (item.group === undefined) {
            item.group = '';
          }
          result.push(item);
        }
      }
      result.sort((a: BookMeta, b: BookMeta): number => b.updatedAt - a.updatedAt);
      return result;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'parse library failed');
      return undefined;
    }
  }

  /** library.json 解析失败时另存一份原始内容，避免后续覆盖写把现场彻底冲掉 */
  private static backupBrokenLibrary(): void {
    const raw = FileUtil.readText(LibraryStore.libraryPath());
    if (raw.length === 0) {
      return;
    }
    const backupPath = `${AppPaths.getFilesDir()}/library.broken.json`;
    FileUtil.writeText(backupPath, raw);
    hilog.error(DOMAIN, TAG, 'library.json unparsable, backup to %{public}s', backupPath);
  }

  static getBook(bookId: string): BookMeta | undefined {
    const books = LibraryStore.getBooks();
    for (let i = 0; i < books.length; i++) {
      if (books[i].id === bookId) {
        return books[i];
      }
    }
    return undefined;
  }

  static saveBooks(books: BookMeta[]): void {
    FileUtil.writeTextAtomic(LibraryStore.libraryPath(), JSON.stringify(books));
  }

  static saveBook(book: BookMeta): void {
    const books = LibraryStore.loadBooks();
    if (books === undefined) {
      // 原文件损坏：先留一份现场，再以当前书重建，至少不丢这本书、也不彻底冲掉其余数据
      LibraryStore.backupBrokenLibrary();
      LibraryStore.saveBooks([book]);
      return;
    }
    let found = false;
    for (let i = 0; i < books.length; i++) {
      if (books[i].id === book.id) {
        books[i] = book;
        found = true;
        break;
      }
    }
    if (!found) {
      books.push(book);
    }
    LibraryStore.saveBooks(books);
  }

  static removeBook(bookId: string): void {
    LibraryStore.removeBooks([bookId]);
  }

  /** 所有已存在的分组名（按首次出现顺序去重） */
  static listGroups(): string[] {
    const books = LibraryStore.getBooks();
    const names: string[] = [];
    for (let i = 0; i < books.length; i++) {
      const name = books[i].group;
      if (name !== undefined && name.length > 0 && names.indexOf(name) < 0) {
        names.push(name);
      }
    }
    return names;
  }

  /** 重命名分组：把所有属于 oldName 的书改到 newName */
  static renameGroup(oldName: string, newName: string): void {
    if (oldName.length === 0 || newName.length === 0 || oldName === newName) {
      return;
    }
    const books = LibraryStore.getBooks();
    let changed = false;
    for (let i = 0; i < books.length; i++) {
      if (books[i].group === oldName) {
        books[i].group = newName;
        changed = true;
      }
    }
    if (changed) {
      LibraryStore.saveBooks(books);
    }
  }

  /** 批量设置分组；group 传空串表示移出分组 */
  static setGroup(bookIds: string[], group: string): void {
    if (bookIds.length === 0) {
      return;
    }
    const books = LibraryStore.getBooks();
    let changed = false;
    for (let i = 0; i < books.length; i++) {
      if (bookIds.indexOf(books[i].id) >= 0) {
        books[i].group = group;
        changed = true;
      }
    }
    if (changed) {
      LibraryStore.saveBooks(books);
    }
  }

  static removeBooks(bookIds: string[]): void {
    if (bookIds.length === 0) {
      return;
    }
    const books = LibraryStore.loadBooks();
    if (books === undefined) {
      // 表损坏时若照常删除，会把 library.json 覆盖成空表（等于清空书架），宁可本次不删
      LibraryStore.backupBrokenLibrary();
      hilog.error(DOMAIN, TAG, 'skip removeBooks: library.json unparsable');
      return;
    }
    const remain: BookMeta[] = [];
    for (let i = 0; i < books.length; i++) {
      if (bookIds.indexOf(books[i].id) < 0) {
        remain.push(books[i]);
      }
    }
    LibraryStore.saveBooks(remain);
    for (let i = 0; i < bookIds.length; i++) {
      const bookId = bookIds[i];
      const bookmarkFile = LibraryStore.bookmarksPath(bookId);
      if (FileUtil.exists(bookmarkFile)) {
        FileUtil.deleteRecursive(bookmarkFile);
      }
      FileUtil.deleteRecursive(AppPaths.bookDir(bookId));
    }
  }

  static getManifest(bookId: string): BookManifest {
    const raw = FileUtil.readText(LibraryStore.manifestPath(bookId));
    if (raw.length === 0) {
      return new BookManifest();
    }
    try {
      const parsed = JSON.parse(raw) as BookManifest;
      if (parsed.chapters === undefined) {
        parsed.chapters = [];
      }
      return parsed;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'parse manifest failed: %{public}s', bookId);
      return new BookManifest();
    }
  }

  static saveManifest(bookId: string, manifest: BookManifest): void {
    FileUtil.writeTextAtomic(LibraryStore.manifestPath(bookId), JSON.stringify(manifest));
  }

  static getBookmarks(bookId: string): Bookmark[] {
    const raw = FileUtil.readText(LibraryStore.bookmarksPath(bookId));
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as Bookmark[];
      parsed.sort((a: Bookmark, b: Bookmark): number => b.createdAt - a.createdAt);
      return parsed;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'parse bookmarks failed: %{public}s', bookId);
      return [];
    }
  }

  static saveBookmarks(bookId: string, bookmarks: Bookmark[]): void {
    FileUtil.writeTextAtomic(LibraryStore.bookmarksPath(bookId), JSON.stringify(bookmarks));
  }

  static getSettings(): ReaderSettings {
    const raw = FileUtil.readText(LibraryStore.settingsPath());
    if (raw.length === 0) {
      return new ReaderSettings();
    }
    try {
      const parsed = JSON.parse(raw) as ReaderSettings;
      if (parsed.fontSize === undefined) {
        parsed.fontSize = 18;
      }
      if (parsed.lineHeightRatio === undefined) {
        parsed.lineHeightRatio = 1.7;
      }
      if (parsed.theme === undefined) {
        parsed.theme = ReadingTheme.EYE;
      }
      // 旧版本的 settings.json 没有方向字段，补默认值（方向已从"每本书"改为"按书类型统一"）
      if (parsed.textReadingMode === undefined) {
        parsed.textReadingMode = ReadingMode.VERTICAL;
      }
      if (parsed.imageReadingMode === undefined) {
        parsed.imageReadingMode = ReadingMode.VERTICAL;
      }
      // 翻页方式：旧配置只有方向，按方向补默认（左右 → 横滑）
      if (parsed.textPageTurn === undefined) {
        parsed.textPageTurn = parsed.textReadingMode === ReadingMode.HORIZONTAL
          ? PageTurnMode.SLIDE : PageTurnMode.VERTICAL;
      }
      if (parsed.imagePageTurn === undefined) {
        parsed.imagePageTurn = parsed.imageReadingMode === ReadingMode.HORIZONTAL
          ? PageTurnMode.SLIDE : PageTurnMode.VERTICAL;
      }
      if (parsed.fontFamily === undefined) {
        parsed.fontFamily = '';
      }
      if (parsed.textAlignMode === undefined) {
        parsed.textAlignMode = TextAlignMode.AUTO;
      }
      // 页脚时间电量默认显示；旧配置没有这个字段
      if (parsed.showFooterTime === undefined) {
        parsed.showFooterTime = true;
      }
      return parsed;
    } catch (e) {
      return new ReaderSettings();
    }
  }

  static saveSettings(settings: ReaderSettings): void {
    FileUtil.writeTextAtomic(LibraryStore.settingsPath(), JSON.stringify(settings));
  }
}
