import { display, MeasureOptions, MeasureUtils, UIContext } from '@kit.ArkUI';

export class PageRange {
  start: number = 0;
  end: number = 0;

  static of(start: number, end: number): PageRange {
    const range = new PageRange();
    range.start = start;
    range.end = end;
    return range;
  }
}

export class PaginationResult {
  ranges: PageRange[] = [];
  pageStarts: number[] = [];
}

/** 单页测量校正的最大迭代次数 */
const FIT_MAX_ITERATIONS = 5;
/** 标定探针：全角样本字数 / 半角样本 / 行高样本行数 */
const CJK_PROBE_COUNT = 20;
const ASCII_PROBE = 'abcdefghijklmnopqrstuvwxyz';
const LINE_PROBE_ROWS = 8;
const LINE_PROBE_CHARS = 6;
const MIN_LINES_PER_PAGE = 1;
/** 一次性跑完分页时的单片页数（仅 paginate() 同步入口使用） */
const FULL_STEP_PAGES = 256;
/** 同步入口的死循环保护 */
const MAX_PAGE_GUARD = 20000;

/**
 * 排版标定值（像素单位）。
 *
 * 旧实现每页都要二分 measureTextSize：候选窗口 2500~8000 字、每页 10+ 次测量，
 * 一章几万字时主线程要连卡几秒（首屏白屏）。
 * 现在改为先用几根探针标定字宽与行高，之后按字符宽度模型推算每页边界，
 * 每页再用一次实测校验（个别页补测），测量次数和测量文本长度都降了一个数量级。
 */
export class PaginationMetrics {
  cjkWidth: number = 1;
  asciiWidth: number = 1;
  lineHeight: number = 1;
  maxWidth: number = 1;
}

/**
 * 分页游标：可分批推进。
 * 调用方每片调一次 step()，片间让出主线程，长章节既不会一次性占满主线程，
 * 也能随时丢弃中途结果（字号 / 行距 / 视口变化）。
 */
export class PaginationSession {
  private text: string = '';
  private widthVp: number = 0;
  private fontSize: number = 0;
  private lineHeightVp: number = 0;
  private pageHeightPx: number = 1;
  private firstPageHeightPx: number = 1;
  private utils: MeasureUtils | undefined = undefined;
  private metrics: PaginationMetrics = new PaginationMetrics();
  private fontFamily: string = '';
  private cursor: number = 0;
  private finished: boolean = false;
  private pages: PaginationResult = new PaginationResult();

  constructor(text: string, widthVp: number, fontSize: number, lineHeightVp: number,
    pageHeightPx: number, firstPageHeightPx: number, utils: MeasureUtils | undefined,
    metrics: PaginationMetrics, fontFamily: string = '') {
    this.text = text;
    this.widthVp = widthVp;
    this.fontSize = fontSize;
    this.lineHeightVp = lineHeightVp;
    this.pageHeightPx = pageHeightPx > 0 ? pageHeightPx : 1;
    this.firstPageHeightPx = firstPageHeightPx > 0 ? firstPageHeightPx : 1;
    this.utils = utils;
    this.metrics = metrics;
    this.fontFamily = fontFamily;
  }

  isFinished(): boolean {
    return this.finished;
  }

  result(): PaginationResult {
    return this.pages;
  }

  /** 推进最多 maxPages 页 */
  step(maxPages: number): void {
    if (this.finished) {
      return;
    }
    const count = maxPages > 0 ? maxPages : 1;
    for (let i = 0; i < count; i++) {
      if (this.finished) {
        return;
      }
      this.appendNextPage();
    }
  }

