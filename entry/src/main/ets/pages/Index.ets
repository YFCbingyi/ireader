import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { window } from '@kit.ArkUI';
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
  @State selecting: boolean = false;
  @State selectedIds: string[] = [];
  @State topInset: number = 0;
  @State bottomInset: number = 0;

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
    this.exitSelect();
    this.loadBooks();
    this.ensureFullScreenWindow();
    this.refreshInsets();
    // 阅读页恢复系统栏是异步操作，稍后再测量一次安全区，避免拿到旧值
    setTimeout(() => {
      this.refreshInsets();
    }, 150);
  }

  private loadBooks(): void {
    this.books = LibraryStore.getBooks();
  }

  private async ensureFullScreenWindow(): Promise<void> {
    try {
      const win = await window.getLastWindow(this.appContext());
      await win.setWindowLayoutFullScreen(true);
      await win.setWindowSystemBarEnable(['status', 'navigation']);
    } catch (e) {
      const err = e as BusinessError;
      console.error(`ensure full screen window failed: ${err.message}`);
    }
  }

  private async refreshInsets(): Promise<void> {
    try {
      const win = await window.getLastWindow(this.appContext());
      const systemArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cutoutArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const indicatorArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      // 刘海/挖孔区域比状态栏更高时取较大值，保证标题不被遮挡
      const top = Math.max(px2vp(systemArea.topRect.height), px2vp(cutoutArea.topRect.height));
      const bottom = px2vp(indicatorArea.bottomRect.height);
      this.topInset = top > 0 ? top : 0;
      this.bottomInset = bottom > 0 ? bottom : 0;
    } catch (e) {
      const err = e as BusinessError;
      console.error(`refresh insets failed: ${err.message}`);
      this.topInset = 0;
      this.bottomInset = 0;
    }
  }

  private tabBarInset(): number {
    return this.bottomInset + TAB_BAR_INSET;
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
    this.exitSelect();
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

  private enterSelect(book: BookMeta): void {
    this.selecting = true;
    this.selectedIds = [book.id];
  }

  private exitSelect(): void {
    this.selecting = false;
    this.selectedIds = [];
  }

  private isSelected(bookId: string): boolean {
    return this.selectedIds.indexOf(bookId) >= 0;
  }

  private toggleSelect(book: BookMeta): void {
    if (!this.selecting) {
      return;
    }
    if (this.isSelected(book.id)) {
      const next: string[] = [];
      for (let i = 0; i < this.selectedIds.length; i++) {
        if (this.selectedIds[i] !== book.id) {
          next.push(this.selectedIds[i]);
        }
      }
      this.selectedIds = next;
      if (next.length === 0) {
        this.selecting = false;
      }
    } else {
      const next: string[] = this.selectedIds.slice();
      next.push(book.id);
      this.selectedIds = next;
    }
  }

  private allSelected(): boolean {
    return this.books.length > 0 && this.selectedIds.length === this.books.length;
  }

  private toggleSelectAll(): void {
    if (this.allSelected()) {
      this.selectedIds = [];
      return;
    }
    const next: string[] = [];
    for (let i = 0; i < this.books.length; i++) {
      next.push(this.books[i].id);
    }
    this.selectedIds = next;
  }

  private confirmBatchDelete(): void {
    const count = this.selectedIds.length;
    if (count === 0) {
      return;
    }
    const ids: string[] = this.selectedIds.slice();
    this.getUIContext().showAlertDialog({
      title: '删除书籍',
      message: `确定删除选中的 ${count} 本书吗？阅读进度和书签也会一并删除。`,
      primaryButton: {
        value: '删除',
        action: () => {
          LibraryStore.removeBooks(ids);
          this.exitSelect();
          this.loadBooks();
          this.toast(`已删除 ${count} 本`);
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
    .padding({ left: 28, right: 28, bottom: this.tabBarInset() - 30 })
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
    .margin({ bottom: this.bottomInset + 16 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          if (this.selecting) {
            Text('取消')
              .fontSize(15)
              .fontColor('#8B5E3C')
              .padding({ top: 8, bottom: 8, right: 12 })
              .onClick(() => {
                this.exitSelect();
              })
            Blank()
            Text(`已选 ${this.selectedIds.length} 本`)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#2B2B2B')
            Blank()
            Text(this.allSelected() ? '取消全选' : '全选')
              .fontSize(14)
              .fontColor('#8B5E3C')
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .onClick(() => {
                this.toggleSelectAll();
              })
            Button('删除')
              .type(ButtonType.Capsule)
              .backgroundColor(this.selectedIds.length > 0 ? '#B23A2E' : '#D9D0C2')
              .fontColor('#FFF8ED')
              .fontSize(13)
              .height(34)
              .enabled(this.selectedIds.length > 0)
              .onClick(() => {
                this.confirmBatchDelete();
              })
          } else {
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
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: this.topInset + 18, bottom: 14 })
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
                    selecting: this.selecting,
                    selected: this.isSelected(item.id),
                    onOpen: (book: BookMeta): void => {
                      this.openBook(book);
                    },
                    onLongPress: (book: BookMeta): void => {
                      if (this.selecting) {
                        this.toggleSelect(book);
                      } else {
                        this.enterSelect(book);
                      }
                    },
                    onSelect: (book: BookMeta): void => {
                      this.toggleSelect(book);
                    }
                  })
                }
              }, (item: BookMeta) => `${item.id}_${item.updatedAt}`)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(12)
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 20, right: 20, top: 6, bottom: this.tabBarInset() })
            .scrollBar(BarState.Off)
          }
        } else if (this.currentTab === TAB_DISCOVER) {
          DiscoverPanel()
        } else {
          ProfilePanel({ bottomInset: this.tabBarInset() })
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
