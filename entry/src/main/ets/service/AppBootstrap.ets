import { common } from '@kit.AbilityKit';
import { AppPaths } from '../utils/AppPaths';
import { AppAppearanceStore } from './AppAppearanceStore';
import { LibraryStore } from './LibraryStore';

/**
 * 页面入口的统一初始化：sandbox 路径单例 + 数据目录创建。
 * 每个页面入口都必须调用一次，漏调会让所有 store 写到 /undefined/... 下。
 * 放在 service 层而不是 utils，避免 utils 反向依赖 service。
 */
export class AppBootstrap {
  static init(context: common.UIAbilityContext): void {
    AppPaths.init(context.filesDir);
    LibraryStore.init();
    AppAppearanceStore.init();
  }
}
