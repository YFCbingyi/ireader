import { ConfigurationConstant } from '@kit.AbilityKit';
import { BookMeta, BookType } from '../model/BookModels';
import { ShelfTheme, ShelfThemeColors } from '../model/ShelfTheme';

// 封面书名文字区：字号 14，字体框宽度以实测为准
const TITLE_FONT_SIZE = 14;
const TITLE_LINE_HEIGHT = 20;
// 封面下方的书名标签：字号 13，最多两行，行高固定以便同排卡片对齐
const LABEL_FONT_SIZE = 13;
const LABEL_LINE_HEIGHT = 17;


@Component
export struct BookCard {
  @Prop book: BookMeta = new BookMeta();
  @Prop selecting: boolean = false;
  @Prop selected: boolean = false;
  // 封面书名文字区实测宽度（vp），用来算每行能放几个字
  @State coverTextWidth: number = 0;
  // 封面下方书名标签的实测宽度（vp）
  @State labelWidth: number = 0;
  onOpen: (book: BookMeta) => void = (book: BookMeta): void => {};
  onLongPress: (book: BookMeta) => void = (book: BookMeta): void => {};
  onSelect: (book: BookMeta) => void = (book: BookMeta): void => {};
  // 深色模式：卡片自身的书名/进度/选择圈跟随主题，封面美术不跟随
  @StorageProp('systemColorMode') @Watch('onSystemColorModeChanged') systemColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State palette: ShelfThemeColors = ShelfTheme.light();

  aboutToAppear(): void {
    this.applyPalette();
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

  private displayTitle(): string {
    return this.book.title.length === 0 ? '无题' : this.book.title;
  }

  /** 单个字符占的宽度：半角按 0.55，全角按 1 */
  private charUnits(code: number): number {
    return code < 128 ? 0.55 : 1;
  }

  private textUnits(text: string): number {
    let units = 0;
    for (let i = 0; i < text.length; i++) {
      units += this.charUnits(text.charCodeAt(i));
    }
    return units;
  }

  /** 一行能放多少宽度单位：按实测宽度和字号换算，宽度未知时给个保守值 */
  private lineCapacity(width: number, fontSize: number, padding: number): number {
    const inner = width - padding;
    if (inner <= 0) {
      return 5;
    }
    return Math.max(3, Math.floor(inner / fontSize));
  }

  /** 取宽度不超过 maxUnits 的最长前缀 */
  private fitPrefix(text: string, maxUnits: number): string {
    let units = 0;
    let cut = 0;
    for (let i = 0; i < text.length; i++) {
      const unit = this.charUnits(text.charCodeAt(i));
      if (units + unit > maxUnits) {
        break;
      }
      units += unit;
      cut = i + 1;
    }
    return text.substring(0, cut);
  }

  /**
   * 封面书名排版：最多两行。
   * 切点按实测宽度算，且末行不留 1~2 个字的孤字，
   * 例如「工藤新一的日本后」切成「工藤新一的 / 日本后」，而不是「工藤新一的日 / 本后」。
   */
  private splitTitleLines(title: string, capacity: number): string[] {
    if (this.textUnits(title) <= capacity) {
      return [title];
    }
    let cut = this.fitPrefix(title, capacity).length;
    while (cut > 1 && this.textUnits(title.substring(cut)) < 3) {
      cut--;
    }
    const head = title.substring(0, cut);
    const rest = title.substring(cut);
    if (this.textUnits(rest) <= capacity) {
      return [head, rest];
    }
    return [head, `${this.fitPrefix(rest, capacity - 1)}…`];
  }

  private coverTitleLines(): string[] {
    return this.splitTitleLines(this.displayTitle(),
      this.lineCapacity(this.coverTextWidth, TITLE_FONT_SIZE, 12));
  }

  private labelTitleLines(): string[] {
    return this.splitTitleLines(this.displayTitle(),
      this.lineCapacity(this.labelWidth, LABEL_FONT_SIZE, 0));
  }

  private progressText(): string {
    if (this.book.chapterCount <= 0) {
      return '暂无章节';
    }
    const progress = this.book.progress;
    const percent = Math.round(progress.percent * 100);
    if (progress.updatedAt > 0) {
      return `第 ${progress.chapterIndex + 1}/${this.book.chapterCount} 章 · ${percent}%`;
    }
    return `共 ${this.book.chapterCount} 章`;
  }

  private tapCard(): void {
    if (this.selecting) {
      this.onSelect(this.book);
      return;
    }
    this.onOpen(this.book);
  }

  @Builder
  bookCover() {
    Row() {
      Column()
        .width(9)
        .height('100%')
        .linearGradient({
          angle: 90,
          colors: [['#66000000', 0.0], ['#2E000000', 0.55], ['#12000000', 1.0]]
        })

      Stack() {
        if (this.book.type === BookType.IMAGE) {
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 135,
              colors: [['#2C5F6E', 0.0], ['#3F8B99', 1.0]]
            })
        } else {
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 135,
              colors: [['#8B5E3C', 0.0], ['#B8860B', 1.0]]
            })
        }

