/**
 * 上下连续卷轴的块窗口（Engine 层）。
 *
 * 一章被切成 [章标题块] + [若干正文块]，块是滚动列表的最小单元：
 * 每块约 600 字（在换行处截断），既不会因整章一个 Text 撑爆渲染，
 * 也不会像逐行建模那样产生上千个列表项。
 *
 * 与 PageWindow 一样不依赖 UI：只维护块序列与章范围，锚点查找返回索引，
 * 滚动由容器层用 Scroller.scrollToIndex 完成。
 */

/** 正文分块：每块约 600 字 */
const CHUNK_CHARS = 600;
/** 换行补齐的最大回溯字符数（超出就硬切，避免长段无换行时块过大） */
const CHUNK_NEWLINE_SLACK = 160;

/** 连续卷轴的文本块：章标题 / 正文分块，带所属章节号 */
export class ReaderBlock {
  kind: string = '';
  text: string = '';
  chapterIndex: number = 0;
  start: number = 0;
  end: number = 0;

  static of(kind: string, text: string, chapterIndex: number, start: number, end: number): ReaderBlock {
    const block = new ReaderBlock();
    block.kind = kind;
    block.text = text;
    block.chapterIndex = chapterIndex;
    block.start = start;
    block.end = end;
    return block;
  }
}

/** 跨章块数据源：支持整表重置，以及尾部追加 / 头部前插 / 两端回收的增量通知 */
export class ReaderBlockSource implements IDataSource {
  private blocks: ReaderBlock[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.blocks.length;
  }

  getData(index: number): ReaderBlock {
    const block = this.blocks[index];
    return block !== undefined ? block : ReaderBlock.of('text', '', 0, 0, 0);
  }

  /** 可见区间内是否包含某类块（竖排用来判断章标题是否在屏幕上） */
  hasKindBetween(start: number, end: number, kind: string): boolean {
    if (this.blocks.length === 0) {
      return false;
    }
    const from = Math.max(0, start);
    const to = Math.min(this.blocks.length - 1, end);
    for (let i = from; i <= to; i++) {
      if (this.blocks[i].kind === kind) {
        return true;
      }
    }
    return false;
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 内部块数组只读视图，供组件计算锚点与进度 */
  snapshot(): ReaderBlock[] {
    return this.blocks;
  }

  reset(blocks: ReaderBlock[]): void {
    this.blocks = blocks;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  /** 尾部追加若干块 */
  append(newBlocks: ReaderBlock[]): void {
    if (newBlocks.length === 0) {
      return;
    }
    const startIndex = this.blocks.length;
    for (let i = 0; i < newBlocks.length; i++) {
      this.blocks.push(newBlocks[i]);
    }
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < newBlocks.length; j++) {
        listener.onDataAdd(startIndex + j);
      }
    }
  }

  /** 头部前插若干块（调用方需自行做滚动位置补偿） */
  prepend(newBlocks: ReaderBlock[]): void {
    if (newBlocks.length === 0) {
      return;
    }
    const combined: ReaderBlock[] = [];
    for (let i = 0; i < newBlocks.length; i++) {
      combined.push(newBlocks[i]);
    }
    for (let i = 0; i < this.blocks.length; i++) {
      combined.push(this.blocks[i]);
    }
    this.blocks = combined;
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < newBlocks.length; j++) {
        listener.onDataAdd(j);
      }
    }
  }

  /** 从头部移除 count 块 */
  removeHead(count: number): void {
    if (count <= 0 || this.blocks.length === 0) {
      return;
    }
    let removeCount = count;
    if (removeCount > this.blocks.length) {
      removeCount = this.blocks.length;
    }
    this.blocks.splice(0, removeCount);
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < removeCount; j++) {
        listener.onDataDelete(0);
      }
    }
  }

  /** 通知区间内的块内容变了（划线刷新），只重建这些项 */
  refreshRange(from: number, to: number): void {
    const total = this.blocks.length;
    if (total === 0) {
      return;
    }
    const start = from < 0 ? 0 : from;
    const end = to >= total ? total - 1 : to;
    for (let i = start; i <= end; i++) {
      for (let j = 0; j < this.listeners.length; j++) {
        this.listeners[j].onDataChange(i);
      }
    }
  }

  /** 从尾部移除 count 块 */
  removeTail(count: number): void {
    if (count <= 0 || this.blocks.length === 0) {
      return;
    }
    let removeCount = count;
    if (removeCount > this.blocks.length) {
      removeCount = this.blocks.length;
    }
    const startIndex = this.blocks.length - removeCount;
    this.blocks.splice(startIndex, removeCount);
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < removeCount; j++) {
        listener.onDataDelete(startIndex);
      }
    }
  }
}

/** 块窗口：块序列 + 章范围 + 章全文 / 块数索引 */
export class BlockWindow {
  readonly source: ReaderBlockSource = new ReaderBlockSource();
  startChapter: number = 0;
  endChapter: number = -1;
  private texts: Map<number, string> = new Map();
  private counts: Map<number, number> = new Map();
  private loading: Set<number> = new Set();

