import { hilog } from '@kit.PerformanceAnalysisKit';
import { DailyReading, ReadingStats } from '../model/ReadingStats';
import { AppPaths } from '../utils/AppPaths';
import { FileUtil } from '../utils/FileUtil';

const DOMAIN = 0x0005;
const TAG = 'ReadingStats';
const MAX_DAYS = 90;

export class ReadingStatsStore {
  private static path(): string {
    return `${AppPaths.getFilesDir()}/reading_stats.json`;
  }

  static get(): ReadingStats {
    const raw = FileUtil.readText(ReadingStatsStore.path());
    if (raw.length === 0) {
      return new ReadingStats();
    }
    try {
      const parsed = JSON.parse(raw) as ReadingStats;
      const stats = new ReadingStats();
      stats.totalSeconds = parsed.totalSeconds !== undefined ? Math.max(0, parsed.totalSeconds) : 0;
      stats.updatedAt = parsed.updatedAt !== undefined ? parsed.updatedAt : 0;
      const days = parsed.days !== undefined ? parsed.days : [];
      for (let i = 0; i < days.length; i++) {
        const item = days[i];
        if (item !== undefined && item.date !== undefined && item.date.length > 0) {
          stats.days.push(DailyReading.of(item.date, Math.max(0, item.seconds)));
        }
      }
      stats.days.sort((a: DailyReading, b: DailyReading): number => a.date < b.date ? -1 : (a.date > b.date ? 1 : 0));
      return stats;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'parse reading stats failed');
      return new ReadingStats();
    }
  }

  static addSeconds(seconds: number): void {
    const delta = Math.floor(seconds);
    if (delta <= 0) {
      return;
    }
    const stats = ReadingStatsStore.get();
    const key = ReadingStatsStore.todayKey();
    let found = false;
    for (let i = 0; i < stats.days.length; i++) {
      if (stats.days[i].date === key) {
        stats.days[i].seconds += delta;
        found = true;
        break;
      }
    }
    if (!found) {
      stats.days.push(DailyReading.of(key, delta));
    }
    stats.totalSeconds += delta;
    stats.updatedAt = Date.now();
    if (stats.days.length > MAX_DAYS) {
      stats.days = stats.days.slice(stats.days.length - MAX_DAYS);
    }
    FileUtil.writeTextAtomic(ReadingStatsStore.path(), JSON.stringify(stats));
  }

  static todaySeconds(): number {
    const stats = ReadingStatsStore.get();
    const key = ReadingStatsStore.todayKey();
    for (let i = 0; i < stats.days.length; i++) {
      if (stats.days[i].date === key) {
        return stats.days[i].seconds;
      }
    }
    return 0;
  }

  static recentDays(count: number): DailyReading[] {
    const stats = ReadingStatsStore.get();
    const result: DailyReading[] = [];
    const today = new Date();
    for (let offset = count - 1; offset >= 0; offset--) {
      const day = new Date(today.getFullYear(), today.getMonth(), today.getDate() - offset);
      const key = ReadingStatsStore.keyOf(day);
      let seconds = 0;
      for (let i = 0; i < stats.days.length; i++) {
        if (stats.days[i].date === key) {
          seconds = stats.days[i].seconds;
          break;
        }
      }
      result.push(DailyReading.of(key, seconds));
    }
    return result;
  }

  static readDayCount(): number {
    const stats = ReadingStatsStore.get();
    let days = 0;
    for (let i = 0; i < stats.days.length; i++) {
      if (stats.days[i].seconds > 0) {
        days++;
      }
    }
    return days;
  }

  static formatDuration(seconds: number): string {
    const total = Math.max(0, Math.floor(seconds));
    if (total < 60) {
      return `${total} 秒`;
    }
    const minutes = Math.floor(total / 60);
    if (minutes < 60) {
      return `${minutes} 分钟`;
    }
    const hours = Math.floor(minutes / 60);
    const restMinutes = minutes % 60;
    if (hours < 24) {
      return restMinutes > 0 ? `${hours} 小时 ${restMinutes} 分钟` : `${hours} 小时`;
    }
    const days = Math.floor(hours / 24);
    const restHours = hours % 24;
    return restHours > 0 ? `${days} 天 ${restHours} 小时` : `${days} 天`;
  }

  static dayLabel(dateKey: string): string {
    const parts = dateKey.split('-');
    if (parts.length !== 3) {
      return dateKey;
    }
    const year = Number.parseInt(parts[0], 10);
    const month = Number.parseInt(parts[1], 10);
    const day = Number.parseInt(parts[2], 10);
    const date = new Date(year, month - 1, day);
    const names: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return names[date.getDay()];
  }

  static todayKey(): string {
    return ReadingStatsStore.keyOf(new Date());
  }

  private static keyOf(date: Date): string {
    const month = date.getMonth() + 1;
    const day = date.getDate();
    return `${date.getFullYear()}-${month < 10 ? '0' : ''}${month}-${day < 10 ? '0' : ''}${day}`;
  }
}
