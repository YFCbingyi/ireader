import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'FileUtil';

export class FileUtil {
  static ensureDir(path: string): void {
    if (path.length === 0) {
      return;
    }
    if (!fs.accessSync(path)) {
      fs.mkdirSync(path, true);
    }
  }

  static exists(path: string): boolean {
    return fs.accessSync(path);
  }

  static readText(path: string): string {
    if (!fs.accessSync(path)) {
      return '';
    }
    try {
      return fs.readTextSync(path);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'readText failed: %{public}s %{public}s', path, err.message);
      return '';
    }
  }

  static writeText(path: string, content: string): void {
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
    } finally {
      fs.closeSync(file);
    }
  }

  static writeTextAtomic(path: string, content: string): void {
    const tempPath = `${path}.tmp`;
    FileUtil.writeText(tempPath, content);
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
      fs.renameSync(tempPath, path);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'rename failed: %{public}s %{public}s', path, err.message);
      FileUtil.writeText(path, content);
      if (fs.accessSync(tempPath)) {
        fs.unlinkSync(tempPath);
      }
    }
  }

  static readUriBytes(uri: string, maxBytes: number): Uint8Array {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      if (stat.size > maxBytes) {
        throw new Error('文件过大');
      }
      const buffer = new ArrayBuffer(stat.size);
      if (stat.size > 0) {
        fs.readSync(file.fd, buffer);
      }
      return new Uint8Array(buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  static copyUriToFile(uri: string, destPath: string): void {
    const source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      fs.copyFileSync(source.fd, destPath);
    } finally {
      fs.closeSync(source);
    }
  }

  static deleteRecursive(path: string): void {
    if (!fs.accessSync(path)) {
      return;
    }
    try {
      const stat = fs.statSync(path);
      if (stat.isDirectory()) {
        const names = fs.listFileSync(path);
        for (let i = 0; i < names.length; i++) {
          FileUtil.deleteRecursive(`${path}/${names[i]}`);
        }
        fs.rmdirSync(path);
      } else {
        fs.unlinkSync(path);
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'delete failed: %{public}s %{public}s', path, err.message);
    }
  }

  static listFiles(path: string): string[] {
    if (!fs.accessSync(path)) {
      return [];
    }
    try {
      return fs.listFileSync(path);
    } catch (e) {
      return [];
    }
  }

  static isDirectory(path: string): boolean {
    try {
      return fs.statSync(path).isDirectory();
    } catch (e) {
      return false;
    }
  }

  static fileSize(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (e) {
      return 0;
    }
  }

  static uriSize(uri: string): number {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      return fs.statSync(file.fd).size;
    } catch (e) {
      return 0;
    } finally {
      if (file !== undefined) {
        fs.closeSync(file);
      }
    }
  }

  static pathSize(path: string): number {
    if (!fs.accessSync(path)) {
      return 0;
    }
    let total = 0;
    try {
      const stat = fs.statSync(path);
      if (!stat.isDirectory()) {
        return stat.size;
      }
      const names = fs.listFileSync(path);
      for (let i = 0; i < names.length; i++) {
        total += FileUtil.pathSize(`${path}/${names[i]}`);
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'dir size failed: %{public}s %{public}s', path, err.message);
    }
    return total;
  }
}
