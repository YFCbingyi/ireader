/**
 * 书库首页（书架 / 发现 / 我的）色板。
 *
 * 浅色沿用原有米色纸感配色；深色为同一套语义的暗夜版本，
 * 主色（棕）在深底上提亮，保证小字号与图标仍有足够对比。
 * 字段命名按语义划分，页面里不要再直接写颜色字面量。
 */
export class ShelfThemeColors {
  // 页面与浮层底
  bg: string = '#F7F4EE';
  barBg: string = '#CCF7F4EE';
  tabBarBg: string = '#CCFFFDF7';
  surface: string = '#FFFFFF';
  surfaceAlt: string = '#FBF8F2';
  surfaceSink: string = '#EFEAE0';
  // 文字
  text: string = '#2B2B2B';
  subText: string = '#8C8C8C';
  subtleText: string = '#A8A8A8';
  tabIdle: string = '#8A7A64';
  // 主色
  accent: string = '#8B5E3C';
  accentText: string = '#FFF8ED';
  accentSoft: string = '#338B5E3C';
  // 胶囊 / 分隔 / 描边
  chipBg: string = '#EFE7D8';
  chipText: string = '#5C4A32';
  divider: string = '#EFE7D8';
  border: string = '#E6E0D4';
  // 图标笔画
  ink: string = '#3A3A3A';
  // 遮罩
  overlay: string = '#99000000';
  scrim: string = '#4D000000';
  // 语义色
  danger: string = '#C4553C';
  success: string = '#2F7D5A';
  disabled: string = '#B9C4BC';
  // 阴影
  shadow: string = '#33000000';
  accentShadow: string = '#1A8B5E3C';
}

export class ShelfTheme {
  static resolve(systemDark: boolean): ShelfThemeColors {
    return systemDark ? ShelfTheme.dark() : ShelfTheme.light();
  }

  static light(): ShelfThemeColors {
    return new ShelfThemeColors();
  }

  static dark(): ShelfThemeColors {
    const colors = new ShelfThemeColors();
    colors.bg = '#111110';
    colors.barBg = '#CC181816';
    colors.tabBarBg = '#CC201E1A';
    colors.surface = '#1C1B17';
    colors.surfaceAlt = '#22211D';
    colors.surfaceSink = '#2A2823';
    colors.text = '#E8E4DB';
    colors.subText = '#9A948B';
    colors.subtleText = '#7C766D';
    colors.tabIdle = '#8A8378';
    colors.accent = '#C08B5C';
    colors.accentText = '#141210';
    colors.accentSoft = '#33C08B5C';
    colors.chipBg = '#2A2823';
    colors.chipText = '#D8CFC0';
    colors.divider = '#332F28';
    colors.border = '#34302A';
    colors.ink = '#D8CFC0';
    colors.overlay = '#B3000000';
    colors.scrim = '#73000000';
    colors.danger = '#E08A7A';
    colors.success = '#6FC08C';
    colors.disabled = '#4A463F';
    colors.shadow = '#66000000';
    colors.accentShadow = '#33000000';
    return colors;
  }
}
