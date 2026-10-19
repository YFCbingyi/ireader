import { BookMeta } from '../model/BookModels';
import { AppPaths } from '../utils/AppPaths';

@Component
export struct BookCard {
  @Prop book: BookMeta = new BookMeta();
  onOpen: (book: BookMeta) => void = (book: BookMeta): void => {};
  onLongPress: (book: BookMeta) => void = (book: BookMeta): void => {};

  private coverText(): string {
    if (this.book.title.length === 0) {
      return '书';
    }
    return this.book.title.substring(0, 2);
  }

  private progressText(): string {
    if (this.book.chapterCount <= 0) {
      return '暂无章节';
    }
    const progress = this.book.progress;
    const percent = Math.round(progress.percent * 100);
    if (progress.updatedAt > 0) {
      return `第 ${progress.chapterIndex + 1}/${this.book.chapterCount} 章 · ${percent}%`;
    }
    return `共 ${this.book.chapterCount} 章`;
  }

  build() {
    Column() {
      if (this.book.coverFile.length > 0) {
        Image(AppPaths.uri(this.book.coverFile))
          .width('100%')
          .aspectRatio(0.72)
          .objectFit(ImageFit.Cover)
          .autoResize(true)
          .borderRadius(10)
          .backgroundColor('#E7E2D6')
      } else {
        Column() {
          Text(this.coverText())
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFF8ED')
        }
        .width('100%')
        .aspectRatio(0.72)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(10)
        .linearGradient({
          angle: 135,
          colors: [['#8B5E3C', 0.0], ['#B8860B', 1.0]]
        })
      }

      Text(this.book.title)
        .width('100%')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#2B2B2B')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })

      Text(this.progressText())
        .width('100%')
        .fontSize(11)
        .fontColor('#8C8C8C')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 3 })
    }
    .width('100%')
    .margin({ bottom: 18 })
    .onClick(() => {
      this.onOpen(this.book);
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.onLongPress(this.book);
        })
    )
  }
}
