import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BookMeta, ReaderParams } from '../model/BookModels';
import { DailyReading } from '../model/ReadingStats';
import { ShelfTheme, ShelfThemeColors } from '../model/ShelfTheme';
import { AppBootstrap } from '../service/AppBootstrap';
import { HabitSummary, HeatDay, HeatWeek, ProfileStats, ShelfSummary } from '../service/ProfileStats';
import { LibraryStore } from '../service/LibraryStore';
import { ReadingStatsStore } from '../service/ReadingStatsStore';

// 与 AppScope/app.json5 的 versionName 保持一致
const APP_VERSION = '1.0.0';
// 设置行点击分发：0 数据明细 / 1 关于 / 2 隐私 / 3 清空统计
const KIND_DATA = 0;
const KIND_ABOUT = 1;
const KIND_PRIVACY = 2;
const KIND_CLEAR = 3;

@Component
export struct ProfilePanel {
  @Prop bottomInset: number = 30;
  @Prop topInset: number = 0;
  /** Index.onPageShow 递增，从阅读页返回时强制刷新统计 */
  @Prop @Watch('onRefreshTick') refreshTick: number = 0;

  @State totalText: string = '0 秒';
  @State todayText: string = '0 秒';
  @State readDayCount: number = 0;
  @State bookCount: number = 0;
  @State week: DailyReading[] = [];
  @State todayKey: string = '';
  @State heatWeeks: HeatWeek[] = [];
  @State habit: HabitSummary = new HabitSummary();
  @State shelf: ShelfSummary = new ShelfSummary();
  @State continueTitle: string = '';
  @State continueDetail: string = '';
  @State continueAction: string = '';
  @State continuePercent: number = 0;
  @State shelfDetail: string = '';
  @State storageText: string = '统计中…';
  // @Builder 按值传参不会随状态刷新，数值统一放状态数组，在 builder 内部按索引读取
  @State statValues: string[] = ['0 天', '0 天', '0 本', '0 秒', '0 秒', '0 秒'];
  @State settingValues: string[] = ['统计中…', '', '应用沙箱', `版本 ${APP_VERSION}`,
    '纯本地 · 无账号', '不可恢复'];
  @StorageProp('systemColorMode') @Watch('onSystemColorModeChanged') systemColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State palette: ShelfThemeColors = ShelfTheme.light();

  private settingLabels: string[] = ['本地占用', '数据明细', '存储位置', '关于 ireader', '隐私说明', '清空阅读统计'];
  private settingKinds: number[] = [KIND_DATA, KIND_DATA, KIND_PRIVACY, KIND_ABOUT, KIND_PRIVACY, KIND_CLEAR];
  private settingDanger: boolean[] = [false, false, false, false, false, true];
  private continueBookId: string = '';
  private sizeTimer: number = -1;
  private destroyed: boolean = false;

