import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { RemoteLogger } from '../RemoteLogger';
import { LocalGenUIIds } from './LocalGenUIModels';

/**
 * Preview images of generated apps, taken from the real rendered runtime.
 * Derived data: losing a thumbnail never affects the app, only its tile.
 */
export class LocalGenUIThumbnailStore {
  private readonly directory: string;

  constructor(filesDir: string) {
    this.directory = `${filesDir}/local-genui/thumbnails`;
  }

  private prefix(appId: string): string {
    LocalGenUIIds.require(appId, 'app');
    return `${appId.replace(/[^A-Za-z0-9_-]/g, '_')}-`;
  }

  /** Versioned file names keep the image component from showing a cached preview. */
  private files(appId: string): string[] {
    try {
      if (!fs.accessSync(this.directory)) {
        return [];
      }
      const prefix = this.prefix(appId);
      return fs.listFileSync(this.directory).filter((name: string) => name.startsWith(prefix)).sort();
    } catch (_err) {
      return [];
    }
  }

  existing(appId: string): string {
    const files = this.files(appId);
    return files.length > 0 ? `${this.directory}/${files[files.length - 1]}` : '';
  }

  /** Crops the top square of the rendered page and stores it as JPEG. */
  async save(appId: string, pixelMap: image.PixelMap): Promise<string> {
    try {
      const info = await pixelMap.getImageInfo();
      const side = Math.min(info.size.width, info.size.height);
      if (side <= 0) {
        return '';
      }
      await pixelMap.crop({ x: 0, y: 0, size: { width: side, height: side } });
      const target = Math.min(side, 480);
      if (target < side) {
        await pixelMap.scale(target / side, target / side);
      }
      const packer = image.createImagePacker();
      const data = await packer.packToData(pixelMap, { format: 'image/jpeg', quality: 86 });
      await packer.release();
      if (!fs.accessSync(this.directory)) {
        fs.mkdirSync(this.directory, true);
      }
      const previous = this.files(appId);
      const path = `${this.directory}/${this.prefix(appId)}${Date.now()}.jpg`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, data);
      } finally {
        fs.closeSync(file);
      }
      previous.forEach((name: string) => this.unlink(`${this.directory}/${name}`));
      return path;
    } catch (err) {
      RemoteLogger.warn(`local genui thumbnail save failed: ${String(err)}`);
      return '';
    } finally {
      void pixelMap.release();
    }
  }

  remove(appId: string): void {
    this.files(appId).forEach((name: string) => this.unlink(`${this.directory}/${name}`));
  }

  private unlink(path: string): void {
    try {
      fs.unlinkSync(path);
    } catch (_err) {
      // Derived data; a stale file is harmless.
    }
  }
}
