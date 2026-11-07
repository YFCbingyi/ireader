import { ConfigurationConstant } from '@kit.AbilityKit';
import { AppSkin, ShelfTheme, ShelfThemeColors } from '../model/ShelfTheme';

/**
 * 多选状态栏：书架页与分组页共用。
 * 中间的动作按钮文案由调用方注入（书架「分组至」/ 分组页「移出分组」），其余交互完全一致。
 */
@Component
export struct BookSelectBar {
  @Prop selectedCount: number = 0;
  @Prop allSelected: boolean = false;
  @Prop actionLabel: string = '';
  onCancel: () => void = (): void => {
  };
  onToggleAll: () => void = (): void => {
  };
  onAction: () => void = (): void => {
  };
  onDelete: () => void = (): void => {
  };
  @StorageProp('systemColorMode') @Watch('onSystemColorModeChanged') systemColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp('appSkin') @Watch('onAppSkinChanged') appSkin: string = AppSkin.GOLD;
  @State palette: ShelfThemeColors = ShelfTheme.light();

  aboutToAppear(): void {
    this.applyPalette();
  }

  private applyPalette(): void {
    const next = ShelfTheme.resolve(this.systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK,
      this.appSkin);
    if (next.key !== this.palette.key) {
      this.palette = next;
    }
  }

  private onSystemColorModeChanged(): void {
    this.applyPalette();
  }

  private onAppSkinChanged(): void {
    this.applyPalette();
  }

  build() {
    Row() {
      Text('取消')
        .fontSize(15)
        .fontColor(this.palette.accent)
        .padding({ top: 8, bottom: 8, right: 12 })
        .onClick(() => {
          this.onCancel();
        })
      Blank()
      Text(`已选 ${this.selectedCount} 本`)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.text)
      Blank()
      Text(this.allSelected ? '取消全选' : '全选')
        .fontSize(14)
        .fontColor(this.palette.accent)
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .onClick(() => {
          this.onToggleAll();
        })
      Text(this.actionLabel)
        .fontSize(14)
        .fontColor(this.selectedCount > 0 ? this.palette.accent : this.palette.disabled)
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .onClick(() => {
          this.onAction();
        })
      Button('删除')
        .type(ButtonType.Capsule)
        .backgroundColor(this.selectedCount > 0 ? this.palette.danger : this.palette.disabled)
        .fontColor(this.palette.accentText)
        .fontSize(13)
        .height(34)
        .enabled(this.selectedCount > 0)
        .onClick(() => {
          this.onDelete();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
