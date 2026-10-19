import { display, MeasureUtils, UIContext } from '@kit.ArkUI';

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

const PAGE_BREAK_BACK_LINES = 1;

export class TextPaginator {
  static paginate(ui: UIContext, text: string, widthVp: number, heightVp: number,
    fontSize: number, lineHeight: number): PaginationResult {
    const result = new PaginationResult();
    if (text.length === 0) {
      result.ranges.push(PageRange.of(0, 0));
      result.pageStarts.push(0);
      return result;
    }
    const safeWidth = Math.max(1, widthVp);
    const safeHeight = Math.max(1, heightVp);
    const utils = ui.getMeasureUtils();
    let density = 1;
    try {
      density = display.getDefaultDisplaySync().densityPixels;
    } catch (e) {
      density = 1;
    }
    const pageHeightPx = safeHeight * density;
    const probe = TextPaginator.measureHeight(utils, '测试文本', safeWidth, fontSize, lineHeight);
    if (probe <= 0) {
      return TextPaginator.fallback(text, safeWidth, safeHeight, fontSize, lineHeight);
    }

    const charsPerLine = Math.max(1, Math.floor(safeWidth / Math.max(1, fontSize)));
    const maxBack = charsPerLine * PAGE_BREAK_BACK_LINES;

    let start = 0;
    let guard = 0;
    while (start < text.length && guard < 20000) {
      guard++;
      let maxEnd = Math.min(text.length, start + 2500);
      let best = TextPaginator.measureEnd(utils, text, start, maxEnd, safeWidth, fontSize,
        lineHeight, pageHeightPx);
      if (best >= maxEnd && maxEnd < text.length) {
        maxEnd = Math.min(text.length, start + 8000);
        best = TextPaginator.measureEnd(utils, text, start, maxEnd, safeWidth, fontSize,
          lineHeight, pageHeightPx);
      }
      if (best <= start) {
        best = start + 1;
      }
      best = TextPaginator.preferNewline(text, start, best, maxBack);
      result.ranges.push(PageRange.of(start, best));
      result.pageStarts.push(start);
      start = best;
    }
    if (result.ranges.length === 0) {
      result.ranges.push(PageRange.of(0, 0));
      result.pageStarts.push(0);
    }
    return result;
  }

  private static measureEnd(utils: MeasureUtils, text: string, start: number, maxEnd: number,
    widthVp: number, fontSize: number, lineHeight: number, pageHeightPx: number): number {
    let low = start + 1;
    let high = maxEnd;
    let best = start + 1;
    while (low <= high) {
      const mid = Math.floor((low + high) / 2);
      const height = TextPaginator.measureHeight(utils, text.substring(start, mid), widthVp,
        fontSize, lineHeight);
      if (height > 0 && height <= pageHeightPx) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return best;
  }

  private static measureHeight(utils: MeasureUtils, content: string, widthVp: number,
    fontSize: number, lineHeight: number): number {
    try {
      const size: SizeOptions = utils.measureTextSize({
        textContent: content,
        constraintWidth: `${widthVp}vp`,
        fontSize: fontSize,
        lineHeight: lineHeight
      });
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

  private static preferNewline(text: string, start: number, best: number, maxBack: number): number {
    const floor = Math.max(start + 1, best - maxBack);
    for (let i = best - 1; i >= floor; i--) {
      if (text.charAt(i) === '\n') {
        return i + 1;
      }
    }
    return best;
  }

  private static fallback(text: string, widthVp: number, heightVp: number,
    fontSize: number, lineHeight: number): PaginationResult {
    const result = new PaginationResult();
    const charsPerLine = Math.max(1, Math.floor(widthVp / Math.max(1, fontSize)));
    const linesPerPage = Math.max(1, Math.floor(heightVp / Math.max(1, lineHeight)));
    const pageChars = Math.max(1, charsPerLine * linesPerPage);
    let start = 0;
    while (start < text.length) {
      let end = Math.min(text.length, start + pageChars);
      end = TextPaginator.preferNewline(text, start, end, charsPerLine * PAGE_BREAK_BACK_LINES);
      if (end <= start) {
        end = start + 1;
      }
      result.ranges.push(PageRange.of(start, end));
      result.pageStarts.push(start);
      start = end;
    }
    if (result.ranges.length === 0) {
      result.ranges.push(PageRange.of(0, 0));
      result.pageStarts.push(0);
    }
    return result;
  }
}
