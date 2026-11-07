import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { ShelfTheme, ShelfThemeColors } from '../model/ShelfTheme';
import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BookMeta, BookType, GroupParams, ImportResult, ReaderParams } from '../model/BookModels';
import { AppPaths } from '../utils/AppPaths';
import { SelectionUtil } from '../utils/SelectionUtil';
import { WindowUtil } from '../utils/WindowUtil';
import { AppBootstrap } from '../service/AppBootstrap';
import { LibraryStore } from '../service/LibraryStore';
import { BookSelectBar } from '../components/BookSelectBar';
import { ImportService } from '../service/ImportService';
import { BookCard } from '../components/BookCard';
import { DiscoverPanel } from '../components/DiscoverPanel';
import { ProfilePanel } from '../components/ProfilePanel';

const TAB_BOOKSHELF = 0;
const TAB_DISCOVER = 1;
const TAB_PROFILE = 2;
const TAB_BAR_INSET = 112;
// 毛玻璃参数：背景模糊半径。半透明底色随浅/深色主题来自 ShelfThemeColors
// 顶部标题栏整条通栏模糊；底部只有导航胶囊自身模糊
const BLUR_RADIUS = 20;
const TAB_BAR_HEIGHT = 56;
const TAB_BAR_MARGIN = 16;
// 书架内容筛选：全部 / 文本书 / 图片书
const FILTER_ALL = 0;
const FILTER_TEXT = 1;
const FILTER_IMAGE = 2;
// TXT 支持一次多选导入；图片书一次只能导入一个 ZIP（子目录即章节，多包易混淆）
const TXT_MAX_SELECT = 20;
const ZIP_MAX_SELECT = 1;

@Entry
@Component
struct Index {
  @State books: BookMeta[] = [];
  @State importing: boolean = false;
  @State importStage: string = '';
  @State currentTab: number = TAB_BOOKSHELF;
  @State bookFilter: number = FILTER_ALL;
  @State groups: string[] = [];
  @State selecting: boolean = false;
  @State selectedIds: string[] = [];
  // 长按单本进入的管理态：该书放大、其余雾化，书下方弹出操作项
  @State managing: boolean = false;
  @State manageTargetId: string = '';
  // 分组选择面板 / 新建分组对话框
  @State groupSheetVisible: boolean = false;
  @State newGroupVisible: boolean = false;
  @State newGroupName: string = '';
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  // 「我的」页刷新信号：从阅读页返回时让统计组件重新取数
  @State profileRefresh: number = 0;
  // 顶部浮动栏实测高度：内容区用它做首屏留白，滚动后内容才能滑进模糊区
  @State topBarHeight: number = 0;
  // 深色模式：EntryAbility 在创建与配置变更时写入，页面只做消费
  @StorageProp('systemColorMode') @Watch('onSystemColorModeChanged') systemColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State palette: ShelfThemeColors = ShelfTheme.light();