  /** 把一章切成 [章标题块] + [正文分块]；title 为空则只有正文块 */
  buildChapter(chapter: number, text: string, title: string): ReaderBlock[] {
    const blocks: ReaderBlock[] = [];
    if (title.length > 0) {
      blocks.push(ReaderBlock.of('title', title, chapter, 0, 0));
    }
    let cursor = 0;
    while (cursor < text.length) {
      let end = Math.min(text.length, cursor + CHUNK_CHARS);
      if (end < text.length) {
        // 尽量在换行处断开，避免把一段切两半
        const newline = text.indexOf('\n', end);
        if (newline > 0 && newline - end < CHUNK_NEWLINE_SLACK) {
          end = newline + 1;
        }
      }
      blocks.push(ReaderBlock.of('text', text.substring(cursor, end), chapter, cursor, end));
      cursor = end;
    }
    return blocks;
  }

  /** 以 center 为中心重建窗口，chapters 与 texts 一一对应 */
  reset(center: number, chapters: number[], texts: string[], titleOf: (chapter: number) => string): void {
    this.loading.clear();
    this.texts.clear();
    this.counts.clear();
    const blocks: ReaderBlock[] = [];
    for (let i = 0; i < chapters.length; i++) {
      const chapter = chapters[i];
      const text = i < texts.length ? texts[i] : '';
      const chapterBlocks = this.buildChapter(chapter, text, titleOf(chapter));
      this.texts.set(chapter, text);
      this.counts.set(chapter, chapterBlocks.length);
      for (let j = 0; j < chapterBlocks.length; j++) {
        blocks.push(chapterBlocks[j]);
      }
    }
    this.startChapter = chapters.length > 0 ? chapters[0] : center;
    this.endChapter = chapters.length > 0 ? chapters[chapters.length - 1] : center;
    this.source.reset(blocks);
  }

  /** 尾部追加一章，返回是否插入（章号必须紧邻窗口末尾） */
  append(chapter: number, text: string, title: string): boolean {
    if (chapter !== this.endChapter + 1) {
      return false;
    }
    const blocks = this.buildChapter(chapter, text, title);
    this.texts.set(chapter, text);
    this.counts.set(chapter, blocks.length);
    this.source.append(blocks);
    this.endChapter = chapter;
    return true;
  }

  /** 头部前插一章，返回是否插入（章号必须紧邻窗口头部） */
  prepend(chapter: number, text: string, title: string): boolean {
    if (chapter !== this.startChapter - 1) {
      return false;
    }
    const blocks = this.buildChapter(chapter, text, title);
    this.texts.set(chapter, text);
    this.counts.set(chapter, blocks.length);
    this.source.prepend(blocks);
    this.startChapter = chapter;
    return true;
  }

  /** 移除头部章，返回移除的块数 */
  removeHead(): number {
    const count = this.blockCount(this.startChapter);
    this.texts.delete(this.startChapter);
    this.counts.delete(this.startChapter);
    this.source.removeHead(count);
    this.startChapter++;
    return count;
  }

  /** 移除尾部章，返回移除的块数 */
  removeTail(): number {
    const count = this.blockCount(this.endChapter);
    this.texts.delete(this.endChapter);
    this.counts.delete(this.endChapter);
    this.source.removeTail(count);
    this.endChapter--;
    return count;
  }

  chapterCount(): number {
    return this.endChapter - this.startChapter + 1;
  }

  hasChapter(chapter: number): boolean {
    return this.texts.has(chapter);
  }

  chapterText(chapter: number): string {
    const text = this.texts.get(chapter);
    return text !== undefined ? text : '';
  }

  blockCount(chapter: number): number {
    const count = this.counts.get(chapter);
    return count !== undefined ? count : 0;
  }

  totalCount(): number {
    return this.source.totalCount();
  }

  blockAt(index: number): ReaderBlock | undefined {
    const blocks = this.source.snapshot();
    return blocks[index];
  }

  snapshot(): ReaderBlock[] {
    return this.source.snapshot();
  }

  hasKindBetween(start: number, end: number, kind: string): boolean {
    return this.source.hasKindBetween(start, end, kind);
  }

  // ===== 加载中标记 =====

  isLoading(chapter: number): boolean {
    return this.loading.has(chapter);
  }

  markLoading(chapter: number): void {
    this.loading.add(chapter);
  }

  clearLoading(chapter: number): void {
    this.loading.delete(chapter);
  }

  clearAllLoading(): void {
    this.loading.clear();
  }

  /**
   * 在块列表里找到「某章、某偏移」所在的块索引。
   *
   * 注意：不能一遇到标题块就返回。标题块的 start/end 都是 0，若在此直接 return，
   * 任何一次锚点补偿（前插 / 头部回收 / 打开书恢复进度）都会落到该章标题，
   * 表现为"滚到章末又跳回章首"。
   *
   * - offset <= 0 视为章首，返回标题块（无标题则返回该章第一块正文）
   * - offset > 0 返回最后一个 start <= offset 的正文块（偏移超过章末时即最后一块，
   *   "上一章"按钮定位到章末依赖这一点）
   */
  findBlockIndex(chapter: number, offset: number): number {
    const blocks = this.source.snapshot();
    let titleIndex = -1;
    let firstTextIndex = -1;
    let matchedTextIndex = -1;
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      if (block.chapterIndex !== chapter) {
        continue;
      }
      if (block.kind === 'title') {
        if (titleIndex < 0) {
          titleIndex = i;
        }
        continue;
      }
      if (firstTextIndex < 0) {
        firstTextIndex = i;
      }
      if (block.start <= offset) {
        matchedTextIndex = i;
      }
    }
    if (offset <= 0) {
      return titleIndex >= 0 ? titleIndex : firstTextIndex;
    }
    if (matchedTextIndex >= 0) {
      return matchedTextIndex;
    }
    return titleIndex >= 0 ? titleIndex : firstTextIndex;
  }
}