        Column()
          .width('calc(100% - 12vp)')
          .height('calc(100% - 12vp)')
          .border({ width: 1, color: '#33FFF8ED' })
          .borderRadius(6)

        Column() {
          ForEach(this.coverTitleLines(), (line: string, index: number) => {
            Text(line)
              .width('100%')
              .fontSize(TITLE_FONT_SIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFF8ED')
              .lineHeight(TITLE_LINE_HEIGHT)
              .maxLines(1)
              .textAlign(TextAlign.Center)
          }, (line: string, index: number) => `title_${index}_${line}`)
          Column()
            .width(24)
            .height(1)
            .backgroundColor('#66FFF8ED')
            .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 6, right: 6 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onAreaChange((oldValue: Area, newValue: Area) => {
          const width = Number(newValue.width);
          if (width > 0 && Math.abs(width - this.coverTextWidth) > 0.5) {
            this.coverTextWidth = width;
          }
        })

        if (!this.selecting) {
          Stack({ alignContent: Alignment.TopEnd }) {
            Text(this.book.type === BookType.IMAGE ? '图' : 'TXT')
              .fontSize(9)
              .fontColor('#FFF8ED')
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(4)
              .backgroundColor('#33FFFFFF')
              .border({ width: 1, color: '#4DFFFFFF' })
              .margin({ top: 6, right: 10 })
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        }

        if (this.book.group !== undefined && this.book.group.length > 0) {
          Stack({ alignContent: Alignment.TopStart }) {
            Text(this.book.group)
              .fontSize(9)
              .fontColor('#FFF8ED')
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(4)
              .backgroundColor('#59000000')
              .margin({ top: 6, left: 10 })
              .maxLines(1)
              .constraintSize({ maxWidth: 66 })
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .layoutWeight(1)
      .height('100%')

      Column()
        .width(5)
        .height('100%')
        .backgroundColor(this.palette.surfaceSink)
    }
    .width('100%')
    .aspectRatio(0.72)
    .borderRadius(10)
    .clip(true)
    .draggable(false)
    .shadow({ radius: 10, color: this.palette.shadow, offsetX: 0, offsetY: 4 })
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        this.bookCover()

        // 书名最多两行：切点按实测宽度算，末行不留孤字；固定两行高度保证同排卡片进度行对齐
        Column() {
          ForEach(this.labelTitleLines(), (line: string, index: number) => {
            Text(line)
              .width('100%')
              .fontSize(LABEL_FONT_SIZE)
              .lineHeight(LABEL_LINE_HEIGHT)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette.text)
              .maxLines(1)
          }, (line: string, index: number) => `label_${index}_${line}`)
        }
        .width('100%')
        .constraintSize({ minHeight: LABEL_LINE_HEIGHT * 2 })
        .margin({ top: 8 })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          const width = Number(newValue.width);
          if (width > 0 && Math.abs(width - this.labelWidth) > 0.5) {
            this.labelWidth = width;
          }
        })

        Text(this.progressText())
          .width('100%')
          .fontSize(11)
          .fontColor(this.palette.subText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .width('100%')
      .margin({ bottom: 18 })
      .onClick(() => {
        this.tapCard();
      })
      .gesture(
        LongPressGesture()
          .onAction(() => {
            this.onLongPress(this.book);
          })
      )

      if (this.selecting) {
        Stack() {
          Circle()
            .width(24)
            .height(24)
            .fill(this.selected ? this.palette.accent : this.palette.chipBg)
            .stroke(this.selected ? this.palette.accent : this.palette.subtleText)
            .strokeWidth(1.5)
          if (this.selected) {
            Text('✓')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.accentText)
          }
        }
        .width(24)
        .height(24)
        .margin({ top: 6, right: 8 })
        .onClick(() => {
          this.onSelect(this.book);
        })
      }
    }
    .width('100%')
  }
}
