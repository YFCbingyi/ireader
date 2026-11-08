import { AppEnv, AppEnvStore } from '../model/AppEnv';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { BookMeta, BookType } from '../model/BookModels';
import { ImageCoverStyle, TextCoverStyle } from '../model/CoverStyle';
import { ShelfTheme, ShelfThemeColors } from '../theme/ShelfTheme';
import { AppPaths } from '../utils/AppPaths';

// 经典书卷：封面书名文字区字号
const TITLE_FONT_SIZE = 14;
const TITLE_LINE_HEIGHT = 20;
// 「排版大字」样式的书名：字号大、行高紧，撑起封面
const TYPE_FONT_SIZE = 19;
const TYPE_LINE_HEIGHT = 22;
// 「精装书脊」的书名：左对齐，字号略小，三行以内
const SPINE_FONT_SIZE = 13;
const SPINE_LINE_HEIGHT = 18;
// 「首图封面」的书名压在图片底部，字号小一点
const PHOTO_FONT_SIZE = 12;
const PHOTO_LINE_HEIGHT = 15;
// 「文人竖排」逐字排布：行高 17，最多 7 字（再多会顶到印章）
const INK_FONT_SIZE = 15;
const INK_LINE_HEIGHT = 17;
const INK_MAX_CHARS = 7;
// 基准封面宽度：书架卡片封面约 105vp，缩略封面按实测宽度等比缩小字号与间距
const BASE_COVER_WIDTH = 105;
const MIN_SCALE = 0.45;
const MAX_SCALE = 1.15;

/**
 * 书卡封面：按「我的 - 外观」里选的封面样式渲染。
 *
 * 抽成独立组件是为了让书架卡片和分组卡的 2×2 缩略封面用同一套绘制逻辑，
 * 换样式时两处同时生效。尺寸完全由父容器决定（宽高各 100%），
 * 字号与间距按实测宽度等比缩放，因此缩略封面是大封面同比例的缩小版。
 */
@ComponentV2
export struct BookCover {
  @Param book: BookMeta = new BookMeta();
  /** 分组卡里的迷你封面：关掉角标和投影，小尺寸下挤在一起反而看不清 */
  @Param mini: boolean = false;
  /** 书架卡片多选态下藏掉类型角标 */
  @Param showTypeBadge: boolean = true;
  @Local env: AppEnv = AppEnvStore.get();
  @Monitor('env.colorMode') onColorModeMonitor(): void {
    this.applyPalette();
  }

  @Monitor('env.appSkin') onSkinMonitor(): void {
    this.applyPalette();
  }

  @Local palette: ShelfThemeColors = ShelfTheme.light();
  // 封面实测宽度（vp）：既用来算书名每行几个字，也用来算缩放比例
  @Local coverWidth: number = 0;

  aboutToAppear(): void {
    this.applyPalette();
  }

  private applyPalette(): void {
    const next = ShelfTheme.resolve(this.env.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK,
      this.env.appSkin);
    if (next.key !== this.palette.key) {
      this.palette = next;
    }
  }

  /** 相对基准封面的缩放比例：缩略封面不会缩到看不清，大卡片也不会无限放大 */
  private coverScale(): number {
    const width = this.coverWidth;
    if (width <= 0) {
      return this.mini ? MIN_SCALE : 1;
    }
    return Math.min(MAX_SCALE, Math.max(MIN_SCALE, width / BASE_COVER_WIDTH));
  }

