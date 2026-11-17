import { display, window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { RemoteLogger } from './RemoteLogger';

/** Window-local orientation preference; never inferred from a rotated viewport. */
export class WindowOrientationService {
  private mainWindow?: window.Window;
  private generation: number = 0;
  private applying: boolean = false;
  private desired?: window.Orientation;
  private applied?: window.Orientation;
  private foldChanged: (status: display.FoldStatus) => void = (_status: display.FoldStatus) => this.refresh();
  private modeChanged: (mode: display.FoldDisplayMode) => void = (_mode: display.FoldDisplayMode) => this.refresh();
  private displayChanged: (id: number) => void = (_id: number) => this.refresh();

  static locksPortrait(foldable: boolean, status: number, type: string, shortSideVp: number): boolean {
    if (foldable && status !== display.FoldStatus.FOLD_STATUS_UNKNOWN) {
      // Other nonzero statuses include partially expanded multi-fold devices.
      return status === display.FoldStatus.FOLD_STATUS_FOLDED;
    }
    return type === 'phone' && shortSideVp > 0 && shortSideVp < 600;
  }

  start(mainWindow: window.Window): void {
    this.stop();
    this.mainWindow = mainWindow;
    try { display.on('foldStatusChange', this.foldChanged); } catch (_err) {
      RemoteLogger.warn('Fold status subscription unavailable for orientation');
    }
    try { display.on('foldDisplayModeChange', this.modeChanged); } catch (_err) {
      RemoteLogger.warn('Fold display subscription unavailable for orientation');
    }
    try { display.on('change', this.displayChanged); } catch (_err) {
      RemoteLogger.warn('Display subscription unavailable for orientation');
    }
    this.refresh();
  }

  stop(): void {
    this.generation++;
    this.mainWindow = undefined;
    this.applied = undefined;
    this.desired = undefined;
    this.applying = false;
    try { display.off('foldStatusChange', this.foldChanged); } catch (_err) {}
    try { display.off('foldDisplayModeChange', this.modeChanged); } catch (_err) {}
    try { display.off('change', this.displayChanged); } catch (_err) {}
  }

  refresh(): void {
    if (!this.mainWindow) return;
    try {
      const metrics = display.getDefaultDisplaySync();
      const shortSide = Math.min(metrics.width, metrics.height) / metrics.densityPixels;
      let foldable: boolean = false;
      let status: display.FoldStatus = display.FoldStatus.FOLD_STATUS_UNKNOWN;
      try {
        foldable = display.isFoldable();
        if (foldable) status = display.getFoldStatus();
      } catch (_err) {
        // Non-folding devices may not expose fold APIs; physical size remains
        // rotation-independent and never treats a landscape phone as a tablet.
      }
      const locked = WindowOrientationService.locksPortrait(
        foldable, status, deviceInfo.deviceType, shortSide);
      this.desired = locked ? window.Orientation.PORTRAIT : window.Orientation.AUTO_ROTATION_UNSPECIFIED;
      void this.applyLatest();
    } catch (err) {
      RemoteLogger.warn(`Failed to resolve window orientation: ${JSON.stringify(err)}`);
    }
  }

  private async applyLatest(): Promise<void> {
    if (this.applying || !this.mainWindow) return;
    const generation = this.generation;
    const mainWindow = this.mainWindow;
    this.applying = true;
    try {
      while (generation === this.generation && this.desired !== undefined && this.desired !== this.applied) {
        const orientation = this.desired;
        try {
          await mainWindow.setPreferredOrientation(orientation);
          if (generation !== this.generation) return;
          this.applied = orientation;
          RemoteLogger.info(`Window orientation preference applied: ${orientation}`);
        } catch (err) {
          RemoteLogger.warn(`Failed to apply window orientation: ${JSON.stringify(err)}`);
          if (this.desired === orientation) break;
        }
      }
    } finally {
      if (generation === this.generation) this.applying = false;
    }
  }
}
