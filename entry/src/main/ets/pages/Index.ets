import { AppEnv, AppEnvStore } from '../model/AppEnv';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Motion } from '../theme/MotionTokens';
import { Haptics } from '../utils/Haptics';
import { ShelfTheme, ShelfThemeColors } from '../theme/ShelfTheme';
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
import { BookCover } from '../components/BookCover';
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
// 导入上限：一次最多选 100 个文件；选文件夹时扫描结果同样按此上限截断
const IMPORT_MAX_FILES = 100;
// 导入类型：文本书 / EPUB / ZIP 图片包（文件夹扫描后按扩展名分派）
const IMPORT_TXT = 0;
const IMPORT_EPUB = 1;
const IMPORT_ZIP = 2;

/** 一个待导入项：来源地址（picker uri，或文件夹里的子项 uri）与导入类型 */
class ImportItem {
  uri: string = '';
  kind: number = IMPORT_TXT;

  static of(uri: string, kind: number): ImportItem {
    const item = new ImportItem();
    item.uri = uri;
    item.kind = kind;
    return item;
  }
}

/** 文件夹扫描出来的扩展名 → 导入类型 */
function importKindOf(ext: string): number {
  if (ext === 'epub') {
    return IMPORT_EPUB;
  }
  if (ext === 'zip') {
    return IMPORT_ZIP;
  }
  return IMPORT_TXT;
}

/**
 * 给「导入文件夹」挑一个不混书的分组名：
 * 目标名已被另一类型的书占用时改用带后缀的名字，避免图片书与文本书并到一组。
 */
function freeGroupName(base: string, type: string): string {
  const existing = LibraryStore.typeOfGroup(base);
  if (existing.length === 0 || existing === type) {
    return base;
  }
  const suffix = type === BookType.IMAGE ? '（图书）' : '（文本）';
  let name = `${base}${suffix}`;
  let index = 2;
  while (true) {
    const taken = LibraryStore.typeOfGroup(name);
    if (taken.length === 0 || taken === type) {
      return name;
    }
    name = `${base}${suffix}${index}`;
    index++;
  }
}

@Entry
@ComponentV2
struct Index {
  @Local books: BookMeta[] = [];
  @Local importing: boolean = false;
  @Local importStage: string = '';
  @Local currentTab: number = TAB_BOOKSHELF;
  @Local bookFilter: number = FILTER_ALL;
  @Local groups: string[] = [];
  @Local selecting: boolean = false;
  @Local selectedIds: string[] = [];
  // 长按单本进入的管理态：该书放大、其余雾化，书下方弹出操作项
  @Local managing: boolean = false;
  @Local manageTargetId: string = '';
  // 分组选择面板 / 新建分组对话框
  @Local groupSheetVisible: boolean = false;
  @Local newGroupVisible: boolean = false;
  @Local newGroupName: string = '';
  @Local topInset: number = 0;
  @Local bottomInset: number = 0;
  // 「我的」页刷新信号：从阅读页返回时让统计组件重新取数
  @Local profileRefresh: number = 0;
  // 顶部浮动栏实测高度：内容区用它做首屏留白，滚动后内容才能滑进模糊区
  @Local topBarHeight: number = 0;
  // 底部导航胶囊实测宽度：选中滑块按三等分定位
  @Local tabBarWidth: number = 0;
  // 书架网格的滚动进度（量化到 1/12，避免每帧重建顶栏）：0 = 顶栏全透明，1 = 皮肤原生毛玻璃
  @Local topBarReveal: number = 0;
  private shelfScroller: Scroller = new Scroller();
  // 循环动效的两个开关：onAppear 后翻一次，配合 iterations:-1 + Alternate 变成无限呼吸
  @Local overlayPulse: boolean = false;
  @Local illustrationBreath: boolean = false;
  // 深色模式：EntryAbility 在创建与配置变更时写入，页面只做消费
  // App 级环境（系统深浅色 / 皮肤）：@ComponentV2 不支持 @StorageProp，改用 @ObservedV2 单例
  @Local env: AppEnv = AppEnvStore.get();
  @Monitor('env.colorMode') onColorModeMonitor(): void {
    this.onSystemColorModeChanged();
  }

