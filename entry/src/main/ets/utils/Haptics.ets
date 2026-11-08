import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppEnvStore } from '../model/AppEnv';

const DOMAIN = 0x0006;
const TAG = 'Haptics';

/**
 * 触觉反馈：只在「动作完成 / 越过阈值 / 状态切换」这几个关键节点短促来一下，
 * 不跟手、不连发。开启「减弱动效」时一起静音，避免双重打扰。
 *
 * 需要 ohos.permission.VIBRATE（normal 级权限，module.json5 声明即可，无弹窗）。
 */
export class Haptics {
  private static fire(duration: number): void {
    if (AppEnvStore.get().motionReduced) {
      return;
    }
    const effect: vibrator.VibrateTime = { type: 'time', duration: duration };
    const attribute: vibrator.VibrateAttribute = { id: 0, usage: 'touch' };
    try {
      vibrator.startVibration(effect, attribute).catch((err: BusinessError) => {
        // 无马达 / 权限被撤：静默失败，绝不影响主流程
        hilog.debug(DOMAIN, TAG, 'vibrate failed %{public}s', err.message);
      });
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'vibrate unavailable');
    }
  }

  /** 轻触：进入管理态、越过阈值、Tab 切换 */
  static tap(): void {
    Haptics.fire(12);
  }

  /** 稍重：导入完成、删除确认等一次性结果 */
  static bump(): void {
    Haptics.fire(24);
  }
}
