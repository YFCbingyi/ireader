import { Annotation } from '../model/Annotation';
import { Bookmark, BookMeta, ReaderSettings } from '../model/BookModels';
import { ReadingStats } from '../model/ReadingStats';
import { AnnotationStore } from './AnnotationStore';
import { AppAppearanceStore } from './AppAppearanceStore';
import { LibraryStore } from './LibraryStore';
import { ReadingStatsStore } from './ReadingStatsStore';

/** 一本书的书签 + 划线，按书分开装，便于日后按 bookId 恢复 */
export class BackupBookEntries {
  bookId: string = '';
  bookmarks: Bookmark[] = [];
  annotations: Annotation[] = [];
}

/** 导出的只是阅读数据，不含书籍正文 / 图片 */
export class BackupPayload {
  app: string = 'ireader';
  version: number = 1;
  exportedAt: number = 0;
  containsBookContent: boolean = false;
  /** App 外观皮肤，与阅读主题(settings.theme)分开保存 */
  appSkin: string = '';
  books: BookMeta[] = [];
  settings: ReaderSettings = new ReaderSettings();
  stats: ReadingStats = new ReadingStats();
  entries: BackupBookEntries[] = [];
}

export class BackupService {
  static buildJson(): string {
    const payload = new BackupPayload();
    payload.exportedAt = Date.now();
    payload.books = LibraryStore.getBooks();
    payload.settings = LibraryStore.getSettings();
    payload.appSkin = AppAppearanceStore.current();
    payload.stats = ReadingStatsStore.get();
    for (let i = 0; i < payload.books.length; i++) {
      const bookId = payload.books[i].id;
      const item = new BackupBookEntries();
      item.bookId = bookId;
      item.bookmarks = LibraryStore.getBookmarks(bookId);
      item.annotations = AnnotationStore.load(bookId);
      payload.entries.push(item);
    }
    return JSON.stringify(payload);
  }
}
