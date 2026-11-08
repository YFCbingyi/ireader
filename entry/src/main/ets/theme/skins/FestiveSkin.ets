import { ShelfThemeColors } from '../ThemeColors';
import { SkinTheme } from '../SkinTheme';

/**
 * 喜庆红：正红强调色 + 暖粉底；封面取朱红 → 橘红。
 */
export const FESTIVE_SKIN: SkinTheme = new SkinTheme('festive', '喜庆红', '#C0392B',
  (colors: ShelfThemeColors, dark: boolean): void => {
    if (dark) {
      colors.bg = '#1A1210';
      colors.barBg = '#CC1A1210';
      colors.tabBarBg = '#CC241815';
      colors.surface = '#241815';
      colors.surfaceAlt = '#2C1D19';
      colors.surfaceSink = '#3A2621';
      colors.accent = '#E57368';
      colors.accentText = '#1A1210';
      colors.accentSoft = '#33E57368';
      colors.chipBg = '#3A2621';
      colors.chipText = '#F0D6D0';
      colors.divider = '#422E28';
      colors.border = '#4A322B';
      colors.tabIdle = '#B08A80';
      colors.ink = '#F0D6D0';
      colors.accentShadow = '#33000000';
    } else {
      colors.bg = '#FFF7F3';
      colors.barBg = '#CCFFF7F3';
      colors.tabBarBg = '#CCFFF9F5';
      colors.surfaceAlt = '#FFF9F5';
      colors.surfaceSink = '#F7E7E0';
      colors.accent = '#C0392B';
      colors.accentText = '#FFF6F0';
      colors.accentSoft = '#33C0392B';
      colors.chipBg = '#F7E0DA';
      colors.chipText = '#8C342A';
      colors.divider = '#F3DED7';
      colors.border = '#EED3CA';
      colors.tabIdle = '#A85E52';
      colors.ink = '#3A2B28';
      colors.accentShadow = '#1AC0392B';
    }
    colors.coverTextStart = dark ? '#8E231D' : '#A62B22';
    colors.coverTextEnd = dark ? '#C4533A' : '#D9643C';
    colors.coverImageStart = dark ? '#6E2A22' : '#8E3126';
    colors.coverImageEnd = dark ? '#A2432C' : '#C4553A';
    colors.coverInk = '#FFF6F0';
    colors.coverInkSoft = '#33FFF6F0';
    colors.coverInkLine = '#66FFF6F0';
  });
