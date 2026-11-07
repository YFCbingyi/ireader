import { BookMeta } from '../model/BookModels';
import { DailyReading, ReadingStats } from '../model/ReadingStats';
import { AppPaths } from '../utils/AppPaths';
import { FileUtil } from '../utils/FileUtil';
import { ReadingStatsStore } from './ReadingStatsStore';

/** 阅读习惯聚合：全部由 reading_stats.json 派生，不新增持久化字段 */
export class HabitSummary {
  streak: number = 0;
  longestStreak: number = 0;
  weekSeconds: number = 0;
  averageSeconds: number = 0;
  bestSeconds: number = 0;
  activeDays: number = 0;
}

/** 热力图里的一天；future 表示本周还没到的日期 */
export class HeatDay {
  date: string = '';
  seconds: number = 0;
  /** 0 未读，1~4 由浅到深 */
  level: number = 0;
  future: boolean = false;
}

/** 一列 = 一周，周一在第一行 */
export class HeatWeek {
  days: HeatDay[] = [];
}

export class ShelfSummary {
  readingCount: number = 0;
  finishedCount: number = 0;
  unreadCount: number = 0;
  averagePercent: number = 0;
  chapterCount: number = 0;
  groupCount: number = 0;
  noteFileCount: number = 0;
  bookmarkFileCount: number = 0;
}

/** 「我的」页取数层：只做计算与读盘，UI 组件不直接碰日期换算 */
export class ProfileStats {
  /** 13 周 = 91 格，覆盖 MAX_DAYS(90) 能留下的全部历史 */
  private static WEEK_COUNT: number = 13;

  static habit(stats: ReadingStats): HabitSummary {
    const result = new HabitSummary();
    let total = 0;
    for (let i = 0; i < stats.days.length; i++) {
      const seconds = stats.days[i].seconds;
      if (seconds <= 0) {
        continue;
      }
      result.activeDays++;
      total += seconds;
      if (seconds > result.bestSeconds) {
        result.bestSeconds = seconds;
      }
    }
    result.averageSeconds = result.activeDays > 0 ? Math.round(total / result.activeDays) : 0;

    const today = new Date();
    const weekday = (today.getDay() + 6) % 7;
    const todayKey = ReadingStatsStore.todayKey();
    for (let i = 0; i <= weekday; i++) {
      const day = new Date(today.getFullYear(), today.getMonth(), today.getDate() - weekday + i);
      result.weekSeconds += ProfileStats.secondsOf(stats.days, ReadingStatsStore.keyOf(day));
    }

    // 今天还没读时从昨天起算，连续记录不会因为「尚未开始今天的阅读」显示为 0
    let offset = ProfileStats.secondsOf(stats.days, todayKey) > 0 ? 0 : 1;
    while (offset < 120) {
      const day = new Date(today.getFullYear(), today.getMonth(), today.getDate() - offset);
      if (ProfileStats.secondsOf(stats.days, ReadingStatsStore.keyOf(day)) <= 0) {
        break;
      }
      result.streak++;
      offset++;
    }

    let running = 0;
    let previous = '';
    for (let i = 0; i < stats.days.length; i++) {
      const item = stats.days[i];
      if (item.seconds <= 0) {
        running = 0;
        previous = '';
        continue;
      }
      running = running > 0 && ProfileStats.isNextDay(previous, item.date) ? running + 1 : 1;
      if (running > result.longestStreak) {
        result.longestStreak = running;
      }
      previous = item.date;
    }
    return result;
  }

