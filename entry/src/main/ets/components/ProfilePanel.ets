import { AppEnv, AppEnvStore } from '../model/AppEnv';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { BookMeta, ReaderParams } from '../model/BookModels';
import { CoverStyleMeta, ImageCoverStyle, TextCoverStyle } from '../model/CoverStyle';
import { DailyReading } from '../model/ReadingStats';
import { AppSkin, AppSkinMeta, ShelfTheme, ShelfThemeColors } from '../model/ShelfTheme';
import { AppBootstrap } from '../service/AppBootstrap';
import { AppAppearanceStore } from '../service/AppAppearanceStore';
import { BackupService } from '../service/BackupService';
import { HabitSummary, HeatDay, HeatWeek, NoteEntry, NoteSummary, ProfileStats, ShelfSummary } from '../service/ProfileStats';
import { LibraryStore } from '../service/LibraryStore';
import { ReadingStatsStore } from '../service/ReadingStatsStore';
import { FileUtil } from '../utils/FileUtil';

// 与 AppScope/app.json5 的 versionName 保持一致
const APP_VERSION = '1.0.0';
// 设置行点击分发：0 数据明细 / 1 关于 / 2 隐私 / 3 清空统计 / 4 导出备份 / 5 外观
const KIND_DATA = 0;
const KIND_ABOUT = 1;
const KIND_PRIVACY = 2;
const KIND_CLEAR = 3;
const KIND_EXPORT = 4;
const KIND_SKIN = 5;

@ComponentV2
export struct ProfilePanel {
  @Param bottomInset: number = 30;
  @Param topInset: number = 0;
  /** Index.onPageShow 递增，从阅读页返回时强制刷新统计 */
  @Param refreshTick: number = 0;
  @Monitor('refreshTick') onRefreshTickWatch(): void {
    this.onRefreshTick();
  }

  @Local totalText: string = '0 秒';
  @Local todayText: string = '0 秒';
  @Local readDayCount: number = 0;
  @Local bookCount: number = 0;
  @Local week: DailyReading[] = [];
  @Local todayKey: string = '';
  @Local heatWeeks: HeatWeek[] = [];
  @Local habit: HabitSummary = new HabitSummary();
  @Local shelf: ShelfSummary = new ShelfSummary();
  @Local continueTitle: string = '';
  @Local continueDetail: string = '';
  @Local continueAction: string = '';
  @Local continuePercent: number = 0;
  @Local shelfDetail: string = '';
  @Local storageText: string = '统计中…';
  // @Builder 按值传参不会随状态刷新，数值统一放状态数组，在 builder 内部按索引读取
  @Local statValues: string[] = ['0 天', '0 天', '0 本', '0 秒', '0 秒', '0 秒', '0 条', '0 条', '0 条'];
  @Local settingValues: string[] = ['统计中…', '', '应用沙箱', 'JSON 快照',
    `版本 ${APP_VERSION}`, '纯本地 · 无账号', '不可恢复', '金棕'];
  @Local noteSummary: NoteSummary = new NoteSummary();
  @Local recentNotes: NoteEntry[] = [];
  @Local skinPickerVisible: boolean = false;
  // App 级环境（系统深浅色 / 皮肤）：@ComponentV2 不支持 @StorageProp，改用 @ObservedV2 单例
  @Local env: AppEnv = AppEnvStore.get();
  @Monitor('env.colorMode') onColorModeMonitor(): void {
    this.onSystemColorModeChanged();
  }

  @Monitor('env.appSkin') onSkinMonitor(): void {
    this.onAppSkinChanged();
  }
  @Local palette: ShelfThemeColors = ShelfTheme.light();

  private settingLabels: string[] = ['本地占用', '数据明细', '存储位置', '导出备份',
    '关于 ireader', '隐私说明', '清空阅读统计', 'App 主题'];
  private settingKinds: number[] = [KIND_DATA, KIND_DATA, KIND_PRIVACY, KIND_EXPORT,
    KIND_ABOUT, KIND_PRIVACY, KIND_CLEAR, KIND_SKIN];
  private settingDanger: boolean[] = [false, false, false, false, false, false, true, false];
  private continueBookId: string = '';
  private booksSnapshot: BookMeta[] = [];
  private slowTimer: number = -1;
  private destroyed: boolean = false;

