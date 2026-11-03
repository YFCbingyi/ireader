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

  build() {
    Row() {
      Text('取消')
        .fontSize(15)
        .fontColor('#8B5E3C')
        .padding({ top: 8, bottom: 8, right: 12 })
        .onClick(() => {
          this.onCancel();
        })
      Blank()
      Text(`已选 ${this.selectedCount} 本`)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#2B2B2B')
      Blank()
      Text(this.allSelected ? '取消全选' : '全选')
        .fontSize(14)
        .fontColor('#8B5E3C')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .onClick(() => {
          this.onToggleAll();
        })
      Text(this.actionLabel)
        .fontSize(14)
        .fontColor(this.selectedCount > 0 ? '#8B5E3C' : '#C4B69E')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .onClick(() => {
          this.onAction();
        })
      Button('删除')
        .type(ButtonType.Capsule)
        .backgroundColor(this.selectedCount > 0 ? '#B23A2E' : '#D9D0C2')
        .fontColor('#FFF8ED')
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
