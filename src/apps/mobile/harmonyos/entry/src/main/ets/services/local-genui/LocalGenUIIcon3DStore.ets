import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { RemoteLogger } from '../RemoteLogger';

/**
 * 3D pictures for Local GenUI apps, the phone counterpart of the reference
 * app's `/api/icon3d` route: Microsoft Fluent Emoji 3D (MIT) at one pinned
 * upstream commit, fetched once and kept on the device.
 *
 * The runtime asks for `<ROOT><commit>/<asset path>`; only that commit and
 * asset paths of the documented shape are served, so a generated app cannot
 * use this address to reach anything else. Pictures are derived data: losing
 * the cache only costs a download.
 *
 * A cover may also ask for the animated picture of the same emoji at
 * `<ROOT>animated/<commit>/<asset path>`: Microsoft Fluent Emoji animated (MIT),
 * animated PNGs pinned the same way. They are larger, so only covers use them
 * and the static picture stays on screen until one arrives.
 */
export const LOCAL_GENUI_ICON3D_ROOT: string = 'https://genui-assets.openbitfun.invalid/fluent-emoji/';
/** Must equal `sha` in web-ui fluent-emoji-3d-index.json (checked by a test). */
export const LOCAL_GENUI_ICON3D_COMMIT: string = '1ffb34c752ecf5d402f04cfb4b392c77f57c54bc';
const UPSTREAM: string = `https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@${LOCAL_GENUI_ICON3D_COMMIT}/assets/`;
/** `<Name>/[Default/]3D/<name>_3d[_default].png`, as in the upstream index. */
const ASSET_PATH: RegExp = /^[\p{L}\p{N}][\p{L}\p{N} ,.'&()!_-]{0,80}\/(Default\/)?3D\/[\p{Ll}\p{N}][\p{Ll}\p{N}_().!'&,-]{0,100}_3d(_default)?\.png$/u;
const MAX_BYTES: number = 2 * 1024 * 1024;
/** Must equal `sha` in fluent-emoji-animated-index.json (checked by a test). */
export const LOCAL_GENUI_ICON3D_ANIMATED_COMMIT: string = 'daa0365c09795789ed2bc6e8b228c97736cb6669';
const ANIMATED_SEGMENT: string = 'animated/';
// The animated repository stores its files in Git LFS; the CDN serves only the pointers.
const ANIMATED_UPSTREAM: string = `https://media.githubusercontent.com/media/microsoft/fluentui-emoji-animated/${LOCAL_GENUI_ICON3D_ANIMATED_COMMIT}/assets/`;
/** `<Name>/[Default/]animated/<name>_animated[_default].png`, as in the animated index. */
const ANIMATED_PATH: RegExp = /^[\p{L}\p{N}][\p{L}\p{N} ,.'&()!_-]{0,80}\/(Default\/)?animated\/[\p{Ll}\p{N}][\p{Ll}\p{N}_().!'&,-]{0,100}_animated(_default)?\.png$/u;
const ANIMATED_MAX_BYTES: number = 6 * 1024 * 1024;

/** One served picture: where it comes from upstream and how large it may be. */
interface PictureAsset {
  key: string;
  url: string;
  maxBytes: number;
}

export class LocalGenUIIcon3DStore {
  private readonly directory: string;
  private readonly inflight: Map<string, Promise<ArrayBuffer | undefined>> = new Map<string, Promise<ArrayBuffer | undefined>>();

  constructor(filesDir: string) {
    this.directory = `${filesDir}/local-genui/icon3d`;
  }

  /** The asset path a runtime URL names, or '' when the URL is not a served picture. */
  static assetPath(url: string): string {
    return LocalGenUIIcon3DStore.pinnedPath(url, LOCAL_GENUI_ICON3D_ROOT, LOCAL_GENUI_ICON3D_COMMIT, ASSET_PATH);
  }

  /** The animated asset path a runtime URL names, or '' when it is not a served animation. */
  static animatedAssetPath(url: string): string {
    return LocalGenUIIcon3DStore.pinnedPath(url, LOCAL_GENUI_ICON3D_ROOT + ANIMATED_SEGMENT,
      LOCAL_GENUI_ICON3D_ANIMATED_COMMIT, ANIMATED_PATH);
  }