  aboutToAppear(): void {
    this.destroyed = false;
    AppBootstrap.init(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.applyPalette();
    this.loadStats();
    this.scheduleSlowData();
  }

  aboutToDisappear(): void {
    this.destroyed = true;
    if (this.slowTimer !== -1) {
      clearTimeout(this.slowTimer);
      this.slowTimer = -1;
    }
  }

  private applyPalette(): void {
    const next = ShelfTheme.resolve(this.env.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK,
      this.env.appSkin);
    if (next.key !== this.palette.key) {
      this.palette = next;
    }
  }

  private onSystemColorModeChanged(): void {
    this.applyPalette();
  }

  private onAppSkinChanged(): void {
    this.applyPalette();
    this.refreshSettingValues();
  }

  private onRefreshTick(): void {
    // 占用只在组件创建时算一次；笔记每次从阅读页返回都要重取
    this.loadStats();
    this.scheduleSlowData();
  }

  private loadStats(): void {
    const stats = ReadingStatsStore.get();
    this.totalText = ReadingStatsStore.formatDuration(stats.totalSeconds);
    this.week = ReadingStatsStore.recentDays(7);
    this.todayText = ReadingStatsStore.formatDuration(
      this.week.length > 0 ? this.week[this.week.length - 1].seconds : 0);
    const books = LibraryStore.getBooks();
    this.booksSnapshot = books;
    this.bookCount = books.length;
    this.todayKey = ReadingStatsStore.todayKey();
    this.habit = ProfileStats.habit(stats);
    this.readDayCount = this.habit.activeDays;
    this.heatWeeks = ProfileStats.heatWeeks(stats);
    this.shelf = ProfileStats.shelf(books);
    this.shelfDetail = `${this.bookCount} 本 · ${this.shelf.chapterCount} 章`;
    this.refreshStatValues();
    this.refreshSettingValues();
    this.loadContinue(books);
  }

  private refreshStatValues(): void {
    this.statValues = [
      `${this.readDayCount} 天`,
      `${this.habit.streak} 天`,
      `${this.bookCount} 本`,
      ProfileStats.shortDuration(this.habit.weekSeconds),
      ProfileStats.shortDuration(this.habit.averageSeconds),
      ProfileStats.shortDuration(this.habit.bestSeconds),
      `${this.noteSummary.highlightCount} 条`,
      `${this.noteSummary.noteCount} 条`,
      `${this.noteSummary.bookmarkCount} 条`
    ];
  }

  private refreshSettingValues(): void {
    this.settingValues = [this.storageText, this.shelfDetail, '应用沙箱', 'JSON 快照',
      `版本 ${APP_VERSION}`, '纯本地 · 无账号', '不可恢复', AppSkinMeta.label(this.env.appSkin)];
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

  /** 逐书读笔记 + 递归统计沙箱都较慢，放到首帧之后统一算，避免进页面卡顿 */
  private scheduleSlowData(): void {
    if (this.slowTimer !== -1) {
      clearTimeout(this.slowTimer);
    }
    this.slowTimer = setTimeout(() => {
      this.slowTimer = -1;
      if (this.destroyed) {
        return;
      }
      if (this.storageText === '统计中…') {
        this.storageText = ProfileStats.formatSize(ProfileStats.storageBytes());
        this.refreshSettingValues();
      }
      this.noteSummary = ProfileStats.notes(this.booksSnapshot);
      this.recentNotes = this.noteSummary.recent;
      this.refreshStatValues();
    }, 150);
  }

  /** 点最近笔记：带上章号与章内偏移，阅读页会直接落到划线位置 */
  private async openNote(entry: NoteEntry): Promise<void> {
    const params = new ReaderParams();
    params.bookId = entry.bookId;
    params.jumpChapter = entry.chapterIndex;
    params.jumpOffset = entry.charOffset;
    try {
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/Reader', params: params });
    } catch (e) {
      const err = e as BusinessError;
      this.toast(`打开失败：${err.message}`);
    }
  }

  /** 导出阅读数据：由用户选保存位置，写入一个 JSON（不含书籍正文与图片） */
  private async exportBackup(): Promise<void> {
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [`ireader-backup-${ReadingStatsStore.todayKey()}.json`];
      options.fileSuffixChoices = ['JSON 文件|.json'];
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const docPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await docPicker.save(options);
      if (uris.length === 0) {
        return;
      }
      FileUtil.writeUriText(uris[0], BackupService.buildJson());
      this.toast('阅读数据已导出（不含书籍正文）');
    } catch (e) {
      const err = e as BusinessError;
      if (err.message !== undefined && err.message.length > 0) {
        this.toast(`导出失败：${err.message}`);
      }
    }
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
    if (kind === KIND_EXPORT) {
      this.exportBackup();
      return;
    }
    if (kind === KIND_SKIN) {
      this.skinPickerVisible = true;
      return;
    }
    this.confirmClearStats();
  }

  /** 选皮肤：落盘 + 广播 AppStorage，书架/发现/我的页立即换色，阅读页不受影响 */
  private chooseSkin(skin: string): void {
    AppAppearanceStore.saveSkin(skin);
    this.skinPickerVisible = false;
    this.toast(`已切换为${AppSkinMeta.label(skin)}`);
  }

  /** 文本书封面：只改文本书这一项，弹层不关闭，方便连续对比 */
  private chooseTextCover(style: string): void {
    if (this.env.textCover === style) {
      return;
    }
    AppAppearanceStore.saveCovers(style, this.env.imageCover);
    this.toast(`书籍封面：${CoverStyleMeta.textLabel(style)}`);
  }

  /** 图片书封面：只改图片书这一项 */
  private chooseImageCover(style: string): void {
    if (this.env.imageCover === style) {
      return;
    }
    AppAppearanceStore.saveCovers(this.env.textCover, style);
    this.toast(`图书封面：${CoverStyleMeta.imageLabel(style)}`);
  }

  private showDataDialog(): void {
    this.getUIContext().showAlertDialog({
      title: '本机数据',
      message: `书籍 ${this.bookCount} 本 · 章节 ${this.shelf.chapterCount} 章 · 分组 ${this.shelf.groupCount} 个\n` +
        `笔记文件 ${this.shelf.noteFileCount} 份 · 书签文件 ${this.shelf.bookmarkFileCount} 份\n` +
        `划线 ${this.noteSummary.highlightCount} 条 · 想法 ${this.noteSummary.noteCount} 条 · 书签 ${this.noteSummary.bookmarkCount} 条\n` +
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
  noteCard() {
    Column() {
      Row() {
        Text('我的笔记')
          .fontSize(13)
          .fontColor(this.palette.subtleText)
        Blank()
        Text(`${this.noteSummary.highlightCount + this.noteSummary.noteCount} 条记录`)
          .fontSize(11)
          .fontColor(this.palette.subtleText)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        this.statCell('划线', 6)
        Divider().vertical(true).height(32).color(this.palette.chipBg)
        this.statCell('想法', 7)
        Divider().vertical(true).height(32).color(this.palette.chipBg)
        this.statCell('书签', 8)
      }
      .width('100%')
      .height(50)
      .alignItems(VerticalAlign.Center)
      .margin({ top: 8 })

      if (this.recentNotes.length === 0) {
        Text('划选正文即可添加划线或想法，记录会出现在这里。')
          .width('100%')
          .fontSize(12)
          .fontColor(this.palette.subtleText)
          .margin({ top: 12 })
      } else {
        Column() {
          ForEach(this.recentNotes, (item: NoteEntry, index: number) => {
            Column() {
              if (index > 0) {
                Divider().color(this.palette.chipBg)
              }
              Row() {
                Text(item.kind === 1 ? '想法' : '划线')
                  .fontSize(10)
                  .fontColor(this.palette.accentText)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(6)
                  .backgroundColor(this.palette.accent)
                Text(item.quote.length > 0 ? item.quote : '（无原文）')
                  .fontSize(13)
                  .fontColor(this.palette.text)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                  .margin({ left: 8 })
                Text('›')
                  .fontSize(15)
                  .fontColor(this.palette.subtleText)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              Text(`${item.bookTitle} · 第 ${item.chapterIndex + 1} 章`)
                .width('100%')
                .fontSize(11)
                .fontColor(this.palette.subtleText)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 6 })

              if (item.note.length > 0) {
                Text(`想法：${item.note}`)
                  .width('100%')
                  .fontSize(11)
                  .fontColor(this.palette.chipText)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 4 })
              }
            }
            .width('100%')
            .padding({ top: 12, bottom: 12 })
            .onClick(() => {
              this.openNote(item);
            })
          }, (item: NoteEntry) => `${item.id}_${item.quote}_${item.note}`)
        }
        .width('100%')
        .margin({ top: 6 })
      }
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
      this.sectionTitle('外观')
      Column() {
        this.settingRow(7)
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor(this.palette.surface)
      .border({ width: 1, color: this.palette.chipBg })

      this.sectionTitle('数据与存储')
      Column() {
        this.settingRow(0)
        this.settingDivider()
        this.settingRow(1)
        this.settingDivider()
        this.settingRow(2)
        this.settingDivider()
        this.settingRow(3)
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor(this.palette.surface)
      .border({ width: 1, color: this.palette.chipBg })

      this.sectionTitle('关于')
      Column() {
        this.settingRow(4)
        this.settingDivider()
        this.settingRow(5)
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor(this.palette.surface)
      .border({ width: 1, color: this.palette.chipBg })

      this.sectionTitle('危险操作')
      Column() {
        this.settingRow(6)
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor(this.palette.surface)
      .border({ width: 1, color: this.palette.chipBg })
    }
    .width('100%')
  }

  /** 外观弹层里的迷你封面示意：只表达版式，不画真实书名 */
  @Builder
  coverSwatch(style: string, image: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      if (image) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 145,
            colors: [[this.palette.coverImageStart, 0.0], [this.palette.coverImageEnd, 1.0]]
          })
        if (style === ImageCoverStyle.FILM) {
          Text('图')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#4DFFFFFF')
          Column() {
            Column()
              .width('100%')
              .height(4)
              .backgroundColor('#59000000')
            Blank()
            Column()
              .width('100%')
              .height(4)
              .backgroundColor('#59000000')
          }
          .width('100%')
          .height('100%')
        } else {
          Stack({ alignContent: Alignment.Bottom }) {
            Column()
              .width('100%')
              .height(22)
              .linearGradient({ angle: 180, colors: [['#00000000', 0.0], ['#B3000000', 1.0]] })
            Row() {
              Column()
                .width(18)
                .height(2)
                .backgroundColor('#FFFFFF')
                .margin({ left: 5, bottom: 5 })
              Blank()
            }
            .width('100%')
            .height(22)
            .alignItems(VerticalAlign.Bottom)
          }
          .width('100%')
          .height('100%')
        }
      } else if (style === TextCoverStyle.SPINE) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 175,
            colors: this.env.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
              ? [[this.palette.surfaceSink, 0.0], [this.palette.surface, 1.0]]
              : [[this.palette.coverInk, 0.0], [this.palette.coverInk, 0.5], [this.palette.chipBg, 1.0]]
          })
        Row() {
          Column()
            .width(8)
            .height('100%')
            .linearGradient({
              angle: 90,
              colors: [[this.palette.coverTextStart, 0.0], [this.palette.coverTextEnd, 1.0]]
            })
          Blank()
        }
        .width('100%')
        .height('100%')
        Column() {
          Blank()
          Column()
            .width(14)
            .height(1.5)
            .backgroundColor(this.palette.coverTextStart)
          Column()
            .width(20)
            .height(1.5)
            .backgroundColor(this.palette.coverTextStart)
            .margin({ top: 3 })
          Column()
            .width(11)
            .height(1.5)
            .backgroundColor(this.palette.coverTextStart)
            .margin({ top: 3, bottom: 10 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 14, right: 6 })
        .alignItems(HorizontalAlign.Start)
      } else if (style === TextCoverStyle.TYPE) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 150,
            colors: [[this.palette.coverTextStart, 0.0], [this.palette.coverTextEnd, 1.0]]
          })
        Column() {
          Blank()
          Column()
            .width(26)
            .height(3)
            .backgroundColor(this.palette.coverInk)
          Column()
            .width(18)
            .height(3)
            .backgroundColor(this.palette.coverInk)
            .margin({ top: 4 })
          Column()
            .width(12)
            .height(1.5)
            .backgroundColor(this.palette.coverInkLine)
            .margin({ top: 7, bottom: 9 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 6, right: 6 })
        .alignItems(HorizontalAlign.Start)
      } else if (style === TextCoverStyle.INK) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [[this.palette.surfaceAlt, 0.0], [this.palette.surface, 1.0]]
          })
        Column()
          .width(1.5)
          .height(26)
          .backgroundColor(this.palette.text)
          .margin({ top: -6 })
        Row() {
          Column()
            .width(7)
            .height(7)
            .borderRadius(1)
            .backgroundColor('#B23A2E')
            .margin({ left: 6, bottom: 7 })
          Blank()
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Bottom)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 135,
            colors: [[this.palette.coverTextStart, 0.0], [this.palette.coverTextEnd, 1.0]]
          })
        Column()
          .width('calc(100% - 8vp)')
          .height('calc(100% - 8vp)')
          .border({ width: 1, color: this.palette.coverInkSoft })
          .borderRadius(3)
        Column()
          .width(16)
          .height(1)
          .backgroundColor(this.palette.coverInkLine)
      }
    }
    .width(46)
    .height(64)
    .borderRadius(5)
    .clip(true)
    .border({
      width: 2,
      color: (image ? this.env.imageCover === style : this.env.textCover === style)
        ? this.palette.accent : this.palette.border
    })
  }

  /** App 皮肤选择弹层：与阅读页「背景」面板互不影响 */
  @Builder
  skinPicker() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette.scrim)
        .onClick(() => {
          this.skinPickerVisible = false;
        })

      Column() {
        Text('App 主题')
          .width('100%')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
        Text('只影响书架 / 发现 / 我的页；阅读页主题在书内「背景」里单独设置')
          .width('100%')
          .fontSize(12)
          .fontColor(this.palette.subtleText)
          .margin({ top: 8 })

        Row() {
          ForEach(AppSkinMeta.options(), (skin: string) => {
            Column() {
              Stack({ alignContent: Alignment.Center }) {
                Circle()
                  .width(44)
                  .height(44)
                  .fill(AppSkinMeta.swatch(skin))
                  .stroke(this.env.appSkin === skin ? this.palette.accentText : this.palette.border)
                  .strokeWidth(this.env.appSkin === skin ? 3 : 1)
                if (this.env.appSkin === skin) {
                  Text('✓')
                    .fontSize(18)
                    .fontColor(this.palette.accentText)
                }
              }
              .width(44)
              .height(44)

              Text(AppSkinMeta.label(skin))
                .fontSize(12)
                .fontColor(this.env.appSkin === skin ? this.palette.accent : this.palette.subText)
                .margin({ top: 8 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.chooseSkin(skin);
            })
          }, (skin: string) => skin)
        }
        .width('100%')
        .margin({ top: 22 })

        Divider()
          .color(this.palette.chipBg)
          .margin({ top: 20, bottom: 16 })

        Text('书籍封面')
          .width('100%')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.text)
        Text('文本书的封面版式，改完书架立刻生效')
          .width('100%')
          .fontSize(11)
          .fontColor(this.palette.subtleText)
          .margin({ top: 4 })

        Row({ space: 6 }) {
          ForEach(CoverStyleMeta.textOptions(), (style: string) => {
            Column() {
              this.coverSwatch(style, false)
              Text(CoverStyleMeta.textLabel(style))
                .fontSize(10)
                .fontColor(this.env.textCover === style ? this.palette.accent : this.palette.subText)
                .margin({ top: 6 })
                .maxLines(1)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.chooseTextCover(style);
            })
          }, (style: string) => `text_cover_${style}`)
        }
        .width('100%')
        .margin({ top: 12 })

        Text('图书封面')
          .width('100%')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.text)
          .margin({ top: 18 })
        Text('图片书的封面版式')
          .width('100%')
          .fontSize(11)
          .fontColor(this.palette.subtleText)
          .margin({ top: 4 })

        Row({ space: 6 }) {
          ForEach(CoverStyleMeta.imageOptions(), (style: string) => {
            Column() {
              this.coverSwatch(style, true)
              Text(CoverStyleMeta.imageLabel(style))
                .fontSize(10)
                .fontColor(this.env.imageCover === style ? this.palette.accent : this.palette.subText)
                .margin({ top: 6 })
                .maxLines(1)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.chooseImageCover(style);
            })
          }, (style: string) => `image_cover_${style}`)
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 400 })
      .padding({ left: 22, right: 22, top: 22, bottom: 24 })
      .borderRadius(24)
      .backgroundColor(this.palette.surfaceAlt)
      .border({ width: 1, color: this.palette.border })
      .shadow({ radius: 26, color: this.palette.shadow, offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          this.totalCard()
          this.continueCard()
          this.statsGrid()
          this.weeklyCard()
          this.heatmapCard()
          this.noteCard()
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
          Text('导出的备份只包含进度、书签、划线、统计与设置，不含书籍正文和图片。')
            .width('100%')
            .fontSize(11)
            .fontColor(this.palette.subtleText)
            .lineHeight(18)
            .margin({ top: 4 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: this.topInset + 4, bottom: this.bottomInset })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)

      if (this.skinPickerVisible) {
        this.skinPicker()
      }
    }
    .width('100%')
    .layoutWeight(1)
  }
}