  private appContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private isSystemDark(): boolean {
    return this.systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  /** 只在配色真正变化时重建对象，避免每次渲染都传新对象导致整页重排 */
  private applyPalette(): void {
    const next = ShelfTheme.resolve(this.isSystemDark());
    if (next.bg !== this.palette.bg) {
      this.palette = next;
    }
  }

  private onSystemColorModeChanged(): void {
    this.applyPalette();
  }

  aboutToAppear(): void {
    AppBootstrap.init(this.appContext());
    this.applyPalette();
    this.loadBooks();
  }

  onPageShow(): void {
    this.exitSelect();
    this.loadBooks();
    this.profileRefresh++;
    this.ensureFullScreenWindow();
    this.refreshInsets();
    // 阅读页恢复系统栏是异步操作，稍后再测量一次安全区，避免拿到旧值
    setTimeout(() => {
      this.refreshInsets();
    }, 150);
  }

  private loadBooks(): void {
    this.books = LibraryStore.getBooks();
    this.groups = LibraryStore.listGroups();
    // 书架被清空后，筛选器也跟着回到「所有内容」，避免停在空分类上
    if (this.books.length === 0) {
      this.bookFilter = FILTER_ALL;
    }
  }

  private matchType(book: BookMeta): boolean {
    if (this.bookFilter === FILTER_TEXT) {
      return book.type === BookType.TEXT;
    }
    if (this.bookFilter === FILTER_IMAGE) {
      return book.type === BookType.IMAGE;
    }
    return true;
  }

  /** 书架只展示未分组的书；已放入分组的书只在分组页面里出现 */
  private visibleBooks(): BookMeta[] {
    const result: BookMeta[] = [];
    for (let i = 0; i < this.books.length; i++) {
      const book = this.books[i];
      const inGroup = book.group !== undefined && book.group.length > 0;
      if (!inGroup && this.matchType(book)) {
        result.push(book);
      }
    }
    return result;
  }

  /** 网格里实际要画的卡片数：分组卡 + 未分组的书 */
  private gridCount(): number {
    return this.groups.length + this.visibleBooks().length;
  }

  private countOf(filter: number): number {
    let total = 0;
    for (let i = 0; i < this.books.length; i++) {
      const book = this.books[i];
      if (book.group !== undefined && book.group.length > 0) {
        continue;
      }
      if (filter === FILTER_TEXT && book.type !== BookType.TEXT) {
        continue;
      }
      if (filter === FILTER_IMAGE && book.type !== BookType.IMAGE) {
        continue;
      }
      total++;
    }
    return total;
  }

  private changeFilter(filter: number): void {
    if (this.bookFilter === filter) {
      return;
    }
    this.exitSelect();
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.bookFilter = filter;
    });
  }

  /** 打开分组的独立页面（书籍不在书架里重复展示） */
  private async openGroupPage(group: string): Promise<void> {
    // 管理态下点分组卡只当作「点其他地方」：先退出选中，不跳页
    if (this.managing) {
      this.exitManage();
      return;
    }
    const params = new GroupParams();
    params.group = group;
    this.exitSelect();
    try {
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/GroupBooks', params: params });
    } catch (e) {
      const err = e as BusinessError;
      this.toast(`打开分组失败：${err.message}`);
    }
  }

  private groupCount(group: string): number {
    return this.books.filter((book: BookMeta): boolean => book.group === group).length;
  }

  /** 选中的书里是否有已在分组内的（决定面板是否给「移出分组」） */
  private selectedHasGroup(): boolean {
    for (let i = 0; i < this.books.length; i++) {
      if (this.selectedIds.indexOf(this.books[i].id) >= 0 && this.books[i].group.length > 0) {
        return true;
      }
    }
    return false;
  }

  /** 分组卡预览用：该分组前 4 本 */
  private groupBooks(group: string): BookMeta[] {
    const result: BookMeta[] = [];
    for (let i = 0; i < this.books.length; i++) {
      if (this.books[i].group === group) {
        result.push(this.books[i]);
        if (result.length >= 4) {
          break;
        }
      }
    }
    return result;
  }

  /** 分组卡预览格里的书名：不足位返回空串 */
  private groupPreviewTitle(group: string, index: number): string {
    const list = this.groupBooks(group);
    if (list.length <= index) {
      return '';
    }
    return list[index].title.length === 0 ? '无题' : list[index].title;
  }

  /** 分组卡预览格是否画成图片书的配色 */
  private groupPreviewIsImage(group: string, index: number): boolean {
    const list = this.groupBooks(group);
    return list.length > index && list[index].type === BookType.IMAGE;
  }

  /** 长按单本：进入管理态，该书放大、其余雾化，书下方弹出操作项 */
  private enterManage(book: BookMeta): void {
    this.selecting = false;
    this.managing = true;
    this.manageTargetId = book.id;
    this.selectedIds = [book.id];
  }

  private exitManage(): void {
    this.managing = false;
    this.manageTargetId = '';
  }

  /** 管理态 → 多选态，保留当前选中的这本 */
  private startMultiSelect(): void {
    const target = this.manageTargetId;
    this.managing = false;
    this.manageTargetId = '';
    this.selecting = true;
    if (this.selectedIds.length === 0 && target.length > 0) {
      this.selectedIds = [target];
    }
  }

  private openGroupSheet(): void {
    if (this.selectedIds.length === 0) {
      this.toast('请先选择书籍');
      return;
    }
    this.newGroupName = '';
    this.groupSheetVisible = true;
  }

  private closeGroupSheet(): void {
    this.groupSheetVisible = false;
    this.newGroupName = '';
  }

  private applyGroup(group: string): void {
    const ids: string[] = this.selectedIds.slice();
    if (ids.length === 0) {
      this.closeGroupSheet();
      return;
    }
    LibraryStore.setGroup(ids, group);
    this.closeGroupSheet();
    this.exitSelect();
    this.loadBooks();
    this.toast(group.length > 0 ? `已将 ${ids.length} 本移入「${group}」` : `已将 ${ids.length} 本移出分组`);
  }

  private openNewGroupDialog(): void {
    this.closeGroupSheet();
    this.newGroupName = '';
    this.newGroupVisible = true;
  }

  private cancelNewGroup(): void {
    this.newGroupVisible = false;
    this.newGroupName = '';
  }

  private confirmNewGroup(): void {
    const name = this.newGroupName.trim();
    if (name.length === 0) {
      this.toast('请输入分组名称');
      return;
    }
    this.newGroupVisible = false;
    this.applyGroup(name);
  }

  /** 筛选后无书时的提示文案 */
  private emptyTitle(): string {
    if (this.books.length > 0) {
      return '书本都在分组里';
    }
    if (this.bookFilter === FILTER_TEXT) {
      return '还没有文本书';
    }
    if (this.bookFilter === FILTER_IMAGE) {
      return '还没有图片书';
    }
    return '书架还是空的';
  }

  private emptyHint(): string {
    if (this.books.length > 0) {
      return '点上面的分组卡片进去看';
    }
    if (this.bookFilter === FILTER_TEXT) {
      return '导入 TXT 文本后，会显示在这里';
    }
    if (this.bookFilter === FILTER_IMAGE) {
      return '导入 ZIP 图片包后，会显示在这里';
    }
    return '导入 TXT 文本或 ZIP 图片包开始阅读';
  }

  private async ensureFullScreenWindow(): Promise<void> {
    await WindowUtil.enableFullScreen(this.appContext());
  }

  private async refreshInsets(): Promise<void> {
    const insets = await WindowUtil.systemInsets(this.getUIContext());
    this.topInset = insets.top;
    this.bottomInset = insets.bottom;
  }

  private tabBarInset(): number {
    return this.bottomInset + TAB_BAR_INSET;
  }

  /**
   * 内容区顶部留白：优先用顶部模糊栏的实测高度。
   * 首帧还没测到时用估算值兜底，避免内容一瞬间被状态栏/标题压住再跳下来。
   */
  private topGapHeight(): number {
    return this.topBarHeight > 0 ? this.topBarHeight : this.topInset + 130;
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
    // 书架页不再显示副标题：书籍数量已由筛选胶囊导航的数量徽标承担
    return '';
  }

  private tabColor(index: number): string {
    return this.currentTab === index ? this.palette.accentText : this.palette.tabIdle;
  }

  private switchTab(index: number): void {
    if (this.currentTab === index) {
      return;
    }
    this.exitSelect();
    // 弹性过渡：导航切换用 springMotion 给出"落定"手感，不用固定 duration
    this.getUIContext().animateTo({ curve: curves.springMotion(0.35, 0.85) }, () => {
      this.currentTab = index;
    });
    if (index === TAB_BOOKSHELF) {
      this.loadBooks();
    }
  }

  private async openBook(book: BookMeta): Promise<void> {
    // 管理态/多选态下点击只做状态切换，不打开书
    if (this.managing) {
      this.exitManage();
      return;
    }
    if (this.selecting) {
      this.toggleSelect(book);
      return;
    }
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
    this.managing = false;
    this.manageTargetId = '';
    this.selecting = true;
    this.selectedIds = [book.id];
  }

  private exitSelect(): void {
    this.selecting = false;
    this.managing = false;
    this.manageTargetId = '';
    this.selectedIds = [];
  }

  private isSelected(bookId: string): boolean {
    return SelectionUtil.contains(this.selectedIds, bookId);
  }

  private toggleSelect(book: BookMeta): void {
    if (!this.selecting) {
      return;
    }
    const next: string[] = SelectionUtil.toggle(this.selectedIds, book.id);
    this.selectedIds = next;
    // 最后一项取消选中即退出多选（与抽取前一致，不动 managing 状态）
    if (next.length === 0) {
      this.selecting = false;
    }
  }

  private allSelected(): boolean {
    return SelectionUtil.allSelected(this.selectedIds, this.visibleBooks().length);
  }

  private toggleSelectAll(): void {
    if (this.allSelected()) {
      this.selectedIds = [];
      return;
    }
    this.selectedIds = SelectionUtil.collectIds(this.visibleBooks());
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

  /**
   * 导入 TXT：支持一次多选。
   * 串行逐本导入（避免多个 taskpool 任务同时读盘争 IO），单本失败不影响后续，
   * 结束后统一刷新书架并汇总结果。
   */
  private async importTxt(): Promise<void> {
    if (this.importing) {
      return;
    }
    const context = this.appContext();
    try {
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['文本文件|.txt'];
      options.maxSelectNumber = TXT_MAX_SELECT;
      const docPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await docPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      this.importing = true;
      this.importStage = '准备导入';
      const count = uris.length;
      let okCount = 0;
      let okTitle = '';
      let skippedImages = 0;
      let firstError = '';
      for (let i = 0; i < count; i++) {
        const prefix = count > 1 ? `第 ${i + 1}/${count} 本 · ` : '';
        this.importStage = `${prefix}准备导入`;
        const result = await ImportService.importTxt(uris[i],
          (stage: string, current: number, total: number): void => {
            const detail = total > 1 ? `${stage} ${current}/${total}` : stage;
            this.importStage = `${prefix}${detail}`;
          });
        if (result.success) {
          okCount++;
          okTitle = result.title;
          skippedImages += result.skippedImages;
        } else if (firstError.length === 0) {
          firstError = count > 1 ? `第 ${i + 1} 本：${result.message}` : result.message;
        }
      }
      this.loadBooks();
      this.reportImportSummary(okCount, count, okTitle, skippedImages, firstError);
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

  /** 多选导入的汇总提示：全成功只报数量，有失败时带首个失败原因 */
  private reportImportSummary(okCount: number, total: number, okTitle: string,
    skippedImages: number, firstError: string): void {
    if (total <= 1) {
      if (okCount === 1) {
        this.toast(skippedImages > 0
          ? `已导入《${okTitle}》，跳过 ${skippedImages} 张超大或损坏图片`
          : `已导入《${okTitle}》`);
      } else {
        this.toast(`导入失败：${firstError.length > 0 ? firstError : '未知错误'}`);
      }
      return;
    }
    if (okCount === total) {
      this.toast(skippedImages > 0
        ? `已导入 ${okCount} 本，跳过 ${skippedImages} 张超大或损坏图片`
        : `已导入 ${okCount} 本`);
      return;
    }
    if (okCount === 0) {
      this.toast(`${total} 本均导入失败：${firstError.length > 0 ? firstError : '未知错误'}`);
      return;
    }
    this.toast(`已导入 ${okCount} 本，${total - okCount} 本失败：${firstError}`);
  }

  /** 导入图片书：一次只能选一个 ZIP */
  private async importZip(): Promise<void> {
    if (this.importing) {
      return;
    }
    const context = this.appContext();
    try {
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['压缩包|.zip'];
      options.maxSelectNumber = ZIP_MAX_SELECT;
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

  /**
   * 单个筛选段。label 与 filter 均为固定值（@Builder 按值传参不会因外部状态变化而刷新），
   * 数量在这里直接读 this.books 计算，导入后才会即时更新。
   */
  @Builder
  filterItem(filter: number, label: string) {
    Row({ space: 5 }) {
      Text(label)
        .fontSize(14)
        .fontWeight(this.bookFilter === filter ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.bookFilter === filter ? this.palette.accentText : this.palette.tabIdle)
        .maxLines(1)
      Text(`${this.countOf(filter)}`)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.bookFilter === filter ? this.palette.accent : this.palette.tabIdle)
        .padding({ left: 6, right: 6, top: 1, bottom: 2 })
        .borderRadius(8)
        .backgroundColor(this.bookFilter === filter ? this.palette.accentText : this.palette.chipBg)
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(17)
    .backgroundColor(this.bookFilter === filter ? this.palette.accent : '#00000000')
    .shadow({
      radius: this.bookFilter === filter ? 8 : 0,
      color: this.bookFilter === filter ? this.palette.accentSoft : '#00000000',
      offsetX: 0,
      offsetY: this.bookFilter === filter ? 3 : 0
    })
    .onClick(() => {
      this.changeFilter(filter);
    })
  }

  /** 书架内容筛选胶囊导航：全部 / 文本书 / 图片书（各段带实时数量徽标） */
  @Builder
  filterBar() {
    Row() {
      this.filterItem(FILTER_ALL, '书架')
      this.filterItem(FILTER_TEXT, '文本')
      this.filterItem(FILTER_IMAGE, '图书')
    }
    .width('100%')
    .height(42)
    .padding(4)
    .borderRadius(21)
    .backgroundColor(this.palette.surfaceAlt)
    .border({ width: 1, color: this.palette.chipBg })
    .shadow({ radius: 12, color: this.palette.accentShadow, offsetX: 0, offsetY: 4 })
  }

  /** 操作项图标：0 多选 / 1 分组至 / 2 删除 */
  @Builder
  menuIcon(kind: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (kind === 0) {
        Column()
          .width(17)
          .height(17)
          .borderRadius(4)
          .border({ width: 1.5, color: this.palette.ink })
        Column()
          .width(7)
          .height(7)
          .borderRadius(2)
          .backgroundColor(this.palette.ink)
      } else if (kind === 1) {
        Column()
          .width(17)
          .height(17)
          .borderRadius(4)
          .border({ width: 1.5, color: this.palette.ink })
        Circle()
          .width(7)
          .height(7)
          .fill(this.palette.ink)
          .translate({ x: 5, y: 5 })
      } else {
        Column()
          .width(13)
          .height(1.6)
          .borderRadius(1)
          .backgroundColor(this.palette.ink)
          .translate({ y: -7 })
        Column()
          .width(11)
          .height(12)
          .borderRadius(2.5)
          .border({ width: 1.6, color: this.palette.ink })
          .translate({ y: 1.5 })
      }
    }
    .width(20)
    .height(20)
  }

  /** 长按书籍后，从书籍下方弹出的三个操作项（参照阅读 App 的竖排卡片菜单） */
  @Builder
  bookActionMenu() {
    Column() {
      Row() {
        this.menuIcon(0)
        Text('多选')
          .fontSize(16)
          .fontColor(this.palette.text)
          .margin({ left: 14 })
      }
      .width('100%')
      .height(54)
      .padding({ left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.startMultiSelect();
      })

      Divider()
        .color(this.palette.surfaceSink)
        .margin({ left: 54, right: 14 })

      Row() {
        this.menuIcon(1)
        Text('分组至')
          .fontSize(16)
          .fontColor(this.palette.text)
          .margin({ left: 14 })
      }
      .width('100%')
      .height(54)
      .padding({ left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openGroupSheet();
      })

      Divider()
        .color(this.palette.surfaceSink)
        .margin({ left: 54, right: 14 })

      Row() {
        this.menuIcon(2)
        Text('删除')
          .fontSize(16)
          .fontColor(this.palette.text)
          .margin({ left: 14 })
      }
      .width('100%')
      .height(54)
      .padding({ left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.confirmBatchDelete();
      })
    }
    .width(240)
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.palette.surface)
  }

  /** 分组卡里的 2×2 封面缩略格：有书时画迷你封面（书脊 + 书名），不足 4 本的空位留白 */
  @Builder
  groupCell(name: string, index: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.groupBooks(name).length > index) {
        Row() {
          // 书脊：右侧一本书越靠左越暗的压边
          Column()
            .width(2.5)
            .height('100%')
            .linearGradient({
              angle: 90,
              colors: [['#66000000', 0.0], ['#2E000000', 0.55], ['#12000000', 1.0]]
            })

          Column() {
            Text(this.groupPreviewTitle(name, index))
              .width('100%')
              .fontSize(7)
              .lineHeight(9)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFF8ED')
              .maxLines(3)
              .textAlign(TextAlign.Center)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .height('100%')
          .padding({ left: 1, right: 1 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .borderRadius(3)
        .clip(true)
        .linearGradient({
          angle: 135,
          colors: this.groupPreviewIsImage(name, index)
            ? [['#2C5F6E', 0.0], ['#3F8B99', 1.0]]
            : [['#8B5E3C', 0.0], ['#B8860B', 1.0]]
        })
      }
    }
    .layoutWeight(1)
    .height('100%')
  }

  /** 已有分组：2×2 封面预览 + 分组名 + 本数 */
  @Builder
  groupTile(name: string) {
    Column() {
      Column({ space: 4 }) {
        Row({ space: 4 }) {
          this.groupCell(name, 0)
          this.groupCell(name, 1)
        }
        .layoutWeight(1)
        .width('100%')

        Row({ space: 4 }) {
          this.groupCell(name, 2)
          this.groupCell(name, 3)
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .aspectRatio(1)
      .padding(7)
      .borderRadius(9)
      .backgroundColor(this.palette.surface)
      .border({ width: 1, color: this.palette.border })

      Text(name)
        .fontSize(15)
        .fontColor(this.palette.text)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })

      Text(`共 ${this.groupCount(name)} 本`)
        .fontSize(12)
        .fontColor(this.palette.subtleText)
        .width('100%')
        .margin({ top: 2 })
    }
    .width('100%')
    .onClick(() => {
      this.applyGroup(name);
    })
  }

  /** 书架网格里的分组卡片：2×2 封面预览 + 分组名 + 共 N 本 */
  @Builder
  groupGridCard(name: string) {
    Column() {
      Column({ space: 5 }) {
        Row({ space: 5 }) {
          this.groupCell(name, 0)
          this.groupCell(name, 1)
        }
        .layoutWeight(1)
        .width('100%')

        Row({ space: 5 }) {
          this.groupCell(name, 2)
          this.groupCell(name, 3)
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .aspectRatio(0.72)
      .padding(8)
      .borderRadius(10)
      .backgroundColor(this.palette.surface)
      .border({ width: 1, color: this.palette.border })

      Text(name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.text)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })

      Text(`共 ${this.groupCount(name)} 本`)
        .fontSize(11)
        .fontColor(this.palette.subText)
        .width('100%')
        .margin({ top: 2 })
    }
    .width('100%')
    .margin({ bottom: 18 })
    .onClick(() => {
      this.openGroupPage(name);
    })
  }

  /** 新建分组入口格子 */
  @Builder
  newGroupTile() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(26)
          .height(1.6)
          .borderRadius(1)
          .backgroundColor(this.palette.ink)
        Column()
          .width(1.6)
          .height(26)
          .borderRadius(1)
          .backgroundColor(this.palette.ink)
      }
      .width('100%')
      .aspectRatio(1)
      .borderRadius(9)
      .backgroundColor(this.palette.surfaceAlt)
      .border({ width: 1, color: this.palette.border })

      Text('新建分组')
        .fontSize(15)
        .fontColor(this.palette.text)
        .width('100%')
        .margin({ top: 8 })

      Text(' ')
        .fontSize(12)
        .width('100%')
        .margin({ top: 2 })
    }
    .width('100%')
    .onClick(() => {
      this.openNewGroupDialog();
    })
  }

  /** 分组至：全屏面板（3 列分组预览 + 新建分组） */
  @Builder
  groupSheet() {
    Stack({ alignContent: Alignment.Top }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette.surfaceSink)
        .onClick(() => {
          this.closeGroupSheet();
        })

      Column() {
        Row() {
          Text('分组至')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.text)
          Blank()
          if (this.selectedHasGroup()) {
            Text('移出分组')
              .fontSize(14)
              .fontColor(this.palette.tabIdle)
              .padding({ left: 6, right: 14, top: 6, bottom: 6 })
              .onClick(() => {
                this.applyGroup('');
              })
          }
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(16)
              .height(1.8)
              .borderRadius(1)
              .backgroundColor(this.palette.ink)
              .rotate({ angle: 45 })
            Column()
              .width(16)
              .height(1.8)
              .borderRadius(1)
              .backgroundColor(this.palette.ink)
              .rotate({ angle: -45 })
          }
          .width(34)
          .height(34)
          .borderRadius(17)
          .backgroundColor(this.palette.surfaceSink)
          .onClick(() => {
            this.closeGroupSheet();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Grid() {
          GridItem() {
            this.newGroupTile()
          }
          ForEach(this.groups, (name: string) => {
            GridItem() {
              this.groupTile(name)
            }
          }, (name: string) => `${name}_${this.groupCount(name)}`)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(10)
        .rowsGap(18)
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 20 })
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('calc(100% - 46vp)')
      .padding({ left: 18, right: 18, top: this.topInset + 24, bottom: this.bottomInset + 20 })
      .backgroundColor(this.palette.surfaceAlt)
      .borderRadius({ topLeft: 26, topRight: 26 })
      .margin({ top: 46 })
    }
    .width('100%')
    .height('100%')
  }

  /** 新建分组对话框（居中卡片 + 下划线输入框 + 取消/确定） */
  @Builder
  newGroupDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette.scrim)
        .onClick(() => {
          this.cancelNewGroup();
        })

      Column() {
        Text('新建分组')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.text)
          .width('100%')
          .textAlign(TextAlign.Center)

        Column() {
          TextInput({ placeholder: '新建分组', text: this.newGroupName })
            .maxLength(36)
            .fontSize(15)
            .fontColor(this.palette.text)
            .placeholderColor(this.palette.subtleText)
            .placeholderFont({ size: 15 })
            .backgroundColor('#00000000')
            .padding({ left: 0, right: 0 })
            .height(40)
            .onChange((value: string) => {
              this.newGroupName = value;
            })
          Row() {
            Blank()
            Text(`${this.newGroupName.length}/36`)
              .fontSize(11)
              .fontColor(this.palette.subtleText)
          }
          .width('100%')

          Column()
            .width('100%')
            .height(1)
            .backgroundColor(this.palette.border)
        }
        .width('100%')
        .margin({ top: 18 })

        Row() {
          Text('取消')
            .fontSize(16)
            .fontColor(this.palette.danger)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 15, bottom: 15 })
            .onClick(() => {
              this.cancelNewGroup();
            })
          Column()
            .width(1)
            .height(22)
            .backgroundColor(this.palette.border)
          Text('确定')
            .fontSize(16)
            .fontColor(this.newGroupName.trim().length > 0 ? this.palette.success : this.palette.disabled)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 15, bottom: 15 })
            .onClick(() => {
              this.confirmNewGroup();
            })
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 400 })
      .padding({ left: 22, right: 22, top: 22, bottom: 4 })
      .backgroundColor(this.palette.surfaceAlt)
      .borderRadius(24)
      .shadow({ radius: 26, color: this.palette.shadow, offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
  }

  /** 设置按钮左侧的圆形「已下载」按钮：圆环内一个向下箭头 */
  @Builder
  downloadsButton() {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(20)
        .height(20)
        .fillOpacity(0)
        .stroke(this.palette.chipText)
        .strokeWidth(1.5)

      // 箭头竖杆
      Column()
        .width(1.6)
        .height(9)
        .borderRadius(1)
        .backgroundColor(this.palette.chipText)
        .translate({ x: 0, y: -1 })

      // 箭头头部左斜杆
      Column()
        .width(1.6)
        .height(6)
        .borderRadius(1)
        .backgroundColor(this.palette.chipText)
        .rotate({ angle: 45 })
        .translate({ x: -1.7, y: 1.7 })

      // 箭头头部右斜杆
      Column()
        .width(1.6)
        .height(6)
        .borderRadius(1)
        .backgroundColor(this.palette.chipText)
        .rotate({ angle: -45 })
        .translate({ x: 1.7, y: 1.7 })
    }
    .width(38)
    .height(38)
    .borderRadius(19)
    .backgroundColor(this.palette.chipBg)
    .border({ width: 1, color: this.palette.border })
    .shadow({ radius: 8, color: this.palette.accentShadow, offsetX: 0, offsetY: 2 })
    .margin({ right: 8 })
    .onClick(() => {
      this.toast(`已下载 ${this.books.length} 本，全部保存在本机书架`);
    })
  }

  /** 右上角圆形设置按钮：四点图标，点开统一入口导入 TXT / 图片包 */
  @Builder
  importMenuButton() {
    Column() {
      Column({ space: 5 }) {
        Row({ space: 5 }) {
          Circle().width(5).height(5).fill(this.palette.chipText)
          Circle().width(5).height(5).fill(this.palette.chipText)
        }

        Row({ space: 5 }) {
          Circle().width(5).height(5).fill(this.palette.chipText)
          Circle().width(5).height(5).fill(this.palette.chipText)
        }
      }
    }
    .width(38)
    .height(38)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(19)
    .backgroundColor(this.palette.chipBg)
    .border({ width: 1, color: this.palette.border })
    .shadow({ radius: 8, color: this.palette.accentShadow, offsetX: 0, offsetY: 2 })
    .bindMenu(this.importMenu)
  }

  @Builder
  importMenu() {
    Menu() {
      MenuItem({ content: '导入 TXT 文本' })
        .onClick(() => {
          this.importTxt();
        })
      MenuItem({ content: '导入 ZIP 图片包' })
        .onClick(() => {
          this.importZip();
        })
    }
  }

  @Builder
  emptyState() {
    Column() {
      Text(this.emptyTitle())
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text)
      Text(this.emptyHint())
        .fontSize(14)
        .fontColor(this.palette.subText)
        .margin({ top: 10 })
      Row() {
        if (this.bookFilter !== FILTER_IMAGE) {
          Button('导入 TXT')
            .type(ButtonType.Capsule)
            .backgroundColor(this.palette.accent)
            .fontColor(this.palette.accentText)
            .fontSize(15)
            .onClick(() => {
              this.importTxt();
            })
        }
        if (this.bookFilter !== FILTER_TEXT) {
          Button('导入图片包')
            .type(ButtonType.Capsule)
            .backgroundColor(this.palette.chipBg)
            .fontColor(this.palette.chipText)
            .fontSize(15)
            .margin({ left: this.bookFilter === FILTER_IMAGE ? 0 : 14 })
            .onClick(() => {
              this.importZip();
            })
        }
      }
      .margin({ top: 28 })

      Text('TXT 支持 UTF-8 / GBK，可一次多选；图片包为 ZIP，单次一个，子目录即章节')
        .fontSize(12)
        .fontColor(this.palette.subtleText)
        .margin({ top: 22 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 28, right: 28, top: this.topGapHeight(), bottom: this.tabBarInset() - 30 })
  }

  /** 三个 tab 的系统符号：集中在一处，便于替换名称 */
  private tabSymbol(index: number): Resource {
    if (index === TAB_BOOKSHELF) {
      return $r('sys.symbol.book');
    }
    if (index === TAB_DISCOVER) {
      return $r('sys.symbol.compass');
    }
    return $r('sys.symbol.person');
  }

  /** 原手绘几何图标（约 10 个形状图层）改为单图层矢量符号，选中项播放一次弹跳 */
  @Builder
  tabIcon(index: number) {
    SymbolGlyph(this.tabSymbol(index))
      .fontSize(this.currentTab === index ? 20 : 18)
      .fontColor([this.tabColor(index)])
      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.UP),
        this.currentTab === index)
      .width(22)
      .height(22)
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
    .backgroundColor(this.currentTab === index ? this.palette.accent : '#00000000')
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
    .height(TAB_BAR_HEIGHT)
    .padding(4)
    .borderRadius(28)
    // 半透明底色 + 背景模糊：只有这根导航胶囊是毛玻璃，其余内容不遮
    .backgroundColor(this.palette.tabBarBg)
    .backdropBlur(BLUR_RADIUS)
    .border({ width: 1, color: this.palette.chipBg })
    .shadow({ radius: 22, color: this.palette.accentShadow, offsetX: 0, offsetY: 8 })
    .margin({ bottom: this.bottomInset + TAB_BAR_MARGIN })
    // 原为 blur(8)：对已做 backdropBlur 的层再模糊是双重离屏渲染，改用透明度淡出
    .opacity(this.managing ? 0.4 : 1)
  }

  /**
   * 顶部毛玻璃栏：标题行 + 筛选胶囊。
   * 通栏覆盖内容区，书架内容上滑时会从它下方经过并被模糊。
   * 实测高度写给 topBarHeight，供内容区做首屏留白。
   */
  @Builder
  topBar() {
    Column() {
      Row() {
        if (this.selecting) {
          BookSelectBar({
            selectedCount: this.selectedIds.length,
            allSelected: this.allSelected(),
            actionLabel: '分组至',
            onCancel: (): void => {
              this.exitSelect();
            },
            onToggleAll: (): void => {
              this.toggleSelectAll();
            },
            onAction: (): void => {
              this.openGroupSheet();
            },
            onDelete: (): void => {
              this.confirmBatchDelete();
            }
          })
        } else {
          Column() {
            Text(this.tabTitle())
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.text)
            if (this.tabSubtitle().length > 0) {
              Text(this.tabSubtitle())
                .fontSize(12)
                .fontColor(this.palette.subtleText)
                .margin({ top: 2 })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          // 管理态下不再提供「取消」按钮：点弹窗外部即可退出，右上角留给书架图标按钮
          if (!this.managing && this.currentTab === TAB_BOOKSHELF) {
            this.downloadsButton()
            this.importMenuButton()
          }
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.topInset + 18, bottom: 14 })
      .alignItems(VerticalAlign.Center)
      .blur(this.managing ? 8 : 0)

      if (this.currentTab === TAB_BOOKSHELF && !this.selecting && this.books.length > 0) {
        Column({ space: 8 }) {
          this.filterBar()
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 6 })
        .blur(this.managing ? 8 : 0)
      }
    }
    .width('100%')
    .backgroundColor(this.palette.barBg)
    .backdropBlur(BLUR_RADIUS)
    // Stack 的 alignContent 是 Bottom，这里必须显式贴到顶边，否则标题栏会掉到底部
    .position({ x: 0, y: 0 })
    // 空白处吃掉点击（不穿透到下面的书卡），但滑动仍交给书架列表
    .hitTestBehavior(HitTestMode.Transparent)
    .onClick(() => {
      // 点顶部栏空白也退出管理态
      if (this.managing) {
        this.exitManage();
      }
    })
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const height = Number(newValue.height);
      if (height > 0 && Math.abs(height - this.topBarHeight) > 0.5) {
        this.topBarHeight = height;
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.currentTab === TAB_BOOKSHELF) {
          if (this.gridCount() === 0) {
            this.emptyState()
          } else {
            Grid() {
              // 首屏留白：与顶部模糊栏等高的一整行（3 列各占一格），
              // 让内容初始从模糊栏下方开始；滚动后这行会滑出屏幕，书籍才能滑进模糊区
              ForEach([0, 1, 2], (index: number) => {
                GridItem() {
                  Column()
                    .width('100%')
                    .height(this.topGapHeight())
                }
              }, (index: number) => `top_gap_${index}`)
              ForEach(this.groups, (name: string) => {
                GridItem() {
                  this.groupGridCard(name)
                }
                // 管理态下分组卡属于「其余内容」：与书卡一样雾化，否则只有书被处理、分组看着还是亮的
                .blur(this.managing ? 8 : 0)
                .opacity(this.managing ? 0.5 : 1)
              }, (name: string) => `group_${name}_${this.groupCount(name)}`)
              ForEach(this.visibleBooks(), (item: BookMeta) => {
                GridItem() {
                  Column() {
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
                          this.enterManage(book);
                        }
                      },
                      onSelect: (book: BookMeta): void => {
                        this.toggleSelect(book);
                      }
                    })
                  }
                  .width('100%')
                  .blur(this.managing && this.manageTargetId !== item.id ? 8 : 0)
                  .opacity(this.managing && this.manageTargetId !== item.id ? 0.5 : 1)
                  .scale({
                    x: this.managing && this.manageTargetId === item.id ? 1.1 : 1,
                    y: this.managing && this.manageTargetId === item.id ? 1.1 : 1
                  })
                  .zIndex(this.managing && this.manageTargetId === item.id ? 2 : 0)
                  .outline({
                    width: this.managing && this.manageTargetId === item.id ? 2 : 0,
                    color: this.palette.accent,
                    radius: 16
                  })
                  .bindPopup(this.managing && this.manageTargetId === item.id
                    && !this.groupSheetVisible && !this.newGroupVisible, {
                    builder: this.bookActionMenu,
                    placement: Placement.Bottom,
                    popupColor: this.palette.surface,
                    enableArrow: false,
                    // 点外部即收起弹窗，再由 onStateChange 同步退出管理态。
                    // 注意：autoCancel 为 false 时弹窗的遮障层会吞掉外部点击，页面里的 onClick 收不到。
                    autoCancel: true,
                    radius: 18,
                    shadow: ShadowStyle.OUTER_DEFAULT_MD,
                    onStateChange: (event) => {
                      if (!event.isVisible && this.managing) {
                        this.exitManage();
                      }
                    }
                  })
                }
              }, (item: BookMeta) => `${item.id}_${item.updatedAt}_${item.group}`)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(12)
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 20, right: 20, bottom: this.bottomInset + 24 })
            .scrollBar(BarState.Off)
            // 点网格空白处退出管理态（书卡与分组卡各自消费自己的点击）
            .onClick(() => {
              if (this.managing) {
                this.exitManage();
              }
            })
          }
        } else if (this.currentTab === TAB_DISCOVER) {
          DiscoverPanel()
        } else {
          // 底部留白与书架一致：内容滚到底也能穿过导航胶囊，被毛玻璃糊掉
          ProfilePanel({
            bottomInset: this.bottomInset + 24,
            topInset: this.topGapHeight(),
            refreshTick: this.profileRefresh
          })
        }
      }
      .width('100%')
      .height('100%')

      this.topBar()
      this.tabBar()

      if (this.groupSheetVisible) {
        this.groupSheet()
      }

      if (this.newGroupVisible) {
        this.newGroupDialog()
      }

      if (this.importing) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            // 导入遮罩是黑底，此处固定浅色，不跟随深色主题变暗
            .color('#FFF8ED')
          Text(this.importStage.length > 0 ? this.importStage : '正在导入')
            .fontSize(14)
            .fontColor('#FFF8ED')
            .margin({ top: 14 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette.overlay)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