  aboutToAppear(): void {
    this.destroyed = false;
    AppBootstrap.init(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.applyPalette();
    this.loadStats();
    this.scheduleStorageSize();
  }

  aboutToDisappear(): void {
    this.destroyed = true;
    if (this.sizeTimer !== -1) {
      clearTimeout(this.sizeTimer);
      this.sizeTimer = -1;
    }
  }

  private applyPalette(): void {
    const next = ShelfTheme.resolve(this.systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    if (next.bg !== this.palette.bg) {
      this.palette = next;
    }
  }

  private onSystemColorModeChanged(): void {
    this.applyPalette();
  }

  private onRefreshTick(): void {
    // 占用仅在组件创建时算一次；统计刷新不重复遍历整个沙箱
    this.loadStats();
  }

  private loadStats(): void {
    const stats = ReadingStatsStore.get();
    this.totalText = ReadingStatsStore.formatDuration(stats.totalSeconds);
    this.week = ReadingStatsStore.recentDays(7);
    this.todayText = ReadingStatsStore.formatDuration(
      this.week.length > 0 ? this.week[this.week.length - 1].seconds : 0);
    const books = LibraryStore.getBooks();
    this.bookCount = books.length;
    this.todayKey = ReadingStatsStore.todayKey();
    this.habit = ProfileStats.habit(stats);
    this.readDayCount = this.habit.activeDays;
    this.heatWeeks = ProfileStats.heatWeeks(stats);
    this.shelf = ProfileStats.shelf(books);
    this.shelfDetail = `${this.bookCount} 本 · ${this.shelf.chapterCount} 章`;
    this.statValues = [
      `${this.readDayCount} 天`,
      `${this.habit.streak} 天`,
      `${this.bookCount} 本`,
      ProfileStats.shortDuration(this.habit.weekSeconds),
      ProfileStats.shortDuration(this.habit.averageSeconds),
      ProfileStats.shortDuration(this.habit.bestSeconds)
    ];
    this.refreshSettingValues();
    this.loadContinue(books);
  }

  private refreshSettingValues(): void {
    this.settingValues = [this.storageText, this.shelfDetail, '应用沙箱',
      `版本 ${APP_VERSION}`, '纯本地 · 无账号', '不可恢复'];
  }

  private loadContinue(books: BookMeta[]): void {
    const book = ProfileStats.continueBook(books);
    if (book === undefined) {
      this.continueBookId = '';
      this.continueTitle = '还没有书';
      this.continueDetail = '去书架导入一本，开始第一次阅读';
      this.continueAction = '';
      this.continuePercent = 0;
      return;
    }
    this.continueBookId = book.id;
    this.continueTitle = book.title.length > 0 ? book.title : '无题';
    this.continuePercent = ProfileStats.percentLabel(book);
    this.continueDetail = `第 ${book.progress.chapterIndex + 1} 章 · 已读 ${this.continuePercent}%`;
    this.continueAction = this.continuePercent > 0 ? '继续阅读' : '开始阅读';
  }

  /** 递归统计沙箱占用可能稍慢，放到首帧之后算一次，避免进页面卡顿 */
  private scheduleStorageSize(): void {
    if (this.sizeTimer !== -1) {
      clearTimeout(this.sizeTimer);
    }
    this.storageText = '统计中…';
    this.refreshSettingValues();
    this.sizeTimer = setTimeout(() => {
      this.sizeTimer = -1;
      if (this.destroyed) {
        return;
      }
      this.storageText = ProfileStats.formatSize(ProfileStats.storageBytes());
      this.refreshSettingValues();
    }, 120);
  }

  private async openContinueBook(): Promise<void> {
    if (this.continueBookId.length === 0) {
      this.toast('先去书架导入一本书吧');
      return;
    }
    const params = new ReaderParams();
    params.bookId = this.continueBookId;
    try {
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/Reader', params: params });
    } catch (e) {
      const err = e as BusinessError;
      this.toast(`打开失败：${err.message}`);
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      const err = e as BusinessError;
      console.error(`toast failed: ${err.message}`);
    }
  }

  private onSettingClick(kind: number): void {
    if (kind === KIND_DATA) {
      this.showDataDialog();
      return;
    }
    if (kind === KIND_ABOUT) {
      this.showAboutDialog();
      return;
    }
    if (kind === KIND_PRIVACY) {
      this.showPrivacyDialog();
      return;
    }
    this.confirmClearStats();
  }

  private showDataDialog(): void {
    this.getUIContext().showAlertDialog({
      title: '本机数据',
      message: `书籍 ${this.bookCount} 本 · 章节 ${this.shelf.chapterCount} 章 · 分组 ${this.shelf.groupCount} 个\n` +
        `笔记文件 ${this.shelf.noteFileCount} 份 · 书签文件 ${this.shelf.bookmarkFileCount} 份\n` +
        `在读 ${this.shelf.readingCount} 本 · 已读完 ${this.shelf.finishedCount} 本 · 未开始 ${this.shelf.unreadCount} 本\n` +
        `平均完成度 ${this.shelf.averagePercent}% · 共占用 ${this.storageText}`,
      primaryButton: { value: '知道了', action: () => {} },
      secondaryButton: { value: '取消', action: () => {} }
    });
  }

  private showAboutDialog(): void {
    this.getUIContext().showAlertDialog({
      title: '关于 ireader',
      message: `版本 ${APP_VERSION}\n本地 TXT / 图片书阅读器。无账号、无联网，书籍、进度、书签、划线与阅读统计全部保存在本机。`,
      primaryButton: { value: '知道了', action: () => {} },
      secondaryButton: { value: '取消', action: () => {} }
    });
  }

  private showPrivacyDialog(): void {
    this.getUIContext().showAlertDialog({
      title: '数据与隐私',
      message: '所有内容仅存于应用沙箱 filesDir。卸载应用后数据会一并删除且无法恢复；应用不会上传任何书籍内容或阅读记录。',
      primaryButton: { value: '知道了', action: () => {} },
      secondaryButton: { value: '取消', action: () => {} }
    });
  }

  private confirmClearStats(): void {
    this.getUIContext().showAlertDialog({
      title: '清空阅读统计',
      message: '将删除累计时长、每日记录与阅读天数。书籍、进度、书签和划线不受影响，此操作不可恢复。',
      primaryButton: {
        value: '清空',
        action: () => {
          ReadingStatsStore.clear();
          this.loadStats();
          this.toast('阅读统计已清空');
        }
      },
      secondaryButton: { value: '取消', action: () => {} }
    });
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

  private heatOpacity(level: number): number {
    if (level <= 1) {
      return 0.28;
    }
    if (level === 2) {
      return 0.5;
    }
    if (level === 3) {
      return 0.72;
    }
    return 1;
  }

  @Builder
  statCell(label: string, index: number) {
    Column() {
      Text(this.statValues[index])
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.text)
        .maxLines(1)
      Text(label)
        .fontSize(12)
        .fontColor(this.palette.subtleText)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding({ left: 2, right: 2 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  totalCard() {
    Column() {
      Text('累计阅读时长')
        .fontSize(13)
        .fontColor(this.palette.subtleText)
      Text(this.totalText)
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.accent)
        .margin({ top: 8 })
      Text(`今日 ${this.todayText} · 本周 ${ProfileStats.shortDuration(this.habit.weekSeconds)}`)
        .fontSize(13)
        .fontColor(this.palette.chipText)
        .margin({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .borderRadius(16)
    .backgroundColor(this.palette.surface)
    .border({ width: 1, color: this.palette.chipBg })
  }

  @Builder
  continueCard() {
    Column() {
      Row() {
        Column() {
          Text('继续阅读')
            .fontSize(13)
            .fontColor(this.palette.subtleText)
          Text(this.continueTitle)
            .width('100%')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 6 })
          Text(this.continueDetail)
            .width('100%')
            .fontSize(12)
            .fontColor(this.palette.chipText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.continueAction.length > 0) {
          Text(this.continueAction)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.accentText)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .borderRadius(18)
            .backgroundColor(this.palette.accent)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Column()
          .width(`${this.continuePercent}%`)
          .height('100%')
          .borderRadius(2)
          .backgroundColor(this.palette.accent)
      }
      .width('100%')
      .height(4)
      .borderRadius(2)
      .clip(true)
      .backgroundColor(this.palette.chipBg)
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(20)
    .margin({ top: 12 })
    .borderRadius(16)
    .backgroundColor(this.palette.surface)
    .border({ width: 1, color: this.palette.chipBg })
    .onClick(() => {
      this.openContinueBook();
    })
  }

  @Builder
  statsGrid() {
    Column() {
      Row() {
        this.statCell('阅读天数', 0)
        Divider().vertical(true).height(32).color(this.palette.chipBg)
        this.statCell('连续阅读', 1)
        Divider().vertical(true).height(32).color(this.palette.chipBg)
        this.statCell('书架书籍', 2)
      }
      .width('100%')
      .height(50)
      .alignItems(VerticalAlign.Center)

      Divider()
        .color(this.palette.chipBg)
        .margin({ top: 4, bottom: 4 })

      Row() {
        this.statCell('本周合计', 3)
        Divider().vertical(true).height(32).color(this.palette.chipBg)
        this.statCell('日均阅读', 4)
        Divider().vertical(true).height(32).color(this.palette.chipBg)
        this.statCell('单日最长', 5)
      }
      .width('100%')
      .height(50)
      .alignItems(VerticalAlign.Center)

      Text(`最长连续 ${this.habit.longestStreak} 天 · 在读 ${this.shelf.readingCount} 本 · ` +
        `已读完 ${this.shelf.finishedCount} 本 · 平均完成度 ${this.shelf.averagePercent}%`)
        .width('100%')
        .fontSize(11)
        .fontColor(this.palette.subtleText)
        .margin({ top: 10 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .margin({ top: 12 })
    .borderRadius(16)
    .backgroundColor(this.palette.surface)
    .border({ width: 1, color: this.palette.chipBg })
  }

  @Builder
  weeklyCard() {
    Column() {
      Text('最近 7 天')
        .width('100%')
        .fontSize(13)
        .fontColor(this.palette.subtleText)

      Row() {
        ForEach(this.week, (item: DailyReading) => {
          Column() {
            Text(this.barText(item))
              .fontSize(10)
              .fontColor(this.palette.subtleText)
              .margin({ bottom: 6 })
            Column()
              .width(16)
              .height(this.barHeight(item))
              .borderRadius(5)
              .backgroundColor(item.seconds > 0 ? this.palette.accent : this.palette.border)
            Text(item.date === this.todayKey ? '今天' : ReadingStatsStore.dayLabel(item.date))
              .fontSize(11)
              .fontColor(item.date === this.todayKey ? this.palette.accent : this.palette.subtleText)
              .margin({ top: 6 })
          }
          .layoutWeight(1)
          .height(170)
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Center)
        }, (item: DailyReading) => `${item.date}_${item.seconds}`)
      }
      .width('100%')
      .margin({ top: 12 })
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding(20)
    .margin({ top: 12 })
    .borderRadius(16)
    .backgroundColor(this.palette.surface)
    .border({ width: 1, color: this.palette.chipBg })
  }

  @Builder
  heatLegend(level: number) {
    Column()
      .width(12)
      .height(12)
      .borderRadius(3)
      .backgroundColor(level > 0 ? this.palette.accent : this.palette.chipBg)
      .opacity(level > 0 ? this.heatOpacity(level) : 1)
  }

  @Builder
  heatmapCard() {
    Column() {
      Row() {
        Text('近 13 周阅读')
          .fontSize(13)
          .fontColor(this.palette.subtleText)
        Blank()
        Text(`有记录 ${this.readDayCount} 天`)
          .fontSize(11)
          .fontColor(this.palette.subtleText)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 3 }) {
        ForEach(this.heatWeeks, (week: HeatWeek) => {
          Column({ space: 3 }) {
            ForEach(week.days, (day: HeatDay) => {
              Column()
                .width(15)
                .height(15)
                .borderRadius(3)
                .backgroundColor(day.level > 0 && !day.future ? this.palette.accent : this.palette.chipBg)
                .opacity(day.future ? 0.32 : (day.level > 0 ? this.heatOpacity(day.level) : 1))
            }, (day: HeatDay) => `${day.date}_${day.level}_${day.future}`)
          }
        }, (week: HeatWeek) => `heat_week_${week.days.length > 0 ? week.days[0].date : 'none'}`)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Top)
      .margin({ top: 14 })

      Row({ space: 4 }) {
        Text('少')
          .fontSize(10)
          .fontColor(this.palette.subtleText)
        this.heatLegend(0)
        this.heatLegend(1)
        this.heatLegend(2)
        this.heatLegend(3)
        this.heatLegend(4)
        Text('多')
          .fontSize(10)
          .fontColor(this.palette.subtleText)
      }
      .width('100%')
      .margin({ top: 12 })
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)

      Text('每格一天，周一在每列首行；颜色越深，当天读得越久。')
        .width('100%')
        .fontSize(11)
        .fontColor(this.palette.subtleText)
        .margin({ top: 10 })
    }
    .width('100%')
    .padding(20)
    .margin({ top: 12 })
    .borderRadius(16)
    .backgroundColor(this.palette.surface)
    .border({ width: 1, color: this.palette.chipBg })
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .width('100%')
      .fontSize(12)
      .fontColor(this.palette.subtleText)
      .margin({ top: 20, bottom: 8, left: 4 })
  }

  @Builder
  settingRow(index: number) {
    Row() {
      Text(this.settingLabels[index])
        .fontSize(14)
        .fontColor(this.settingDanger[index] ? this.palette.danger : this.palette.text)
      Blank()
      Text(this.settingValues[index])
        .fontSize(12)
        .fontColor(this.palette.subtleText)
        .maxLines(1)
      Text('›')
        .fontSize(16)
        .fontColor(this.palette.subtleText)
        .margin({ left: 6 })
    }
    .width('100%')
    .height(46)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onSettingClick(this.settingKinds[index]);
    })
  }

  @Builder
  settingDivider() {
    Divider()
      .color(this.palette.chipBg)
      .margin({ left: 14, right: 14 })
  }

  @Builder
  settingsArea() {
    Column() {
      this.sectionTitle('数据与存储')
      Column() {
        this.settingRow(0)
        this.settingDivider()
        this.settingRow(1)
        this.settingDivider()
        this.settingRow(2)
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor(this.palette.surface)
      .border({ width: 1, color: this.palette.chipBg })

      this.sectionTitle('关于')
      Column() {
        this.settingRow(3)
        this.settingDivider()
        this.settingRow(4)
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor(this.palette.surface)
      .border({ width: 1, color: this.palette.chipBg })

      this.sectionTitle('危险操作')
      Column() {
        this.settingRow(5)
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor(this.palette.surface)
      .border({ width: 1, color: this.palette.chipBg })
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column() {
        this.totalCard()
        this.continueCard()
        this.statsGrid()
        this.weeklyCard()
        this.heatmapCard()
        this.settingsArea()

        Text('阅读时长按页面停留累计，应用进入后台或退出阅读页后停止计时；每日记录最多保留 90 天。')
          .width('100%')
          .fontSize(11)
          .fontColor(this.palette.subtleText)
          .lineHeight(18)
          .margin({ top: 18 })
        Text('统计只保存在本机，清空统计不会影响书架里的书与阅读进度。')
          .width('100%')
          .fontSize(11)
          .fontColor(this.palette.subtleText)
          .lineHeight(18)
          .margin({ top: 4 })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.topInset + 4, bottom: this.bottomInset })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
  }
}
