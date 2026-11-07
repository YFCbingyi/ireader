import { ConfigurationConstant } from '@kit.AbilityKit';
import { ShelfTheme, ShelfThemeColors } from '../model/ShelfTheme';

@Component
export struct DiscoverPanel {
  @StorageProp('systemColorMode') @Watch('onSystemColorModeChanged') systemColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State palette: ShelfThemeColors = ShelfTheme.light();

  aboutToAppear(): void {
    this.applyPalette();
  }

  private applyPalette(): void {
    const next = ShelfTheme.resolve(this.systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    if (next.bg !== this.palette.bg) {
      this.palette = next;
    }
  }

  private onSystemColorModeChanged(): void {
    this.applyPalette();
  }

  build() {
    Column() {
      Stack() {
        Circle()
          .width(88)
          .height(88)
          .fill(this.palette.chipBg)
        Circle()
          .width(36)
          .height(36)
          .fillOpacity(0)
          .stroke(this.palette.accent)
          .strokeWidth(2)
        Circle()
          .width(8)
          .height(8)
          .fill(this.palette.accent)
          .offset({ x: 0, y: -14 })
      }
      .width(88)
      .height(88)

      Text('发现')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text)
        .margin({ top: 22 })
      Text('精选书单与更多好书，正在准备中')
        .fontSize(13)
        .fontColor(this.palette.subtleText)
        .margin({ top: 10 })
      Text('敬请期待')
        .fontSize(12)
        .fontColor(this.palette.subtleText)
        .margin({ top: 6 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: 100 })
  }
}
