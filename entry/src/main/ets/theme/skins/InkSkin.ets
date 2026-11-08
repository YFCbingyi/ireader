import { ShelfThemeColors } from '../ThemeColors';
import { SkinTheme } from '../SkinTheme';

/**
 * 深黑：中性灰强调色 + 灰底；封面为中性炭黑 → 石墨灰，不带蓝紫。
 */
export const INK_SKIN: SkinTheme = new SkinTheme('ink', '深黑', '#2B2B2B',
  (colors: ShelfThemeColors, dark: boolean): void => {
    if (dark) {
      colors.bg = '#0E0E0E';
      colors.barBg = '#CC0E0E0E';
      colors.tabBarBg = '#CC181818';
      colors.surface = '#1A1A1A';
      colors.surfaceAlt = '#202020';
      colors.surfaceSink = '#282828';
      colors.accent = '#E6E6E6';
      colors.accentText = '#111111';
      colors.accentSoft = '#33E6E6E6';
      colors.chipBg = '#262626';
      colors.chipText = '#E0E0E0';
      colors.divider = '#303030';
      colors.border = '#333333';
      colors.tabIdle = '#8E8E8E';
      colors.ink = '#E0E0E0';
      colors.accentShadow = '#33000000';
    } else {
      colors.bg = '#F4F4F4';
      colors.barBg = '#CCF4F4F4';
      colors.tabBarBg = '#CCFFFFFF';
      colors.surfaceAlt = '#FAFAFA';
      colors.surfaceSink = '#E9E9E9';
      colors.text = '#1F1F1F';
      colors.accent = '#2B2B2B';
      colors.accentText = '#FFFFFF';
      colors.accentSoft = '#332B2B2B';
      colors.chipBg = '#E8E8E8';
      colors.chipText = '#333333';
      colors.divider = '#E4E4E4';
      colors.border = '#DCDCDC';
      colors.tabIdle = '#6E6E6E';
      colors.ink = '#2B2B2B';
      colors.accentShadow = '#1A2B2B2B';
    }
    colors.coverTextStart = dark ? '#1F1F1F' : '#2B2B2B';
    colors.coverTextEnd = dark ? '#3A3A3A' : '#4A4A4A';
    colors.coverImageStart = dark ? '#24262A' : '#303338';
    colors.coverImageEnd = dark ? '#484C52' : '#5B5F66';
    colors.coverInk = '#FFFFFF';
    colors.coverInkSoft = '#33FFFFFF';
    colors.coverInkLine = '#66FFFFFF';
  });