  private appendNextPage(): void {
    const text = this.text;
    const start = this.cursor;
    if (start >= text.length) {
      if (this.pages.ranges.length === 0) {
        this.pages.ranges.push(PageRange.of(0, 0));
        this.pages.pageStarts.push(0);
      }
      this.finished = true;
      return;
    }
    const heightPx = this.pages.ranges.length === 0 ? this.firstPageHeightPx : this.pageHeightPx;
    const lineHeight = this.metrics.lineHeight > 0 ? this.metrics.lineHeight : 1;
    let maxLines = Math.floor(heightPx / lineHeight);
    if (maxLines < MIN_LINES_PER_PAGE) {
      maxLines = MIN_LINES_PER_PAGE;
    }
    let end = TextPaginator.modelPageEnd(text, start, maxLines, this.metrics);
    if (end <= start) {
      end = start + 1;
    }
    if (end > text.length) {
      end = text.length;
    }
    if (this.utils !== undefined) {
      end = this.fitEnd(start, end, heightPx, maxLines);
    }
    if (end <= start) {
      end = start + 1;
    }
    if (end > text.length) {
      end = text.length;
    }
    this.pages.ranges.push(PageRange.of(start, end));
    this.pages.pageStarts.push(start);
    this.cursor = end;
  }

  /**
   * 用实测高度校正模型推算的页尾：
   * - 溢出：按比例回缩（高度对字符数近线性），一般 1~2 次收敛
   * - 实测行数没占满 maxLines（模型把字宽算大了）：按模型补一行再实测确认
   * 模型准确时每页只需 1 次测量。
   */
  private fitEnd(start: number, guess: number, heightPx: number, maxLines: number): number {
    const utils = this.utils;
    if (utils === undefined) {
      return guess;
    }
    const text = this.text;
    const lineHeight = this.metrics.lineHeight > 0 ? this.metrics.lineHeight : heightPx;
    let end = guess;
    let measured = TextPaginator.measureHeight(utils, text.substring(start, end),
      this.widthVp, this.fontSize, this.lineHeightVp, this.fontFamily);
    if (measured <= 0) {
      return guess;
    }
    for (let i = 0; i < FIT_MAX_ITERATIONS; i++) {
      if (measured > heightPx) {
        const ratio = heightPx / measured;
        let scaled = ratio > 0.98 ? 0.98 : ratio;
        if (scaled < 0.2) {
          scaled = 0.2;
        }
        let next = start + Math.floor((end - start) * scaled);
        if (next >= end) {
          next = end - 1;
        }
        if (next <= start) {
          next = start + 1;
        }
        if (next > text.length) {
          next = text.length;
        }
        end = next;
        measured = TextPaginator.measureHeight(utils, text.substring(start, end),
          this.widthVp, this.fontSize, this.lineHeightVp, this.fontFamily);
        if (measured <= 0) {
          return end;
        }
        continue;
      }
      const usedLines = Math.max(1, Math.round(measured / lineHeight));
      if (usedLines >= maxLines || end >= text.length) {
        break;
      }
      let next = TextPaginator.modelPageEnd(text, end, 1, this.metrics);
      if (next <= end) {
        next = end + 1;
      }
      if (next > text.length) {
        next = text.length;
      }
      const extended = TextPaginator.measureHeight(utils, text.substring(start, next),
        this.widthVp, this.fontSize, this.lineHeightVp, this.fontFamily);
      if (extended <= 0 || extended > heightPx) {
        break;
      }
      end = next;
      measured = extended;
    }
    return end;
  }
}

