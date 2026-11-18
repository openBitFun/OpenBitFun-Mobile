import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import {
  LocalGenUIDesktopCardApp,
  LocalGenUIDesktopCardBinding,
  LocalGenUIDesktopCardData,
  LocalGenUIDesktopCards
} from './LocalGenUIDesktopCards';

const FORM_NOT_EXIST: number = 16501001;
/**
 * How long an "Add to desktop" menu stays claimable by the next new card. The
 * launcher adds the card within seconds of the tap; a short window keeps a
 * card added later from the system widget picker from taking the app.
 */
const PENDING_ADD_TTL_MS: number = 60000;

interface LocalGenUIDesktopCardPendingAdd {
  appId: string;
  stagedAt: number;
}

/**
 * Desktop card state shared by the UI process and the card host process
 * (`LocalGenUIFormAbility`). Both run in the same app sandbox, so the state is
 * small JSON files under `filesDir` instead of the RDB the UI process owns:
 *
 * - `bindings/<form>.json`: which app a home-screen card opens.
 * - `apps/<app>.json`: what the card shows for that app (title, preview, whether
 *   the app still exists).
 *
 * Writes go through a temporary file and a rename, so a reader in the other
 * process sees the old file or the new one, never half of one. Everything here
 * is derived data: losing it costs a card its content, never the app itself.
 */
export class LocalGenUIDesktopCardStore {
  private readonly root: string;

  constructor(filesDir: string) {
    this.root = `${filesDir}/local-genui/desktop-cards`;
  }

  // Bindings

  bind(formId: string, appId: string): void {
    if (formId.length === 0 || !LocalGenUIDesktopCards.isAppId(appId)) {
      return;
    }
    const binding: LocalGenUIDesktopCardBinding = { formId, appId, boundAt: new Date().toISOString() };
    this.writeJson(this.bindingPath(formId), JSON.stringify(binding));
  }

  unbind(formId: string): void {
    this.unlink(this.bindingPath(formId));
  }

  appOf(formId: string): string {
    const binding = this.readJson<LocalGenUIDesktopCardBinding>(this.bindingPath(formId));
    return binding && LocalGenUIDesktopCards.isAppId(binding.appId) ? binding.appId : '';
  }

  /** Cards on the home screen that open `appId`. */
  formsOf(appId: string): string[] {
    const forms: string[] = [];
    this.list(`${this.root}/bindings`).forEach((name: string) => {
      const binding = this.readJson<LocalGenUIDesktopCardBinding>(`${this.root}/bindings/${name}`);
      if (binding && binding.appId === appId && binding.formId.length > 0) {
        forms.push(binding.formId);
      }
    });
    return forms;
  }

  // Pending add

  /**
   * Some launchers neither forward custom want parameters to `onAddForm` nor
   * call the `AddFormMenuItem` callback, so the card host would not know which
   * app a new card opens. The UI process stages the app when the add menu
   * opens; the card host claims it once, for the card it is adding.
   */
  stagePendingAdd(appId: string, now: number = Date.now()): void {
    if (!LocalGenUIDesktopCards.isAppId(appId)) {
      return;
    }
    const pending: LocalGenUIDesktopCardPendingAdd = { appId, stagedAt: now };
    this.writeJson(this.pendingPath(), JSON.stringify(pending));
  }

  claimPendingAdd(now: number = Date.now()): string {
    const pending = this.readJson<LocalGenUIDesktopCardPendingAdd>(this.pendingPath());
    this.unlink(this.pendingPath());
    if (!pending || !LocalGenUIDesktopCards.isAppId(pending.appId)) {
      return '';
    }
    const age = now - pending.stagedAt;
    return age >= 0 && age <= PENDING_ADD_TTL_MS ? pending.appId : '';
  }

  // App projections

  app(appId: string): LocalGenUIDesktopCardApp | undefined {
    return this.readJson<LocalGenUIDesktopCardApp>(this.appPath(appId));
  }

