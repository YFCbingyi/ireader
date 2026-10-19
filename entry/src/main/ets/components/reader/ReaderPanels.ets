import { Bookmark, ChapterMeta, ReadingMode } from '../../model/BookModels';
import { ReaderThemeColors, ReadingTheme } from '../../model/ReaderTheme';

@Component
export struct ReaderPanels {
  @Prop panel: string = '';
  @Prop chapters: ChapterMeta[] = [];
  @Prop currentChapter: number = 0;
  @Prop bookmarks: Bookmark[] = [];
  @Prop isImageBook: boolean = false;
  @Prop readingMode: ReadingMode = ReadingMode.VERTICAL;
  @Prop fontSize: number = 18;
  @Prop lineHeightRatio: number = 1.7;
  @Prop theme: ReadingTheme = ReadingTheme.EYE;
  @Prop colors: ReaderThemeColors = new ReaderThemeColors();

  onClose: () => void = (): void => {};
  onSelectChapter: (index: number) => void = (index: number): void => {};
  onSelectBookmark: (bookmark: Bookmark) => void = (bookmark: Bookmark): void => {};
  onDeleteBookmark: (bookmark: Bookmark) => void = (bookmark: Bookmark): void => {};
  onModeChange: (mode: ReadingMode) => void = (mode: ReadingMode): void => {};
  onFontSizeChange: (size: number) => void = (size: number): void => {};
  onLineHeightChange: (ratio: number) => void = (ratio: number): void => {};
  onThemeChange: (theme: ReadingTheme) => void = (theme: ReadingTheme): void => {};

  private panelTitle(): string {
    if (this.panel === 'catalog') {
      return '目录';
    }
    if (this.panel === 'bookmarks') {
      return '书签';
    }
    return '阅读设置';
  }

  @Builder
  modeButton(label: string, value: ReadingMode) {
    Text(label)
      .fontSize(14)
      .fontColor(this.readingMode === value ? this.colors.accentText : this.colors.chipText)
      .backgroundColor(this.readingMode === value ? this.colors.accent : this.colors.chipBg)
      .padding({ left: 18, right: 18, top: 9, bottom: 9 })
      .borderRadius(18)
      .margin({ right: 12 })
      .onClick(() => {
        this.onModeChange(value);
      })
  }

  @Builder
  themeButton(label: string, value: ReadingTheme) {
    Text(label)
      .fontSize(14)
      .fontColor(this.theme === value ? this.colors.accentText : this.colors.chipText)
      .backgroundColor(this.theme === value ? this.colors.accent : this.colors.chipBg)
      .padding({ left: 14, right: 14, top: 9, bottom: 9 })
      .borderRadius(18)
      .margin({ right: 10, bottom: 8 })
      .onClick(() => {
        this.onThemeChange(value);
      })
  }

  @Builder
  lineHeightButton(label: string, value: number, matched: boolean) {
    Text(label)
      .fontSize(14)
      .fontColor(matched ? this.colors.accentText : this.colors.chipText)
      .backgroundColor(matched ? this.colors.accent : this.colors.chipBg)
      .padding({ left: 18, right: 18, top: 9, bottom: 9 })
      .borderRadius(18)
      .margin({ right: 12 })
      .onClick(() => {
        this.onLineHeightChange(value);
      })
  }

