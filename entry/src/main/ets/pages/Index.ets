import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BookMeta, ImportResult, ReaderParams } from '../model/BookModels';
import { AppPaths } from '../utils/AppPaths';
import { LibraryStore } from '../service/LibraryStore';
import { ImportService } from '../service/ImportService';
import { BookCard } from '../components/BookCard';
import { DiscoverPanel } from '../components/DiscoverPanel';
import { ProfilePanel } from '../components/ProfilePanel';

const TAB_BOOKSHELF = 0;
const TAB_DISCOVER = 1;
const TAB_PROFILE = 2;
const TAB_BAR_INSET = 112;

@Entry
@Component
struct Index {
  @State books: BookMeta[] = [];
  @State importing: boolean = false;
  @State importStage: string = '';
  @State currentTab: number = TAB_BOOKSHELF;

  private appContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    const context = this.appContext();
    AppPaths.init(context.filesDir);
    LibraryStore.init();
    this.loadBooks();
  }

  onPageShow(): void {
    this.loadBooks();
  }

  private loadBooks(): void {
    this.books = LibraryStore.getBooks();
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private tabTitle(): string {
    if (this.currentTab === TAB_DISCOVER) {
      return '发现';
    }
    if (this.currentTab === TAB_PROFILE) {
      return '我的';
    }
    return '书架';
  }

  private tabSubtitle(): string {
    if (this.currentTab === TAB_DISCOVER) {
      return '更多好书，敬请期待';
    }
    if (this.currentTab === TAB_PROFILE) {
      return '本地阅读 · 统计只保存在本机';
    }
    return this.books.length > 0 ? `${this.books.length} 本书` : '本地阅读';
  }

  private tabColor(index: number): string {
    return this.currentTab === index ? '#FFF8ED' : '#8A7A64';
  }

  private switchTab(index: number): void {
    if (this.currentTab === index) {
      return;
    }
    this.currentTab = index;
    if (index === TAB_BOOKSHELF) {
      this.loadBooks();
    }
  }

  private async openBook(book: BookMeta): Promise<void> {
    const params = new ReaderParams();
    params.bookId = book.id;
    try {
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/Reader', params: params });
    } catch (e) {
      const err = e as BusinessError;
      this.toast(`打开失败：${err.message}`);
    }
  }

  private confirmDelete(book: BookMeta): void {
    this.getUIContext().showAlertDialog({
      title: '删除书籍',
      message: `确定删除《${book.title}》吗？阅读进度和书签也会一并删除。`,
      primaryButton: {
        value: '删除',
        action: () => {
          LibraryStore.removeBook(book.id);
          this.loadBooks();
          this.toast('已删除');
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {
        }
      }
    });
  }

  private handleImportResult(result: ImportResult): void {
    if (result.success) {
      this.loadBooks();
      if (result.skippedImages > 0) {
        this.toast(`已导入《${result.title}》，跳过 ${result.skippedImages} 张超大或损坏图片`);
      } else {
        this.toast(`已导入《${result.title}》`);
      }
    } else {
      this.toast(`导入失败：${result.message}`);
    }
  }

  private async importTxt(): Promise<void> {
    if (this.importing) {
      return;
    }
    const context = this.appContext();
    try {
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['文本文件|.txt'];
      options.maxSelectNumber = 1;
      const docPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await docPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      this.importing = true;
      this.importStage = '准备导入';
      const result = await ImportService.importTxt(uris[0],
        (stage: string, current: number, total: number): void => {
          this.importStage = total > 1 ? `${stage} ${current}/${total}` : stage;
        });
      this.handleImportResult(result);
    } catch (e) {
      const err = e as BusinessError;
      if (err.message !== undefined && err.message.length > 0) {
        this.toast(`导入失败：${err.message}`);
      }
    } finally {
      this.importing = false;
      this.importStage = '';
    }
  }

  private async importZip(): Promise<void> {
    if (this.importing) {
      return;
    }
    const context = this.appContext();
    try {
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['压缩包|.zip'];
      options.maxSelectNumber = 1;
      const docPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await docPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      this.importing = true;
      this.importStage = '准备导入';
      const result = await ImportService.importZip(uris[0],
        (stage: string, current: number, total: number): void => {
          this.importStage = total > 1 ? `${stage} ${current}/${total}` : stage;
        });
      this.handleImportResult(result);
    } catch (e) {
      const err = e as BusinessError;
      if (err.message !== undefined && err.message.length > 0) {
        this.toast(`导入失败：${err.message}`);
      }
    } finally {
      this.importing = false;
      this.importStage = '';
    }
  }

  @Builder
  emptyState() {
    Column() {
      Text('书架还是空的')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#2B2B2B')
      Text('导入 TXT 文本或 ZIP 图片包开始阅读')
        .fontSize(14)
        .fontColor('#8C8C8C')
        .margin({ top: 10 })
      Row() {
        Button('导入 TXT')
          .type(ButtonType.Capsule)
          .backgroundColor('#8B5E3C')
          .fontColor('#FFF8ED')
          .fontSize(15)
          .onClick(() => {
            this.importTxt();
          })
        Button('导入图片包')
          .type(ButtonType.Capsule)
          .backgroundColor('#EFE7D8')
          .fontColor('#5C4A32')
          .fontSize(15)
          .margin({ left: 14 })
          .onClick(() => {
            this.importZip();
          })
      }
      .margin({ top: 28 })

      Text('TXT 支持 UTF-8 / GBK；图片包为 ZIP，子目录即章节')
        .fontSize(12)
        .fontColor('#A8A8A8')
        .margin({ top: 22 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 28, right: 28, bottom: TAB_BAR_INSET - 30 })
  }

  @Builder
  tabIcon(index: number) {
    Column() {
      if (index === TAB_BOOKSHELF) {
        Row({ space: 2 }) {
          Column()
            .width(3.5)
            .height(13)
            .borderRadius(2)
            .backgroundColor(this.tabColor(index))
          Column()
            .width(3.5)
            .height(18)
            .borderRadius(2)
            .backgroundColor(this.tabColor(index))
          Column()
            .width(3.5)
            .height(15)
            .borderRadius(2)
            .backgroundColor(this.tabColor(index))
        }
        .height(18)
        .alignItems(VerticalAlign.Bottom)
      } else if (index === TAB_DISCOVER) {
        Stack() {
          Circle()
            .width(17)
            .height(17)
            .fillOpacity(0)
            .stroke(this.tabColor(index))
            .strokeWidth(1.5)
          Circle()
            .width(5)
            .height(5)
            .fill(this.tabColor(index))
        }
        .width(18)
        .height(18)
      } else {
        Column() {
          Circle()
            .width(7)
            .height(7)
            .fill(this.tabColor(index))
          Column()
            .width(15)
            .height(8)
            .borderRadius({ topLeft: 8, topRight: 8, bottomLeft: 3, bottomRight: 3 })
            .backgroundColor(this.tabColor(index))
            .margin({ top: 2 })
        }
      }
    }
    .width(20)
    .height(20)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  tabItem(index: number, label: string) {
    Column() {
      this.tabIcon(index)
      Text(label)
        .fontSize(11)
        .fontColor(this.tabColor(index))
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .borderRadius(24)
    .backgroundColor(this.currentTab === index ? '#8B5E3C' : '#00000000')
    .onClick(() => {
      this.switchTab(index);
    })
  }

  @Builder
  tabBar() {
    Row() {
      this.tabItem(TAB_BOOKSHELF, '书架')
      this.tabItem(TAB_DISCOVER, '发现')
      this.tabItem(TAB_PROFILE, '我的')
    }
    .width('80%')
    .constraintSize({ maxWidth: 380 })
    .height(56)
    .padding(4)
    .borderRadius(28)
    .backgroundColor('#F5FFFDF7')
    .border({ width: 1, color: '#EFE7D8' })
    .shadow({ radius: 22, color: '#268B5E3C', offsetX: 0, offsetY: 8 })
    .margin({ bottom: 28 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Column() {
            Text(this.tabTitle())
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#2B2B2B')
            Text(this.tabSubtitle())
              .fontSize(12)
              .fontColor('#9C8C72')
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          if (this.currentTab === TAB_BOOKSHELF) {
            Button('导入TXT')
              .type(ButtonType.Capsule)
              .backgroundColor('#8B5E3C')
              .fontColor('#FFF8ED')
              .fontSize(13)
              .height(34)
              .onClick(() => {
                this.importTxt();
              })
            Button('图片包')
              .type(ButtonType.Capsule)
              .backgroundColor('#EFE7D8')
              .fontColor('#5C4A32')
              .fontSize(13)
              .height(34)
              .margin({ left: 8 })
              .onClick(() => {
                this.importZip();
              })
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 18, bottom: 14 })
        .alignItems(VerticalAlign.Center)

        if (this.currentTab === TAB_BOOKSHELF) {
          if (this.books.length === 0) {
            this.emptyState()
          } else {
            Grid() {
              ForEach(this.books, (item: BookMeta) => {
                GridItem() {
                  BookCard({
                    book: item,
                    onOpen: (book: BookMeta): void => {
                      this.openBook(book);
                    },
                    onLongPress: (book: BookMeta): void => {
                      this.confirmDelete(book);
                    }
                  })
                }
              }, (item: BookMeta) => `${item.id}_${item.updatedAt}`)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(12)
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 20, right: 20, top: 6, bottom: TAB_BAR_INSET })
            .scrollBar(BarState.Off)
          }
        } else if (this.currentTab === TAB_DISCOVER) {
          DiscoverPanel()
        } else {
          ProfilePanel({ bottomInset: TAB_BAR_INSET })
        }
      }
      .width('100%')
      .height('100%')

      this.tabBar()

      if (this.importing) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color('#FFF8ED')
          Text(this.importStage.length > 0 ? this.importStage : '正在导入')
            .fontSize(14)
            .fontColor('#FFF8ED')
            .margin({ top: 14 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F4EE')
  }
}
