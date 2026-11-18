import { window } from '@kit.ArkUI';
import { RemoteLogger } from '../RemoteLogger';

/** Applies a page's preference while visible and restores the host's preference. */
export class LocalGenUIOrientation {
  private readonly context: () => Context;
  private original?: window.Orientation;
  private applied?: window.Orientation;
  private pending: Promise<void> = Promise.resolve();
  private serial: number = 0;

  constructor(context: () => Context) {
    this.context = context;
  }

  /** Serialize rotations so a late window lookup cannot override a close/remount. */
  sync(visible: boolean, preference: string = 'auto'): Promise<void> {
    const serial = ++this.serial;
    this.pending = this.pending.then(async (): Promise<void> => {
      if (serial !== this.serial) return;
      const requested = visible && preference === 'landscape' ? window.Orientation.AUTO_ROTATION_LANDSCAPE :
        visible && preference === 'portrait' ? window.Orientation.AUTO_ROTATION_PORTRAIT : undefined;
      if (requested === undefined && this.original === undefined) return;
      try {
        const main = await window.getLastWindow(this.context());
        if (serial !== this.serial) return;
        if (this.original === undefined) this.original = main.getPreferredOrientation();
        const next = requested === undefined ? this.original : requested;
        if (next !== this.applied) {
          await main.setPreferredOrientation(next);
          this.applied = next;
        }
        if (requested === undefined) {
          this.original = undefined;
          this.applied = undefined;
        }
      } catch (err) {
        RemoteLogger.warn(`local genui orientation failed: ${err instanceof Error ? err.message : String(err)}`);
      }
    });
    return this.pending;
  }
}
