import fs from 'node:fs';
import path from 'node:path';

const root = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function writeBmp(file, width, height, r, g, b) {
  const rowSize = Math.ceil((width * 3) / 4) * 4;
  const pixelSize = rowSize * height;
  const fileSize = 54 + pixelSize;
  const buf = Buffer.alloc(fileSize);
  buf.write('BM', 0);
  buf.writeUInt32LE(fileSize, 2);
  buf.writeUInt32LE(54, 10);
  buf.writeUInt32LE(40, 14);
  buf.writeInt32LE(width, 18);
  buf.writeInt32LE(height, 22);
  buf.writeUInt16LE(1, 26);
  buf.writeUInt16LE(24, 28);
  buf.writeUInt32LE(0, 30);
  buf.writeUInt32LE(pixelSize, 34);
  buf.writeInt32LE(2835, 38);
  buf.writeInt32LE(2835, 42);
  buf.writeUInt32LE(0, 46);
  buf.writeUInt32LE(0, 50);

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = 54 + y * rowSize + x * 3;
      const border = x < 10 || y < 10 || x >= width - 10 || y >= height - 10;
      const band = y > 30 && y < 70;
      buf[idx] = border || band ? 245 : b;
      buf[idx + 1] = border || band ? 245 : g;
      buf[idx + 2] = border || band ? 245 : r;
    }
  }
  ensureDir(path.dirname(file));
  fs.writeFileSync(file, buf);
}

const sampleText = [
  '第一章 初见',
  '',
  '山间的雾还没有散尽，少年背着旧书箱，沿着石阶一步一步往上走。',
  '他听说山顶有一座藏书楼，里面收着许多已经绝版的旧书。',
  '',
  '石阶很长，走到半山腰时，他听见远处传来钟声。',
  '钟声在山谷里回荡，像是有人在轻轻翻动一页纸。',
  '',
  '第二章 旧书楼',
  '',
  '藏书楼的门没有锁，只挂着一盏风灯。',
  '少年推门进去，灰尘在光柱里慢慢浮动。',
  '',
  '书架一直延伸到屋顶，每一本书的扉页上都写着同一个名字。',
  '他抽出其中一本，发现里面夹着一片已经干枯的枫叶。',
  '',
  '第三章 归途',
  '',
  '下山的时候，雾已经散了。',
  '少年回头看了一眼藏书楼，风灯依旧亮着。',
  '',
  '他把那片枫叶夹进了自己的笔记本里。',
  '很多年以后，他仍然记得那个下午，记得书页翻动的声音。',
  ''
].join('\n');

ensureDir(root);
fs.writeFileSync(path.join(root, 'sample_utf8.txt'), sampleText, 'utf8');

const chapterRoot = path.join(root, 'images_with_chapters', '第01卷');
writeBmp(path.join(chapterRoot, '第01话', '001.bmp'), 300, 600, 86, 120, 160);
writeBmp(path.join(chapterRoot, '第01话', '002.bmp'), 300, 600, 100, 140, 170);
writeBmp(path.join(chapterRoot, '第01话', '003.bmp'), 300, 600, 120, 150, 180);
writeBmp(path.join(chapterRoot, '第02话', '001.bmp'), 300, 900, 160, 120, 90);
writeBmp(path.join(chapterRoot, '第02话', '002.bmp'), 300, 600, 170, 130, 100);
writeBmp(path.join(chapterRoot, '第02话', '003.bmp'), 300, 450, 180, 140, 110);
fs.writeFileSync(path.join(chapterRoot, '第01话', 'readme.txt'), 'not an image', 'utf8');

const flatRoot = path.join(root, 'images_flat');
writeBmp(path.join(flatRoot, '001.bmp'), 300, 600, 80, 130, 120);
writeBmp(path.join(flatRoot, '002.bmp'), 300, 600, 90, 140, 130);
writeBmp(path.join(flatRoot, '003.bmp'), 300, 900, 100, 150, 140);
writeBmp(path.join(flatRoot, '004.bmp'), 300, 600, 110, 160, 150);

console.log('test data generated at', root);
