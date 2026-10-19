import { util } from '@kit.ArkTS';

const MAX_CHAPTER_CHARS = 80000;
const MAX_CHAPTERS = 5000;

export class ChapterDraft {
  title: string = '';
  content: string = '';

  static of(title: string, content: string): ChapterDraft {
    const draft = new ChapterDraft();
    draft.title = title;
    draft.content = content;
    return draft;
  }
}

export class TextCodec {
  static decode(bytes: Uint8Array): string {
    if (bytes.length === 0) {
      return '';
    }
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
      return TextCodec.decodeWith('utf-8', bytes, true);
    }
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      return TextCodec.decodeWith('utf-16le', bytes, false);
    }
    if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
      return TextCodec.decodeWith('utf-16be', bytes, false);
    }
    try {
      return TextCodec.decodeWith('utf-8', bytes, true);
    } catch (e) {
      try {
        const gbkText = TextCodec.decodeWith('gbk', bytes, false);
        if (gbkText.indexOf('\uFFFD') < 0) {
          return gbkText;
        }
        try {
          const gbText = TextCodec.decodeWith('gb18030', bytes, false);
          if (gbText.indexOf('\uFFFD') < 0) {
            return gbText;
          }
        } catch (e3) {
        }
        return gbkText;
      } catch (e2) {
        try {
          return TextCodec.decodeWith('gb18030', bytes, false);
        } catch (e3) {
          return TextCodec.decodeWith('utf-8', bytes, false);
        }
      }
    }
  }

  private static decodeWith(encoding: string, bytes: Uint8Array, fatal: boolean): string {
    const decoder = util.TextDecoder.create(encoding, { fatal: fatal, ignoreBOM: false });
    return decoder.decodeToString(bytes);
  }

  static normalize(text: string): string {
    let result = text;
    if (result.length > 0 && result.charCodeAt(0) === 0xFEFF) {
      result = result.substring(1);
    }
    result = result.split('\r\n').join('\n');
    result = result.split('\r').join('\n');
    return result;
  }

  static splitChapters(text: string, fallbackTitle: string): ChapterDraft[] {
    const result: ChapterDraft[] = [];
    const lines = text.split('\n');
    const heading = new RegExp('^\\s*(第[0-9零一二三四五六七八九十百千万两]+[章回节卷部篇][^\\n]{0,30}|序章|楔子|引子|前言|后记|尾声|番外[^\\n]{0,20})\\s*$');
    let currentTitle = '前言';
    let contentLines: string[] = [];
    let sawHeading = false;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (heading.test(line)) {
        sawHeading = true;
        const content = contentLines.join('\n').trim();
        if (content.length > 0) {
          result.push(ChapterDraft.of(currentTitle, content));
        }
        currentTitle = line.trim();
        contentLines = [];
      } else {
        contentLines.push(line);
      }
    }

    const tail = contentLines.join('\n').trim();
    if (tail.length > 0) {
      result.push(ChapterDraft.of(sawHeading ? currentTitle : fallbackTitle, tail));
    }
    if (result.length === 0) {
      const empty = text.trim();
      result.push(ChapterDraft.of(fallbackTitle, empty));
    }

    const expanded = TextCodec.splitLongChapters(result);
    if (expanded.length > MAX_CHAPTERS) {
      throw new Error('章节数量过多（超过 5000 章）');
    }
    return expanded;
  }

  private static splitLongChapters(drafts: ChapterDraft[]): ChapterDraft[] {
    const result: ChapterDraft[] = [];
    for (let i = 0; i < drafts.length; i++) {
      const draft = drafts[i];
      let content = draft.content;
      let part = 1;
      while (content.length > MAX_CHAPTER_CHARS) {
        let cut = content.lastIndexOf('\n', MAX_CHAPTER_CHARS);
        if (cut <= 0) {
          cut = MAX_CHAPTER_CHARS;
        }
        const piece = content.substring(0, cut).trim();
        const title = part === 1 ? draft.title : `${draft.title}（续${part}）`;
        if (piece.length > 0) {
          result.push(ChapterDraft.of(title, piece));
        }
        content = content.substring(cut).trim();
        part++;
      }
      if (content.length > 0) {
        const title = part === 1 ? draft.title : `${draft.title}（续${part}）`;
        result.push(ChapterDraft.of(title, content));
      }
    }
    return result;
  }
}
