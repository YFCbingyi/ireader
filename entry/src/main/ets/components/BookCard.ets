import { AppEnv, AppEnvStore } from '../model/AppEnv';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { Motion } from '../theme/MotionTokens';
import { BookMeta } from '../model/BookModels';
import { ShelfTheme, ShelfThemeColors } from '../theme/ShelfTheme';
import { BookCover } from './BookCover';

// 封面下方的书名标签：字号 13，最多两行，行高固定以便同排卡片对齐
const LABEL_FONT_SIZE = 13;
const LABEL_LINE_HEIGHT = 17;
// 聚焦 / 按压反馈的弹簧由 MotionTokens.slow() 统一给出（response 0.5，比默认更慢、回弹更足）
// 长按聚焦时封面的放大倍率（此时整页其余内容被雾化）
const FOCUSED_COVER_SCALE = 1.18;
// 手指按下的即时反馈倍率（还未越过长按阈值）
const PRESSED_COVER_SCALE = 1.06;

@ComponentV2
export struct BookCard {
  @Param book: BookMeta = new BookMeta();
  @Param selecting: boolean = false;
  @Param selected: boolean = false;
  // 长按聚焦：整页雾化时只有这一本的封面作为主体清晰放大，书名与进度不显示
  @Param focused: boolean = false;
  // 封面下方书名标签的实测宽度（vp）
  @Local labelWidth: number = 0;
  // 按下态：驱动封面斜向高光带（点按即时反馈）
  @Local pressed: boolean = false;
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

  /** 封面缩放倍率：缩放主体只有封面，下方的书名与进度不参与 */
  private coverScale(): number {
    if (this.selecting) {
      return 1;
    }
    if (this.focused) {
      return FOCUSED_COVER_SCALE;
    }
    if (this.pressed) {
      return PRESSED_COVER_SCALE;
    }
    return 1;
  }

  /**
   * 封面放大后向上抬起自身溢出的那一半（百分比相对封面自身高度）。
   * 缩放默认是绕中心放大，若不抬，封面底边会向文字区多长出半截，
   * 与下方的隐形容名区叠在一起，视觉上就是封面和菜单之间那条难看的大缝隙。
   */
  private coverLiftRatio(): string {
    const extra = (this.coverScale() - 1) / 2;
    return `${-extra * 100}%`;
  }

  /** 长按聚焦时只留封面：书名与进度整块撤出布局（否则会在封面和菜单之间留出一段死白） */
  private labelVisible(): Visibility {
    return this.focused && !this.selecting ? Visibility.None : Visibility.Visible;
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
          Stack({ alignContent: Alignment.Center }) {
            BookCover({ book: this.book, showTypeBadge: !this.selecting })
            // 按压高光：斜向半透明白带，按下时淡入并右移，制造封面被光扫过的质感
            if (!this.selecting) {
              Column()
                .width('100%')
                .height('100%')
                .linearGradient({
                  angle: 115,
                  colors: [['#00FFFFFF', 0.0], ['#33FFFFFF', 0.42], ['#0DFFFFFF', 0.58], ['#00FFFFFF', 1.0]]
                })
                .translate({ x: this.pressed || this.focused ? 16 : -14 })
                .opacity(this.pressed || this.focused ? 1 : 0)
                .animation(Motion.slow())
                .hitTestBehavior(HitTestMode.None)
            }
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .aspectRatio(0.72)
        // 只有封面作为主体放大：长按聚焦时最大，手指刚按下时给一点即时反馈。
        // 绕中心放大后整体上抬溢出的那一半，让封面底边始终停在原位，不压占下方文字区
        .scale({
          x: this.coverScale(),
          y: this.coverScale()
        })
        .translate({ y: this.coverLiftRatio() })
        .zIndex(this.focused && !this.selecting ? 5 : (this.pressed && !this.selecting ? 3 : 0))
        .animation(Motion.slow())

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
        .visibility(this.labelVisible())
        Text(this.progressText())
          .width('100%')
          .fontSize(11)
          .fontColor(this.palette.subText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
          .visibility(this.labelVisible())
      }
      .width('100%')
      .margin({ bottom: 18 })
      .onTouch((event: TouchEvent) => {
        const down = event.type === TouchType.Down || event.type === TouchType.Move;
        if (this.pressed !== down) {
          this.pressed = down;
        }
      })
      .onClick(() => {
        this.pressed = false;
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