export class TextPaginator {
  /**
   * 创建增量分页游标。所有排版参数在创建时标定一次，之后 step() 只做模型推算 + 单页实测。
   * @param firstPageExtraHeight 首页被标题等元素占用的高度（vp），仅首页扣减
   */
  static createSession(ui: UIContext, text: string, widthVp: number, heightVp: number,
    fontSize: number, lineHeightVp: number, firstPageExtraHeight: number = 0,
    fontFamily: string = ''): PaginationSession {
    const safeWidth = Math.max(1, widthVp);
    const safeHeight = Math.max(1, heightVp);
    const extra = firstPageExtraHeight > 0 ? firstPageExtraHeight : 0;
    let density = 1;
    try {
      density = display.getDefaultDisplaySync().densityPixels;
    } catch (e) {
      density = 1;
    }
    if (!(density > 0)) {
      density = 1;
    }
    // 启发式初值：全角字符按一个字号宽，半角取一半，行高用设置值
    const metrics = new PaginationMetrics();
    metrics.maxWidth = safeWidth * density;
    metrics.lineHeight = Math.max(1, lineHeightVp * density);
    metrics.cjkWidth = Math.max(1, fontSize * density);
    metrics.asciiWidth = Math.max(0.5, metrics.cjkWidth * 0.5);
    let utils: MeasureUtils | undefined = undefined;
    try {
      utils = ui.getMeasureUtils();
    } catch (e) {
      utils = undefined;
    }
    if (utils !== undefined) {
      const measurable = TextPaginator.calibrate(utils, safeWidth, fontSize, lineHeightVp, density, metrics,
        fontFamily);
      if (!measurable) {
        // 测高都不可用：退回纯模型推算（不再逐页校验）
        utils = undefined;
      }
    }
    const pageHeightPx = safeHeight * density;
    const firstHeightPx = Math.max(1, safeHeight - extra) * density;
    return new PaginationSession(text, safeWidth, fontSize, lineHeightVp, pageHeightPx,
      firstHeightPx, utils, metrics, fontFamily);
  }

  /** 一次性跑完分页（保持旧接口，供不需要分片的调用方使用） */
  static paginate(ui: UIContext, text: string, widthVp: number, heightVp: number,
    fontSize: number, lineHeight: number, firstPageExtraHeight: number = 0): PaginationResult {
    const session = TextPaginator.createSession(ui, text, widthVp, heightVp, fontSize, lineHeight,
      firstPageExtraHeight);
    let guard = 0;
    while (!session.isFinished() && guard < MAX_PAGE_GUARD) {
      guard++;
      session.step(FULL_STEP_PAGES);
    }
    return session.result();
  }

  /**
   * 标定字宽与行高。返回测高是否可用（决定后续是否做单页校验）。
   * 字宽探针失败时保留启发式值，只影响模型初值精度，不影响正确性。
   */
  private static calibrate(utils: MeasureUtils, widthVp: number, fontSize: number,
    lineHeightVp: number, density: number, metrics: PaginationMetrics,
    fontFamily: string = ''): boolean {
    const rows: string[] = [];
    let charsPerRow = Math.floor(widthVp / Math.max(1, fontSize));
    if (charsPerRow > LINE_PROBE_CHARS) {
      charsPerRow = LINE_PROBE_CHARS;
    }
    if (charsPerRow < 1) {
      charsPerRow = 1;
    }
    let row = '';
    for (let i = 0; i < charsPerRow; i++) {
      row += '国';
    }
    for (let i = 0; i < LINE_PROBE_ROWS; i++) {
      rows.push(row);
    }
    const emPx = Math.max(1, fontSize * density);
    const lineProbe = rows.join('\n');
    const probeHeight = TextPaginator.measureHeight(utils, lineProbe, widthVp, fontSize, lineHeightVp,
      fontFamily);
    let measurable = false;
    if (probeHeight > 0) {
      measurable = true;
      const derivedLineHeight = probeHeight / LINE_PROBE_ROWS;
      const expectedLineHeight = Math.max(1, lineHeightVp * density);
      // 探针意外换行或测量异常时保留设置值，避免行高被放大后每页行数被砍半
      if (derivedLineHeight > expectedLineHeight * 0.7
        && derivedLineHeight < expectedLineHeight * 1.8) {
        metrics.lineHeight = derivedLineHeight;
      }
    }
    let cjkProbe = '';
    for (let i = 0; i < CJK_PROBE_COUNT; i++) {
      cjkProbe += '国';
    }
    const cjkProbeWidth = TextPaginator.measureWidth(utils, cjkProbe, fontSize, lineHeightVp, fontFamily);
    if (cjkProbeWidth > 0) {
      const advance = cjkProbeWidth / CJK_PROBE_COUNT;
      // 只接受合理量级（部分版本无约束测量会返回整行宽度），否则沿用启发式字号宽度
      if (advance > emPx * 0.5 && advance < emPx * 2) {
        metrics.cjkWidth = advance;
      }
    }
    const asciiProbeWidth = TextPaginator.measureWidth(utils, ASCII_PROBE, fontSize, lineHeightVp, fontFamily);
    if (asciiProbeWidth > 0) {
      const advance = asciiProbeWidth / ASCII_PROBE.length;
      if (advance > metrics.cjkWidth * 0.15 && advance < metrics.cjkWidth * 1.2) {
        metrics.asciiWidth = advance;
      }
    }
    if (metrics.cjkWidth <= 0) {
      metrics.cjkWidth = emPx;
    }
    if (metrics.asciiWidth <= 0) {
      metrics.asciiWidth = Math.max(0.5, metrics.cjkWidth * 0.5);
    }
    return measurable;
  }

