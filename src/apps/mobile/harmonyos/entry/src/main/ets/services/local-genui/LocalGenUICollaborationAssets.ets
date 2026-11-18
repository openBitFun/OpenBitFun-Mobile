import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LocalGenUIIds } from './LocalGenUIModels';

export const LOCAL_GENUI_COLLABORATION_ROOT: string = 'https://genui-assets.openbitfun.invalid/collaboration/';
const MAX_BYTES: number = 2 * 1024 * 1024;

/** User media, isolated by generated app. Never treated as a disposable icon cache. */
export class LocalGenUICollaborationAssets {
  private readonly root: string;
  constructor(filesDir: string) { this.root = `${filesDir}/local-genui/collaboration`; }

  static prefix(appId: string): string {
    LocalGenUIIds.require(appId, 'app');
    return `${LOCAL_GENUI_COLLABORATION_ROOT}${encodeURIComponent(appId)}/`;
  }

  static fileName(appId: string, url: string): string {
    const prefix = LocalGenUICollaborationAssets.prefix(appId);
    if (!url.startsWith(prefix)) return '';
    const name = url.substring(prefix.length);
    return /^[a-f0-9]{32}\.jpg$/.test(name) ? name : '';
  }

  private directory(appId: string): string {
    LocalGenUIIds.require(appId, 'app');
    return `${this.root}/${encodeURIComponent(appId)}`;
  }

  async save(appId: string, bytes: ArrayBuffer): Promise<string> {
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_BYTES) throw new Error('collaboration image size unsupported');
    const dir = this.directory(appId);
    if (!await fs.access(dir)) await fs.mkdir(dir, true);
    const name = `${util.generateRandomUUID(false).replace(/-/g, '')}.jpg`;
    const path = `${dir}/${name}`;
    const temporary = `${path}.tmp`;
    const file = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      const count = await fs.write(file.fd, bytes);
      if (count !== bytes.byteLength) throw new Error('incomplete collaboration image write');
    } catch (err) {
      await fs.close(file);
      try { await fs.unlink(temporary); } catch (_ignored) { /* incomplete new file only */ }
      throw new Error(`collaboration image write failed: ${String(err)}`);
    }
    await fs.close(file);
    await fs.rename(temporary, path);
    return LocalGenUICollaborationAssets.prefix(appId) + name;
  }

  async picture(appId: string, url: string): Promise<ArrayBuffer | undefined> {
    const name = LocalGenUICollaborationAssets.fileName(appId, url);
    if (!name) return undefined;
    try {
      const file = await fs.open(`${this.directory(appId)}/${name}`, fs.OpenMode.READ_ONLY);
      try {
        const size = (await fs.stat(file.fd)).size;
        if (size <= 0 || size > MAX_BYTES) return undefined;
        const bytes = new ArrayBuffer(size);
        return await fs.read(file.fd, bytes) === size ? bytes : undefined;
      } finally { await fs.close(file); }
    } catch (_err) { return undefined; }
  }

  /** Only discard a newly received file whose owning request was abandoned. */
  async discard(appId: string, url: string): Promise<void> {
    const name = LocalGenUICollaborationAssets.fileName(appId, url);
    if (!name) return;
    try { await fs.unlink(`${this.directory(appId)}/${name}`); } catch (_err) { /* retain on failure */ }
  }
}
