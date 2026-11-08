import { Skins } from '../theme/ShelfTheme';
import { CoverStyleMeta, ImageCoverStyle, TextCoverStyle } from '../model/CoverStyle';
import { AppEnvStore } from '../model/AppEnv';
import { AppPaths } from '../utils/AppPaths';
import { FileUtil } from '../utils/FileUtil';

/**
 * App 外观：独立于阅读器设置（settings.json）。
 * 皮肤与封面样式都通过 AppEnv（@ObservedV2 单例）广播，所有使用 ShelfTheme 的组件即时生效。
 */
export class AppAppearance {
  skin: string = Skins.defaultId();
  /** 文本书封面样式（TextCoverStyle 值） */
  textCover: string = TextCoverStyle.SPINE;
  /** 图片书封面样式（ImageCoverStyle 值） */
  imageCover: string = ImageCoverStyle.PHOTO;
}

export class AppAppearanceStore {
  private static path(): string {
    return `${AppPaths.getFilesDir()}/app_appearance.json`;
  }

  /** 每个页面入口都会调 AppBootstrap.init，外观在此注入 AppEnv */
  static init(): void {
    const data = AppAppearanceStore.load();
    const env = AppEnvStore.get();
    env.appSkin = data.skin;
    env.textCover = data.textCover;
    env.imageCover = data.imageCover;
  }

  static load(): AppAppearance {
    const data = new AppAppearance();
    const raw = FileUtil.readText(AppAppearanceStore.path());
    if (raw.length === 0) {
      return data;
    }
    try {
      const parsed = JSON.parse(raw) as AppAppearance;
      data.skin = Skins.normalize(parsed.skin !== undefined ? parsed.skin : Skins.defaultId());
      data.textCover = CoverStyleMeta.normalizeText(
        parsed.textCover !== undefined ? parsed.textCover : TextCoverStyle.SPINE);
      data.imageCover = CoverStyleMeta.normalizeImage(
        parsed.imageCover !== undefined ? parsed.imageCover : ImageCoverStyle.PHOTO);
      return data;
    } catch (e) {
      return data;
    }
  }

  static saveSkin(skin: string): void {
    const data = AppAppearanceStore.load();
    data.skin = Skins.normalize(skin);
    AppAppearanceStore.persist(data);
    AppEnvStore.get().appSkin = data.skin;
  }

  /** 封面样式：文本书与图片书分开存，只改传进来的那一项 */
  static saveCovers(textCover: string, imageCover: string): void {
    const data = AppAppearanceStore.load();
    data.textCover = CoverStyleMeta.normalizeText(textCover);
    data.imageCover = CoverStyleMeta.normalizeImage(imageCover);
    AppAppearanceStore.persist(data);
    const env = AppEnvStore.get();
    env.textCover = data.textCover;
    env.imageCover = data.imageCover;
  }

  private static persist(data: AppAppearance): void {
    FileUtil.writeTextAtomic(AppAppearanceStore.path(), JSON.stringify(data));
  }
}
