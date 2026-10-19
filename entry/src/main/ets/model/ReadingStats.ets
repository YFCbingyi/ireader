export class DailyReading {
  date: string = '';
  seconds: number = 0;

  static of(date: string, seconds: number): DailyReading {
    const item = new DailyReading();
    item.date = date;
    item.seconds = seconds;
    return item;
  }
}

export class ReadingStats {
  totalSeconds: number = 0;
  days: DailyReading[] = [];
  updatedAt: number = 0;
}