  /**
   * 按字符宽度模型推算一页的结束位置（不含超出行宽的字符）。
   * 只做纯计算，不触发任何测量。
   */
  static modelPageEnd(text: string, start: number, maxLines: number, metrics: PaginationMetrics): number {
    const maxWidth = metrics.maxWidth > 0 ? metrics.maxWidth : 1;
    const cjkWidth = metrics.cjkWidth > 0 ? metrics.cjkWidth : 1;
    const asciiWidth = metrics.asciiWidth > 0 ? metrics.asciiWidth : cjkWidth * 0.5;
    const length = text.length;
    let lines = 1;
    let width = 0;
    let i = start;
    while (i < length) {
      const code = text.charCodeAt(i);
      if (code === 0x0A) {
        i++;
        width = 0;
        if (i >= length) {
          return i;
        }
        if (lines >= maxLines) {
          // 换行符本身收尾本页最后一行
          return i;
        }
        lines++;
        continue;
      }
      let advance = cjkWidth;
      if (code < 0x80) {
        advance = code === 0x20 ? asciiWidth * 0.5 : asciiWidth;
      }
      if (width + advance > maxWidth && width > 0) {
        if (lines >= maxLines) {
          return i;
        }
        lines++;
        width = 0;
        continue;
      }
      width += advance;
      i++;
    }
    return i;
  }

  /** 测高（px），失败返回 -1 */
  static measureHeight(utils: MeasureUtils, content: string, widthVp: number,
    fontSize: number, lineHeight: number, fontFamily: string = ''): number {
    try {
      const options: MeasureOptions = {
        textContent: content,
        constraintWidth: `${widthVp}vp`,
        fontSize: fontSize,
        lineHeight: lineHeight
      };
      if (fontFamily.length > 0) {
        options.fontFamily = fontFamily;
      }
      const size: SizeOptions = utils.measureTextSize(options);
      let height = 0;
      if (typeof size.height === 'number') {
        height = size.height;
      } else {
        height = Number.parseFloat(String(size.height));
      }
      if (!Number.isFinite(height) || height <= 0) {
        return -1;
      }
      return height;
    } catch (e) {
      return -1;
    }
  }

  /** 测自然宽度（px，不约束换行），失败返回 -1 */
  static measureWidth(utils: MeasureUtils, content: string, fontSize: number,
    lineHeight: number, fontFamily: string = ''): number {
    try {
      const options: MeasureOptions = {
        textContent: content,
        fontSize: fontSize,
        lineHeight: lineHeight
      };
      if (fontFamily.length > 0) {
        options.fontFamily = fontFamily;
      }
      const size: SizeOptions = utils.measureTextSize(options);
      let width = 0;
      if (typeof size.width === 'number') {
        width = size.width;
      } else {
        width = Number.parseFloat(String(size.width));
      }
      if (!Number.isFinite(width) || width <= 0) {
        return -1;
      }
      return width;
    } catch (e) {
      return -1;
    }
  }
}
