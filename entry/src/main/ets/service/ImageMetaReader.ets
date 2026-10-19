import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ImageEntry } from '../model/BookModels';

const DOMAIN = 0x0003;
const TAG = 'ImageMetaReader';

export class ImageMetaReader {
  static readonly MAX_PIXELS: number = 24000000;
  static readonly MAX_SIDE: number = 20000;

  static async read(fileRel: string, absPath: string): Promise<ImageEntry | undefined> {
    let source: image.ImageSource | undefined = undefined;
    try {
      source = image.createImageSource(absPath);
      const info: image.ImageInfo = await source.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      if (width <= 0 || height <= 0) {
        return undefined;
      }
      if (width * height > ImageMetaReader.MAX_PIXELS) {
        return undefined;
      }
      if (width > ImageMetaReader.MAX_SIDE || height > ImageMetaReader.MAX_SIDE) {
        return undefined;
      }
      return ImageEntry.of(fileRel, width, height);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'read image failed: %{public}s %{public}s', absPath, err.message);
      return undefined;
    } finally {
      if (source !== undefined) {
        try {
          await source.release();
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'release image source failed');
        }
      }
    }
  }
}
