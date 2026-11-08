import { AppEnv, AppEnvStore } from '../model/AppEnv';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { BookMeta } from '../model/BookModels';
import { ShelfTheme, ShelfThemeColors } from '../theme/ShelfTheme';
import { BookCover } from './BookCover';

// 封面下方的书名标签：字号 13，最多两行，行高固定以便同排卡片对齐
const LABEL_FONT_SIZE = 13;
const LABEL_LINE_HEIGHT = 17;

@ComponentV2
export struct BookCard {
  @Param book: BookMeta = new BookMeta();
  @Param selecting: boolean = false;
  @Param selected: boolean = false;
  // 封面下方书名标签的实测宽度（vp）
  @Local labelWidth: number = 0;
  @Event onOpen: (book: BookMeta) => void = (book: BookMeta): void => {};
  @Event onLongPress: (book: BookMeta) => void = (book: BookMeta): void => {};
  @Event onSelect: (book: BookMeta) => void = (book: BookMeta): void => {};
  // 亮暗跟随系统、卡片文字跟随「我的 - 外观」皮肤
  // App 级环境（系统深浅色 / 皮肤）：@ComponentV2 不支持 @StorageProp，改用 @ObservedV2 单例
  @Local env: AppEnv = AppEnvStore.get();
  @Monitor('env.colorMode') onColorModeMonitor(): void {
    this.applyPalette();
  }

  @Monitor('env.appSkin') onSkinMonitor(): void {
    this.applyPalette();
  }
  @Local palette: ShelfThemeColors = ShelfTheme.light();

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
   * 两行切分：切点按实测宽度算，且末行不留 1~2 个字的孤字，
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

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        // 封面与分组卡的 2×2 缩略封面共用同一套绘制逻辑
        Column() {
          BookCover({ book: this.book, showTypeBadge: !this.selecting })
        }
        .width('100%')
        .aspectRatio(0.72)

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
