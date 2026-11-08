import { ShelfThemeColors } from './ThemeColors';

/** 皮肤取色函数：在 ThemeBase 基底上覆盖本主题的颜色 */
export type SkinPainter = (colors: ShelfThemeColors, dark: boolean) => void;

/**
 * 一套 App 主题（皮肤）：id、显示名、选择弹层的色块、配色覆盖。
 *
 * 一个主题的「全部颜色」都写在它自己的 paint() 里（见 theme/skins/*.ets），
 * 主题文件之外不再出现任何主题相关的颜色字面量。
 */
export class SkinTheme {
  readonly id: string;
  readonly label: string;
  /** 「我的 - App 主题」弹层里的色块预览色（各皮肤亮色模式下的强调色） */
  readonly swatch: string;
  private readonly painter: SkinPainter;

  constructor(id: string, label: string, swatch: string, painter: SkinPainter) {
    this.id = id;
    this.label = label;
    this.swatch = swatch;
    this.painter = painter;
  }

  paint(colors: ShelfThemeColors, dark: boolean): void {
    this.painter(colors, dark);
  }
}