  /** Record what cards show for an app; no cards are touched. */
  saveApp(app: LocalGenUIDesktopCardApp): void {
    if (!LocalGenUIDesktopCards.isAppId(app.appId)) {
      return;
    }
    this.writeJson(this.appPath(app.appId), JSON.stringify(app));
  }

  /** Record the app and repaint every card bound to it. */
  async publish(app: LocalGenUIDesktopCardApp): Promise<void> {
    const forms = this.formsOf(app.appId);
    if (forms.length === 0 && !this.app(app.appId)) {
      // No card has ever shown this app: nothing to keep in step.
      return;
    }
    this.saveApp(app);
    for (let i = 0; i < forms.length; i++) {
      await this.refresh(forms[i]);
    }
  }

  // Card content

  /** Text-only content for `onAddForm`; the preview follows through `refresh`. */
  textData(formId: string): LocalGenUIDesktopCardData {
    const appId = this.appOf(formId);
    return LocalGenUIDesktopCards.cardData(formId, appId, appId.length > 0 ? this.app(appId) : undefined, false);
  }

  /**
   * Push the card's current content, preview included. A card the launcher
   * already removed fails here; its binding is dropped with it.
   */
  async refresh(formId: string): Promise<boolean> {
    const appId = this.appOf(formId);
    const app = appId.length > 0 ? this.app(appId) : undefined;
    const thumbnail = app && app.available ? app.thumbnailPath : '';
    let fd: number = -1;
    if (thumbnail.length > 0) {
      try {
        fd = fs.openSync(thumbnail, fs.OpenMode.READ_ONLY).fd;
      } catch (_err) {
        fd = -1;
      }
    }
    const data = LocalGenUIDesktopCards.cardData(formId, appId, app, fd >= 0);
    const payload: Record<string, Object> = {};
    payload['formId'] = data.formId;
    payload['appId'] = data.appId;
    payload['state'] = data.state;
    payload['title'] = data.title;
    payload['initial'] = data.initial;
    payload['imageName'] = data.imageName;
    if (fd >= 0 && data.imageName.length > 0) {
      const images: Record<string, number> = {};
      images[data.imageName] = fd;
      payload['formImages'] = images;
    }
    try {
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(payload));
      return true;
    } catch (err) {
      // 16501001: the form id does not exist; the card is gone from the screen.
      if ((err as BusinessError).code === FORM_NOT_EXIST) {
        this.unbind(formId);
      }
      return false;
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (_err) {
          // Already closed by the platform.
        }
      }
    }
  }

  // Files

  private pendingPath(): string {
    return `${this.root}/pending-add.json`;
  }

  private bindingPath(formId: string): string {
    return `${this.root}/bindings/${LocalGenUIDesktopCards.fileKey(formId)}.json`;
  }

  private appPath(appId: string): string {
    return `${this.root}/apps/${LocalGenUIDesktopCards.fileKey(appId)}.json`;
  }

  private list(directory: string): string[] {
    try {
      if (!fs.accessSync(directory)) {
        return [];
      }
      return fs.listFileSync(directory).filter((name: string) => name.endsWith('.json'));
    } catch (_err) {
      return [];
    }
  }

  private readJson<T>(path: string): T | undefined {
    try {
      if (!fs.accessSync(path)) {
        return undefined;
      }
      return JSON.parse(fs.readTextSync(path)) as T;
    } catch (_err) {
      return undefined;
    }
  }

  /** Derived data: a failed write leaves the previous file, never half of one. */
  private writeJson(path: string, text: string): void {
    const temporary = `${path}.${Date.now()}.tmp`;
    try {
      const directory = path.substring(0, path.lastIndexOf('/'));
      if (!fs.accessSync(directory)) {
        fs.mkdirSync(directory, true);
      }
      const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, text);
      } finally {
        fs.closeSync(file);
      }
      fs.renameSync(temporary, path);
    } catch (_err) {
      this.unlink(temporary);
    }
  }

  private unlink(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (_err) {
      // Derived data.
    }
  }
}