  /** 按封面缩放比例换算尺寸，保证缩略封面与大封面比例一致 */
  private scaled(value: number): number {
    return value * this.coverScale();
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
      return 3;
    }
    return Math.max(2, Math.floor(inner / fontSize));
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
    // 封面书名左右各留 12 的内边距
    return this.splitTitleLines(this.displayTitle(),
      this.lineCapacity(this.coverWidth, this.scaled(TITLE_FONT_SIZE), this.scaled(24)));
  }

  /** 精装书脊：书脊占 15，文字左侧让到 24，右侧留 10 */
  private spineTitleLines(): string[] {
    return this.multiLines(this.displayTitle(),
      this.lineCapacity(this.coverWidth, this.scaled(SPINE_FONT_SIZE), this.scaled(34)), 3);
  }

  /** 通用多行切分：最多 maxLines 行，最后一行放不下就用省略号收尾 */
  private multiLines(title: string, capacity: number, maxLines: number): string[] {
    const lines: string[] = [];
    let rest = title;
    while (rest.length > 0 && lines.length < maxLines) {
      if (this.textUnits(rest) <= capacity) {
        lines.push(rest);
        return lines;
      }
      if (lines.length === maxLines - 1) {
        lines.push(`${this.fitPrefix(rest, Math.max(capacity - 1, 1))}…`);
        return lines;
      }
      let cut = this.fitPrefix(rest, capacity).length;
      if (cut < 1) {
        cut = 1;
      }
      lines.push(rest.substring(0, cut));
      rest = rest.substring(cut);
    }
    return lines;
  }

  /** 排版大字样式：字号大，最多三行，行容量按字号换算 */
  private typeTitleLines(): string[] {
    return this.multiLines(this.displayTitle(),
      this.lineCapacity(this.coverWidth, this.scaled(TYPE_FONT_SIZE), this.scaled(18)), 3);
  }

  /** 首图封面：书名压在底部，字号小、最多两行 */
  private photoTitleLines(): string[] {
    return this.multiLines(this.displayTitle(),
      this.lineCapacity(this.coverWidth, this.scaled(PHOTO_FONT_SIZE), this.scaled(16)), 2);
  }

  /** 竖排书名：逐字排，竖向放不下就截断加省略号 */
  private inkChars(): string[] {
    const chars: string[] = [];
    const title = this.displayTitle();
    const max = INK_MAX_CHARS;
    for (let i = 0; i < title.length && i < max; i++) {
      chars.push(title.substring(i, i + 1));
    }
    if (title.length > max) {
      chars[max - 1] = '…';
    }
    return chars;
  }

  /** 印章里的字：取书名第一个字，没有就用「书」 */
  private sealChar(): string {
    const title = this.displayTitle();
    return title.length > 0 ? title.substring(0, 1) : '书';
  }

  private isTextBook(): boolean {
    return this.book.type !== BookType.IMAGE;
  }

  private isDark(): boolean {
    return this.env.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private coverStyle(): string {
    return this.isTextBook() ? this.env.textCover : this.env.imageCover;
  }

  /** 浅纸底样式（精装 / 竖排）：角标要换成深色，否则白字看不见 */
  private isPaperStyle(): boolean {
    const style = this.coverStyle();
    return style === TextCoverStyle.SPINE || style === TextCoverStyle.INK;
  }

  private badgeBg(): string {
    return this.isPaperStyle() ? this.palette.chipBg : '#33FFFFFF';
  }

  private badgeInk(): string {
    return this.isPaperStyle() ? this.palette.chipText : this.palette.coverInk;
  }

  private hasCoverImage(): boolean {
    return this.book.coverFile !== undefined && this.book.coverFile.length > 0;
  }

  private coverImageUri(): string {
    return this.hasCoverImage() ? AppPaths.uri(this.book.coverFile) : '';
  }

  build() {
    Row() {
      // 浅纸底样式（精装 / 竖排）自带书脊与装订线，不再叠深色书脊影
      if (!this.isPaperStyle()) {
        Column()
          .width(this.scaled(9))
          .height('100%')
          .linearGradient({
            angle: 90,
            colors: [['#66000000', 0.0], ['#2E000000', 0.55], ['#12000000', 1.0]]
          })
      }

      Stack({ alignContent: Alignment.Center }) {
        if (this.isTextBook()) {
          if (this.coverStyle() === TextCoverStyle.SPINE) {
            this.coverSpine()
          } else if (this.coverStyle() === TextCoverStyle.TYPE) {
            this.coverType()
          } else if (this.coverStyle() === TextCoverStyle.INK) {
            this.coverInk()
          } else {
            this.coverClassic()
          }
        } else if (this.coverStyle() === ImageCoverStyle.PHOTO && this.hasCoverImage()) {
          this.coverPhoto()
        } else {
          this.coverFilm()
        }

        if (!this.mini && this.showTypeBadge) {
          Stack({ alignContent: Alignment.TopEnd }) {
            Text(this.isTextBook() ? 'TXT' : '图')
              .fontSize(9)
              .fontColor(this.badgeInk())
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(4)
              .backgroundColor(this.badgeBg())
              .border({ width: 1, color: '#4DFFFFFF' })
              .margin({ top: 6, right: 10 })
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        }

        if (!this.mini && this.book.group !== undefined && this.book.group.length > 0) {
          Stack({ alignContent: Alignment.TopStart }) {
            Text(this.book.group)
              .fontSize(9)
              .fontColor(this.palette.coverInk)
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
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const width = Number(newValue.width);
        if (width > 0 && Math.abs(width - this.coverWidth) > 0.5) {
          this.coverWidth = width;
        }
      })

      Column()
        .width(this.scaled(5))
        .height('100%')
        .backgroundColor(this.isPaperStyle() ? this.palette.border : this.palette.surfaceSink)
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.scaled(10))
    .clip(true)
    .draggable(false)
    .shadow({
      radius: this.mini ? 0 : 10,
      color: this.mini ? '#00000000' : this.palette.shadow,
      offsetX: 0,
      offsetY: this.mini ? 0 : 4
    })
  }

  /** 经典书卷：渐变底 + 细内框 + 居中书名 */
  @Builder
  coverClassic() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 135,
          colors: [[this.palette.coverTextStart, 0.0], [this.palette.coverTextEnd, 1.0]]
        })

      Column()
        .width('calc(100% - 12vp)')
        .height('calc(100% - 12vp)')
        .border({ width: 1, color: this.palette.coverInkSoft })
        .borderRadius(this.scaled(6))

      Column() {
        ForEach(this.coverTitleLines(), (line: string, index: number) => {
          Text(line)
            .width('100%')
            .fontSize(this.scaled(TITLE_FONT_SIZE))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.coverInk)
            .lineHeight(this.scaled(TITLE_LINE_HEIGHT))
            .maxLines(1)
            .textAlign(TextAlign.Center)
        }, (line: string, index: number) => `classic_${index}_${line}`)
        Column()
          .width(this.scaled(24))
          .height(1)
          .backgroundColor(this.palette.coverInkLine)
          .margin({ top: this.scaled(8) })
      }
      .width('100%')
      .padding({ left: this.scaled(12), right: this.scaled(12) })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }

  /** 精装书脊：左侧深色书脊 + 浅纸面 + 左对齐书名 + 底部饰线 */
  @Builder
  coverSpine() {
    Stack({ alignContent: Alignment.Center }) {
      // 纸面：亮色是象牙白压到浅米色；深色模式换成深纸，避免白到黑的脏渐变
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 175,
          colors: this.isDark()
            ? [[this.palette.surfaceSink, 0.0], [this.palette.surface, 1.0]]
            : [[this.palette.coverInk, 0.0], [this.palette.coverInk, 0.5], [this.palette.chipBg, 1.0]]
        })

      // 深色书脊
      Row() {
        Column()
          .width(this.scaled(15))
          .height('100%')
          .linearGradient({
            angle: 90,
            colors: [[this.palette.coverTextStart, 0.0], [this.palette.coverTextEnd, 1.0]]
          })
        Blank()
      }
      .width('100%')
      .height('100%')

      // 书脊压纹高光
      Row() {
        Column()
          .width(1)
          .height('80%')
          .backgroundColor('#4DFFFFFF')
          .margin({ left: this.scaled(4) })
        Blank()
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)

      Column() {
        ForEach(this.spineTitleLines(), (line: string, index: number) => {
          Text(line)
            .width('100%')
            .fontSize(this.scaled(SPINE_FONT_SIZE))
            .lineHeight(this.scaled(SPINE_LINE_HEIGHT))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDark() ? this.palette.ink : this.palette.coverTextStart)
            .maxLines(1)
            .textAlign(TextAlign.Start)
        }, (line: string, index: number) => `spine_${index}_${line}`)
        Column()
          .width(this.scaled(18))
          .height(this.scaled(1.5))
          .backgroundColor(this.isDark() ? this.palette.accent : this.palette.coverTextEnd)
          .margin({ top: this.scaled(9) })
      }
      .width('100%')
      .height('100%')
      .padding({
        left: this.scaled(24),
        right: this.scaled(10),
        top: this.scaled(14),
        bottom: this.scaled(14)
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  /** 排版大字：渐变底 + 大量留白 + 大字号书名 */
  @Builder
  coverType() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 150,
          colors: [[this.palette.coverTextStart, 0.0], [this.palette.coverTextEnd, 1.0]]
        })

      Column() {
        Text(this.book.chapterCount > 0 ? `共 ${this.book.chapterCount} 章` : '')
          .fontSize(this.scaled(8))
          .fontColor(this.palette.coverInkSoft)
          .maxLines(1)
        Blank()
        ForEach(this.typeTitleLines(), (line: string, index: number) => {
          Text(line)
            .width('100%')
            .fontSize(this.scaled(TYPE_FONT_SIZE))
            .lineHeight(this.scaled(TYPE_LINE_HEIGHT))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.coverInk)
            .maxLines(1)
            .textAlign(TextAlign.Start)
        }, (line: string, index: number) => `type_${index}_${line}`)
        Column()
          .width(this.scaled(22))
          .height(this.scaled(1.5))
          .backgroundColor(this.palette.coverInkLine)
          .margin({ top: this.scaled(8) })
      }
      .width('100%')
      .height('100%')
      .padding({
        left: this.scaled(9),
        right: this.scaled(9),
        top: this.scaled(11),
        bottom: this.scaled(11)
      })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  /** 文人竖排：纸底 + 竖排书名 + 朱红印章 */
  @Builder
  coverInk() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [[this.palette.surfaceAlt, 0.0], [this.palette.surface, 1.0]]
        })

      // 右侧书口细线
      Row() {
        Blank()
        Column()
          .width(1)
          .height('74%')
          .backgroundColor(this.palette.border)
      }
      .width('100%')
      .height('100%')
      .padding({ right: this.scaled(7) })

      // 竖排书名：逐字一列
      Column() {
        ForEach(this.inkChars(), (ch: string, index: number) => {
          Text(ch)
            .fontSize(this.scaled(INK_FONT_SIZE))
            .lineHeight(this.scaled(INK_LINE_HEIGHT))
            .fontWeight(FontWeight.Regular)
            .fontColor(this.palette.text)
            .maxLines(1)
            .textAlign(TextAlign.Center)
        }, (ch: string, index: number) => `ink_${index}_${ch}`)
      }
      .justifyContent(FlexAlign.Center)
      .padding({ right: this.scaled(14) })

      // 朱红印章
      Row() {
        Column() {
          Text(this.sealChar())
            .fontSize(this.scaled(9))
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
        }
        .width(this.scaled(16))
        .height(this.scaled(16))
        .borderRadius(this.scaled(3))
        .backgroundColor('#B23A2E')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        Blank()
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Bottom)
      .padding({ left: this.scaled(8), bottom: this.scaled(8) })
    }
    .width('100%')
    .height('100%')
  }

  /** 首图封面：第一张图当底，压暗后书名贴左下 */
  @Builder
  coverPhoto() {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.coverImageUri())
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .autoResize(true)
        .draggable(false)

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [['#00000000', 0.0], ['#00000000', 0.42], ['#B3000000', 1.0]]
        })

      Column() {
        Blank()
        ForEach(this.photoTitleLines(), (line: string, index: number) => {
          Text(line)
            .width('100%')
            .fontSize(this.scaled(PHOTO_FONT_SIZE))
            .lineHeight(this.scaled(PHOTO_LINE_HEIGHT))
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textAlign(TextAlign.Start)
            .shadow({ radius: 4, color: '#99000000', offsetX: 0, offsetY: 1 })
        }, (line: string, index: number) => `photo_${index}_${line}`)
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.scaled(8), right: this.scaled(8), bottom: this.scaled(9) })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  /** 胶片条：渐变底 + 上下齿孔带 + 大号「图」字水印 */
  @Builder
  coverFilm() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 145,
          colors: [[this.palette.coverImageStart, 0.0], [this.palette.coverImageEnd, 1.0]]
        })

      Text('图')
        .fontSize(this.scaled(46))
        .fontWeight(FontWeight.Bold)
        .fontColor('#26FFFFFF')

      Column() {
        this.filmPerforation()
        Blank()
        this.filmPerforation()
      }
      .width('100%')
      .height('100%')

      Column() {
        Blank()
        ForEach(this.coverTitleLines(), (line: string, index: number) => {
          Text(line)
            .width('100%')
            .fontSize(this.scaled(TITLE_FONT_SIZE))
            .lineHeight(this.scaled(TITLE_LINE_HEIGHT))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.coverInk)
            .maxLines(1)
            .textAlign(TextAlign.Center)
        }, (line: string, index: number) => `film_${index}_${line}`)
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.scaled(8), right: this.scaled(8), bottom: this.scaled(14) })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  filmPerforation() {
    Row({ space: this.scaled(4) }) {
      ForEach([0, 1, 2, 3, 4, 5], (item: number) => {
        Column()
          .width(this.scaled(3))
          .height(this.scaled(3))
          .borderRadius(this.scaled(1.5))
          .backgroundColor('#59FFFFFF')
      }, (item: number) => `perf_${item}`)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: this.scaled(5), bottom: this.scaled(5) })
  }
}
