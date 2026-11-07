import { AppPaths } from '../utils/AppPaths';
import { FileUtil } from '../utils/FileUtil';

/** 解析出的 EPUB 章节：标题 + 纯文本正文 + 相对解压根的 href */
export class EpubChapter {
  title: string = '';
  content: string = '';
  href: string = '';
}

export class EpubBook {
  title: string = '';
  chapters: EpubChapter[] = [];
  /** 封面图相对 filesDir 的路径，空串表示没有封面 */
  coverRel: string = '';
}

/** epub 文本抽取的最大字符数（单章），防止畸形文件撑爆内存 */
const MAX_CHAPTER_CHARS = 2000000;

const BLOCK_OPEN = [
  'p', 'div', 'br', 'li', 'tr', 'section', 'article', 'blockquote', 'pre',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'table'
];

/**
 * EPUB 解析器（在解压后的目录上工作）。
 *
 * 只做「取文本」：EPUB 内部是 XHTML 流，图片 / 样式一律丢弃，
 * 每章转成纯文本后按现有的 ChapterMeta + 单章 txt 落盘方式复用，
 * 因此阅读器、分页、进度、搜索、划线全部不需要为 EPUB 做任何改动。
 *
 * 解析步骤：META-INF/container.xml → OPF → metadata/manifest/spine → 逐章抽文本。
 */
export class EpubParser {
  static parse(extractDir: string): EpubBook {
    const containerPath = `${extractDir}/META-INF/container.xml`;
    if (!FileUtil.exists(containerPath)) {
      throw new Error('不是有效的 EPUB：缺少 META-INF/container.xml');
    }
    const opfRel = EpubParser.attrOfFirst(FileUtil.readText(containerPath), 'rootfile', 'full-path');
    if (opfRel.length === 0) {
      throw new Error('不是有效的 EPUB：container.xml 中缺少 rootfile');
    }
    const opfPath = EpubParser.join(extractDir, opfRel);
    if (!FileUtil.exists(opfPath)) {
      throw new Error('不是有效的 EPUB：找不到 OPF 文件');
    }
    const opfDir = EpubParser.dirOf(opfRel);
    const opf = FileUtil.readText(opfPath);

    const book = new EpubBook();
    book.title = EpubParser.textOf(opf, 'dc:title');

    // manifest: id -> href / media-type / properties
    const ids: string[] = [];
    const hrefs: string[] = [];
    const mediaTypes: string[] = [];
    const properties: string[] = [];
    const items = EpubParser.allTags(opf, 'item');
    for (let i = 0; i < items.length; i++) {
      ids.push(EpubParser.attr(items[i], 'id'));
      hrefs.push(EpubParser.attr(items[i], 'href'));
      mediaTypes.push(EpubParser.attr(items[i], 'media-type'));
      properties.push(EpubParser.attr(items[i], 'properties'));
    }

    // spine: 阅读顺序
    const spine = EpubParser.allTags(opf, 'itemref');
    for (let i = 0; i < spine.length; i++) {
      const linear = EpubParser.attr(spine[i], 'linear');
      if (linear === 'no') {
        continue;
      }
      const idref = EpubParser.attr(spine[i], 'idref');
      const index = ids.indexOf(idref);
      if (index < 0) {
        continue;
      }
      const mediaType = mediaTypes[index].toLowerCase();
      if (mediaType.length > 0 && mediaType.indexOf('html') < 0) {
        continue;
      }
      const href = EpubParser.decodeHref(hrefs[index]);
      if (href.length === 0) {
        continue;
      }
      const filePath = EpubParser.join(extractDir, EpubParser.join(opfDir, href));
      if (!FileUtil.exists(filePath)) {
        continue;
      }
      const html = FileUtil.readText(filePath);
      const chapter = new EpubChapter();
      chapter.href = href;
      chapter.content = EpubParser.htmlToText(html).substring(0, MAX_CHAPTER_CHARS);
      if (chapter.content.length === 0) {
        continue;
      }
      chapter.title = EpubParser.chapterTitle(html, href, book.chapters.length);
      book.chapters.push(chapter);
    }

    if (book.chapters.length === 0) {
      throw new Error('EPUB 中没有可读的文本章节');
    }

    // 封面：properties 含 cover-image 的 item，退回 meta name="cover"
    let coverHref = '';
    for (let i = 0; i < properties.length; i++) {
      if (properties[i].indexOf('cover-image') >= 0) {
        coverHref = EpubParser.decodeHref(hrefs[i]);
        break;
      }
    }
    if (coverHref.length === 0) {
      const coverId = EpubParser.attrOfFirst(opf, 'meta', 'content');
      if (coverId.length > 0) {
        const index = ids.indexOf(coverId);
        if (index >= 0) {
          coverHref = EpubParser.decodeHref(hrefs[index]);
        }
      }
    }
    if (coverHref.length > 0) {
      const coverPath = EpubParser.join(extractDir, EpubParser.join(opfDir, coverHref));
      if (FileUtil.exists(coverPath)) {
        book.coverRel = AppPaths.relative(coverPath);
      }
    }
    return book;
  }

