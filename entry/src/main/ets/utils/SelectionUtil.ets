import { BookMeta } from '../model/BookModels';

/** 书架/分组页共用的多选计算：只做纯数组运算，状态仍由页面持有 */
export class SelectionUtil {
  static contains(ids: string[], id: string): boolean {
    return ids.indexOf(id) >= 0;
  }

  /** 切换单本选中，返回新数组；返回空数组表示已取消全部选中（调用方据此退出多选态） */
  static toggle(ids: string[], id: string): string[] {
    if (ids.indexOf(id) < 0) {
      const added: string[] = ids.slice();
      added.push(id);
      return added;
    }
    const remain: string[] = [];
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] !== id) {
        remain.push(ids[i]);
      }
    }
    return remain;
  }

  /** 是否全选：列表为空时视为未全选 */
  static allSelected(ids: string[], total: number): boolean {
    return total > 0 && ids.length === total;
  }

  static collectIds(books: BookMeta[]): string[] {
    const ids: string[] = [];
    for (let i = 0; i < books.length; i++) {
      ids.push(books[i].id);
    }
    return ids;
  }
}
