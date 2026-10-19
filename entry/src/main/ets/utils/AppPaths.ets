import { fileUri } from '@kit.CoreFileKit';

export class AppPaths {
  private static baseDir: string = '';

  static init(filesDir: string): void {
    AppPaths.baseDir = filesDir;
  }

  static getFilesDir(): string {
    return AppPaths.baseDir;
  }

  static abs(rel: string): string {
    if (rel.length === 0) {
      return '';
    }
    if (rel.startsWith('/')) {
      return rel;
    }
    return `${AppPaths.baseDir}/${rel}`;
  }

  static uri(rel: string): string {
    const absPath = AppPaths.abs(rel);
    if (absPath.length === 0) {
      return '';
    }
    return fileUri.getUriFromPath(absPath);
  }

  static relative(absPath: string): string {
    const prefix = `${AppPaths.baseDir}/`;
    if (absPath.startsWith(prefix)) {
      return absPath.substring(prefix.length);
    }
    return absPath;
  }

  static bookDir(bookId: string): string {
    return `${AppPaths.baseDir}/books/${bookId}`;
  }

  static bookRel(bookId: string): string {
    return `books/${bookId}`;
  }
}
