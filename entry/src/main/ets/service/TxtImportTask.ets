import { taskpool } from '@kit.ArkTS';
import { FileUtil } from '../utils/FileUtil';
import { TextCodec } from './TextCodec';

/** TaskPool 内构建、跨线程以 JSON 传回的章节元信息 */
interface ChapterJson {
  title: string;
  relFile: string;
  charCount: number;
}

interface ParseJson {
  chapters: ChapterJson[];
  charCount: number;
}

/** 主线程侧结果对象 */
export class TxtChapterResult {
  title: string = '';
  relFile: string = '';
  charCount: number = 0;
}

export class TxtParseResult {
  chapters: TxtChapterResult[] = [];
  charCount: number = 0;
}

/**
 * TaskPool 任务：读源文件 → 解码 → 切分章节 → 逐章写盘。
 * 只接收绝对路径与基本类型；返回 JSON 字符串，避免自定义 class 跨线程序列化失败。
 */
@Concurrent
function parseTxtTask(srcPath: string, textDir: string, relDir: string, fallbackTitle: string,
  maxBytes: number): string {
  const size = FileUtil.fileSize(srcPath);
  if (size <= 0) {
    throw new Error('文件为空');
  }
  if (size > maxBytes) {
    throw new Error('文件过大');
  }
  const bytes = FileUtil.readUriBytes(srcPath, maxBytes);
  if (bytes.length === 0) {
    throw new Error('文件为空');
  }
  const text = TextCodec.normalize(TextCodec.decode(bytes));
  if (text.trim().length === 0) {
    throw new Error('文本内容为空');
  }
  const drafts = TextCodec.splitChapters(text, fallbackTitle);
  if (drafts.length === 0) {
    throw new Error('未解析出任何章节');
  }
  FileUtil.ensureDir(textDir);
  const chapters: ChapterJson[] = [];
  let total = 0;
  for (let i = 0; i < drafts.length; i++) {
    // worker 内不依赖 AppPaths，文件名统一 4 位补零，保证字典序与章序一致
    let name = i.toString();
    while (name.length < 4) {
      name = `0${name}`;
    }
    const content = drafts[i].content;
    FileUtil.writeText(`${textDir}/${name}.txt`, content);
    const item: ChapterJson = {
      title: drafts[i].title,
      relFile: `${relDir}/text/${name}.txt`,
      charCount: content.length
    };
    chapters.push(item);
    total += content.length;
  }
  const payload: ParseJson = { chapters: chapters, charCount: total };
  return JSON.stringify(payload);
}

export class TxtImportTask {
  /** 在 TaskPool 中解析 TXT；调用方负责传入沙箱绝对路径与已存在的 relative 前缀 */
  static async parse(srcPath: string, textDir: string, relDir: string, fallbackTitle: string,
    maxBytes: number): Promise<TxtParseResult> {
    const raw: Object = await taskpool.execute(parseTxtTask, srcPath, textDir, relDir,
      fallbackTitle, maxBytes);
    const json = raw as string;
    const payload: ParseJson = JSON.parse(json) as ParseJson;
    const result = new TxtParseResult();
    if (payload.chapters === undefined) {
      return result;
    }
    for (let i = 0; i < payload.chapters.length; i++) {
      const source = payload.chapters[i];
      const chapter = new TxtChapterResult();
      chapter.title = source.title;
      chapter.relFile = source.relFile;
      chapter.charCount = source.charCount;
      result.chapters.push(chapter);
      result.charCount += source.charCount;
    }
    return result;
  }
}
