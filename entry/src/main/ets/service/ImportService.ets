import { zlib } from '@kit.BasicServicesKit';
import {
  BookManifest,
  BookMeta,
  BookType,
  ChapterMeta,
  ImageEntry,
  ImportProgressCallback,
  ImportResult
} from '../model/BookModels';
import { AppPaths } from '../utils/AppPaths';
import { FileUtil } from '../utils/FileUtil';
import { NaturalSort } from '../utils/NaturalSort';
import { ImageMetaReader } from './ImageMetaReader';
import { LibraryStore } from './LibraryStore';
import { TxtImportTask } from './TxtImportTask';
import { EpubBook, EpubParser } from './EpubParser';

const MAX_TEXT_BYTES = 50 * 1024 * 1024;
const MAX_ZIP_ORIGINAL_BYTES = 2 * 1024 * 1024 * 1024;
const MAX_ZIP_LABEL = '2GB';
const MAX_CHAPTERS = 1000;
const MAX_EPUB_BYTES = 500 * 1024 * 1024;
const MAX_EPUB_LABEL = '500MB';
// 文件夹扫描的目录数上限（防止误选超大目录时长时间卡在遍历上）
const MAX_SCAN_DIRS = 60;

export class ChapterScan {
  title: string = '';
  dir: string = '';
  images: string[] = [];
}

/** 文件夹扫描结果：一个可导入的书籍文件（kind 为扩展名：txt / epub / zip） */
export class FolderBook {
  uri: string = '';
  kind: string = '';

  static of(uri: string, kind: string): FolderBook {
    const book = new FolderBook();
    book.uri = uri;
    book.kind = kind;
    return book;
  }
}

export class ImportService {
  static async importTxt(uri: string, onProgress: ImportProgressCallback): Promise<ImportResult> {
    const bookId = ImportService.newId();
    const bookDir = AppPaths.bookDir(bookId);
    const bookRel = AppPaths.bookRel(bookId);
    // 源文件先落到沙箱，TaskPool 只处理绝对路径（worker 内不可用 picker 授权的 uri 与 AppPaths）
    const sourcePath = `${bookDir}/source.txt`;
    try {
      const title = ImportService.titleFromUri(uri);
      onProgress('复制文件', 0, 1);
      FileUtil.ensureDir(bookDir);
      FileUtil.copyUriToFile(uri, sourcePath);
      if (FileUtil.fileSize(sourcePath) <= 0) {
        throw new Error('文件为空');
      }
      // 解析、切分与逐章写盘都在 TaskPool 内完成，不占用 UI 线程
      onProgress('解析章节', 0, 0);
      const parsed = await TxtImportTask.parse(sourcePath, `${bookDir}/text`, bookRel,
        title, MAX_TEXT_BYTES);
      if (parsed.chapters.length === 0) {
        throw new Error('未解析出任何章节');
      }
      const manifest = new BookManifest();
      for (let i = 0; i < parsed.chapters.length; i++) {
        const item = parsed.chapters[i];
        manifest.chapters.push(ChapterMeta.text(item.title, item.relFile, item.charCount));
      }
      // 指纹要看章节内容，只能等切分完成；命中就把本次解析出来的书目录整个丢掉
      const fingerprint = ImportService.fingerprintOf(BookType.TEXT, manifest);
      const existed = ImportService.findDuplicate(BookType.TEXT, manifest.chapters.length, fingerprint);
      if (existed !== undefined) {
        FileUtil.deleteRecursive(bookDir);
        return ImportResult.duplicated(existed.id, existed.title);
      }
      onProgress('写入书架', 0, 1);
      LibraryStore.saveManifest(bookId, manifest);
      const book = BookMeta.of(bookId, title, BookType.TEXT, manifest.chapters.length, fingerprint);
      LibraryStore.saveBook(book);
      return ImportResult.ok(bookId, title, 0);
    } catch (e) {
      FileUtil.deleteRecursive(bookDir);
      return ImportResult.fail(ImportService.errorMessage(e as Error));
    } finally {
      // 源文件仅导入期需要，成功路径清掉避免占用双份磁盘
      FileUtil.deleteRecursive(sourcePath);
    }
  }

