/**
 * 左右分页的页窗口（Engine 层）。
 *
 * 只负责「数据」：跨章页序列、章级分页缓存的 LRU、窗口边界、加载中标记、锚点查页。
 * 不依赖任何 ArkUI 状态，索引补偿由容器层根据这里返回的页数自行处理
 * （前插返回 +n、头部回收返回 -n），这样换渲染容器不需要改窗口逻辑。
 */

/** 一页：带所属章与章内字符偏移，key 跨章唯一 */
export class PagedItem {
  key: string = '';
  chapter: number = 0;
  pageIndex: number = 0;
  text: string = '';
  start: number = 0;

  static of(chapter: number, pageIndex: number, text: string, start: number): PagedItem {
    const item = new PagedItem();
    item.key = `${chapter}_${pageIndex}`;
    item.chapter = chapter;
    item.pageIndex = pageIndex;
    item.text = text;
    item.start = start;
    return item;
  }
}

/** 某章的分页结果缓存项：key 由排版参数拼成，参数一变整条失效 */
export class PagedChapter {
  key: string = '';
  items: PagedItem[] = [];

  static of(key: string, items: PagedItem[]): PagedChapter {
    const chapter = new PagedChapter();
    chapter.key = key;
    chapter.items = items;
    return chapter;
  }
}

/**
 * 跨章页数据源：支持整表重置，以及尾部追加章、头部前插章、两端回收。
 * 前插会让既有页索引整体后移，调用方必须做索引补偿。
 */
export class PagedSource implements IDataSource {
  private items: PagedItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): PagedItem {
    const item = this.items[index];
    return item !== undefined ? item : PagedItem.of(0, 0, '', 0);
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

  itemAt(index: number): PagedItem | undefined {
    return this.items[index];
  }

  reset(newItems: PagedItem[]): void {
    this.items = newItems;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  /** 尾部追加一章的页：不影响既有索引 */
  appendChapter(newItems: PagedItem[]): void {
    if (newItems.length === 0) {
      return;
    }
    const startIndex = this.items.length;
    for (let i = 0; i < newItems.length; i++) {
      this.items.push(newItems[i]);
    }
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < newItems.length; j++) {
        listener.onDataAdd(startIndex + j);
      }
    }
  }

  /** 头部前插一章的页：既有页索引整体后移 newItems.length */
  prependChapter(newItems: PagedItem[]): void {
    if (newItems.length === 0) {
      return;
    }
    const combined: PagedItem[] = [];
    for (let i = 0; i < newItems.length; i++) {
      combined.push(newItems[i]);
    }
    for (let i = 0; i < this.items.length; i++) {
      combined.push(this.items[i]);
    }
    this.items = combined;
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < newItems.length; j++) {
        listener.onDataAdd(j);
      }
    }
  }

  chapterCountOf(chapter: number): number {
    let count = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].chapter === chapter) {
        count++;
      }
    }
    return count;
  }

  /** 移除整个头部的某一章，返回被移除的页数 */
  removeHeadChapter(chapter: number): number {
    const count = this.chapterCountOf(chapter);
    if (count <= 0) {
      return 0;
    }
    this.items.splice(0, count);
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < count; j++) {
        listener.onDataDelete(0);
      }
    }
    return count;
  }

  /** 移除整个尾部的某一章，返回被移除的页数 */
  removeTailChapter(chapter: number): number {
    const count = this.chapterCountOf(chapter);
    if (count <= 0) {
      return 0;
    }
    const startIndex = this.items.length - count;
    this.items.splice(startIndex, count);
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < count; j++) {
        listener.onDataDelete(startIndex);
      }
    }
    return count;
  }

  /** 通知区间内的页内容变了（划线刷新），只重建这些项 */
  refreshRange(from: number, to: number): void {
    const total = this.items.length;
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

  /** 某章在当前窗口内的起始页索引，不存在返回 -1 */
  chapterStartIndex(chapter: number): number {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].chapter === chapter) {
        return i;
      }
    }
    return -1;
  }

  /** 当前窗口内所有页的章号快照（调试与自检用） */
  chapters(): number[] {
    const result: number[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const chapter = this.items[i].chapter;
      if (result.indexOf(chapter) < 0) {
        result.push(chapter);
      }
    }
    return result;
  }
}

/** 页窗口：页序列 + 章级缓存 + 窗口边界 */
export class PageWindow {
  readonly source: PagedSource = new PagedSource();
  /** 窗口内最小 / 最大章号；-1 表示窗口未建立 */
  startChapter: number = -1;
  endChapter: number = -1;
  /** 章级分页缓存上限（LRU） */
  private cacheLimit: number = 6;
  private cache: Map<number, PagedChapter> = new Map();
  private cacheKeys: number[] = [];
  private loading: Set<number> = new Set();
  private chapterLengths: Map<number, number> = new Map();