  @Monitor('env.appSkin') onSkinMonitor(): void {
    this.onAppSkinChanged();
  }
  @Local palette: ShelfThemeColors = ShelfTheme.light();

  private appContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private isSystemDark(): boolean {
    return this.env.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  /** key 含皮肤 + 亮暗，换皮肤时底色不变也能触发重绘 */
  private applyPalette(): void {
    const next = ShelfTheme.resolve(this.isSystemDark(), this.env.appSkin);
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

  /**
   * 当前筛选下要展示的分组：分组里放的是文本书就只在「文本」里出现，图书就只在「图书」里出现。
   * 分组内类型唯一（导入与手动分组都做了约束），所以按组内第一本书的类型判断即可。
   */
  private visibleGroups(): string[] {
    if (this.bookFilter === FILTER_ALL) {
      return this.groups;
    }
    const wantText: boolean = this.bookFilter === FILTER_TEXT;
    const result: string[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      const type = LibraryStore.typeOfGroup(this.groups[i]);
      if (wantText ? type === BookType.TEXT : type === BookType.IMAGE) {
        result.push(this.groups[i]);
      }
    }
    return result;
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

  /** 网格里实际要画的卡片数：当前筛选下的分组卡 + 未分组的书 */
  private gridCount(): number {
    return this.visibleGroups().length + this.visibleBooks().length;
  }

  /**
   * 筛选徽标里的数量：按类型统计全部书籍（书架上的 + 分组里的）。
   * 分组卡也算这个筛选下的内容，只数未分组的书会让徽标和眼前的卡片对不上。
   */
  private countOf(filter: number): number {
    let total = 0;
    for (let i = 0; i < this.books.length; i++) {
      const book = this.books[i];
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

  /** 分组卡预览格里第 index 本书；不足位返回空书（缩略格留白） */
  private groupBookAt(group: string, index: number): BookMeta {
    const list = this.groupBooks(group);
    return list.length > index ? list[index] : new BookMeta();
  }

  /** 分组卡预览格是否有书占位 */
  private hasGroupBook(group: string, index: number): boolean {
    return this.groupBooks(group).length > index;
  }

  /** 长按单本：进入管理态，该书放大、其余雾化，书下方弹出操作项 */
  private enterManage(book: BookMeta): void {
    this.selecting = false;
    this.managing = true;
    this.manageTargetId = book.id;
    this.selectedIds = [book.id];
    // 长按进入管理态是"模式切换"，给一次轻触确认
    Haptics.tap();
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

  /**
   * 分组选择面板里可用的分组：只列与当前选中书同类型的分组，
   * 免得点了才被「不能混放」拦下来。选中的书类型不一（或为空）时不做限制。
   */
  private groupOptions(): string[] {
    const picked = LibraryStore.typeOfBooks(this.selectedIds);
    if (picked.length === 0 || picked === LibraryStore.MIXED_TYPE) {
      return this.groups;
    }
    const result: string[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      const type = LibraryStore.typeOfGroup(this.groups[i]);
      if (type.length === 0 || type === picked) {
        result.push(this.groups[i]);
      }
    }
    return result;
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
    // 分组内只允许一种书：图书与文本书不能混放（移出分组不受限制）
    if (group.length > 0) {
      const picked = LibraryStore.typeOfBooks(ids);
      if (picked === LibraryStore.MIXED_TYPE) {
        this.toast('图书与文本书不能放在同一个分组，请分开选择');
        return;
      }
      const existing = LibraryStore.typeOfGroup(group);
      if (existing.length > 0 && existing !== picked) {
        this.toast(`「${group}」里已经是${LibraryStore.typeLabel(existing)}，不能再放入${LibraryStore.typeLabel(picked)}`);
        return;
      }
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

  /** 筛选后无内容时的提示文案（分组卡也算内容，不会被当成空态） */
  private emptyTitle(): string {
    if (this.bookFilter === FILTER_TEXT) {
      return '还没有文本书';
    }
    if (this.bookFilter === FILTER_IMAGE) {
      return '还没有图片书';
    }
    return '书架还是空的';
  }

  private emptyHint(): string {
    if (this.bookFilter === FILTER_TEXT) {
      return '导入 TXT 文本或 EPUB 后，会显示在这里';
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

  /** 两位十六进制（ArkTS 没有 padStart 的隐式重载习惯，手写补零更稳） */
  private hex2(value: number): string {
    let alpha = Math.round(value);
    if (alpha < 0) {
      alpha = 0;
    }
    if (alpha > 255) {
      alpha = 255;
    }
    const text = alpha.toString(16).toUpperCase();
    return text.length === 1 ? `0${text}` : text;
  }

  /**
   * 顶栏底色随滚动浮现：首屏完全透明（只留标题，页面更干净），
   * 内容即将滑进顶栏时渐变到皮肤原生 barBg 的透明度，此时毛玻璃也一起打开。
   * 只在书架页跟着网格走，其它 tab 内部自己滚动，直接给完全态。
   */
  private topBarBg(): string {
    const base = this.palette.barBg;
    if (this.currentTab !== TAB_BOOKSHELF) {
      return base;
    }
    const hasAlpha = base.length === 9;
    const rgb = hasAlpha ? base.substring(3) : base.substring(1);
    const fullAlpha = hasAlpha ? Number.parseInt(base.substring(1, 3), 16) : 255;
    return `#${this.hex2(fullAlpha * this.topBarReveal)}${rgb}`;
  }

  /** 顶栏毛玻璃开关：透明阶段不做背景模糊，省掉一次离屏渲染 */
  private topBarBlur(): number {
    return this.currentTab === TAB_BOOKSHELF && this.topBarReveal < 0.08 ? 0 : BLUR_RADIUS;
  }

  /** 滚动距离 → 顶栏浮现比例，量化成 12 档，既能跟手又不会每帧重建整棵顶栏 */
  private updateTopBarReveal(offset: number): void {
    const span = Math.max(80, this.topGapHeight() * 0.7);
    let ratio = offset / span;
    if (ratio < 0) {
      ratio = 0;
    }
    if (ratio > 1) {
      ratio = 1;
    }
    const stepped = Math.round(ratio * 12) / 12;
    if (stepped !== this.topBarReveal) {
      this.topBarReveal = stepped;
    }
  }

  /**
   * 循环呼吸参数：iterations:-1 + Alternate 让一次状态翻转变成无限循环。
   * 减弱动效时 duration 归零，直接静态。
   */
  private pulseParam(duration: number): AnimateParam {
    if (this.env.motionReduced) {
      return { duration: 0 };
    }
    return { duration: duration, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate };
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
    this.getUIContext().animateTo(Motion.soft(), () => {
      this.currentTab = index;
    });
    if (index === TAB_BOOKSHELF) {
      // 网格是 if 分支重建的，滚动位置回到顶部，顶栏也跟着回到透明态
      this.topBarReveal = 0;
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

  /** 导入 TXT：一次最多选 IMPORT_MAX_FILES 个文件 */
  private async importTxt(): Promise<void> {
    await this.pickFiles(IMPORT_TXT, ['文本文件|.txt']);
  }

  /**
   * 选文件后批量导入：最多 IMPORT_MAX_FILES 个。
   * 串行逐本导入（避免多个 taskpool 任务同时读盘争 IO），单本失败不影响后续，
   * 结束后统一刷新书架并汇总结果。
   */
  private async pickFiles(kind: number, filters: string[]): Promise<void> {
    if (this.importing) {
      return;
    }
    const context = this.appContext();
    try {
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = filters;
      options.maxSelectNumber = IMPORT_MAX_FILES;
      const docPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await docPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      const count = Math.min(uris.length, IMPORT_MAX_FILES);
      const items: ImportItem[] = [];
      for (let i = 0; i < count; i++) {
        items.push(ImportItem.of(uris[i], kind));
      }
      await this.runImport(items);
    } catch (e) {
      this.reportImportError(e as BusinessError);
    }
  }

  /**
   * 导入文件夹：选中目录后递归收集其中的 txt / epub / zip 批量导入。
   * 目录选择不参与后缀过滤，格式由扫描结果决定；
   * 导入完成后统一归到与文件夹同名的分组里（同名分组已存在则直接并入）。
   */
  private async importFolder(): Promise<void> {
    if (this.importing) {
      return;
    }
    const context = this.appContext();
    try {
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      options.maxSelectNumber = 1;
      const docPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await docPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      this.importing = true;
      this.importStage = '扫描文件夹';
      const books = ImportService.scanFolder(uris[0], IMPORT_MAX_FILES);
      if (books.length === 0) {
        this.toast('文件夹里没有找到 TXT / EPUB / ZIP 文件');
        return;
      }
      const items: ImportItem[] = [];
      for (let i = 0; i < books.length; i++) {
        items.push(ImportItem.of(books[i].uri, importKindOf(books[i].kind)));
      }
      await this.runImport(items, ImportService.folderNameOf(uris[0]));
    } catch (e) {
      this.reportImportError(e as BusinessError);
    } finally {
      // runImport 正常结束时会自行复位；扫描阶段提前返回 / 抛异常时在这里兜底
      if (this.importing) {
        this.importing = false;
        this.importStage = '';
      }
    }
  }

  /**
   * 批量串行导入：进度写进导入遮罩，结束后刷新书架并汇总提示。
   * groupName 非空时，本次成功导入的书统一并入该分组（用于「导入文件夹」）。
   */
  private async runImport(items: ImportItem[], groupName: string = ''): Promise<void> {
    const count = Math.min(items.length, IMPORT_MAX_FILES);
    if (count === 0) {
      return;
    }
    this.importing = true;
    this.importStage = '准备导入';
    let okCount = 0;
    let dupCount = 0;
    let okTitle = '';
    let skippedImages = 0;
    let firstError = '';
    // 分组内不能混书：文本书与图书分别归组，两个分组名都从文件夹名派生
    const textIds: string[] = [];
    const imageIds: string[] = [];
    // 「导入文件夹」时命中的书架旧书：不重复导入，但要把还没分组的挪进本次分组
    const staleTextIds: string[] = [];
    const staleImageIds: string[] = [];
    try {
      for (let i = 0; i < count; i++) {
        const item = items[i];
        const prefix = count > 1 ? `第 ${i + 1}/${count} 本 · ` : '';
        this.importStage = `${prefix}准备导入`;
        const onProgress = (stage: string, current: number, total: number): void => {
          const detail = total > 1 ? `${stage} ${current}/${total}` : stage;
          this.importStage = `${prefix}${detail}`;
        };
        let result: ImportResult = ImportResult.fail('未执行');
        if (item.kind === IMPORT_EPUB) {
          result = await ImportService.importEpub(item.uri, onProgress);
        } else if (item.kind === IMPORT_ZIP) {
          result = await ImportService.importZip(item.uri, onProgress);
        } else {
          result = await ImportService.importTxt(item.uri, onProgress);
        }
        if (result.success) {
          okCount++;
          okTitle = result.title;
          skippedImages += result.skippedImages;
          if (item.kind === IMPORT_ZIP) {
            imageIds.push(result.bookId);
          } else {
            textIds.push(result.bookId);
          }
        } else if (result.duplicate) {
          dupCount++;
          okTitle = result.title;
          // 只把"还在书架上（未分组）"的旧书挪进分组；已归到别的分组的保持原样，不破坏用户分类
          const existing = LibraryStore.getBook(result.bookId);
          if (existing !== undefined && existing.group.length === 0) {
            if (item.kind === IMPORT_ZIP) {
              staleImageIds.push(result.bookId);
            } else {
              staleTextIds.push(result.bookId);
            }
          }
        } else if (firstError.length === 0) {
          firstError = count > 1 ? `第 ${i + 1} 本：${result.message}` : result.message;
        }
      }
      // 分组要写在 loadBooks 之前：书架的分组胶囊由 library.json 现算，先分组再刷新才能立刻看到。
      // 两类都有书时图片书固定用「文件夹名（图书）」，避免与文本书分组同名
      const usedGroups: string[] = [];
      if (groupName.length > 0) {
        const hasText = textIds.length > 0 || staleTextIds.length > 0;
        const hasImage = imageIds.length > 0 || staleImageIds.length > 0;
        if (hasText) {
          const textGroup = freeGroupName(groupName, BookType.TEXT);
          LibraryStore.setGroup(textIds, textGroup);
          if (staleTextIds.length > 0) {
            LibraryStore.setGroup(staleTextIds, textGroup);
          }
          usedGroups.push(textGroup);
        }
        if (hasImage) {
          const baseName = hasText ? `${groupName}（图书）` : groupName;
          const imageGroup = freeGroupName(baseName, BookType.IMAGE);
          LibraryStore.setGroup(imageIds, imageGroup);
          if (staleImageIds.length > 0) {
            LibraryStore.setGroup(staleImageIds, imageGroup);
          }
          usedGroups.push(imageGroup);
        }
      }
      this.loadBooks();
      if (okCount > 0) {
        // 导入完成是一次"结果到达"，比入场更该有触觉
        Haptics.bump();
      }
      this.reportImportSummary(okCount, count, okTitle, skippedImages, firstError, usedGroups, dupCount);
    } finally {
      this.importing = false;
      this.importStage = '';
    }
  }

  private reportImportError(err: BusinessError): void {
    if (err !== undefined && err.message !== undefined && err.message.length > 0) {
      this.toast(`导入失败：${err.message}`);
    }
  }

  /**
   * 导入汇总提示：新导入 / 跳过已存在 / 失败 三类分别报数，
   * 有分组时说明归到哪些分组（分组可能因类型不同而拆成两个）。
   */
  private reportImportSummary(okCount: number, total: number, okTitle: string,
    skippedImages: number, firstError: string, usedGroups: string[] = [], dupCount: number = 0): void {
    let groupHint = '';
    if (usedGroups.length > 0) {
      let names = '';
      for (let i = 0; i < usedGroups.length; i++) {
        names += `「${usedGroups[i]}」`;
      }
      groupHint = `，已归入分组${names}`;
    }
    const imageHint = skippedImages > 0 ? `，跳过 ${skippedImages} 张超大或损坏图片` : '';
    if (total <= 1) {
      if (okCount === 1) {
        this.toast(`已导入《${okTitle}》${imageHint}${groupHint}`);
        return;
      }
      if (dupCount === 1) {
        this.toast(`《${okTitle}》已导入过，已忽略${groupHint}`);
        return;
      }
      this.toast(`导入失败：${firstError.length > 0 ? firstError : '未知错误'}`);
      return;
    }
    const failed = total - okCount - dupCount;
    let message = okCount > 0 ? `已导入 ${okCount} 本` : '没有导入新书';
    if (dupCount > 0) {
      message += `，跳过 ${dupCount} 本已导入`;
    }
    if (failed > 0) {
      message += `，${failed} 本失败：${firstError.length > 0 ? firstError : '未知错误'}`;
    }
    this.toast(message + imageHint + groupHint);
  }

  /** 导入 EPUB：一次最多选 IMPORT_MAX_FILES 个，解包后按 spine 顺序抽成单章 txt */
  private async importEpub(): Promise<void> {
    await this.pickFiles(IMPORT_EPUB, ['EPUB 电子书|.epub']);
  }

  /** 导入图片书：一次最多选 IMPORT_MAX_FILES 个 ZIP，每个包一本书 */
  private async importZip(): Promise<void> {
    await this.pickFiles(IMPORT_ZIP, ['压缩包|.zip']);
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

  /** 分组卡里的 2×2 封面缩略格：与书架卡片同一套封面绘制，只是按格子尺寸等比缩小；不足 4 本的空位留白 */
  @Builder
  groupCell(name: string, index: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.hasGroupBook(name, index)) {
        BookCover({ book: this.groupBookAt(name, index), mini: true })
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
          ForEach(this.groupOptions(), (name: string) => {
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

  /** 设置按钮左侧的「已下载」按钮：次要操作，保留描边底，点按给出本机书架数量反馈 */
  @Builder
  downloadsButton() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.arrow_down_circle'))
        .fontSize(20)
        .fontColor([this.palette.chipText])
    }
    .width(38)
    .height(38)
    .borderRadius(19)
    .backgroundColor(this.palette.chipBg)
    .border({ width: 1, color: this.palette.border })
    .shadow({ radius: 8, color: this.palette.accentShadow, offsetX: 0, offsetY: 2 })
    .margin({ right: 8 })
    .stateStyles({
      normal: {
        .scale({ x: 1, y: 1 })
      },
      pressed: {
        .scale({ x: 0.92, y: 0.92 })
      }
    })
    .animation(Motion.soft())
    .onClick(() => {
      this.toast(`已下载 ${this.books.length} 本，全部保存在本机书架`);
    })
  }

  /** 右上角「导入」主按钮：主色实底与阅读页同款加号，点开 TXT / 图片包菜单 */
  @Builder
  importMenuButton() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(21)
        .fontColor([this.palette.accentText])
    }
    .width(38)
    .height(38)
    .borderRadius(19)
    .backgroundColor(this.palette.accent)
    .shadow({ radius: 10, color: this.palette.accentShadow, offsetX: 0, offsetY: 3 })
    .stateStyles({
      normal: {
        .scale({ x: 1, y: 1 })
      },
      pressed: {
        .scale({ x: 0.92, y: 0.92 })
      }
    })
    .animation(Motion.soft())
    .bindMenu(this.importMenu)
  }

  @Builder
  importMenu() {
    Menu() {
      MenuItem({ content: '导入 TXT 文本' })
        .onClick(() => {
          this.importTxt();
        })
      MenuItem({ content: '导入 EPUB 电子书' })
        .onClick(() => {
          this.importEpub();
        })
      MenuItem({ content: '导入 ZIP 图片包' })
        .onClick(() => {
          this.importZip();
        })
      MenuItem({ content: '导入文件夹' })
        .onClick(() => {
          this.importFolder();
        })
    }
  }

  /**
   * 空态插画：一本摊开的书（两页绕内侧边微微立起 + 中缝 + 三条书页线）。
   * 整块做 2.8s 的 1↔1.03 呼吸，空页面不再是一堆静态文字的冷清感。
   */
  @Builder
  emptyIllustration() {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(136)
        .height(136)
        .fill(this.palette.chipBg)
        .opacity(0.75)

      // 左页：绕右边（中缝）转出一点角度，再用位移把中缝对到中心
      Column() {
        Column().width('62%').height(2).borderRadius(1)
          .backgroundColor(this.palette.border).margin({ top: 20 })
        Column().width('46%').height(2).borderRadius(1)
          .backgroundColor(this.palette.border).margin({ top: 9 })
        Column().width('54%').height(2).borderRadius(1)
          .backgroundColor(this.palette.border).margin({ top: 9 })
      }
      .width(46)
      .height(66)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.palette.surface)
      .border({ width: 1, color: this.palette.border })
      .borderRadius({ topLeft: 8, bottomLeft: 8, topRight: 3, bottomRight: 3 })
      .rotate({ angle: 7, centerX: '100%', centerY: '50%' })
      .translate({ x: -23 })

      // 右页：镜像
      Column() {
        Column().width('62%').height(2).borderRadius(1)
          .backgroundColor(this.palette.border).margin({ top: 26 })
        Column().width('46%').height(2).borderRadius(1)
          .backgroundColor(this.palette.border).margin({ top: 9 })
        Column().width('54%').height(2).borderRadius(1)
          .backgroundColor(this.palette.border).margin({ top: 9 })
      }
      .width(46)
      .height(66)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.palette.surface)
      .border({ width: 1, color: this.palette.border })
      .borderRadius({ topLeft: 3, bottomLeft: 3, topRight: 8, bottomRight: 8 })
      .rotate({ angle: -7, centerX: '0%', centerY: '50%' })
      .translate({ x: 23 })

      // 中缝
      Column()
        .width(2)
        .height(64)
        .borderRadius(1)
        .backgroundColor(this.palette.border)
    }
    .width(136)
    .height(120)
    .margin({ bottom: 26 })
    .scale({
      x: this.illustrationBreath ? 1.03 : 1,
      y: this.illustrationBreath ? 1.03 : 1
    })
    .animation(this.pulseParam(2800))
    .onAppear(() => {
      this.illustrationBreath = true;
    })
  }

  /** 骨架卡：与真实书卡同比例（封面 0.72 + 两行文字位） */
  @Builder
  skeletonCard() {
    Column() {
      Column()
        .width('100%')
        .aspectRatio(0.72)
        .borderRadius(10)
        .backgroundColor(this.palette.chipBg)
      Column()
        .width('70%')
        .height(10)
        .borderRadius(5)
        .backgroundColor(this.palette.chipBg)
        .margin({ top: 10 })
        .alignSelf(ItemAlign.Start)
      Column()
        .width('45%')
        .height(8)
        .borderRadius(4)
        .backgroundColor(this.palette.chipBg)
        .margin({ top: 7 })
        .alignSelf(ItemAlign.Start)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 导入骨架屏：用页面底色盖住书架，铺两排灰卡 + 整块呼吸。
   * 比原来的「黑底 + 一个转圈」轻得多：用户看到的是"书架正在长出来"。
   */
  @Builder
  importSkeleton() {
    Column() {
      Column()
        .width('100%')
        .height(Math.max(0, this.topGapHeight() - 16))

      Column({ space: 24 }) {
        Row({ space: 12 }) {
          ForEach([0, 1, 2], (index: number) => {
            this.skeletonCard()
          }, (index: number) => `skeleton_a_${index}`)
        }
        .width('100%')
        Row({ space: 12 }) {
          ForEach([0, 1, 2], (index: number) => {
            this.skeletonCard()
          }, (index: number) => `skeleton_b_${index}`)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      // 整块骨架一起明暗：一次动画，比逐卡扫光便宜且同样"在动"
      .opacity(this.overlayPulse ? 0.55 : 1)
      .animation(this.pulseParam(1200))
      .onAppear(() => {
        this.overlayPulse = true;
      })

      Row() {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.palette.accent)
        Text(this.importStage.length > 0 ? this.importStage : '正在导入')
          .fontSize(13)
          .fontColor(this.palette.subText)
          .margin({ left: 8 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 30 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .transition(TransitionEffect.OPACITY.animation(Motion.fade(200)))
  }

  @Builder
  emptyState() {
    Column() {
      this.emptyIllustration()
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
        Button('导入文件夹')
          .type(ButtonType.Capsule)
          .backgroundColor(this.palette.chipBg)
          .fontColor(this.palette.chipText)
          .fontSize(15)
          .margin({ left: 14 })
          .onClick(() => {
            this.importFolder();
          })
      }
      .margin({ top: 28 })

      Text('TXT 支持 UTF-8 / GBK，一次最多选 100 个文件；也可选择文件夹批量导入（TXT / EPUB / ZIP）')
        .fontSize(12)
        .fontColor(this.palette.subtleText)
        .textAlign(TextAlign.Center)
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

  /** 分层设色的次层色：主色压一层透明度，符号第二层因此比主层淡，层次立刻分明 */
  private symbolLayer(color: string, alpha: string): string {
    if (color.startsWith('#') && color.length === 9) {
      return `#${alpha}${color.substring(3)}`;
    }
    if (color.startsWith('#') && color.length === 7) {
      return `#${alpha}${color.substring(1)}`;
    }
    return color;
  }

  /** 原手绘几何图标（约 10 个形状图层）改为矢量符号：分层设色 + 选中项播放一次弹跳 */
  @Builder
  tabIcon(index: number) {
    SymbolGlyph(this.tabSymbol(index))
      .fontSize(this.currentTab === index ? 20 : 18)
      .fontColor([this.tabColor(index),
        this.symbolLayer(this.tabColor(index), this.currentTab === index ? 'B3' : '8C')])
      .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
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
    .onClick(() => {
      this.switchTab(index);
    })
  }

  /** 选中胶囊的单段宽度：导航胶囊内容区三等分（实测宽度减掉左右各 4vp 内边距） */
  private tabSliderWidth(): number {
    if (this.tabBarWidth <= 0) {
      return 0;
    }
    return (this.tabBarWidth - 8) / 3;
  }

  @Builder
  tabBar() {
    Stack({ alignContent: Alignment.Start }) {
      // 选中胶囊：随 currentTab 平移，替代原来「三段各自点亮」的硬切换
      Column()
        .width(this.tabSliderWidth())
        .height(48)
        .borderRadius(24)
        .backgroundColor(this.palette.accent)
        .shadow({ radius: 14, color: this.palette.accentSoft, offsetX: 0, offsetY: 5 })
        .translate({ x: this.tabSliderWidth() * this.currentTab })
        .animation(Motion.quick())
        .visibility(this.tabSliderWidth() > 0 ? Visibility.Visible : Visibility.Hidden)

      Row() {
        this.tabItem(TAB_BOOKSHELF, '书架')
        this.tabItem(TAB_DISCOVER, '发现')
        this.tabItem(TAB_PROFILE, '我的')
      }
      .width('100%')
      .height(48)
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
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width);
      if (width > 0 && Math.abs(width - this.tabBarWidth) > 0.5) {
        this.tabBarWidth = width;
      }
    })
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
    // 底色与毛玻璃都随滚动浮现：首屏干净，滚动后才是毛玻璃（不要在滚动内容上加模糊）
    .backgroundColor(this.topBarBg())
    .backdropBlur(this.topBarBlur())
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
            Grid(this.shelfScroller) {
              // 首屏留白：与顶部模糊栏等高的一整行（3 列各占一格），
              // 让内容初始从模糊栏下方开始；滚动后这行会滑出屏幕，书籍才能滑进模糊区
              ForEach([0, 1, 2], (index: number) => {
                GridItem() {
                  Column()
                    .width('100%')
                    .height(this.topGapHeight())
                }
              }, (index: number) => `top_gap_${index}`)
              ForEach(this.visibleGroups(), (name: string) => {
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
                      // 长按聚焦：只有这本的封面放大清晰，其余内容（含书名 / 进度）淡出
                      focused: this.managing && this.manageTargetId === item.id,
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
                  // 聚焦卡的缩放交给 BookCard 内部的封面自己完成，这里只负责整页雾化
                  .blur(this.managing && this.manageTargetId !== item.id ? 8 : 0)
                  .opacity(this.managing && this.manageTargetId !== item.id ? 0.5 : 1)
                  .zIndex(this.managing && this.manageTargetId === item.id ? 2 : 0)
                  // 聚焦卡不加描边：封面已放大越出原格，描边会横穿封面；清晰度本身已足够区分
                  .outline({
                    width: 0,
                    color: this.palette.accent,
                    radius: 16
                  })
                  // 雾化 / 描边与封面放大共用同一条慢弹簧，进出管理态是一段连续过渡
                  .animation(Motion.slow())
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
            // 顶栏随滚动浮现：读绝对偏移而不是累加增量，回弹/越界都不会漂
            .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
              this.updateTopBarReveal(this.shelfScroller.currentOffset().yOffset);
            })
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
        this.importSkeleton()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