  static async importZip(uri: string, onProgress: ImportProgressCallback): Promise<ImportResult> {
    const bookId = ImportService.newId();
    const bookDir = AppPaths.bookDir(bookId);
    const zipPath = `${bookDir}/source.zip`;
    const extractDir = `${bookDir}/content`;
    const title = ImportService.titleFromUri(uri);
    try {
      const zipBytes = FileUtil.uriSize(uri);
      if (zipBytes > MAX_ZIP_ORIGINAL_BYTES) {
        throw new Error(`压缩包超过 ${MAX_ZIP_LABEL}`);
      }
      FileUtil.ensureDir(bookDir);
      onProgress('复制压缩包', 0, 1);
      FileUtil.copyUriToFile(uri, zipPath);
      let originalSize = 0;
      try {
        originalSize = await zlib.getOriginalSize(zipPath);
      } catch (e) {
        originalSize = 0;
      }
      if (originalSize > MAX_ZIP_ORIGINAL_BYTES) {
        throw new Error(`压缩包解压后超过 ${MAX_ZIP_LABEL}`);
      }
      onProgress('解压中', 0, 1);
      FileUtil.ensureDir(extractDir);
      await zlib.decompressFile(zipPath, extractDir);
      if (originalSize <= 0) {
        const extractedSize = FileUtil.pathSize(extractDir);
        if (extractedSize > MAX_ZIP_ORIGINAL_BYTES) {
          throw new Error(`压缩包解压后超过 ${MAX_ZIP_LABEL}`);
        }
      }

      const scans = ImportService.scanChapters(extractDir);
      if (scans.length === 0) {
        throw new Error('压缩包中未找到图片');
      }
      if (scans.length > MAX_CHAPTERS) {
        throw new Error('章节数量超过 1000');
      }
      // 查重放在读图片元数据之前：重复的包到这里就能确认，不必逐张读尺寸
      const fingerprint = ImportService.fingerprintOfScans(scans);
      const existed = ImportService.findDuplicate(BookType.IMAGE, scans.length, fingerprint);
      if (existed !== undefined) {
        FileUtil.deleteRecursive(bookDir);
        return ImportResult.duplicated(existed.id, existed.title);
      }
      let totalImages = 0;
      for (let i = 0; i < scans.length; i++) {
        totalImages += scans[i].images.length;
      }


      const manifest = new BookManifest();
      let processed = 0;
      let skipped = 0;
      for (let c = 0; c < scans.length; c++) {
        const scan = scans[c];
        const chapterImages: ImageEntry[] = [];
        for (let k = 0; k < scan.images.length; k++) {
          const absPath = scan.images[k];
          const relPath = AppPaths.relative(absPath);
          const entry = await ImageMetaReader.read(relPath, absPath);
          if (entry !== undefined) {
            chapterImages.push(entry);
          } else {
            skipped++;
          }
          processed++;
          if (processed % 10 === 0) {
            onProgress('读取图片', processed, totalImages);
          }
        }
        if (chapterImages.length > 0) {
          manifest.chapters.push(ChapterMeta.image(scan.title, chapterImages));
        }
      }

      if (manifest.chapters.length === 0) {
        throw new Error('没有可用的图片');
      }

      onProgress('生成章节', manifest.chapters.length, manifest.chapters.length);
      LibraryStore.saveManifest(bookId, manifest);
      const book = BookMeta.of(bookId, title, BookType.IMAGE, manifest.chapters.length, fingerprint);
      book.coverFile = manifest.chapters[0].images[0].file;
      LibraryStore.saveBook(book);

      if (FileUtil.exists(zipPath)) {
        FileUtil.deleteRecursive(zipPath);
      }
      return ImportResult.ok(bookId, title, skipped);
    } catch (e) {
      FileUtil.deleteRecursive(bookDir);
      return ImportResult.fail(ImportService.errorMessage(e as Error));
    }
  }

