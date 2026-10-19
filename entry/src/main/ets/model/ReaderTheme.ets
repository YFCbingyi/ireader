export enum ReadingTheme {
  WHITE = 'white',
  EYE = 'eye',
  DARK = 'dark',
  SYSTEM = 'system'
}

export class ReaderThemeColors {
  bg: string = '#F7F3E8';
  text: string = '#2B2B2B';
  subText: string = '#8C8C8C';
  barBg: string = '#E6F7F3E8';
  barText: string = '#2B2B2B';
  accent: string = '#8B5E3C';
  accentText: string = '#FFF8ED';
  panelBg: string = '#FDFBF4';
  panelText: string = '#2B2B2B';
  panelSubText: string = '#8C8C8C';
  divider: string = '#EFE7D8';
  chipBg: string = '#EFE7D8';
  chipText: string = '#5C4A32';
  selectedItemBg: string = '#F0E4D0';
  danger: string = '#B85C5C';
}

export class ReaderTheme {
  static resolve(theme: ReadingTheme, systemDark: boolean): ReaderThemeColors {
    if (theme === ReadingTheme.DARK) {
      return ReaderTheme.dark();
    }
    if (theme === ReadingTheme.WHITE) {
      return ReaderTheme.white();
    }
    if (theme === ReadingTheme.SYSTEM) {
      return systemDark ? ReaderTheme.dark() : ReaderTheme.white();
    }
    return ReaderTheme.eye();
  }

  static eye(): ReaderThemeColors {
    const colors = new ReaderThemeColors();
    colors.bg = '#CBE3D1';
    colors.text = '#2E3A32';
    colors.subText = '#5F7566';
    colors.barBg = '#E6CBE3D1';
    colors.barText = '#2E3A32';
    colors.accent = '#3F6B4E';
    colors.accentText = '#F2FBF6';
    colors.panelBg = '#F2FBF6';
    colors.panelText = '#2E3A32';
    colors.panelSubText = '#5F7566';
    colors.divider = '#B7D2BE';
    colors.chipBg = '#BBD7C3';
    colors.chipText = '#3A4A3F';
    colors.selectedItemBg = '#B3D2BC';
    colors.danger = '#A8474B';
    return colors;
  }

  static white(): ReaderThemeColors {
    const colors = new ReaderThemeColors();
    colors.bg = '#FFFFFF';
    colors.text = '#2B2B2B';
    colors.subText = '#8C8C8C';
    colors.barBg = '#F2FFFFFF';
    colors.barText = '#2B2B2B';
    colors.accent = '#8B5E3C';
    colors.accentText = '#FFF8ED';
    colors.panelBg = '#FFFFFF';
    colors.panelText = '#2B2B2B';
    colors.panelSubText = '#8C8C8C';
    colors.divider = '#EDEDED';
    colors.chipBg = '#F3F3F3';
    colors.chipText = '#5C4A32';
    colors.selectedItemBg = '#F5EFE6';
    colors.danger = '#B85C5C';
    return colors;
  }

  static dark(): ReaderThemeColors {
    const colors = new ReaderThemeColors();
    colors.bg = '#121212';
    colors.text = '#C9C9C9';
    colors.subText = '#8A8A8A';
    colors.barBg = '#E61C1C1C';
    colors.barText = '#E8E8E8';
    colors.accent = '#C9A227';
    colors.accentText = '#141414';
    colors.panelBg = '#1C1C1C';
    colors.panelText = '#E0E0E0';
    colors.panelSubText = '#8F8F8F';
    colors.divider = '#2E2E2E';
    colors.chipBg = '#2A2A2A';
    colors.chipText = '#D5D5D5';
    colors.selectedItemBg = '#2A2418';
    colors.danger = '#D97A7A';
    return colors;
  }

  static label(theme: ReadingTheme): string {
    if (theme === ReadingTheme.WHITE) {
      return '白色';
    }
    if (theme === ReadingTheme.DARK) {
      return '深色';
    }
    if (theme === ReadingTheme.SYSTEM) {
      return '随系统';
    }
    return '护眼';
  }
}
