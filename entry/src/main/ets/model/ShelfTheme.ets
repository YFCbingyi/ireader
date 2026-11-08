/**
 * 书库首页（书架 / 发现 / 我的 / 分组 / 书卡）色板。
 *
 * 两套正交维度：
 *   1) systemColorMode 决定亮 / 暗基底（light() / dark()）；
 *   2) AppSkin 决定皮肤风格（金棕 / 喜庆红 / 深黑 / 天蓝），只覆盖语义色。
 * 阅读页正文主题是另一套 ReaderThemeColors，不受这里影响。
 * 字段命名按语义划分，页面里不要再直接写颜色字面量。
 */
export enum AppSkin {
  GOLD = 'gold',
  FESTIVE = 'festive',
  INK = 'ink',
  SKY = 'sky'
}

export class AppSkinMeta {
  static options(): string[] {
    return [AppSkin.GOLD, AppSkin.FESTIVE, AppSkin.INK, AppSkin.SKY];
  }

  static normalize(raw: string): string {
    if (raw === AppSkin.FESTIVE || raw === AppSkin.INK || raw === AppSkin.SKY) {
      return raw;
    }
    return AppSkin.GOLD;
  }

  static label(skin: string): string {
    if (skin === AppSkin.FESTIVE) {
      return '喜庆红';
    }
    if (skin === AppSkin.INK) {
      return '深黑';
    }
    if (skin === AppSkin.SKY) {
      return '天蓝';
    }
    return '金棕';
  }

  /** 选择弹层里的色块预览色（各皮肤亮色模式下的强调色） */
  static swatch(skin: string): string {
    if (skin === AppSkin.FESTIVE) {
      return '#C0392B';
    }
    if (skin === AppSkin.INK) {
      return '#2B2B2B';
    }
    if (skin === AppSkin.SKY) {
      return '#2F6BD8';
    }
    return '#8B5E3C';
  }
}

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
  // 书卡封面（渐变端点与封面上的文字/描边）；默认值 = 金棕皮肤的暖棕 / 深棕
  coverTextStart: string = '#8B5E3C';
  coverTextEnd: string = '#B8860B';
  coverImageStart: string = '#6B4A28';
  coverImageEnd: string = '#A87C33';
  coverInk: string = '#FFF8ED';
  coverInkSoft: string = '#33FFF8ED';
  coverInkLine: string = '#66FFF8ED';
}

export class ShelfTheme {
  static resolve(systemDark: boolean, skin: string): ShelfThemeColors {
    const colors = systemDark ? ShelfTheme.dark() : ShelfTheme.light();
    const normalized = AppSkinMeta.normalize(skin);
    ShelfTheme.applySkin(colors, normalized, systemDark);
    ShelfTheme.applyCover(colors, normalized, systemDark);
    colors.key = `${normalized}_${systemDark ? 'dark' : 'light'}`;
    return colors;
  }

  /** 四套皮肤各自的封面美术；金棕保留原渐变，其余皮肤在深色模式下略压暗 */
  private static applyCover(colors: ShelfThemeColors, skin: string, dark: boolean): void {
    if (skin === AppSkin.GOLD) {
      // 金棕：文本封面保持暖棕 → 古金
      colors.coverTextStart = '#8B5E3C';
      colors.coverTextEnd = '#B8860B';
      // 图片封面取同色系：深棕 → 铜金，压深一档与文本封面区分
      colors.coverImageStart = dark ? '#54391E' : '#6B4A28';
      colors.coverImageEnd = dark ? '#8A6726' : '#A87C33';
      colors.coverInk = '#FFF8ED';
      colors.coverInkSoft = '#33FFF8ED';
      colors.coverInkLine = '#66FFF8ED';
      return;
    }
    if (skin === AppSkin.FESTIVE) {
      if (dark) {
        colors.coverTextStart = '#8E231D';
        colors.coverTextEnd = '#C4533A';
        colors.coverImageStart = '#6E2A22';
        colors.coverImageEnd = '#A2432C';
      } else {
        colors.coverTextStart = '#A62B22';
        colors.coverTextEnd = '#D9643C';
        colors.coverImageStart = '#8E3126';
        colors.coverImageEnd = '#C4553A';
      }
      colors.coverInk = '#FFF6F0';
      colors.coverInkSoft = '#33FFF6F0';
      colors.coverInkLine = '#66FFF6F0';
      return;
    }
    if (skin === AppSkin.INK) {
      if (dark) {
        colors.coverTextStart = '#1F1F1F';
        colors.coverTextEnd = '#3A3A3A';
        colors.coverImageStart = '#24262A';
        colors.coverImageEnd = '#484C52';
      } else {
        colors.coverTextStart = '#2B2B2B';
        colors.coverTextEnd = '#4A4A4A';
        colors.coverImageStart = '#303338';
        colors.coverImageEnd = '#5B5F66';
      }
      colors.coverInk = '#FFFFFF';
      colors.coverInkSoft = '#33FFFFFF';
      colors.coverInkLine = '#66FFFFFF';
      return;
    }
    // 天蓝
    if (dark) {
      colors.coverTextStart = '#2A55AC';
      colors.coverTextEnd = '#3F86D0';
      colors.coverImageStart = '#244A7C';
      colors.coverImageEnd = '#3D7CB4';
    } else {
      colors.coverTextStart = '#2F6BD8';
      colors.coverTextEnd = '#4F9BE8';
      colors.coverImageStart = '#2A5C97';
      colors.coverImageEnd = '#4F94D2';
    }
    colors.coverInk = '#FFFFFF';
    colors.coverInkSoft = '#33FFFFFF';
    colors.coverInkLine = '#66FFFFFF';
  }

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

  /** 金棕 = 基底零覆盖；其余皮肤只改语义色，danger / success / 遮罩等保持通用 */
  private static applySkin(colors: ShelfThemeColors, skin: string, dark: boolean): void {
    if (skin === AppSkin.GOLD) {
      return;
    }
    if (skin === AppSkin.FESTIVE) {
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
      return;
    }
    if (skin === AppSkin.INK) {
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
      return;
    }
    // 天蓝
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
  }
}
