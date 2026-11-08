/**
 * 书卡封面样式。文本书与图片书各一套，互不影响，都随 App 皮肤取色。
 *
 * 所有样式都是纯矢量绘制（除「首图封面」读一张缩略图），不引入图片资源，
 * 保证书架网格滚动时不掉帧。
 */
export enum TextCoverStyle {
  /** 经典书卷：渐变底 + 细内框 + 居中书名 */
  CLASSIC = 'classic',
  /** 精装书脊：左侧深色书脊 + 浅纸面 + 左对齐书名 */
  SPINE = 'spine',
  /** 排版大字：大字号书名 + 大量留白 */
  TYPE = 'type',
  /** 文人竖排：竖排书名 + 朱红印章 */
  INK = 'ink'
}

export enum ImageCoverStyle {
  /** 首图封面：拿第一张图片当底图，书名压左下 */
  PHOTO = 'photo',
  /** 胶片条：胶片齿孔装饰 + 大号「图」字水印 */
  FILM = 'film'
}

export class CoverStyleMeta {
  static textOptions(): string[] {
    return [TextCoverStyle.SPINE, TextCoverStyle.TYPE, TextCoverStyle.INK, TextCoverStyle.CLASSIC];
  }

  static imageOptions(): string[] {
    return [ImageCoverStyle.PHOTO, ImageCoverStyle.FILM];
  }

  static normalizeText(raw: string): string {
    if (raw === TextCoverStyle.SPINE || raw === TextCoverStyle.TYPE || raw === TextCoverStyle.INK ||
      raw === TextCoverStyle.CLASSIC) {
      return raw;
    }
    return TextCoverStyle.SPINE;
  }

  static normalizeImage(raw: string): string {
    if (raw === ImageCoverStyle.FILM) {
      return raw;
    }
    return ImageCoverStyle.PHOTO;
  }

  static textLabel(style: string): string {
    if (style === TextCoverStyle.SPINE) {
      return '精装书脊';
    }
    if (style === TextCoverStyle.TYPE) {
      return '排版大字';
    }
    if (style === TextCoverStyle.INK) {
      return '文人竖排';
    }
    return '经典书卷';
  }

  static imageLabel(style: string): string {
    if (style === ImageCoverStyle.FILM) {
      return '胶片条';
    }
    return '首图封面';
  }
}
