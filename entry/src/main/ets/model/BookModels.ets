import { ReadingTheme } from './ReaderTheme';

export enum BookType {
  TEXT = 'text',
  IMAGE = 'image'
}

export enum ReadingMode {
  VERTICAL = 'vertical',
  HORIZONTAL = 'horizontal'
}

/** 翻页方式：仿真 / 横滑 / 上下滑动 / 无动效 */
export enum PageTurnMode {
  SIMULATION = 'simulation',
  SLIDE = 'slide',
  VERTICAL = 'vertical',
  NONE = 'none'
}

/** 正文对齐：自动 / 左对齐 / 右对齐 / 两端对齐 */
export enum TextAlignMode {
  AUTO = 'auto',
  LEFT = 'left',
  RIGHT = 'right',
  JUSTIFY = 'justify'
}

export function pageTurnLabel(mode: PageTurnMode): string {
  if (mode === PageTurnMode.SIMULATION) {
    return '仿真';
  }
  if (mode === PageTurnMode.SLIDE) {
    return '横滑';
  }
  if (mode === PageTurnMode.VERTICAL) {
    return '上下滑动';
  }
  return '无动效';
}

export function textAlignLabel(mode: TextAlignMode): string {
  if (mode === TextAlignMode.LEFT) {
    return '左对齐';
  }
  if (mode === TextAlignMode.RIGHT) {
    return '右对齐';
  }
  if (mode === TextAlignMode.JUSTIFY) {
    return '两端对齐';
  }
  return '自动对齐';
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
  // 翻页方式同样按书类型统一：TXT 支持仿真/横滑/上下/无动效，图片书只用横滑/上下/无动效
  textPageTurn: PageTurnMode = PageTurnMode.VERTICAL;
  imagePageTurn: PageTurnMode = PageTurnMode.VERTICAL;
  // 正文字体：空串 = 系统默认字体
  fontFamily: string = '';
  textAlignMode: TextAlignMode = TextAlignMode.AUTO;
  // 页脚左侧是否显示时间与电量（文本书）
  showFooterTime: boolean = true;
}

/** 全文搜索命中：章号 + 章内偏移 + 前后文片段（关键字单独成段，供结果列表高亮） */
export class SearchHit {
  chapterIndex: number = 0;
  charOffset: number = 0;
  chapterTitle: string = '';
  before: string = '';
  match: string = '';
  after: string = '';

  static of(chapterIndex: number, charOffset: number, chapterTitle: string, before: string, match: string,
    after: string): SearchHit {
    const hit = new SearchHit();
    hit.chapterIndex = chapterIndex;
    hit.charOffset = charOffset;
    hit.chapterTitle = chapterTitle;
    hit.before = before;
    hit.match = match;
    hit.after = after;
    return hit;
  }
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
