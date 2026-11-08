import { ShelfThemeColors, ThemeBase } from '../ThemeColors';
import { SkinTheme } from '../SkinTheme';
import { GOLD_SKIN } from './GoldSkin';
import { FESTIVE_SKIN } from './FestiveSkin';
import { INK_SKIN } from './InkSkin';
import { SKY_SKIN } from './SkySkin';

/**
 * 主题注册表 —— 增删主题只动这里和 skins/ 下的文件：
 *   新增：照 FestiveSkin.ets 写一个 XxxSkin.ets，再把它的 SkinTheme 加进下面的数组；
 *   删除：删掉数组里那一行（再删掉对应文件）。
 * 「我的 - App 主题」弹层、取色、持久化归一都会自动跟随，不需要改别处。
 */
const SKINS: SkinTheme[] = [GOLD_SKIN, FESTIVE_SKIN, INK_SKIN, SKY_SKIN];

export class Skins {
  static all(): SkinTheme[] {
    return SKINS;
  }

  /** 默认皮肤（数组第一个）：持久化里没存过值时用它 */
  static defaultId(): string {
    return SKINS[0].id;
  }

  /** 弹层里的主题顺序 */
  static options(): string[] {
    return SKINS.map((skin: SkinTheme): string => skin.id);
  }

  static find(id: string): SkinTheme {
    for (let i = 0; i < SKINS.length; i++) {
      if (SKINS[i].id === id) {
        return SKINS[i];
      }
    }
    return SKINS[0];
  }

  /** 存档里的旧值 / 已删除的主题，一律归一到默认皮肤 */
  static normalize(id: string): string {
    return Skins.find(id).id;
  }

  static label(id: string): string {
    return Skins.find(id).label;
  }

  /** 弹层色块用的预览色 */
  static swatch(id: string): string {
    return Skins.find(id).swatch;
  }

  /** 默认皮肤的亮 / 暗色板：组件 @Local palette 的初值 */
  static light(): ShelfThemeColors {
    return Skins.palette(false, Skins.defaultId());
  }

  static dark(): ShelfThemeColors {
    return Skins.palette(true, Skins.defaultId());
  }

  /** 按亮暗 + 皮肤 id 算出完整色板 */
  static palette(dark: boolean, id: string): ShelfThemeColors {
    const theme = Skins.find(id);
    const colors = dark ? ThemeBase.dark() : ThemeBase.light();
    theme.paint(colors, dark);
    colors.key = `${theme.id}_${dark ? 'dark' : 'light'}`;
    return colors;
  }
}