  private static pinnedPath(url: string, root: string, commit: string, shape: RegExp): string {
    if (!url.startsWith(root)) {
      return '';
    }
    const rest = url.substring(root.length);
    const slash = rest.indexOf('/');
    if (slash < 0 || rest.substring(0, slash) !== commit || rest.indexOf('?') >= 0 || rest.indexOf('#') >= 0) {
      return '';
    }
    let path = '';
    try {
      path = decodeURIComponent(rest.substring(slash + 1));
    } catch (_err) {
      return '';
    }
    return shape.test(path) && path.indexOf('..') < 0 ? path : '';
  }

  private static asset(url: string): PictureAsset | undefined {
    const encode = (path: string): string => path.split('/').map((part: string) => encodeURIComponent(part)).join('/');
    const still = LocalGenUIIcon3DStore.assetPath(url);
    if (still.length > 0) {
      return { key: still, url: UPSTREAM + encode(still), maxBytes: MAX_BYTES };
    }
    const animated = LocalGenUIIcon3DStore.animatedAssetPath(url);
    if (animated.length > 0) {
      return { key: ANIMATED_SEGMENT + animated, url: ANIMATED_UPSTREAM + encode(animated), maxBytes: ANIMATED_MAX_BYTES };
    }
    return undefined;
  }

  /** PNG bytes for a served picture, from the cache or the pinned upstream. */
  async picture(url: string): Promise<ArrayBuffer | undefined> {
    const asset = LocalGenUIIcon3DStore.asset(url);
    if (!asset) {
      return undefined;
    }
    const running = this.inflight.get(asset.key);
    if (running) {
      return running;
    }
    const work = this.load(asset).finally(() => { this.inflight.delete(asset.key); });
    this.inflight.set(asset.key, work);
    return work;
  }

  private cacheFile(path: string): string {
    const base64 = new util.Base64Helper().encodeToStringSync(new util.TextEncoder().encodeInto(path));
    return `${this.directory}/${base64.replace(/[^A-Za-z0-9]/g, '_')}.png`;
  }

  private async load(asset: PictureAsset): Promise<ArrayBuffer | undefined> {
    const file = this.cacheFile(asset.key);
    try {
      if (fs.accessSync(file)) {
        const handle = fs.openSync(file, fs.OpenMode.READ_ONLY);
        try {
          const size = fs.statSync(file).size;
          const buffer = new ArrayBuffer(size);
          fs.readSync(handle.fd, buffer);
          return buffer;
        } finally {
          fs.closeSync(handle);
        }
      }
    } catch (_err) {
      // A damaged cache entry is fetched again.
    }
    const bytes = await this.fetch(asset);
    if (bytes) {
      this.store(file, bytes);
    }
    return bytes;
  }

  private async fetch(asset: PictureAsset): Promise<ArrayBuffer | undefined> {
    const request = http.createHttp();
    try {
      const response = await request.request(asset.url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 8000,
        readTimeout: asset.maxBytes > MAX_BYTES ? 30000 : 10000
      });
      const body = response.result;
      if (response.responseCode !== 200 || !(body instanceof ArrayBuffer) || body.byteLength === 0 || body.byteLength > asset.maxBytes) {
        RemoteLogger.warn(`local genui icon3d unavailable status=${response.responseCode}`);
        return undefined;
      }
      return body;
    } catch (err) {
      RemoteLogger.warn(`local genui icon3d fetch failed: ${err instanceof Error ? err.message : String(err)}`);
      return undefined;
    } finally {
      request.destroy();
    }
  }

  private store(file: string, bytes: ArrayBuffer): void {
    const temporary = `${file}.${Date.now()}.tmp`;
    try {
      if (!fs.accessSync(this.directory)) {
        fs.mkdirSync(this.directory, true);
      }
      const handle = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(handle.fd, bytes);
      } finally {
        fs.closeSync(handle);
      }
      fs.renameSync(temporary, file);
    } catch (_err) {
      try { fs.unlinkSync(temporary); } catch (_ignored) { /* derived data */ }
    }
  }
}
