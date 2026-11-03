import { common } from '@kit.AbilityKit';
import { UIContext, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0007;
const TAG = 'WindowUtil';

/** 安全区尺寸（vp）：top 取状态栏与刘海/挖孔中较大者，bottom 取底部导航条高度 */
export class WindowInsets {
  top: number = 0;
  bottom: number = 0;
}

export class WindowUtil {
  /** 恢复全屏布局并显示系统状态栏 / 导航栏（从阅读页返回书架时调用） */
  static async enableFullScreen(context: common.UIAbilityContext): Promise<void> {
    try {
      const win = await window.getLastWindow(context);
      await win.setWindowLayoutFullScreen(true);
      await win.setWindowSystemBarEnable(['status', 'navigation']);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'enable full screen failed: %{public}s', err.message);
    }
  }

  /** 读取当前窗口安全区；失败时返回 0 / 0，调用方按无留白处理 */
  static async systemInsets(uiContext: UIContext): Promise<WindowInsets> {
    const insets = new WindowInsets();
    try {
      const context = uiContext.getHostContext() as common.UIAbilityContext;
      const win = await window.getLastWindow(context);
      const systemArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cutoutArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const indicatorArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      // 刘海/挖孔区域比状态栏更高时取较大值，保证标题不被遮挡
      const top = Math.max(uiContext.px2vp(systemArea.topRect.height),
        uiContext.px2vp(cutoutArea.topRect.height));
      const bottom = uiContext.px2vp(indicatorArea.bottomRect.height);
      insets.top = top > 0 ? top : 0;
      insets.bottom = bottom > 0 ? bottom : 0;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'read insets failed: %{public}s', err.message);
      insets.top = 0;
      insets.bottom = 0;
    }
    return insets;
  }
}
