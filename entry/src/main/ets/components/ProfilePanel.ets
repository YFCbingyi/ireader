import { common } from '@kit.AbilityKit';
import { DailyReading } from '../model/ReadingStats';
import { AppPaths } from '../utils/AppPaths';
import { LibraryStore } from '../service/LibraryStore';
import { ReadingStatsStore } from '../service/ReadingStatsStore';

@Component
export struct ProfilePanel {
  bottomInset: number = 30;
  topInset: number = 0;

  @State totalText: string = '0 秒';
  @State todayText: string = '0 秒';
  @State readDayCount: number = 0;
  @State bookCount: number = 0;
  @State week: DailyReading[] = [];
  @State todayKey: string = '';

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPaths.init(context.filesDir);
    LibraryStore.init();
    this.loadStats();
  }

  private loadStats(): void {
    const stats = ReadingStatsStore.get();
    this.totalText = ReadingStatsStore.formatDuration(stats.totalSeconds);
    this.todayText = ReadingStatsStore.formatDuration(ReadingStatsStore.todaySeconds());
    this.readDayCount = ReadingStatsStore.readDayCount();
    this.bookCount = LibraryStore.getBooks().length;
    this.todayKey = ReadingStatsStore.todayKey();
    this.week = ReadingStatsStore.recentDays(7);
  }

  private weekMax(): number {
    let max = 1;
    for (let i = 0; i < this.week.length; i++) {
      if (this.week[i].seconds > max) {
        max = this.week[i].seconds;
      }
    }
    return max;
  }

  private barHeight(item: DailyReading): number {
    if (item.seconds <= 0) {
      return 4;
    }
    const height = Math.round(item.seconds / this.weekMax() * 110);
    return height < 6 ? 6 : height;
  }

  private barText(item: DailyReading): string {
    if (item.seconds < 60) {
      return '';
    }
    const minutes = Math.round(item.seconds / 60);
    return minutes >= 60 ? `${Math.floor(minutes / 60)}h` : `${minutes}`;
  }

  @Builder
  statCell(label: string, value: string) {
    Column() {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#2B2B2B')
      Text(label)
        .fontSize(12)
        .fontColor('#9C8C72')
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          Text('累计阅读时长')
            .fontSize(13)
            .fontColor('#9C8C72')
          Text(this.totalText)
            .fontSize(34)
            .fontWeight(FontWeight.Bold)
            .fontColor('#8B5E3C')
            .margin({ top: 8 })
          Text(`今日 ${this.todayText}`)
            .fontSize(13)
            .fontColor('#5C4A32')
            .margin({ top: 6 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(20)
        .borderRadius(16)
        .backgroundColor('#FFFDF7')
        .border({ width: 1, color: '#EFE7D8' })

        Row() {
          this.statCell('阅读天数', `${this.readDayCount} 天`)
          Divider()
            .vertical(true)
            .height(32)
            .color('#EFE7D8')
          this.statCell('书架书籍', `${this.bookCount} 本`)
        }
        .width('100%')
        .padding({ top: 16, bottom: 16 })
        .margin({ top: 12 })
        .borderRadius(16)
        .backgroundColor('#FFFDF7')
        .border({ width: 1, color: '#EFE7D8' })

        Column() {
          Text('最近 7 天')
            .width('100%')
            .fontSize(13)
            .fontColor('#9C8C72')

          Row() {
            ForEach(this.week, (item: DailyReading) => {
              Column() {
                Text(this.barText(item))
                  .fontSize(10)
                  .fontColor('#A8A8A8')
                  .margin({ bottom: 6 })
                Column()
                  .width(16)
                  .height(this.barHeight(item))
                  .borderRadius(5)
                  .backgroundColor(item.seconds > 0 ? '#8B5E3C' : '#E7E2D6')
                Text(item.date === this.todayKey ? '今天' : ReadingStatsStore.dayLabel(item.date))
                  .fontSize(11)
                  .fontColor(item.date === this.todayKey ? '#8B5E3C' : '#A8A8A8')
                  .margin({ top: 6 })
              }
              .layoutWeight(1)
              .height(170)
              .justifyContent(FlexAlign.End)
              .alignItems(HorizontalAlign.Center)
            }, (item: DailyReading) => item.date)
          }
          .width('100%')
          .margin({ top: 12 })
          .alignItems(VerticalAlign.Bottom)
        }
        .width('100%')
        .padding(20)
        .margin({ top: 12 })
        .borderRadius(16)
        .backgroundColor('#FFFDF7')
        .border({ width: 1, color: '#EFE7D8' })

        Text('阅读时长按页面停留累计，应用进入后台或退出阅读页后停止计时。')
          .width('100%')
          .fontSize(11)
          .fontColor('#A8A8A8')
          .lineHeight(18)
          .margin({ top: 16 })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.topInset + 4, bottom: this.bottomInset })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
  }
}
