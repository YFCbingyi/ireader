import { ReadingTheme } from './ReaderTheme';

export enum BookType {
  TEXT = 'text',
  IMAGE = 'image'
}

export enum ReadingMode {
  VERTICAL = 'vertical',
  HORIZONTAL = 'horizontal'
}

export class ReadingProgress {
  chapterIndex: number = 0;
  charOffset: number = 0;
  pageIndex: number = 0;
  scrollRatio: number = 0;
  percent: number = 0;
  updatedAt: number = 0;
}

export class BookMeta {
  id: string = '';
  title: string = '';
  type: BookType = BookType.TEXT;
  coverFile: string = '';
  chapterCount: number = 0;
  // 阅读方向不再按书保存，统一存在 ReaderSettings.textReadingMode / imageReadingMode
  progress: ReadingProgress = new ReadingProgress();
  createdAt: number = 0;
  updatedAt: number = 0;

  static of(id: string, title: string, type: BookType, chapterCount: number): BookMeta {
    const book = new BookMeta();
    book.id = id;
    book.title = title;
    book.type = type;
    book.chapterCount = chapterCount;
    book.createdAt = Date.now();
    book.updatedAt = book.createdAt;
    book.progress = new ReadingProgress();
    book.progress.updatedAt = book.createdAt;
    return book;
  }
}

export class ImageEntry {
  file: string = '';
  width: number = 0;
  height: number = 0;

  static of(file: string, width: number, height: number): ImageEntry {
    const entry = new ImageEntry();
    entry.file = file;
    entry.width = width;
    entry.height = height;
    return entry;
  }
}

export class ChapterMeta {
  title: string = '';
  contentFile: string = '';
  charCount: number = 0;
  images: ImageEntry[] = [];

  static text(title: string, contentFile: string, charCount: number): ChapterMeta {
    const chapter = new ChapterMeta();
    chapter.title = title;
    chapter.contentFile = contentFile;
    chapter.charCount = charCount;
    return chapter;
  }

  static image(title: string, images: ImageEntry[]): ChapterMeta {
    const chapter = new ChapterMeta();
    chapter.title = title;
    chapter.images = images;
    return chapter;
  }
}

export class BookManifest {
  version: number = 1;
  chapters: ChapterMeta[] = [];
}

export class Bookmark {
  id: string = '';
  bookId: string = '';
  chapterIndex: number = 0;
  chapterTitle: string = '';
  charOffset: number = 0;
  pageIndex: number = 0;
  scrollRatio: number = 0;
  preview: string = '';
  createdAt: number = 0;

  static of(bookId: string, chapterIndex: number, chapterTitle: string): Bookmark {
    const bookmark = new Bookmark();
    bookmark.id = `${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    bookmark.bookId = bookId;
    bookmark.chapterIndex = chapterIndex;
    bookmark.chapterTitle = chapterTitle;
    bookmark.createdAt = Date.now();
    return bookmark;
  }
}

export class ReaderSettings {
  fontSize: number = 18;
  lineHeightRatio: number = 1.7;
  theme: ReadingTheme = ReadingTheme.EYE;
  // 阅读方向按书类型统一：所有 TXT 共用一套，所有图片书共用另一套，两者互不影响
  textReadingMode: ReadingMode = ReadingMode.VERTICAL;
  imageReadingMode: ReadingMode = ReadingMode.VERTICAL;
}

export class ReaderParams {
  bookId: string = '';
}

export class ImportResult {
  success: boolean = false;
  bookId: string = '';
  title: string = '';
  message: string = '';
  skippedImages: number = 0;

  static ok(bookId: string, title: string, skippedImages: number): ImportResult {
    const result = new ImportResult();
    result.success = true;
    result.bookId = bookId;
    result.title = title;
    result.skippedImages = skippedImages;
    return result;
  }

  static fail(message: string): ImportResult {
    const result = new ImportResult();
    result.success = false;
    result.message = message;
    return result;
  }
}

export type ImportProgressCallback = (stage: string, current: number, total: number) => void;
