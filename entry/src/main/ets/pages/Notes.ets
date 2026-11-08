import { AppEnv, AppEnvStore } from '../model/AppEnv';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ReaderParams } from '../model/BookModels';
import { ShelfTheme, ShelfThemeColors } from '../theme/ShelfTheme';
import { WindowUtil } from '../utils/WindowUtil';
import { AppBootstrap } from '../service/AppBootstrap';
import { LibraryStore } from '../service/LibraryStore';
import { NoteEntry, NoteSummary, ProfileStats } from '../service/ProfileStats';

// 记录类型：与 ProfileStats.NoteEntry.kind 一一对应
const KIND_HIGHLIGHT = 0;
const KIND_NOTE = 1;
const KIND_BOOKMARK = 2;

/**
 * 「我的笔记」详情页：由「我的 - 我的笔记」卡片点进来。
 * 划线 / 想法 / 书签分三组展示，每组独立计数；点任意一条回到原文对应章内位置。
 */
@Entry
@ComponentV2
struct Notes {
  @Local topInset: number = 0;
  @Local bottomInset: number = 0;
  @Local summary: NoteSummary = new NoteSummary();
  @Local highlights: NoteEntry[] = [];
  @Local notes: NoteEntry[] = [];
  @Local bookmarks: NoteEntry[] = [];
  @Local loading: boolean = true;
  // 深色模式 / 皮肤与书架同源
  // App 级环境（系统深浅色 / 皮肤）：@ComponentV2 不支持 @StorageProp，改用 @ObservedV2 单例
  @Local env: AppEnv = AppEnvStore.get();
  @Monitor('env.colorMode') onColorModeMonitor(): void {
    this.applyPalette();
  }

  @Monitor('env.appSkin') onSkinMonitor(): void {
    this.applyPalette();
  }

  @Local palette: ShelfThemeColors = ShelfTheme.light();

  private destroyed: boolean = false;

