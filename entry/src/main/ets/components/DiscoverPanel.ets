@Component
export struct DiscoverPanel {
  build() {
    Column() {
      Stack() {
        Circle()
          .width(88)
          .height(88)
          .fill('#EFE7D8')
        Circle()
          .width(36)
          .height(36)
          .fillOpacity(0)
          .stroke('#8B5E3C')
          .strokeWidth(2)
        Circle()
          .width(8)
          .height(8)
          .fill('#8B5E3C')
          .offset({ x: 0, y: -14 })
      }
      .width(88)
      .height(88)

      Text('发现')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#2B2B2B')
        .margin({ top: 22 })
      Text('精选书单与更多好书，正在准备中')
        .fontSize(13)
        .fontColor('#9C8C72')
        .margin({ top: 10 })
      Text('敬请期待')
        .fontSize(12)
        .fontColor('#A8A8A8')
        .margin({ top: 6 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: 100 })
  }
}