  @Builder
  catalogPanel() {
    List() {
      ForEach(this.chapters, (item: ChapterMeta, index: number) => {
        ListItem() {
          Row() {
            Text(`${index + 1}`)
              .width(38)
              .fontSize(12)
              .fontColor(this.colors.panelSubText)
            Text(item.title)
              .layoutWeight(1)
              .fontSize(15)
              .fontColor(this.currentChapter === index ? this.colors.accent : this.colors.panelText)
              .fontWeight(this.currentChapter === index ? FontWeight.Bold : FontWeight.Normal)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding({ top: 13, bottom: 13 })
          .backgroundColor(this.currentChapter === index ? this.colors.selectedItemBg : '#00000000')
          .borderRadius(8)
          .onClick(() => {
            this.onSelectChapter(index);
          })
        }
        .width('100%')
      }, (item: ChapterMeta, index: number) => `${index}_${item.title}`)
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  bookmarksPanel() {
    if (this.bookmarks.length === 0) {
      Column() {
        Text('还没有书签')
          .fontSize(15)
          .fontColor(this.colors.panelSubText)
        Text('阅读时点击顶部“书签”即可添加')
          .fontSize(12)
          .fontColor(this.colors.panelSubText)
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      List() {
        ForEach(this.bookmarks, (item: Bookmark, index: number) => {
          ListItem() {
            Row() {
              Column() {
                Text(item.chapterTitle)
                  .fontSize(14)
                  .fontColor(this.colors.panelText)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.preview)
                  .fontSize(12)
                  .fontColor(this.colors.panelSubText)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 4 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .onClick(() => {
                this.onSelectBookmark(item);
              })

              Text('删除')
                .fontSize(13)
                .fontColor(this.colors.danger)
                .padding({ left: 12, top: 8, bottom: 8 })
                .onClick(() => {
                  this.onDeleteBookmark(item);
                })
            }
            .width('100%')
            .padding({ top: 12, bottom: 12 })
            .border({ width: { bottom: 1 }, color: this.colors.divider })
          }
          .width('100%')
        }, (item: Bookmark) => item.id)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  settingsPanel() {
    Scroll() {
      Column() {
        Text('阅读方向')
          .width('100%')
          .fontSize(13)
          .fontColor(this.colors.panelSubText)
          .margin({ top: 10, bottom: 10 })

        Row() {
          this.modeButton('上下', ReadingMode.VERTICAL)
          this.modeButton('左右', ReadingMode.HORIZONTAL)
        }
        .width('100%')

        if (this.isImageBook) {
          Text('上下模式：双指缩小可同屏查看多张，放大后可左右拖动。')
            .width('100%')
            .fontSize(12)
            .fontColor(this.colors.panelSubText)
            .lineHeight(20)
            .margin({ top: 18 })
        } else {
          Text('背景')
            .width('100%')
            .fontSize(13)
            .fontColor(this.colors.panelSubText)
            .margin({ top: 24, bottom: 10 })

          Flex({ wrap: FlexWrap.Wrap }) {
            this.themeButton('护眼', ReadingTheme.EYE)
            this.themeButton('白色', ReadingTheme.WHITE)
            this.themeButton('深色', ReadingTheme.DARK)
            this.themeButton('随系统', ReadingTheme.SYSTEM)
          }
          .width('100%')

          Text('字号')
            .width('100%')
            .fontSize(13)
            .fontColor(this.colors.panelSubText)
            .margin({ top: 18, bottom: 10 })

          Row() {
            Button('A-')
              .type(ButtonType.Capsule)
              .backgroundColor(this.colors.chipBg)
              .fontColor(this.colors.chipText)
              .fontSize(14)
              .onClick(() => {
                this.onFontSizeChange(this.fontSize - 2);
              })
            Text(`${this.fontSize}`)
              .width(60)
              .textAlign(TextAlign.Center)
              .fontSize(16)
              .fontColor(this.colors.panelText)
            Button('A+')
              .type(ButtonType.Capsule)
              .backgroundColor(this.colors.chipBg)
              .fontColor(this.colors.chipText)
              .fontSize(14)
              .onClick(() => {
                this.onFontSizeChange(this.fontSize + 2);
              })
          }
          .width('100%')

          Text('行距')
            .width('100%')
            .fontSize(13)
            .fontColor(this.colors.panelSubText)
            .margin({ top: 24, bottom: 10 })

          Row() {
            this.lineHeightButton('紧凑', 1.4, this.lineHeightRatio < 1.55)
            this.lineHeightButton('标准', 1.7, this.lineHeightRatio >= 1.55 && this.lineHeightRatio < 1.85)
            this.lineHeightButton('宽松', 2.0, this.lineHeightRatio >= 1.85)
          }
          .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 20 })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.onClose();
        })

      Column() {
        Row() {
          Text(this.panelTitle())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.colors.panelText)
            .layoutWeight(1)
          Text('关闭')
            .fontSize(14)
            .fontColor(this.colors.accent)
            .padding({ left: 12, right: 4, top: 8, bottom: 8 })
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .height(52)
        .alignItems(VerticalAlign.Center)

        Divider()
          .color(this.colors.divider)

        if (this.panel === 'catalog') {
          this.catalogPanel()
        } else if (this.panel === 'bookmarks') {
          this.bookmarksPanel()
        } else {
          this.settingsPanel()
        }
      }
      .width('100%')
      .height('62%')
      .backgroundColor(this.colors.panelBg)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .padding({ left: 18, right: 18, bottom: 18 })
    }
    .width('100%')
    .height('100%')
  }
}