  /** 以某章为中心重建窗口（只含该章，前后章由调用方按需补） */
  reset(center: number, items: PagedItem[]): void {
    this.startChapter = center;
    this.endChapter = center;
    this.loading.clear();
    this.source.reset(items);
  }

  totalCount(): number {
    return this.source.totalCount();
  }

  itemAt(index: number): PagedItem | undefined {
    return this.source.itemAt(index);
  }

  isBuilt(): boolean {
    return this.startChapter >= 0 && this.source.totalCount() > 0;
  }

  /** 尾部补章：仅当章号紧邻窗口末尾，返回是否真的插入 */
  appendChapter(chapter: number, items: PagedItem[]): boolean {
    if (chapter !== this.endChapter + 1 || items.length === 0) {
      return false;
    }
    this.source.appendChapter(items);
    this.endChapter = chapter;
    return true;
  }

  /** 头部补章：返回前插的页数（调用方据此把当前页索引后移） */
  prependChapter(chapter: number, items: PagedItem[]): number {
    if (chapter !== this.startChapter - 1 || items.length === 0) {
      return 0;
    }
    this.source.prependChapter(items);
    this.startChapter = chapter;
    return items.length;
  }

  /** 回收窗口头部章，返回被移除的页数 */
  trimHead(): number {
    const removed = this.source.removeHeadChapter(this.startChapter);
    if (removed > 0) {
      this.startChapter++;
    }
    return removed;
  }

  /** 回收窗口尾部章，返回被移除的页数 */
  trimTail(): number {
    const removed = this.source.removeTailChapter(this.endChapter);
    if (removed > 0) {
      this.endChapter--;
    }
    return removed;
  }

  chapterCount(): number {
    if (this.startChapter < 0) {
      return 0;
    }
    return this.endChapter - this.startChapter + 1;
  }

  /**
   * 窗口内「某章、某偏移」对应的页索引，找不到返回 -1。
   *
   * 窗口最多 5 章，先线性扫出该章的页区间（代价可忽略），
   * 区间内页首偏移单调递增，用二分找「最后一个 start <= offset」的页。
   * 长章节（上百页）频繁翻页时，这一步是 O(log n) 而不是 O(n)。
   */
  findPageIndex(chapter: number, offset: number): number {
    const total = this.source.totalCount();
    if (total <= 0) {
      return -1;
    }
    let chapterFirst = -1;
    let chapterLast = -1;
    for (let i = 0; i < total; i++) {
      const item = this.source.itemAt(i);
      if (item === undefined) {
        continue;
      }
      if (item.chapter === chapter) {
        if (chapterFirst < 0) {
          chapterFirst = i;
        }
        chapterLast = i;
      } else if (chapterFirst >= 0) {
        break;
      }
    }
    if (chapterFirst < 0) {
      return -1;
    }
    let low = chapterFirst;
    let high = chapterLast;
    let target = chapterFirst;
    while (low <= high) {
      const mid = Math.floor((low + high) / 2);
      const item = this.source.itemAt(mid);
      if (item === undefined) {
        break;
      }
      if (item.start <= offset) {
        target = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return target;
  }

  // ===== 章级分页缓存（LRU） =====

  cacheGet(chapter: number, key: string): PagedItem[] | undefined {
    const cached = this.cache.get(chapter);
    if (cached === undefined || cached.key !== key) {
      return undefined;
    }
    this.touch(chapter);
    return cached.items;
  }

  cachePut(chapter: number, key: string, items: PagedItem[]): void {
    if (this.cache.size >= this.cacheLimit && this.cacheKeys.length > 0) {
      const oldest = this.cacheKeys.shift();
      if (oldest !== undefined) {
        this.cache.delete(oldest);
      }
    }
    this.cache.set(chapter, PagedChapter.of(key, items));
    this.cacheKeys.push(chapter);
  }

  cacheClear(): void {
    this.cache.clear();
    this.cacheKeys = [];
  }

  private touch(chapter: number): void {
    const index = this.cacheKeys.indexOf(chapter);
    if (index >= 0) {
      this.cacheKeys.splice(index, 1);
      this.cacheKeys.push(chapter);
    }
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

  // ===== 章长度（进度百分比用） =====

  setChapterLength(chapter: number, length: number): void {
    this.chapterLengths.set(chapter, length);
  }

  chapterLength(chapter: number): number {
    const length = this.chapterLengths.get(chapter);
    return length !== undefined ? length : 0;
  }
}