  /**
   * 导入 EPUB：解包后按 spine 顺序抽出每章纯文本，复用文本书的落盘结构。
   *
   * EPUB 只是「ZIP + XML + XHTML」，正文抽成单章 txt 后，
   * 阅读、分页、进度、搜索、划线全都不需要区分来源格式。
   */
  static async importEpub(uri: string, onProgress: ImportProgressCallback): Promise<ImportResult> {
    const bookId = ImportService.newId();
    const bookDir = AppPaths.bookDir(bookId);
    const bookRel = AppPaths.bookRel(bookId);
    const epubPath = `${bookDir}/source.epub`;
    const extractDir = `${bookDir}/content`;
    try {
      const size = FileUtil.uriSize(uri);
      if (size > MAX_EPUB_BYTES) {
        throw new Error(`EPUB 超过 ${MAX_EPUB_LABEL}`);
      }
      FileUtil.ensureDir(bookDir);
      onProgress('复制文件', 0, 1);
      FileUtil.copyUriToFile(uri, epubPath);
      if (FileUtil.fileSize(epubPath) <= 0) {
        throw new Error('文件为空');
      }
      onProgress('解压 epub', 0, 1);
      FileUtil.ensureDir(extractDir);
      await zlib.decompressFile(epubPath, extractDir);
      onProgress('解析章节', 0, 0);
      const parsed = EpubParser.parse(extractDir);
      if (parsed.chapters.length === 0) {
        throw new Error('未解析出任何章节');
      }
      if (parsed.chapters.length > MAX_CHAPTERS) {
        throw new Error('章节数量超过 1000');
      }
      const title = parsed.title.length > 0 ? parsed.title : ImportService.titleFromUri(uri);
      const textDir = `${bookDir}/text`;
      FileUtil.ensureDir(textDir);
      const manifest = new BookManifest();
      for (let i = 0; i < parsed.chapters.length; i++) {
        const chapter = parsed.chapters[i];
        const fileName = `${ImportService.pad4(i + 1)}.txt`;
        FileUtil.writeText(`${textDir}/${fileName}`, chapter.content);
        manifest.chapters.push(ChapterMeta.text(chapter.title, `${bookRel}/text/${fileName}`,
          chapter.content.length));
        if (i % 10 === 0) {
          onProgress('写入章节', i, parsed.chapters.length);
        }
      }
      // 章节正文还在内存里，直接用内存算指纹，不必再回读磁盘；命中就丢掉本次解包目录
      const fingerprint = ImportService.fingerprintOfEpub(parsed);
      const existed = ImportService.findDuplicate(BookType.TEXT, manifest.chapters.length, fingerprint);
      if (existed !== undefined) {
        FileUtil.deleteRecursive(bookDir);
        return ImportResult.duplicated(existed.id, existed.title);
      }
      onProgress('写入书架', parsed.chapters.length, parsed.chapters.length);
      LibraryStore.saveManifest(bookId, manifest);
      const book = BookMeta.of(bookId, title, BookType.TEXT, manifest.chapters.length, fingerprint);
      book.coverFile = parsed.coverRel;
      LibraryStore.saveBook(book);
      // 原始 epub 不再需要；content/ 保留（封面图可能在这里）
      if (FileUtil.exists(epubPath)) {
        FileUtil.deleteRecursive(epubPath);
      }
      return ImportResult.ok(bookId, title, 0);
    } catch (e) {
      FileUtil.deleteRecursive(bookDir);
      return ImportResult.fail(ImportService.errorMessage(e as Error));
    }
  }

