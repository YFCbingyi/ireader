/**
 * 划线记录：一条标注 = 章内 [start, end) 的原文 + 可选想法。
 * start/end 与 ReadingProgress.charOffset 同一坐标（章内字符偏移），
 * 排版变化（字号 / 行距 / 视图宽高）不影响，跨阅读模式通用。
 */
export enum AnnotationKind {
  /** 纯划线：文字加底色 */
  HIGHLIGHT = 'highlight',
  /** 划线 + 想法：文字加下划线 */
  NOTE = 'note'
}

export class Annotation {
  id: string = '';
  chapterIndex: number = 0;
  start: number = 0;
  end: number = 0;
  /** 划线原文，用于列表展示与偏移失效时的兜底匹配 */
  text: string = '';
  /** 想法内容，可为空 */
  note: string = '';
  kind: AnnotationKind = AnnotationKind.HIGHLIGHT;
  createdAt: number = 0;
  updatedAt: number = 0;

  static of(chapterIndex: number, start: number, end: number, text: string, note: string,
    kind: AnnotationKind): Annotation {
    const item = new Annotation();
    item.id = `a${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    item.chapterIndex = chapterIndex;
    item.start = start;
    item.end = end;
    item.text = text;
    item.note = note;
    item.kind = kind;
    item.createdAt = Date.now();
    item.updatedAt = item.createdAt;
    return item;
  }

  /** 是否与 [from, to) 有交集 */
  intersects(from: number, to: number): boolean {
    return this.start < to && this.end > from;
  }

  /** 是否完整覆盖 [from, to) */
  covers(from: number, to: number): boolean {
    return this.start <= from && this.end >= to;
  }
}

/** 渲染片段：同一段落内样式一致的连续文本 */
export class TextSegment {
  key: string = '';
  text: string = '';
  /** 加底色（带想法的划线比纯划线多一层浅底，便于扫读） */
  highlight: boolean = false;
  /** 加下划线 */
  underline: boolean = false;

  static of(key: string, text: string, highlight: boolean, underline: boolean): TextSegment {
    const seg = new TextSegment();
    seg.key = key;
    seg.text = text;
    seg.highlight = highlight;
    seg.underline = underline;
    return seg;
  }
}

/** 把一段正文按标注切分为样式片段（标注之外的段落保持原样） */
export class SegmentBuilder {
  static build(text: string, baseStart: number, annotations: Annotation[]): TextSegment[] {
    const segments: TextSegment[] = [];
    const length = text.length;
    if (length === 0) {
      return segments;
    }
    const baseEnd = baseStart + length;
    let cursor = 0;
    for (let i = 0; i < annotations.length; i++) {
      const ann = annotations[i];
      if (ann.end <= baseStart || ann.start >= baseEnd) {
        continue;
      }
      let from = ann.start - baseStart;
      let to = ann.end - baseStart;
      if (from < 0) {
        from = 0;
      }
      if (to > length) {
        to = length;
      }
      if (to <= cursor) {
        // 已被前一条标注覆盖（重叠时先到先得）
        continue;
      }
      if (from < cursor) {
        from = cursor;
      }
      if (from > cursor) {
        segments.push(TextSegment.of(`p${cursor}`, text.substring(cursor, from), false, false));
      }
      // 划线一律画下划线；带想法的额外加一层浅底
      segments.push(TextSegment.of(`a${from}`, text.substring(from, to),
        ann.kind === AnnotationKind.NOTE, true));
      cursor = to;
    }
    if (cursor < length) {
      segments.push(TextSegment.of(`p${cursor}`, text.substring(cursor), false, false));
    }
    return segments;
  }
}
