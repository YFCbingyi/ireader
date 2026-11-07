/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppEnvStore } from '../model/AppEnv';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    AppEnvStore.get().colorMode = this.currentColorMode();
    AppEnvStore.get().appActive = true;
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    AppEnvStore.get().colorMode = EntryAbility.normalizeColorMode(newConfig.colorMode);
  }

  private currentColorMode(): number {
    try {
      return EntryAbility.normalizeColorMode(this.context.config.colorMode);
    } catch (err) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
  }

  private static normalizeColorMode(mode: ConfigurationConstant.ColorMode | undefined): number {
    if (mode === undefined || mode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    return mode;
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    this.applyImmersiveLayout(windowStage);
  }

  private applyImmersiveLayout(windowStage: window.WindowStage): void {
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true).catch((err: BusinessError) => {
        hilog.error(DOMAIN, 'testTag', 'setWindowLayoutFullScreen failed: %{public}s', err.message);
      });
      mainWindow.setWindowSystemBarEnable(['status', 'navigation']).catch((err: BusinessError) => {
        hilog.error(DOMAIN, 'testTag', 'setWindowSystemBarEnable failed: %{public}s', err.message);
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'applyImmersiveLayout failed: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    AppEnvStore.get().appActive = true;
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    AppEnvStore.get().appActive = false;
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}