import { ShelfThemeColors } from '../ThemeColors';
import { SkinTheme } from '../SkinTheme';

/**
 * 金棕（默认皮肤）：米白纸底 + 暖棕强调色。
 *
 * 页面配色就是 ThemeBase 里的基底本身，所以这里只声明「封面美术」：
 * 文本书封面 暖棕 → 古金，图片书封面 深棕 → 铜金（同色系压深一档做区分）。
 */
export const GOLD_SKIN: SkinTheme = new SkinTheme('gold', '金棕', '#8B5E3C',
  (colors: ShelfThemeColors, dark: boolean): void => {
    colors.coverTextStart = '#8B5E3C';
    colors.coverTextEnd = '#B8860B';
    colors.coverImageStart = dark ? '#54391E' : '#6B4A28';
    colors.coverImageEnd = dark ? '#8A6726' : '#A87C33';
    colors.coverInk = '#FFF8ED';
    colors.coverInkSoft = '#33FFF8ED';
    colors.coverInkLine = '#66FFF8ED';
  });
