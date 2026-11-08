import { ShelfThemeColors } from '../ThemeColors';
import { SkinTheme } from '../SkinTheme';

/**
 * 天蓝：蓝色强调色 + 冷白底；封面为蓝 → 浅蓝。
 */
export const SKY_SKIN: SkinTheme = new SkinTheme('sky', '天蓝', '#2F6BD8',
  (colors: ShelfThemeColors, dark: boolean): void => {
    if (dark) {
      colors.bg = '#0E1420';
      colors.barBg = '#CC0E1420';
      colors.tabBarBg = '#CC151E2C';
      colors.surface = '#161E2C';
      colors.surfaceAlt = '#1C2636';
      colors.surfaceSink = '#243044';
      colors.accent = '#7FB0FF';
      colors.accentText = '#0E1420';
      colors.accentSoft = '#337FB0FF';
      colors.chipBg = '#243044';
      colors.chipText = '#D3E2FA';
      colors.divider = '#2C3A50';
      colors.border = '#33435C';
      colors.tabIdle = '#8CA4C4';
      colors.ink = '#D3E2FA';
      colors.accentShadow = '#33000000';
    } else {
      colors.bg = '#F2F7FF';
      colors.barBg = '#CCF2F7FF';
      colors.tabBarBg = '#CCF8FBFF';
      colors.surfaceAlt = '#F7FAFF';
      colors.surfaceSink = '#E3EDFA';
      colors.accent = '#2F6BD8';
      colors.accentText = '#FFFFFF';
      colors.accentSoft = '#332F6BD8';
      colors.chipBg = '#DEEAFB';
      colors.chipText = '#284E96';
      colors.divider = '#DCE8F8';
      colors.border = '#D3E2F5';
      colors.tabIdle = '#5C7BA8';
      colors.ink = '#2A3A55';
      colors.accentShadow = '#1A2F6BD8';
    }
    colors.coverTextStart = dark ? '#2A55AC' : '#2F6BD8';
    colors.coverTextEnd = dark ? '#3F86D0' : '#4F9BE8';
    colors.coverImageStart = dark ? '#244A7C' : '#2A5C97';
    colors.coverImageEnd = dark ? '#3D7CB4' : '#4F94D2';
    colors.coverInk = '#FFFFFF';
    colors.coverInkSoft = '#33FFFFFF';
    colors.coverInkLine = '#66FFFFFF';
  });
