import { ConfigurationConstant } from '@kit.AbilityKit';
import { ImageCoverStyle, TextCoverStyle } from './CoverStyle';
import { Skins } from '../theme/ShelfTheme';

/**
 * App 级环境状态（系统深浅色 / 前后台 / 皮肤）。
 *
 * V1 时代靠 @StorageProp 订阅 AppStorage；@ComponentV2 不支持 @StorageProp，
 * 改用 @ObservedV2 + @Trace 的全局单例：
 *   - EntryAbility / AppAppearanceStore 直接改字段；
 *   - 组件的 UI 读 this.env.xxx 即自动刷新（@Trace 属性变化会触发依赖它的组件重绘）；
 *   - 需要重算派生色（@Watch 的旧职责）时用 @Monitor('env.colorMode') 监听。
 */
@ObservedV2
export class AppEnv {
  /** 系统深浅色（ConfigurationConstant.ColorMode 值） */
  @Trace colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  /** 应用是否在前台 */
  @Trace appActive: boolean = true;
  /** App 外壳皮肤（theme/skins 里注册的 SkinTheme.id） */
  @Trace appSkin: string = Skins.defaultId();
  /** 文本书封面样式（TextCoverStyle 值） */
  @Trace textCover: string = TextCoverStyle.SPINE;
  /** 图片书封面样式（ImageCoverStyle 值） */
  @Trace imageCover: string = ImageCoverStyle.PHOTO;
  /** 减弱动效：弹簧动画降级为 120ms 淡变（MotionTokens 统一读取） */
  @Trace motionReduced: boolean = false;
}

/** 全局单例入口：所有组件与 Ability 共享同一实例 */
export class AppEnvStore {
  private static env: AppEnv = new AppEnv();

  static get(): AppEnv {
    return AppEnvStore.env;
  }
}