  aboutToAppear(): void {
    AppBootstrap.init(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.applyPalette();
    this.ensureFullScreenWindow();
    this.refreshInsets();
  }

  aboutToDisappear(): void {
    this.destroyed = true;
  }

  onPageShow(): void {
    // 逐书读注解 + 书签文件，放到首帧之后算，避免进页面卡一下；从阅读页返回也会重取
    setTimeout(() => {
      if (!this.destroyed) {
        this.load();
      }
    }, 60);
  }

  private applyPalette(): void {
    const next = ShelfTheme.resolve(this.env.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK,
      this.env.appSkin);
    if (next.key !== this.palette.key) {
      this.palette = next;
    }
  }

  private async ensureFullScreenWindow(): Promise<void> {
    await WindowUtil.enableFullScreen(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  private async refreshInsets(): Promise<void> {
    const insets = await WindowUtil.systemInsets(this.getUIContext());
    this.topInset = insets.top;
    this.bottomInset = insets.bottom;
  }

  private load(): void {
    const summary = ProfileStats.notes(LibraryStore.getBooks());
    this.summary = summary;
    const h: NoteEntry[] = [];
    const n: NoteEntry[] = [];
    const b: NoteEntry[] = [];
    for (let i = 0; i < summary.all.length; i++) {
      const item = summary.all[i];
      if (item.kind === KIND_BOOKMARK) {
        b.push(item);
      } else if (item.kind === KIND_NOTE) {
        n.push(item);
      } else {
        h.push(item);
      }
    }
    this.highlights = h;
    this.notes = n;
    this.bookmarks = b;
    this.loading = false;
  }

  private totalCount(): number {
    return this.highlights.length + this.notes.length + this.bookmarks.length;
  }

  /** 主文案：书签没有正文预览时退回章节名，不显示「（无原文）」 */
  private entryQuote(entry: NoteEntry): string {
    if (entry.quote.length > 0) {
      return entry.quote;
    }
    if (entry.chapterTitle.length > 0) {
      return entry.chapterTitle;
    }
    return entry.kind === KIND_BOOKMARK ? `第 ${entry.chapterIndex + 1} 章` : '（无原文）';
  }

  /** 副标题的章节部分：书签额外带章名 */
  private entryChapterText(entry: NoteEntry): string {
    const base = `第 ${entry.chapterIndex + 1} 章`;
    return entry.chapterTitle.length > 0 ? `${base} · ${entry.chapterTitle}` : base;
  }

  private back(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (e) {
      const err = e as BusinessError;
      console.error(`back failed: ${err.message}`);
    }
  }

  /** 点一条记录：带上章号与章内偏移，阅读页直接落到该位置 */
  private async openEntry(entry: NoteEntry): Promise<void> {
    const params = new ReaderParams();
    params.bookId = entry.bookId;
    params.jumpChapter = entry.chapterIndex;
    params.jumpOffset = entry.charOffset;
    try {
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/Reader', params: params });
    } catch (e) {
      const err = e as BusinessError;
      console.error(`open entry failed: ${err.message}`);
    }
  }

  @Builder
  backButton() {
    Stack({ alignContent: Alignment.Center }) {
      Text('‹')
        .fontSize(26)
        .fontColor(this.palette.ink)
        .margin({ bottom: 3 })
    }
    .width(40)
    .height(40)
    .borderRadius(20)
    .backgroundColor(this.palette.surfaceSink)
    .onClick(() => {
      this.back();
    })
  }

  @Builder
  titleHeader() {
    Row() {
      this.backButton()
      Column() {
        Text('我的笔记')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
          .maxLines(1)
        Text(this.loading
          ? '统计中…'
          : `划线 ${this.highlights.length} · 想法 ${this.notes.length} · 书签 ${this.bookmarks.length}`)
          .fontSize(12)
          .fontColor(this.palette.subtleText)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 14 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 一条记录：摘录 + 书名 / 章节（书签再带想法式备注），整行点击进原文 */
  @Builder
  entryRow(entry: NoteEntry, index: number) {
    Column() {
      if (index > 0) {
        Divider()
          .color(this.palette.chipBg)
          .margin({ left: 16, right: 16 })
      }
      Row() {
        Column() {
          Text(this.entryQuote(entry))
            .width('100%')
            .fontSize(14)
            .fontColor(this.palette.text)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row() {
            Text(entry.bookTitle)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '52%' })
            Text(` · ${this.entryChapterText(entry)}`)
              .fontSize(11)
              .fontColor(this.palette.subtleText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 6 })
          if (entry.note.length > 0) {
            Text(`想法：${entry.note}`)
              .width('100%')
              .fontSize(11)
              .fontColor(this.palette.chipText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('›')
          .fontSize(15)
          .fontColor(this.palette.subtleText)
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .onClick(() => {
        this.openEntry(entry);
      })
    }
    .width('100%')
  }

  /**
   * 三个分组必须各自写成无参 @Builder，并且在内部直接读 this.highlights 等状态。
   * 一旦把数组当参数传进来（按值传递），首帧传入的是空数组快照，
   * 之后 load() 更新了状态也不会重建这几个 builder，页面就会永远停在「暂无记录」。
   */
  @Builder
  highlightSection() {
    Column() {
      Row() {
        Text('划线')
          .fontSize(13)
          .fontColor(this.palette.subtleText)
        Blank()
        Text(`${this.highlights.length} 条`)
          .fontSize(11)
          .fontColor(this.palette.subtleText)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 14, bottom: 6 })

      if (this.highlights.length === 0) {
        Text('暂无记录')
          .width('100%')
          .fontSize(12)
          .fontColor(this.palette.subtleText)
          .padding({ left: 16, right: 16, top: 6, bottom: 16 })
      } else {
        ForEach(this.highlights, (item: NoteEntry, index: number) => {
          this.entryRow(item, index)
        }, (item: NoteEntry) => `h_${item.id}_${item.chapterIndex}`)
      }
    }
    .width('100%')
    .borderRadius(16)
    .backgroundColor(this.palette.surface)
    .border({ width: 1, color: this.palette.chipBg })
    .margin({ bottom: 12 })
  }

  @Builder
  ideaSection() {
    Column() {
      Row() {
        Text('想法')
          .fontSize(13)
          .fontColor(this.palette.subtleText)
        Blank()
        Text(`${this.notes.length} 条`)
          .fontSize(11)
          .fontColor(this.palette.subtleText)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 14, bottom: 6 })

      if (this.notes.length === 0) {
        Text('暂无记录')
          .width('100%')
          .fontSize(12)
          .fontColor(this.palette.subtleText)
          .padding({ left: 16, right: 16, top: 6, bottom: 16 })
      } else {
        ForEach(this.notes, (item: NoteEntry, index: number) => {
          this.entryRow(item, index)
        }, (item: NoteEntry) => `n_${item.id}_${item.chapterIndex}`)
      }
    }
    .width('100%')
    .borderRadius(16)
    .backgroundColor(this.palette.surface)
    .border({ width: 1, color: this.palette.chipBg })
    .margin({ bottom: 12 })
  }

  @Builder
  bookmarkSection() {
    Column() {
      Row() {
        Text('书签')
          .fontSize(13)
          .fontColor(this.palette.subtleText)
        Blank()
        Text(`${this.bookmarks.length} 条`)
          .fontSize(11)
          .fontColor(this.palette.subtleText)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 14, bottom: 6 })

      if (this.bookmarks.length === 0) {
        Text('暂无记录')
          .width('100%')
          .fontSize(12)
          .fontColor(this.palette.subtleText)
          .padding({ left: 16, right: 16, top: 6, bottom: 16 })
      } else {
        ForEach(this.bookmarks, (item: NoteEntry, index: number) => {
          this.entryRow(item, index)
        }, (item: NoteEntry) => `b_${item.id}_${item.chapterIndex}`)
      }
    }
    .width('100%')
    .borderRadius(16)
    .backgroundColor(this.palette.surface)
    .border({ width: 1, color: this.palette.chipBg })
    .margin({ bottom: 12 })
  }

  @Builder
  emptyState() {
    Column() {
      Text('还没有笔记')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text)
      Text('阅读时长按正文划选可加划线与想法，点右上角书签按钮可加书签')
        .fontSize(13)
        .fontColor(this.palette.subText)
        .textAlign(TextAlign.Center)
        .margin({ top: 10 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 28, right: 28, bottom: 40 })
  }

  build() {
    Column() {
      Column() {
        this.titleHeader()
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: this.topInset + 14, bottom: 10 })

      if (!this.loading && this.totalCount() === 0) {
        this.emptyState()
      } else {
        List({ space: 0 }) {
          ListItem() {
            this.highlightSection()
          }
          ListItem() {
            this.ideaSection()
          }
          ListItem() {
            this.bookmarkSection()
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 18, right: 18, bottom: this.bottomInset + 24 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
