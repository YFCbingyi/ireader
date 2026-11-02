import { hilog } from '@kit.PerformanceAnalysisKit';
import { Annotation, AnnotationKind } from '../model/Annotation';
import { AppPaths } from '../utils/AppPaths';
import { FileUtil } from '../utils/FileUtil';

const DOMAIN = 0x0002;
const TAG = 'AnnotationStore';

/**
 * 划线 / 想法持久化：filesDir/annotations/{bookId}.json。
 * 与书签同一套路（逐书一个 JSON），只在增删改时整表写回。
 */
export class AnnotationStore {
  private static dirPath(): string {
    return `${AppPaths.getFilesDir()}/annotations`;
  }

  private static filePath(bookId: string): string {
    return `${AnnotationStore.dirPath()}/${bookId}.json`;
  }

  static load(bookId: string): Annotation[] {
    const raw = FileUtil.readText(AnnotationStore.filePath(bookId));
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as Annotation[];
      const result: Annotation[] = [];
      for (let i = 0; i < parsed.length; i++) {
        const raw = parsed[i];
        if (raw === undefined || raw.id === undefined || raw.id.length === 0) {
          continue;
        }
        if (raw.chapterIndex === undefined || raw.start === undefined || raw.end === undefined) {
          continue;
        }
        if (raw.end <= raw.start) {
          continue;
        }
        // JSON.parse 得到的是无方法的普通对象，必须还原成 Annotation 实例
        // （Annotation.intersects / covers 在渲染与查找时按实例方法调用）
        const item = new Annotation();
        item.id = raw.id;
        item.chapterIndex = raw.chapterIndex;
        item.start = raw.start;
        item.end = raw.end;
        item.text = raw.text !== undefined ? raw.text : '';
        item.note = raw.note !== undefined ? raw.note : '';
        item.kind = raw.kind !== undefined ? raw.kind : AnnotationKind.HIGHLIGHT;
        item.createdAt = raw.createdAt !== undefined ? raw.createdAt : 0;
        item.updatedAt = raw.updatedAt !== undefined ? raw.updatedAt : item.createdAt;
        result.push(item);
      }
      AnnotationStore.sort(result);
      return result;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'parse annotations failed: %{public}s', bookId);
      return [];
    }
  }

  static save(bookId: string, list: Annotation[]): void {
    FileUtil.ensureDir(AnnotationStore.dirPath());
    FileUtil.writeTextAtomic(AnnotationStore.filePath(bookId), JSON.stringify(list));
  }

  /** 按章、章内偏移排序，渲染与查找都依赖这个顺序 */
  static sort(list: Annotation[]): void {
    list.sort((a: Annotation, b: Annotation): number => {
      if (a.chapterIndex !== b.chapterIndex) {
        return a.chapterIndex - b.chapterIndex;
      }
      return a.start - b.start;
    });
  }

  /** 找与 [start, end) 有交集的标注（重叠时取最靠前的一条） */
  static findAt(list: Annotation[], chapterIndex: number, start: number, end: number): Annotation | undefined {
    for (let i = 0; i < list.length; i++) {
      const item = list[i];
      if (item.chapterIndex === chapterIndex && item.intersects(start, end)) {
        return item;
      }
    }
    return undefined;
  }

  static removeById(list: Annotation[], id: string): Annotation[] {
    const remain: Annotation[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].id !== id) {
        remain.push(list[i]);
      }
    }
    return remain;
  }

  /** 某章是否有标注（供渲染层快速判断是否需要切分 Span） */
  static hasInChapter(list: Annotation[], chapterIndex: number): boolean {
    for (let i = 0; i < list.length; i++) {
      if (list[i].chapterIndex === chapterIndex) {
        return true;
      }
    }
    return false;
  }
}
