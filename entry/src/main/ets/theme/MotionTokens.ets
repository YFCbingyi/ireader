import { curves } from '@kit.ArkUI';
import { AppEnvStore } from '../model/AppEnv';

/**
 * 动效 token：曲线与时长集中一处，调手感只改这里，不再满项目撒 springMotion 参数。
 *
 * 四档语义：
 *   quick —— 高频小反馈（tab 滑块、按压），跟手、回弹快
 *   soft  —— 控制栏 / 面板 / 浮层显隐，默认档
 *   slow  —— 大块位移（管理态雾化、封面聚焦），慢而稳
 *   fade  —— 只淡入淡出，不带弹簧
 *
 * 「减弱动效」开启后，弹簧统一降级为 120ms 的 EaseOut：位移还在，回弹和过冲全部去掉。
 */
export class Motion {
  /** 减弱动效时的降级参数：短、无回弹 */
  private static reduced(): AnimateParam {
    return { duration: 120, curve: Curve.EaseOut };
  }

  /** 底层弹簧档：response 越大越慢，damping 越小回弹越明显 */
  static spring(response: number, damping: number): AnimateParam {
    if (AppEnvStore.get().motionReduced) {
      return Motion.reduced();
    }
    return { curve: curves.springMotion(response, damping) };
  }

  /** 高频小反馈：tab 滑块、勾选、按压 */
  static quick(): AnimateParam {
    return Motion.spring(0.32, 0.78);
  }

  /** 控制栏 / 面板 / 浮层的显隐（默认档） */
  static soft(): AnimateParam {
    return Motion.spring(0.35, 0.85);
  }

  /** 大块位移与雾化：管理态、封面聚焦 */
  static slow(): AnimateParam {
    return Motion.spring(0.5, 0.82);
  }

  /** 只做淡出淡入：不带弹簧，避免"弹一下再消失" */
  static fade(duration: number): AnimateParam {
    if (AppEnvStore.get().motionReduced || duration < 120) {
      return Motion.reduced();
    }
    return { duration: duration, curve: Curve.EaseOut };
  }
}
