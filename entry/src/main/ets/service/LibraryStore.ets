import { BookMeta, Bookmark, BookManifest, ReaderSettings, ReadingProgress } from '../model/BookModels';
import { ReadingTheme } from '../model/ReaderTheme';
import { AppPaths } from '../utils/AppPaths';
import { FileUtil } from '../utils/FileUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0002;
const TAG = 'LibraryStore';

export class LibraryStore {
  static init(): void {
    FileUtil.ensureDir(`${AppPaths.getFilesDir()}/books`);
    FileUtil.ensureDir(`${AppPaths.getFilesDir()}/bookmarks`);
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

  static getBooks(): BookMeta[] {
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
          result.push(item);
        }
      }
      result.sort((a: BookMeta, b: BookMeta): number => b.updatedAt - a.updatedAt);
      return result;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'parse library failed');
      return [];
    }
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
    const books = LibraryStore.getBooks();
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

  static removeBooks(bookIds: string[]): void {
    if (bookIds.length === 0) {
      return;
    }
    const books = LibraryStore.getBooks();
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
      return parsed;
    } catch (e) {
      return new ReaderSettings();
    }
  }

  static saveSettings(settings: ReaderSettings): void {
    FileUtil.writeTextAtomic(LibraryStore.settingsPath(), JSON.stringify(settings));
  }
}
