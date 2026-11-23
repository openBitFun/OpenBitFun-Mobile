import { DeviceApiLevelService } from './DeviceApiLevelService';
import { RemoteLogger } from './RemoteLogger';
import { common, Want } from '@kit.AbilityKit';
import { productViewManager } from '@kit.AppGalleryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { DESKTOP_CARD_LAUNCH_PARAM } from './local-genui/LocalGenUIDesktopCards';

export const BUILTIN_LAUNCH_PARAM: string = 'openbitfunBuiltinMiniApp';

/** AppGallery verifies the user-visible label, destination and square picture before it offers to pin. */
export class MiniAppShortcut {
  static async pin(host: Context, id: string, title: string, generated: boolean,
    thumbnail: string, fallback: Resource, revealDesktop: boolean): Promise<number> {
    const context = host as common.UIAbilityContext;
    const path = context.cacheDir + '/miniapp-shortcut-' + Date.now() + '.webp';
    try {
      const source = thumbnail ? image.createImageSource(thumbnail) :
        image.createImageSource((await context.resourceManager.getMediaContent(fallback.id)).buffer as ArrayBuffer);
      if (!source) throw new Error('Shortcut image unavailable');
      try {
        const pixels = await source.createPixelMap({ editable: true });
        try {
          const size = (await pixels.getImageInfo()).size;
          const side = Math.min(size.width, size.height);
          await pixels.crop({ x: Math.floor((size.width - side) / 2), y: Math.floor((size.height - side) / 2),
            size: { width: side, height: side } });
          await pixels.scale(144 / side, 144 / side);
          const packer = image.createImagePacker();
          try {
            const bytes = await packer.packToData(pixels, { format: 'image/webp', quality: 90 });
            if (bytes.byteLength > 102400) throw new Error('Shortcut image exceeds size limit');
            const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
            try { fs.writeSync(file.fd, bytes); } finally { fs.closeSync(file); }
          } finally { await packer.release(); }
        } finally { await pixels.release(); }
      } finally { await source.release(); }
      const parameters: Record<string, Object> = {};
      parameters[generated ? DESKTOP_CARD_LAUNCH_PARAM : BUILTIN_LAUNCH_PARAM] = id;
      const want: Want = { bundleName: context.abilityInfo.bundleName, moduleName: 'entry', abilityName: 'EntryAbility', parameters };
      const result = await productViewManager.checkPinShortcutPermitted(context, id, want,
        title.slice(0, 255), path, '');
      if (result.code !== 0 || !result.tid) return result.code || -1;
      if (revealDesktop) {
        await MiniAppShortcut.pinAndReveal(context, id, result.tid);
      } else {
        await productViewManager.requestNewPinShortcut(context, result.tid);
      }
      return 0;
    } finally {
      if (fs.accessSync(path)) fs.unlinkSync(path);
    }
  }

  private static async containsShortcut(id: string): Promise<boolean> {
    const shortcuts = await productViewManager.getPinShortcutInfos();
    return shortcuts.some((shortcut: productViewManager.PinShortcutInfo) => shortcut.shortcutId === id);
  }

  private static async pinAndReveal(context: common.UIAbilityContext, id: string, tid: string): Promise<void> {
    let watch = false;
    if (DeviceApiLevelService.sdkApiVersion() >= 24) {
      try { watch = !(await MiniAppShortcut.containsShortcut(id)); }
      catch (error) { RemoteLogger.warn('Shortcut query unavailable: ' + String(error)); }
    }
    let settled = false;
    let moved: Promise<void> | undefined;
    const reveal = (): Promise<void> => {
      if (!moved) {
        moved = context.moveAbilityToBackground().catch((error: Error) => {
          moved = undefined;
          RemoteLogger.warn('Unable to background mini app after pin: ' + String(error));
        });
      }
      return moved;
    };
    const observe = async (): Promise<void> => {
      while (!settled) {
        await new Promise<void>((resolve) => setTimeout(resolve, 250));
        if (settled) return;
        const present = await MiniAppShortcut.containsShortcut(id);
        if (settled) return;
        if (present) {
          RemoteLogger.info('Newly pinned shortcut visible before confirmation callback');
          await reveal();
          return;
        }
      }
    };
    const confirmation = productViewManager.requestNewPinShortcut(context, tid);
    if (watch) {
      void observe().catch((error: Error) => RemoteLogger.warn('Shortcut observation stopped: ' + String(error)));
    }
    try {
      await confirmation;
      RemoteLogger.info('Shortcut confirmation completed');
    } finally {
      settled = true;
    }
    await reveal();
  }
}
