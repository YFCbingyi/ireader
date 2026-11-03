import { BookMeta, BookType } from '../model/BookModels';

const TITLE_CHARS_PER_LINE = 6;

@Component
export struct BookCard {
  @Prop book: BookMeta = new BookMeta();
  @Prop selecting: boolean = false;
  @Prop selected: boolean = false;
  onOpen: (book: BookMeta) => void = (book: BookMeta): void => {};
  onLongPress: (book: BookMeta) => void = (book: BookMeta): void => {};
  onSelect: (book: BookMeta) => void = (book: BookMeta): void => {};

  private displayTitle(): string {
    return this.book.title.length === 0 ? '无题' : this.book.title;
  }

  private titleLine(index: number): string {
    const title = this.displayTitle();
    const start = index * TITLE_CHARS_PER_LINE;
    if (start >= title.length) {
      return '';
    }
    const rest = title.substring(start);
    if (rest.length <= TITLE_CHARS_PER_LINE) {
      return rest;
    }
    if (index === 0) {
      return rest.substring(0, TITLE_CHARS_PER_LINE);
    }
    return `${rest.substring(0, TITLE_CHARS_PER_LINE - 1)}…`;
  }

  private hasSecondTitleLine(): boolean {
    return this.displayTitle().length > TITLE_CHARS_PER_LINE;
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

  private tapCard(): void {
    if (this.selecting) {
      this.onSelect(this.book);
      return;
    }
    this.onOpen(this.book);
  }

  @Builder
  bookCover() {
    Row() {
      Column()
        .width(9)
        .height('100%')
        .linearGradient({
          angle: 90,
          colors: [['#66000000', 0.0], ['#2E000000', 0.55], ['#12000000', 1.0]]
        })

      Stack() {
        if (this.book.type === BookType.IMAGE) {
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 135,
              colors: [['#2C5F6E', 0.0], ['#3F8B99', 1.0]]
            })
        } else {
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 135,
              colors: [['#8B5E3C', 0.0], ['#B8860B', 1.0]]
            })
        }

        Column()
          .width('calc(100% - 12vp)')
          .height('calc(100% - 12vp)')
          .border({ width: 1, color: '#33FFF8ED' })
          .borderRadius(6)

        Column() {
          Text(this.titleLine(0))
            .width('100%')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFF8ED')
            .lineHeight(20)
            .maxLines(1)
            .textAlign(TextAlign.Center)
          if (this.hasSecondTitleLine()) {
            Text(this.titleLine(1))
              .width('100%')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFF8ED')
              .lineHeight(20)
              .maxLines(1)
              .textAlign(TextAlign.Center)
          }
          Column()
            .width(24)
            .height(1)
            .backgroundColor('#66FFF8ED')
            .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 6, right: 6 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        if (!this.selecting) {
          Stack({ alignContent: Alignment.TopEnd }) {
            Text(this.book.type === BookType.IMAGE ? '图' : 'TXT')
              .fontSize(9)
              .fontColor('#FFF8ED')
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(4)
              .backgroundColor('#33FFFFFF')
              .border({ width: 1, color: '#4DFFFFFF' })
              .margin({ top: 6, right: 10 })
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        }

        if (this.book.group !== undefined && this.book.group.length > 0) {
          Stack({ alignContent: Alignment.TopStart }) {
            Text(this.book.group)
              .fontSize(9)
              .fontColor('#FFF8ED')
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(4)
              .backgroundColor('#59000000')
              .margin({ top: 6, left: 10 })
              .maxLines(1)
              .constraintSize({ maxWidth: 66 })
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .layoutWeight(1)
      .height('100%')

      Column()
        .width(5)
        .height('100%')
        .backgroundColor('#F4EFE3')
    }
    .width('100%')
    .aspectRatio(0.72)
    .borderRadius(10)
    .clip(true)
    .draggable(false)
    .shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 4 })
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        this.bookCover()

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
          .margin({ top: 2 })
      }
      .width('100%')
      .margin({ bottom: 18 })
      .onClick(() => {
        this.tapCard();
      })
      .gesture(
        LongPressGesture()
          .onAction(() => {
            this.onLongPress(this.book);
          })
      )

      if (this.selecting) {
        Stack() {
          Circle()
            .width(24)
            .height(24)
            .fill(this.selected ? '#8B5E3C' : '#F2FFFDF7')
            .stroke(this.selected ? '#8B5E3C' : '#B9AD9C')
            .strokeWidth(1.5)
          if (this.selected) {
            Text('✓')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFF8ED')
          }
        }
        .width(24)
        .height(24)
        .margin({ top: 6, right: 8 })
        .onClick(() => {
          this.onSelect(this.book);
        })
      }
    }
    .width('100%')
  }
}