  private static scanChapters(extractDir: string): ChapterScan[] {
    let root = extractDir;
    let wrapperTitle = '';
    let guard = 0;
    while (guard < 20) {
      guard++;
      const names = FileUtil.listFiles(root);
      const dirs: string[] = [];
      let hasImage = false;
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        if (ImportService.isIgnored(name)) {
          continue;
        }
        const full = `${root}/${name}`;
        if (FileUtil.isDirectory(full)) {
          dirs.push(full);
        } else if (ImportService.isImageFile(name)) {
          hasImage = true;
        }
      }
      if (!hasImage && dirs.length === 1) {
        wrapperTitle = ImportService.baseName(dirs[0]);
        root = dirs[0];
        continue;
      }
      break;
    }
    const scans: ChapterScan[] = [];
    ImportService.collectImageDirs(root, root, scans, true, wrapperTitle);
    return scans;
  }

  private static collectImageDirs(baseRoot: string, dir: string, scans: ChapterScan[],
    isRoot: boolean, wrapperTitle: string): void {
    const names = FileUtil.listFiles(dir);
    const images: string[] = [];
    const subdirs: string[] = [];
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      if (ImportService.isIgnored(name)) {
        continue;
      }
      const full = `${dir}/${name}`;
      if (FileUtil.isDirectory(full)) {
        subdirs.push(full);
      } else if (ImportService.isImageFile(name)) {
        images.push(full);
      }
    }
    images.sort((a: string, b: string): number => {
      return NaturalSort.compare(ImportService.baseName(a), ImportService.baseName(b));
    });
    subdirs.sort((a: string, b: string): number => {
      return NaturalSort.compare(ImportService.baseName(a), ImportService.baseName(b));
    });

    if (images.length > 0) {
      const scan = new ChapterScan();
      if (isRoot) {
        scan.title = wrapperTitle.length > 0 ? wrapperTitle : '未分章';
      } else {
        scan.title = ImportService.relativeTitle(baseRoot, dir);
      }
      scan.dir = dir;
      scan.images = images;
      scans.push(scan);
    }
    for (let i = 0; i < subdirs.length; i++) {
      ImportService.collectImageDirs(baseRoot, subdirs[i], scans, false, wrapperTitle);
    }
  }

  private static relativeTitle(baseRoot: string, dir: string): string {
    const prefix = `${baseRoot}/`;
    let rel = dir;
    if (dir.startsWith(prefix)) {
      rel = dir.substring(prefix.length);
    } else {
      rel = ImportService.baseName(dir);
    }
    if (rel.length === 0) {
      return '未分章';
    }
    return rel.split('/').join(' · ');
  }

  /**
   * 扫描文件夹（picker 选目录得到的授权 uri），递归收集其中的 txt / epub / zip，最多 limit 个。
   *
   * 子项一律在父级地址后拼名字而不是转成本地路径：picker 的读授权按 uri 前缀生效，
   * 转成裸路径后越出授权范围会读不到文件。
   * 目录数设上限，避免误选根目录这类超大目录时卡在扫描上。
   */
  static scanFolder(uri: string, limit: number): FolderBook[] {
    const result: FolderBook[] = [];
    if (limit <= 0 || uri.length === 0) {
      return result;
    }
    const queue: string[] = [uri];
    let visited = 0;
    while (queue.length > 0 && result.length < limit && visited < MAX_SCAN_DIRS) {
      const dir = queue[0];
      queue.splice(0, 1);
      visited++;
      const names = FileUtil.listDir(dir);
      for (let i = 0; i < names.length; i++) {
        if (result.length >= limit) {
          break;
        }
        const name = names[i];
        if (ImportService.isIgnored(name)) {
          continue;
        }
        const entry = FileUtil.joinEntry(dir, name);
        if (FileUtil.isDirEntry(entry)) {
          if (queue.length + visited < MAX_SCAN_DIRS) {
            queue.push(entry);
          }
          continue;
        }
        const kind = ImportService.bookKindOf(name);
        if (kind.length > 0) {
          result.push(FolderBook.of(entry, kind));
        }
      }
    }
    result.sort((a: FolderBook, b: FolderBook): number => NaturalSort.compare(a.uri, b.uri));
    return result;
  }

  /**
   * 书籍内容指纹：类型 + 章节数 + 总字数 + 首末章摘要。
   *
   * 为什么不是书名：同一本书的「连载版」和「完结版」书名一模一样，但章节数、总字数、末章都不同，
   * 指纹必然不同，能正常导入；而同一份内容重复导入时这些字段完全一致，指纹相同，直接拦下。
   * 只读首末两章，不必为查重把整本书再读一遍。
   */
  static fingerprintOf(type: BookType, manifest: BookManifest): string {
    if (manifest.chapters.length === 0) {
      return '';
    }
    let totalChars = 0;
    let totalImages = 0;
    for (let i = 0; i < manifest.chapters.length; i++) {
      totalChars += manifest.chapters[i].charCount;
      totalImages += manifest.chapters[i].images.length;
    }
    const first = manifest.chapters[0];
    const last = manifest.chapters[manifest.chapters.length - 1];
    let head = '';
    let tail = '';
    if (type === BookType.TEXT) {
      head = FileUtil.hashText(FileUtil.readTextHead(ImportService.chapterPath(first.contentFile), 3000));
      tail = FileUtil.hashText(FileUtil.readTextHead(ImportService.chapterPath(last.contentFile), 3000));
    } else {
      head = first.images.length > 0 ? first.images[0].file : '';
      tail = last.images.length > 0 ? last.images[last.images.length - 1].file : '';
    }
    return ImportService.fingerprintOfParts(type, manifest.chapters.length, totalChars, totalImages,
      head, tail);
  }

  /**
   * EPUB 的指纹：解析结果还在内存里，直接拿正文算，省掉回读磁盘。
   * 与 TXT 走同一套字段，同一种书（BookType.TEXT）之间可以直接比较。
   */
  private static fingerprintOfEpub(book: EpubBook): string {
    if (book.chapters.length === 0) {
      return '';
    }
    let totalChars = 0;
    for (let i = 0; i < book.chapters.length; i++) {
      totalChars += book.chapters[i].content.length;
    }
    const last = book.chapters[book.chapters.length - 1];
    const head = FileUtil.hashText(book.chapters[0].content.substring(0, 3000));
    const tail = FileUtil.hashText(last.content.substring(0, 3000));
    return ImportService.fingerprintOfParts(BookType.TEXT, book.chapters.length, totalChars, 0,
      head, tail);
  }

  private static fingerprintOfParts(type: BookType, chapterCount: number, totalChars: number,
    totalImages: number, head: string, tail: string): string {
    return FileUtil.hashText(`${type}|${chapterCount}|${totalChars}|${totalImages}|${head}|${tail}`);
  }

  /**
   * 图片书指纹：扫描阶段就能算（章节数 + 图片总数 + 首末图文件名），
   * 不必先读完几百张图的元数据，重复导入可以更早退出。
   */
  private static fingerprintOfScans(scans: ChapterScan[]): string {
    if (scans.length === 0) {
      return '';
    }
    let totalImages = 0;
    for (let i = 0; i < scans.length; i++) {
      totalImages += scans[i].images.length;
    }
    const first = scans[0];
    const last = scans[scans.length - 1];
    const head = first.images.length > 0 ? ImportService.baseName(first.images[0]) : '';
    const tail = last.images.length > 0 ? ImportService.baseName(last.images[last.images.length - 1]) : '';
    return FileUtil.hashText(
      `${BookType.IMAGE}|${scans.length}|${totalImages}|${first.title}|${last.title}|${head}|${tail}`);
  }

  /** manifest 里的章节文件是相对沙箱根的路径，读文件前要补全 */
  private static chapterPath(contentFile: string): string {
    return AppPaths.abs(contentFile);
  }

  /**
   * 内容指纹查重：命中就返回书架上的原书（不论它是否在分组里）。
   * 历史书没有指纹，只有章节数相同时才值得补算（否则为每本旧书都读首末章太浪费）。
   */
  private static findDuplicate(type: BookType, chapterCount: number,
    fingerprint: string): BookMeta | undefined {
    if (fingerprint.length === 0) {
      return undefined;
    }
    const books = LibraryStore.getBooks();
    for (let i = 0; i < books.length; i++) {
      const book = books[i];
      if (book.type !== type || book.chapterCount !== chapterCount) {
        continue;
      }
      let stored = book.contentHash ?? '';
      if (stored.length === 0) {
        stored = ImportService.fingerprintOf(book.type, LibraryStore.getManifest(book.id));
        if (stored.length > 0) {
          LibraryStore.setContentHash(book.id, stored);
        }
      }
      if (stored.length > 0 && stored === fingerprint) {
        return book;
      }
    }
    return undefined;
  }

  /**
   * 文件夹名：用于给「导入文件夹」进来的书籍建同名分组。
   * 取地址最后一段（先解码、去掉 query 与末尾斜杠），去掉扩展名的规则不适用于目录。
   */
  static folderNameOf(uri: string): string {
    let decoded = uri;
    try {
      decoded = decodeURIComponent(uri);
    } catch (e) {
      decoded = uri;
    }
    const query = decoded.indexOf('?');
    if (query >= 0) {
      decoded = decoded.substring(0, query);
    }
    let path = decoded;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    const index = path.lastIndexOf('/');
    const name = index >= 0 ? path.substring(index + 1) : path;
    return name.length > 0 ? name : '导入的书';
  }

  /** 可导入的书籍扩展名；返回空串表示不支持的格式 */
  private static bookKindOf(name: string): string {
    const dot = name.lastIndexOf('.');
    if (dot < 0) {
      return '';
    }
    const ext = name.substring(dot + 1).toLowerCase();
    if (ext === 'txt' || ext === 'epub' || ext === 'zip') {
      return ext;
    }
    return '';
  }

  private static isIgnored(name: string): boolean {
    return name.startsWith('.') || name === '__MACOSX' || name === 'Thumbs.db' || name === 'thumbs.db';
  }

  private static isImageFile(name: string): boolean {
    const dot = name.lastIndexOf('.');
    if (dot < 0) {
      return false;
    }
    const ext = name.substring(dot + 1).toLowerCase();
    return ext === 'jpg' || ext === 'jpeg' || ext === 'png' || ext === 'webp' ||
      ext === 'bmp' || ext === 'gif';
  }

  private static baseName(path: string): string {
    const index = path.lastIndexOf('/');
    if (index >= 0) {
      return path.substring(index + 1);
    }
    return path;
  }

  private static titleFromUri(uri: string): string {
    let decoded = uri;
    try {
      decoded = decodeURIComponent(uri);
    } catch (e) {
      decoded = uri;
    }
    let name = decoded.substring(decoded.lastIndexOf('/') + 1);
    const query = name.indexOf('?');
    if (query >= 0) {
      name = name.substring(0, query);
    }
    const dot = name.lastIndexOf('.');
    if (dot > 0) {
      name = name.substring(0, dot);
    }
    return name.length > 0 ? name : '未命名书籍';
  }

  private static pad4(index: number): string {
    const raw = index.toString();
    if (raw.length >= 4) {
      return raw;
    }
    return '0000'.substring(0, 4 - raw.length) + raw;
  }

  private static newId(): string {
    return `${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
  }

  private static errorMessage(e: Error): string {
    if (e !== undefined && e.message !== undefined && e.message.length > 0) {
      return e.message;
    }
    return '导入失败';
  }
}
