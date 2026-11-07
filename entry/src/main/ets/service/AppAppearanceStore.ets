import { AppSkin, AppSkinMeta } from '../model/ShelfTheme';
import { AppPaths } from '../utils/AppPaths';
import { FileUtil } from '../utils/FileUtil';

/**
 * App 外观皮肤：独立于阅读器设置（settings.json）。
 * appSkin 通过 AppStorage 广播，所有使用 ShelfTheme 的组件即时换色。
 */
export class AppAppearance {
  skin: string = AppSkin.GOLD;
}

export class AppAppearanceStore {
  private static path(): string {
    return `${AppPaths.getFilesDir()}/app_appearance.json`;
  }

  /** 每个页面入口都会调 AppBootstrap.init，皮肤在此注入 AppStorage */
  static init(): void {
    AppStorage.setOrCreate<string>('appSkin', AppAppearanceStore.current());
  }

  static current(): string {
    const raw = FileUtil.readText(AppAppearanceStore.path());
    if (raw.length === 0) {
      return AppSkin.GOLD;
    }
    try {
      const parsed = JSON.parse(raw) as AppAppearance;
      return AppSkinMeta.normalize(parsed.skin !== undefined ? parsed.skin : AppSkin.GOLD);
    } catch (e) {
      return AppSkin.GOLD;
    }
  }

  static save(skin: string): void {
    const normalized = AppSkinMeta.normalize(skin);
    const data = new AppAppearance();
    data.skin = normalized;
    FileUtil.writeTextAtomic(AppAppearanceStore.path(), JSON.stringify(data));
    AppStorage.setOrCreate<string>('appSkin', normalized);
  }
}
