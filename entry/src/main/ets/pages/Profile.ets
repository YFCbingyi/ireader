import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppPaths } from '../utils/AppPaths';
import { LibraryStore } from '../service/LibraryStore';
import { ProfilePanel } from '../components/ProfilePanel';

@Entry
@Component
struct Profile {
  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPaths.init(context.filesDir);
    LibraryStore.init();
  }

  private goBack(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (e) {
      const err = e as BusinessError;
      console.error(`back failed: ${err.message}`);
    }
  }

  build() {
    Column() {
      Row() {
        Text('‹ 返回')
          .fontSize(15)
          .fontColor('#8B5E3C')
          .padding({ right: 12, top: 8, bottom: 8 })
          .onClick(() => {
            this.goBack();
          })
        Blank()
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Column() {
        Text('我的')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2B2B2B')
        Text('本地阅读 · 统计只保存在本机')
          .fontSize(12)
          .fontColor('#9C8C72')
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, bottom: 14 })

      ProfilePanel()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F4EE')
  }
}