  /** XHTML → 纯文本：去脚本样式、块级标签转换行、剥标签、解实体、合并空行 */
  static htmlToText(html: string): string {
    let text = html;
    text = EpubParser.regex(text, '<!--[\\s\\S]*?-->', '');
    text = EpubParser.regex(text, '<head[\\s\\S]*?</head>', '');
    text = EpubParser.regex(text, '<script[\\s\\S]*?</script>', '');
    text = EpubParser.regex(text, '<style[\\s\\S]*?</style>', '');
    for (let i = 0; i < BLOCK_OPEN.length; i++) {
      const tag = BLOCK_OPEN[i];
      text = EpubParser.regex(text, `<\\s*${tag}(\\s[^>]*)?>`, '\n');
      text = EpubParser.regex(text, `<\\s*/\\s*${tag}\\s*>`, '\n');
    }
    text = EpubParser.regex(text, '<[^>]*>', '');
    text = EpubParser.decodeEntities(text);
    text = EpubParser.regex(text, '\r\n?', '\n');
    text = EpubParser.regex(text, '[ \\t\\u00a0]+', ' ');
    text = EpubParser.regex(text, ' *\n *', '\n');
    text = EpubParser.regex(text, '\n{3,}', '\n\n');
    return text.trim();
  }

  private static chapterTitle(html: string, href: string, index: number): string {
    const heading = EpubParser.textOfFirst(html, 'h1');
    if (heading.length > 0) {
      return heading;
    }
    const h2 = EpubParser.textOfFirst(html, 'h2');
    if (h2.length > 0) {
      return h2;
    }
    const title = EpubParser.textOf(html, 'title');
    if (title.length > 0) {
      return title;
    }
    const name = EpubParser.baseName(href);
    if (name.length > 0) {
      return name;
    }
    return `第 ${index + 1} 章`;
  }

  private static regex(source: string, pattern: string, replacement: string): string {
    return source.replace(new RegExp(pattern, 'gi'), replacement);
  }

  /** 取某个标签的全部开标签文本（不含标签名） */
  private static allTags(xml: string, tag: string): string[] {
    const result: string[] = [];
    const re = new RegExp(`<${tag}\\b[^>]*>`, 'gi');
    let match: RegExpExecArray | null = re.exec(xml);
    while (match !== null) {
      result.push(match[0]);
      match = re.exec(xml);
    }
    return result;
  }

  private static attr(tagText: string, name: string): string {
    const re = new RegExp(`${name}\\s*=\\s*"([^"]*)"`, 'i');
    const match = re.exec(tagText);
    return match !== null && match.length > 1 ? match[1] : '';
  }

  /** 第一个指定标签的某属性值 */
  private static attrOfFirst(xml: string, tag: string, name: string): string {
    const tags = EpubParser.allTags(xml, tag);
    for (let i = 0; i < tags.length; i++) {
      const value = EpubParser.attr(tags[i], name);
      if (value.length > 0) {
        return value;
      }
    }
    return '';
  }

  /** 指定标签的文本内容（去标签 + 解实体），取第一个 */
  private static textOf(xml: string, tag: string): string {
    const re = new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)</${tag}>`, 'i');
    const match = re.exec(xml);
    if (match === null || match.length < 2) {
      return '';
    }
    return EpubParser.decodeEntities(EpubParser.regex(match[1], '<[^>]*>', '')).trim();
  }

  private static textOfFirst(xml: string, tag: string): string {
    const re = new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)</${tag}>`, 'i');
    const match = re.exec(xml);
    if (match === null || match.length < 2) {
      return '';
    }
    return EpubParser.decodeEntities(EpubParser.regex(match[1], '<[^>]*>', ''))
      .replace(new RegExp('\\s+', 'g'), ' ').trim();
  }

  private static decodeHref(href: string): string {
    if (href.length === 0) {
      return '';
    }
    // 去掉锚点与查询串：spine 里指向的是文件
    let value = href;
    const hash = value.indexOf('#');
    if (hash >= 0) {
      value = value.substring(0, hash);
    }
    const query = value.indexOf('?');
    if (query >= 0) {
      value = value.substring(0, query);
    }
    try {
      return decodeURIComponent(value);
    } catch (e) {
      return value;
    }
  }

  /** 常见实体与数字实体解码 */
  static decodeEntities(text: string): string {
    let result = text;
    const named: string[] = ['nbsp', 'amp', 'lt', 'gt', 'quot', 'apos', 'mdash', 'ndash', 'hellip',
      'ldquo', 'rdquo', 'lsquo', 'rsquo', 'middot', 'times'];
    const values: string[] = [' ', '&', '<', '>', '"', '\'', '—', '–', '…', '“', '”', '‘', '’', '·', '×'];
    for (let i = 0; i < named.length; i++) {
      const re = new RegExp(`&${named[i]};`, 'gi');
      result = result.replace(re, values[i]);
    }
    // 数字实体：&#123; 与 &#x1F600;
    const numeric = new RegExp('&#(x[0-9a-fA-F]+|[0-9]+);', 'g');
    result = result.replace(numeric, (whole: string, body: string): string => {
      let code = 0;
      if (body.length > 1 && (body.charAt(0) === 'x' || body.charAt(0) === 'X')) {
        code = Number.parseInt(body.substring(1), 16);
      } else {
        code = Number.parseInt(body, 10);
      }
      if (!Number.isFinite(code) || code <= 0 || code > 0x10ffff) {
        return whole;
      }
      return String.fromCharCode(code);
    });
    return result;
  }

  private static dirOf(path: string): string {
    const index = path.lastIndexOf('/');
    return index > 0 ? path.substring(0, index) : '';
  }

  private static baseName(path: string): string {
    const index = path.lastIndexOf('/');
    return index >= 0 ? path.substring(index + 1) : path;
  }

  private static join(base: string, rel: string): string {
    if (base.length === 0) {
      return rel;
    }
    if (rel.length === 0) {
      return base;
    }
    return `${base}/${rel}`;
  }
}
