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
import { TextCodec } from './TextCodec';
import { ImageMetaReader } from './ImageMetaReader';
import { LibraryStore } from './LibraryStore';

const MAX_TEXT_BYTES = 50 * 1024 * 1024;
const MAX_ZIP_ORIGINAL_BYTES = 2 * 1024 * 1024 * 1024;
const MAX_ZIP_LABEL = '2GB';
const MAX_CHAPTERS = 1000;

export class ChapterScan {
  title: string = '';
  dir: string = '';
  images: string[] = [];
}

export class ImportService {
  static async importTxt(uri: string, onProgress: ImportProgressCallback): Promise<ImportResult> {
    const bookId = ImportService.newId();
    const bookDir = AppPaths.bookDir(bookId);
    const bookRel = AppPaths.bookRel(bookId);
    try {
      onProgress('读取文本', 0, 1);
      const bytes = FileUtil.readUriBytes(uri, MAX_TEXT_BYTES);
      if (bytes.length === 0) {
        throw new Error('文件为空');
      }
      onProgress('识别编码', 0, 1);
      const text = TextCodec.normalize(TextCodec.decode(bytes));
      if (text.trim().length === 0) {
        throw new Error('文本内容为空');
      }
      const title = ImportService.titleFromUri(uri);
      onProgress('切分章节', 0, 1);
      const drafts = TextCodec.splitChapters(text, title);
      FileUtil.ensureDir(`${bookDir}/text`);
      const manifest = new BookManifest();
      for (let i = 0; i < drafts.length; i++) {
        const relFile = `${bookRel}/text/${ImportService.pad4(i)}.txt`;
        FileUtil.writeText(AppPaths.abs(relFile), drafts[i].content);
        manifest.chapters.push(ChapterMeta.text(drafts[i].title, relFile, drafts[i].content.length));
        onProgress('写入章节', i + 1, drafts.length);
      }
      LibraryStore.saveManifest(bookId, manifest);
      const book = BookMeta.of(bookId, title, BookType.TEXT, manifest.chapters.length);
      LibraryStore.saveBook(book);
      return ImportResult.ok(bookId, title, 0);
    } catch (e) {
      FileUtil.deleteRecursive(bookDir);
      return ImportResult.fail(ImportService.errorMessage(e as Error));
    }
  }

  static async importZip(uri: string, onProgress: ImportProgressCallback): Promise<ImportResult> {
    const bookId = ImportService.newId();
    const bookDir = AppPaths.bookDir(bookId);
    const zipPath = `${bookDir}/source.zip`;
    const extractDir = `${bookDir}/content`;
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
      const title = ImportService.titleFromUri(uri);
      const book = BookMeta.of(bookId, title, BookType.IMAGE, manifest.chapters.length);
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
