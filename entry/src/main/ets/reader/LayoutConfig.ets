/**
 * 排版参数的单点下发结构。
 *
 * 之前分页参数（宽、高、字号、行距、首页标题高度、字体）以六个位置参数在
 * 组件与 TextPaginator 之间传递，任何一处顺序写错都会得到"页边界与显示内容错位"
 * 这种极难定位的问题。收敛成一个结构后：
 *   - 传参不会错位；
 *   - key() 直接作为分页缓存的失效键，参数一变缓存必然失效；
 *   - 测量（measureTextSize）与真实渲染都用这一份值，避免测量约束与 Text 属性不一致。
 */
export class LayoutConfig {
  /** 正文字号（vp） */
  fontSize: number = 18;
  /** 行高（vp），= fontSize * lineHeightRatio */
  lineHeight: number = 30.6;
  /** 内容区宽（vp，已扣掉左右页边距） */
  width: number = 0;
  /** 内容区高（vp，已扣掉页眉页脚与上下留白） */
  height: number = 0;
  /** 仅首页需要扣减的额外高度（章标题等），其余页为 0 */
  firstPageExtraHeight: number = 0;
  /** 正文字体，空串表示系统默认 */
  fontFamily: string = '';

  static of(fontSize: number, lineHeight: number, width: number, height: number,
    firstPageExtraHeight: number, fontFamily: string): LayoutConfig {
    const config = new LayoutConfig();
    config.fontSize = fontSize;
    config.lineHeight = lineHeight;
    config.width = width;
    config.height = height;
    config.firstPageExtraHeight = firstPageExtraHeight > 0 ? firstPageExtraHeight : 0;
    config.fontFamily = fontFamily;
    return config;
  }

  /** 分页缓存键：任一参数变化都会得到不同字符串 */
  key(): string {
    return `${Math.round(this.width)}x${Math.round(this.height)}|${this.fontSize}|${this.lineHeight}|` +
      `${Math.round(this.firstPageExtraHeight)}|${this.fontFamily}`;
  }

  /** 正文可用高度（已扣首页额外高度） */
  bodyHeight(): number {
    return Math.max(1, this.height - this.firstPageExtraHeight);
  }
}
