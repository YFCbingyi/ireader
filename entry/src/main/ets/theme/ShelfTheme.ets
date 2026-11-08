import { ShelfThemeColors } from './ThemeColors';
import { Skins } from './skins/Skins';

export { ShelfThemeColors };
export { SkinTheme } from './SkinTheme';
export { Skins };

/**
 * 主题取色门面：组件只调这三个方法，颜色本身全在 theme/ 文件夹里。
 *
 * 两套正交维度：
 *   1) 系统深浅色 → 亮 / 暗基底（ThemeBase）；
 *   2) 皮肤 id → 在基底上覆盖主题色（theme/skins/*.ets）。
 */
export class ShelfTheme {
  /** 默认皮肤的亮色板：组件的 @Local palette 初值 */
  static light(): ShelfThemeColors {
    return Skins.light();
  }

  /** 默认皮肤的暗色板 */
  static dark(): ShelfThemeColors {
    return Skins.dark();
  }

  /** 按系统深浅色 + 皮肤 id 取完整色板 */
  static resolve(systemDark: boolean, skin: string): ShelfThemeColors {
    return Skins.palette(systemDark, skin);
  }
}