  static heatWeeks(stats: ReadingStats): HeatWeek[] {
    const today = new Date();
    const weekday = (today.getDay() + 6) % 7;
    const start = new Date(today.getFullYear(), today.getMonth(),
      today.getDate() - weekday - (ProfileStats.WEEK_COUNT - 1) * 7);
    const todayKey = ReadingStatsStore.todayKey();
    const weeks: HeatWeek[] = [];
    for (let w = 0; w < ProfileStats.WEEK_COUNT; w++) {
      const week = new HeatWeek();
      for (let d = 0; d < 7; d++) {
        const date = new Date(start.getFullYear(), start.getMonth(),
          start.getDate() + w * 7 + d);
        const key = ReadingStatsStore.keyOf(date);
        const seconds = ProfileStats.secondsOf(stats.days, key);
        const day = new HeatDay();
        day.date = key;
        day.seconds = seconds;
        day.level = ProfileStats.levelOf(seconds);
        day.future = key > todayKey;
        week.days.push(day);
      }
      weeks.push(week);
    }
    return weeks;
  }

  static shelf(books: BookMeta[]): ShelfSummary {
    const result = new ShelfSummary();
    const groups: string[] = [];
    let percentSum = 0;
    for (let i = 0; i < books.length; i++) {
      const book = books[i];
      const clamped = Math.max(0, Math.min(1, book.progress.percent));
      percentSum += clamped;
      if (clamped >= 0.999) {
        result.finishedCount++;
      } else if (clamped > 0.001) {
        result.readingCount++;
      } else {
        result.unreadCount++;
      }
      result.chapterCount += book.chapterCount;
      if (book.group.length > 0 && groups.indexOf(book.group) < 0) {
        groups.push(book.group);
      }
    }
    result.averagePercent = books.length > 0 ? Math.round(percentSum / books.length * 100) : 0;
    result.groupCount = groups.length;
    result.noteFileCount = FileUtil.listFiles(`${AppPaths.getFilesDir()}/annotations`).length;
    result.bookmarkFileCount = FileUtil.listFiles(`${AppPaths.getFilesDir()}/bookmarks`).length;
    return result;
  }

  /** 最近在读：优先找有进度且未读完的一本，其次退回最近更新的书 */
  static continueBook(books: BookMeta[]): BookMeta | undefined {
    for (let i = 0; i < books.length; i++) {
      const percent = books[i].progress.percent;
      if (percent > 0.001 && percent < 0.999) {
        return books[i];
      }
    }
    return books.length > 0 ? books[0] : undefined;
  }

  static storageBytes(): number {
    return FileUtil.pathSize(AppPaths.getFilesDir());
  }

  static formatSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${ProfileStats.oneDecimal(bytes / 1024)} KB`;
    }
    return `${ProfileStats.oneDecimal(bytes / 1024 / 1024)} MB`;
  }

  /** 统计格里用的短时长，避免「12 小时 30 分钟」在三列布局里溢出 */
  static shortDuration(seconds: number): string {
    const total = Math.max(0, Math.floor(seconds));
    if (total < 60) {
      return `${total} 秒`;
    }
    const minutes = Math.floor(total / 60);
    if (minutes < 60) {
      return `${minutes} 分`;
    }
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return rest > 0 ? `${hours} 时 ${rest} 分` : `${hours} 小时`;
  }

  static percentLabel(book: BookMeta): number {
    return Math.round(Math.max(0, Math.min(1, book.progress.percent)) * 100);
  }

  private static oneDecimal(value: number): number {
    return Math.round(value * 10) / 10;
  }

  private static secondsOf(days: DailyReading[], key: string): number {
    for (let i = 0; i < days.length; i++) {
      if (days[i].date === key) {
        return days[i].seconds;
      }
    }
    return 0;
  }

  private static isNextDay(previous: string, current: string): boolean {
    if (previous.length === 0) {
      return false;
    }
    const parts = previous.split('-');
    if (parts.length !== 3) {
      return false;
    }
    const date = new Date(Number.parseInt(parts[0], 10), Number.parseInt(parts[1], 10) - 1,
      Number.parseInt(parts[2], 10) + 1);
    return ReadingStatsStore.keyOf(date) === current;
  }

  private static levelOf(seconds: number): number {
    if (seconds <= 0) {
      return 0;
    }
    if (seconds < 300) {
      return 1;
    }
    if (seconds < 900) {
      return 2;
    }
    if (seconds < 2400) {
      return 3;
    }
    return 4;
  }
}
