import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
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

  /** 异步读文本，用于预取相邻章节，避免阻塞主线程 */
  static async readTextAsync(path: string): Promise<string> {
    if (!fs.accessSync(path)) {
      return '';
    }
    try {
      return await fs.readText(path);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'readTextAsync failed: %{public}s %{public}s', path, err.message);
      return '';
    }
  }

  /**
   * 只读文件头部最多 maxChars 个字符（按字节窗口读取，避免为预览读整章文件）。
   * 窗口尾部截断的多字节字符会被裁剪掉。
   */
  static readTextHead(path: string, maxChars: number): string {
    const size = FileUtil.fileSize(path);
    if (size <= 0) {
      return '';
    }
    const want = Math.max(maxChars, 1) * 4 + 3;
    const readBytes = Math.min(size, want);
    const bytes = FileUtil.readBytesAt(path, 0, readBytes);
    return FileUtil.trimWindowHead(FileUtil.decodeUtf8Lenient(bytes), maxChars);
  }

  /**
   * 只读文件尾部最多 maxChars 个字符（按字节窗口读取）。
   * 窗口头部截断的多字节字符会被裁剪掉。
   */
  static readTextTail(path: string, maxChars: number): string {
    const size = FileUtil.fileSize(path);
    if (size <= 0) {
      return '';
    }
    const want = Math.max(maxChars, 1) * 4 + 3;
    const readBytes = Math.min(size, want);
    const bytes = FileUtil.readBytesAt(path, size - readBytes, readBytes);
    return FileUtil.trimWindowTail(FileUtil.decodeUtf8Lenient(bytes), maxChars);
  }

  /** 异步只读文件头部最多 maxChars 个字符（翻章衔接用，不阻塞主线程） */
  static async readTextHeadAsync(path: string, maxChars: number): Promise<string> {
    const size = FileUtil.fileSize(path);
    if (size <= 0) {
      return '';
    }
    const want = Math.max(maxChars, 1) * 4 + 3;
    const readBytes = Math.min(size, want);
    const bytes = await FileUtil.readBytesAtAsync(path, 0, readBytes);
    return FileUtil.trimWindowHead(FileUtil.decodeUtf8Lenient(bytes), maxChars);
  }

  /** 异步只读文件尾部最多 maxChars 个字符（翻章衔接用，不阻塞主线程） */
  static async readTextTailAsync(path: string, maxChars: number): Promise<string> {
    const size = FileUtil.fileSize(path);
    if (size <= 0) {
      return '';
    }
    const want = Math.max(maxChars, 1) * 4 + 3;
    const readBytes = Math.min(size, want);
    const bytes = await FileUtil.readBytesAtAsync(path, size - readBytes, readBytes);
    return FileUtil.trimWindowTail(FileUtil.decodeUtf8Lenient(bytes), maxChars);
  }

  /** 异步从文件指定字节偏移读取 length 字节 */
  private static async readBytesAtAsync(path: string, position: number, length: number): Promise<Uint8Array> {
    let file: fs.File | undefined = undefined;
    try {
      file = await fs.open(path, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(length);
      let read = 0;
      while (read < length) {
        const n = await fs.read(file.fd, buffer, { offset: position + read, length: length - read });
        if (n <= 0) {
          break;
        }
        read += n;
      }
      const result = new Uint8Array(read);
      const src = new Uint8Array(buffer);
      for (let i = 0; i < read; i++) {
        result[i] = src[i];
      }
      return result;
    } finally {
      if (file !== undefined) {
        await fs.close(file);
      }
    }
  }

  /** 从文件指定字节偏移读取 length 字节，循环读直到读满或 EOF */
  private static readBytesAt(path: string, position: number, length: number): Uint8Array {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(length);
      let read = 0;
      while (read < length) {
        const n = fs.readSync(file.fd, buffer, { offset: position + read, length: length - read });
        if (n <= 0) {
          break;
        }
        read += n;
      }
      const result = new Uint8Array(read);
      const src = new Uint8Array(buffer);
      for (let i = 0; i < read; i++) {
        result[i] = src[i];
      }
      return result;
    } finally {
      if (file !== undefined) {
        fs.closeSync(file);
      }
    }
  }

  /** 章节文件均为 UTF-8，用非致命解码把截断字节替换为 U+FFFD 后统一裁剪 */
  private static decodeUtf8Lenient(bytes: Uint8Array): string {
    if (bytes.length === 0) {
      return '';
    }
    try {
      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      return decoder.decodeToString(bytes);
    } catch (e) {
      return '';
    }
  }

  private static trimWindowHead(text: string, maxChars: number): string {
    let end = text.length;
    while (end > 0 && text.charCodeAt(end - 1) === 0xFFFD) {
      end--;
    }
    let result = text.substring(0, end);
    if (result.length > maxChars) {
      result = result.substring(0, maxChars);
    }
    return result;
  }

  private static trimWindowTail(text: string, maxChars: number): string {
    let start = 0;
    while (start < text.length && text.charCodeAt(start) === 0xFFFD) {
      start++;
    }
    let result = text.substring(start);
    if (result.length > maxChars) {
      result = result.substring(result.length - maxChars);
    }
    return result;
  }

  static writeText(path: string, content: string): void {
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
    } finally {
      fs.closeSync(file);
    }
  }

  /**
   * 原子写：先写 .tmp，再 rename 覆盖目标。
   * 不再「先 unlink 目标」——两次系统调用之间进程被杀，旧文件已删、新文件未就位，
   * 会导致 library/settings/bookmarks/annotations 整文件丢失。
   * 同目录 rename 是原子替换；仅当平台返回失败时才回退为直接覆盖写。
   */
  /** 把文本写入 picker.save() 返回的 uri（该 uri 带临时写授权） */
  static writeUriText(uri: string, content: string): void {
    const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
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
      fs.renameSync(tempPath, path);
      return;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'atomic rename failed, fallback to direct write: %{public}s %{public}s',
        path, err.message);
    }
    try {
      FileUtil.writeText(path, content);
    } finally {
      FileUtil.discardTemp(tempPath);
    }
  }

  /** 清理临时文件，失败不阻塞主流程 */
  private static discardTemp(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'discard temp failed: %{public}s %{public}s', path, err.message);
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

  /**
   * 列目录名。目录可能来自 picker（file://docs/... 的授权 uri），也可能是沙箱路径，
   * 两种形式都试一次：uri 形式优先（授权按 uri 前缀生效），失败再转本地路径。
   */
  static listDir(dir: string): string[] {
    try {
      return fs.listFileSync(dir);
    } catch (e) {
      try {
        return fs.listFileSync(new fileUri.FileUri(dir).path);
      } catch (e2) {
        const err = e2 as BusinessError;
        hilog.error(DOMAIN, TAG, 'listDir failed: %{public}s %{public}s', dir, err.message);
        return [];
      }
    }
  }

  /** 目录项是子目录还是文件（同样兼容 picker uri 与沙箱路径） */
  static isDirEntry(entry: string): boolean {
    try {
      return fs.statSync(entry).isDirectory();
    } catch (e) {
      try {
        return fs.statSync(new fileUri.FileUri(entry).path).isDirectory();
      } catch (e2) {
        return false;
      }
    }
  }

  /** 拼接子项：父级保持原形式（uri 或路径），picker 目录下的子项用 uri 才能继承读授权 */
  static joinEntry(parent: string, name: string): string {
    if (parent.endsWith('/')) {
      return parent + name;
    }
    return `${parent}/${name}`;
  }

  /**
   * 字符串内容的 MD5（32 位十六进制）。
   * 导入查重用的书籍指纹就是「类型 + 章节数 + 首末章摘要」拼成字符串后再取摘要。
   */
  static hashText(text: string): string {
    try {
      const md = cryptoFramework.createMd('MD5');
      md.updateSync({ data: new util.TextEncoder().encodeInto(text) });
      const digest = md.digestSync();
      let hex = '';
      for (let i = 0; i < digest.data.length; i++) {
        hex += digest.data[i].toString(16).padStart(2, '0');
      }
      return hex;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'hashText failed: %{public}s', err.message);
      return '';
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

  /**
   * 分片统计目录大小：每帧最多处理 BATCH 个节点，最多扫 MAX_NODES 个节点。
   * 大书架有十几万个章节文件，全量同步递归会占满主线程触发 APP_INPUT_BLOCK；
   * 超过上限时回调 partial=true，界面显示「≥ 已统计值」而不是长时间停在「统计中…」。
   */
  static pathSizeAsync(path: string, onDone: (bytes: number, partial: boolean) => void): void {
    const BATCH = 100;
    const MAX_NODES = 20000;
    const pending: string[] = [path];
    let total = 0;
    let visited = 0;
    let step: () => void = (): void => {};
    step = (): void => {
      let handled = 0;
      while (pending.length > 0 && handled < BATCH && visited < MAX_NODES) {
        const current = pending.pop();
        if (current === undefined) {
          break;
        }
        handled++;
        visited++;
        try {
          const stat = fs.statSync(current);
          if (!stat.isDirectory()) {
            total += stat.size;
            continue;
          }
          const names = fs.listFileSync(current);
          for (let i = 0; i < names.length; i++) {
            pending.push(`${current}/${names[i]}`);
          }
        } catch (e) {
          const err = e as BusinessError;
          hilog.debug(DOMAIN, TAG, 'skip %{public}s %{public}s', current, err.message);
        }
      }
      if (pending.length > 0 && visited < MAX_NODES) {
        // 留出间隔让输入/渲染事件插队，避免连续 0ms 定时器把输入饿死
        setTimeout(step, 4);
      } else {
        onDone(total, pending.length > 0);
      }
    };
    step();
  }
}
