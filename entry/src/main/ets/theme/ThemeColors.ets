/**
 * 书库外壳（书架 / 发现 / 我的 / 分组 / 书卡）的语义色板。
 *
 * 只描述「字段用途 + 基底配色」，具体皮肤的颜色在 theme/skins/ 下一个皮肤一个文件。
 * 字段默认值 = 金棕皮肤的亮色，作为组件初始化时的兜底
 * （组件的 @Local palette 初值统一走 ShelfTheme.light()）。
 */
export class ShelfThemeColors {
  /** 皮肤 + 亮暗，供组件判断配色是否真的变化（换皮肤时 bg 可能不变） */
  key: string = 'gold_light';
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
  // 书卡封面：文本书封面渐变（文本封面）与图片书封面渐变，另有封面上的文字 / 描边
  coverTextStart: string = '#8B5E3C';
  coverTextEnd: string = '#B8860B';
  coverImageStart: string = '#6B4A28';
  coverImageEnd: string = '#A87C33';
  coverInk: string = '#FFF8ED';
  coverInkSoft: string = '#33FFF8ED';
  coverInkLine: string = '#66FFF8ED';
}

/**
 * 亮 / 暗两套基底（= 金棕的配色）。
 * 皮肤在自己的 paint() 里只覆盖需要改的字段；不会覆盖的字段就沿用基底。
 */
export class ThemeBase {
  static light(): ShelfThemeColors {
    const colors = new ShelfThemeColors();
    colors.key = 'gold_light';
    return colors;
  }

  static dark(): ShelfThemeColors {
    const colors = new ShelfThemeColors();
    colors.key = 'gold_dark';
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
