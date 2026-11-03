import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BookMeta, GroupParams, ReaderParams } from '../model/BookModels';
import { AppPaths } from '../utils/AppPaths';
import { LibraryStore } from '../service/LibraryStore';
import { BookCard } from '../components/BookCard';

/**
 * 分组书籍页：书架网格里的分组卡片点进来的独立页面。
 * 放入分组的书不在书架重复展示，只在这里出现；返回即回到书架。
 */
@Entry
@Component
struct GroupBooks {
  @State group: string = '';
  @State books: BookMeta[] = [];
  @State selecting: boolean = false;
  @State selectedIds: string[] = [];
  @State renameVisible: boolean = false;
  @State groupDraft: string = '';
  @State topInset: number = 0;
  @State bottomInset: number = 0;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPaths.init(context.filesDir);
    LibraryStore.init();
    const raw = this.getUIContext().getRouter().getParams();
    const params = raw as GroupParams;
    if (params !== undefined && params !== null && params.group !== undefined) {
      this.group = params.group;
    }
    this.load();
    this.ensureFullScreenWindow();
    this.refreshInsets();
  }

  onPageShow(): void {
    this.load();
    this.refreshInsets();
  }

  private appContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private load(): void {
    const all = LibraryStore.getBooks();
    const list: BookMeta[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].group === this.group) {
        list.push(all[i]);
      }
    }
    this.books = list;
  }

  private async ensureFullScreenWindow(): Promise<void> {
    try {
      const win = await window.getLastWindow(this.appContext());
      await win.setWindowLayoutFullScreen(true);
      await win.setWindowSystemBarEnable(['status', 'navigation']);
    } catch (e) {
      console.error(`group page full screen failed: ${(e as Error).message}`);
    }
  }

  private async refreshInsets(): Promise<void> {
    try {
      const win = await window.getLastWindow(this.appContext());
      const systemArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cutoutArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const indicatorArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const top = Math.max(this.getUIContext().px2vp(systemArea.topRect.height),
        this.getUIContext().px2vp(cutoutArea.topRect.height));
      const bottom = this.getUIContext().px2vp(indicatorArea.bottomRect.height);
      this.topInset = top > 0 ? top : 0;
      this.bottomInset = bottom > 0 ? bottom : 0;
    } catch (e) {
      console.error(`group page insets failed: ${(e as Error).message}`);
      this.topInset = 0;
      this.bottomInset = 0;
    }
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private back(): void {
    this.getUIContext().getRouter().back();
  }

  private async openBook(book: BookMeta): Promise<void> {
    if (this.selecting) {
      this.toggleSelect(book);
      return;
    }
    const params = new ReaderParams();
    params.bookId = book.id;
    try {
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/Reader', params: params });
    } catch (e) {
      this.toast(`打开失败：${(e as Error).message}`);
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

  /** 选中的书移出分组 → 回到书架 */
  private moveOutSelected(): void {
    const ids: string[] = this.selectedIds.slice();
    if (ids.length === 0) {
      return;
    }
    LibraryStore.setGroup(ids, '');
    this.exitSelect();
    this.load();
    this.toast(`已将 ${ids.length} 本移出「${this.group}」`);
    if (this.books.length === 0) {
      this.back();
    }
  }

  private confirmDelete(): void {
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
          this.load();
          this.toast(`已删除 ${count} 本`);
          if (this.books.length === 0) {
            this.back();
          }
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {
        }
      }
    });
  }

  private openRename(): void {
    this.groupDraft = this.group;
    this.renameVisible = true;
  }

  private cancelRename(): void {
    this.renameVisible = false;
    this.groupDraft = '';
  }

  private confirmRename(): void {
    const name = this.groupDraft.trim();
    if (name.length === 0) {
      this.toast('请输入分组名称');
      return;
    }
    const oldName = this.group;
    LibraryStore.renameGroup(oldName, name);
    this.group = name;
    this.renameVisible = false;
    this.groupDraft = '';
    this.load();
    this.toast(`已重命名为「${name}」`);
  }

  /** 整组移出到书架 */
  private moveOutAll(): void {
    if (this.books.length === 0) {
      return;
    }
    const ids: string[] = [];
    for (let i = 0; i < this.books.length; i++) {
      ids.push(this.books[i].id);
    }
    LibraryStore.setGroup(ids, '');
    this.toast(`已将 ${ids.length} 本移出分组`);
    this.back();
  }

  @Builder
  groupMenu() {
    Menu() {
      MenuItem({ content: '重命名分组' })
        .onClick(() => {
          this.openRename();
        })
      MenuItem({ content: '移出分组' })
        .onClick(() => {
          this.moveOutAll();
        })
    }
  }

  @Builder
  moreButton() {
    Column() {
      Column({ space: 5 }) {
        Row({ space: 5 }) {
          Circle().width(5).height(5).fill('#5C4A32')
          Circle().width(5).height(5).fill('#5C4A32')
        }

        Row({ space: 5 }) {
          Circle().width(5).height(5).fill('#5C4A32')
          Circle().width(5).height(5).fill('#5C4A32')
        }
      }
    }
    .width(38)
    .height(38)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(19)
    .backgroundColor('#EFE7D8')
    .border({ width: 1, color: '#E4D8C4' })
    .shadow({ radius: 8, color: '#1A8B5E3C', offsetX: 0, offsetY: 2 })
    .bindMenu(this.groupMenu)
  }

  @Builder
  backButton() {
    Stack({ alignContent: Alignment.Center }) {
      Text('‹')
        .fontSize(26)
        .fontColor('#3A3A3A')
        .margin({ bottom: 3 })
    }
    .width(40)
    .height(40)
    .borderRadius(20)
    .backgroundColor('#EFEAE0')
    .onClick(() => {
      this.back();
    })
  }

  @Builder
  titleHeader() {
    Row() {
      this.backButton()
      Text(this.group)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor('#2B2B2B')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 14 })
      this.moreButton()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  selectHeader() {
    Row() {
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
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .onClick(() => {
          this.toggleSelectAll();
        })
      Text('移出分组')
        .fontSize(14)
        .fontColor(this.selectedIds.length > 0 ? '#8B5E3C' : '#C4B69E')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .onClick(() => {
          this.moveOutSelected();
        })
      Button('删除')
        .type(ButtonType.Capsule)
        .backgroundColor(this.selectedIds.length > 0 ? '#B23A2E' : '#D9D0C2')
        .fontColor('#FFF8ED')
        .fontSize(13)
        .height(34)
        .enabled(this.selectedIds.length > 0)
        .onClick(() => {
          this.confirmDelete();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  emptyState() {
    Column() {
      Text('分组里还没有书')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#2B2B2B')
      Text('在书架上长按书籍，选择「分组至」把书放进来')
        .fontSize(13)
        .fontColor('#8C8C8C')
        .margin({ top: 10 })
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 28, right: 28, bottom: 40 })
  }

  @Builder
  renameDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#4D000000')
        .onClick(() => {
          this.cancelRename();
        })

      Column() {
        Text('重命名分组')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#2B2B2B')
          .width('100%')
          .textAlign(TextAlign.Center)

        Column() {
          TextInput({ placeholder: '分组名称', text: this.groupDraft })
            .maxLength(36)
            .fontSize(15)
            .fontColor('#2B2B2B')
            .placeholderColor('#A8A29A')
            .placeholderFont({ size: 15 })
            .backgroundColor('#00000000')
            .padding({ left: 0, right: 0 })
            .height(40)
            .onChange((value: string) => {
              this.groupDraft = value;
            })
          Row() {
            Blank()
            Text(`${this.groupDraft.length}/36`)
              .fontSize(11)
              .fontColor('#A8A29A')
          }
          .width('100%')

          Column()
            .width('100%')
            .height(1)
            .backgroundColor('#DCD5C8')
        }
        .width('100%')
        .margin({ top: 18 })

        Row() {
          Text('取消')
            .fontSize(16)
            .fontColor('#C4553C')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 15, bottom: 15 })
            .onClick(() => {
              this.cancelRename();
            })
          Column()
            .width(1)
            .height(22)
            .backgroundColor('#E6E0D4')
          Text('确定')
            .fontSize(16)
            .fontColor(this.groupDraft.trim().length > 0 ? '#2F7D5A' : '#B9C4BC')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 15, bottom: 15 })
            .onClick(() => {
              this.confirmRename();
            })
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 400 })
      .padding({ left: 22, right: 22, top: 22, bottom: 4 })
      .backgroundColor('#FBF8F2')
      .borderRadius(24)
      .shadow({ radius: 26, color: '#33000000', offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Column() {
          if (this.selecting) {
            this.selectHeader()
          } else {
            this.titleHeader()
          }
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: this.topInset + 14, bottom: 10 })

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
            }, (item: BookMeta) => `${item.id}_${item.updatedAt}_${item.group}`)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(12)
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 20, right: 20, top: 6, bottom: this.bottomInset + 24 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')

      if (this.renameVisible) {
        this.renameDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F4EE')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
