import { ImageEntry } from '../../model/BookModels';

/** 图片书左右分页的一页：一张图 + 所属章与章内序号，key 跨章唯一 */
export class ImagePage {
  key: string = '';
  chapter: number = 0;
  imageIndex: number = 0;
  image: ImageEntry = new ImageEntry();

  static of(chapter: number, imageIndex: number, image: ImageEntry): ImagePage {
    const page = new ImagePage();
    page.key = `${chapter}_${imageIndex}`;
    page.chapter = chapter;
    page.imageIndex = imageIndex;
    page.image = image;
    return page;
  }
}

/**
 * 跨章图片页数据源：整表重置 + 两端按章增量追加/前插/回收。
 * 前插会让既有页索引整体后移，调用方需做索引补偿。
 */
export class ImageDataSource implements IDataSource {
  private items: ImagePage[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ImagePage {
    if (index < 0 || index >= this.items.length) {
      return new ImagePage();
    }
    return this.items[index];
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

  reset(items: ImagePage[]): void {
    this.items = items;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  /** 尾部追加一章的页：不影响既有索引 */
  appendChapter(pages: ImagePage[]): number {
    if (pages.length === 0) {
      return 0;
    }
    const startIndex = this.items.length;
    for (let i = 0; i < pages.length; i++) {
      this.items.push(pages[i]);
    }
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < pages.length; j++) {
        listener.onDataAdd(startIndex + j);
      }
    }
    return pages.length;
  }

  /** 头部前插一章的页：既有页索引整体后移 pages.length */
  prependChapter(pages: ImagePage[]): number {
    if (pages.length === 0) {
      return 0;
    }
    const combined: ImagePage[] = [];
    for (let i = 0; i < pages.length; i++) {
      combined.push(pages[i]);
    }
    for (let i = 0; i < this.items.length; i++) {
      combined.push(this.items[i]);
    }
    this.items = combined;
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      for (let j = 0; j < pages.length; j++) {
        listener.onDataAdd(j);
      }
    }
    return pages.length;
  }

  /** 移除整个头部的某一章，返回被移除的页数 */
  removeHeadChapter(chapter: number): number {
    let count = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].chapter === chapter) {
        count++;
      } else {
        break;
      }
    }
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
    let count = 0;
    for (let i = this.items.length - 1; i >= 0; i--) {
      if (this.items[i].chapter === chapter) {
        count++;
      } else {
        break;
      }
    }
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
}
