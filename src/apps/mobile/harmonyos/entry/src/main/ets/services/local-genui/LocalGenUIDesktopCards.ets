import { Want } from '@kit.AbilityKit';
import { LOCAL_GENUI_NAMESPACE } from './LocalGenUIModels';

/**
 * Desktop (home screen) cards of generated apps: pure policy shared by the
 * main UI process and `LocalGenUIFormAbility`. Platform kits are used for
 * types only.
 *
 * A card is an entry, not a runtime: service widgets cannot host ArkWeb, so a
 * card shows the app's title and preview and opens the app in the phone app.
 */
export const DESKTOP_CARD_ABILITY: string = 'LocalGenUIFormAbility';
export const DESKTOP_CARD_FORM_NAME: string = 'local_genui_app';
export const DESKTOP_CARD_MODULE: string = 'entry';
/** 2x2, `formInfo.FormDimension.Dimension_2_2`. */
export const DESKTOP_CARD_DIMENSION: number = 2;
/** Want parameter carrying the app id into `onAddForm`. */
export const DESKTOP_CARD_APP_PARAM: string = 'openbitfunLocalGenUIAppId';
/** Router parameter carrying the app id from a card tap into `EntryAbility`. */
export const DESKTOP_CARD_LAUNCH_PARAM: string = 'openbitfunLocalGenUIApp';
export const FORM_IDENTITY_PARAM: string = 'ohos.extra.param.key.form_identity';

export enum LocalGenUIDesktopCardState {
  /** The card exists but its app is not known to it yet. */
  Pending = 'pending',
  Ready = 'ready',
  /** The app was deleted or can no longer run; the card says so. */
  Missing = 'missing'
}

/** What a card shows for one app; written by the app, read by the card host. */
export interface LocalGenUIDesktopCardApp {
  appId: string;
  title: string;
  thumbnailPath: string;
  available: boolean;
  updatedAt: string;
}

export interface LocalGenUIDesktopCardBinding {
  formId: string;
  appId: string;
  boundAt: string;
}

/** Binding data of the card page (`LocalStorage` keys of the widget). */
export interface LocalGenUIDesktopCardData {
  formId: string;
  appId: string;
  state: string;
  title: string;
  initial: string;
  /** `formImages` key; empty when the card shows the fallback tile. */
  imageName: string;
}

export class LocalGenUIDesktopCards {
  static isAppId(appId: string): boolean {
    return appId.startsWith(LOCAL_GENUI_NAMESPACE) && appId.length > LOCAL_GENUI_NAMESPACE.length;
  }

  /** The want handed to `AddFormMenuItem` for one app. */
  static addWant(bundleName: string, appId: string): Want {
    const parameters: Record<string, Object> = {};
    parameters['ohos.extra.param.key.form_dimension'] = DESKTOP_CARD_DIMENSION;
    parameters['ohos.extra.param.key.form_name'] = DESKTOP_CARD_FORM_NAME;
    parameters['ohos.extra.param.key.module_name'] = DESKTOP_CARD_MODULE;
    parameters[DESKTOP_CARD_APP_PARAM] = appId;
    return { bundleName, abilityName: DESKTOP_CARD_ABILITY, parameters };
  }

  /** App id carried by `onAddForm`'s want, when the launcher forwarded it. */
  static appIdOfAddWant(parameters: Record<string, Object> | undefined): string {
    const value = parameters ? parameters[DESKTOP_CARD_APP_PARAM] : undefined;
    const appId = typeof value === 'string' ? value : '';
    return LocalGenUIDesktopCards.isAppId(appId) ? appId : '';
  }

  /**
   * App id of a card tap. Router events deliver their params as a JSON string
   * under `params`; a direct key is accepted as well. Anything outside the
   * local namespace is ignored, so a crafted want cannot open a remote id.
   */
  static launchAppId(parameters: Record<string, Object> | undefined): string {
    if (!parameters) {
      return '';
    }
    let value: Object | undefined = parameters[DESKTOP_CARD_LAUNCH_PARAM];
    const params = parameters['params'];
    if (value === undefined && typeof params === 'string') {
      try {
        const parsed = JSON.parse(params) as Record<string, Object>;
        value = parsed[DESKTOP_CARD_LAUNCH_PARAM];
      } catch (_err) {
        value = undefined;
      }
    }
    const appId = typeof value === 'string' ? value : '';
    return LocalGenUIDesktopCards.isAppId(appId) ? appId : '';
  }

  /** File-name-safe key; ids are namespaced and may contain `:`. */
  static fileKey(id: string): string {
    return id.replace(/[^A-Za-z0-9_-]/g, '_');
  }

  /** A versioned image key, so the launcher does not keep a cached preview. */
  static imageName(thumbnailPath: string): string {
    if (thumbnailPath.length === 0) {
      return '';
    }
    const base = thumbnailPath.substring(thumbnailPath.lastIndexOf('/') + 1).replace(/\.[^.]*$/, '');
    return `genui_${LocalGenUIDesktopCards.fileKey(base)}`;
  }

  static initial(title: string): string {
    const trimmed = title.trim();
    return trimmed.length > 0 ? Array.from(trimmed)[0] : 'AI';
  }

  /** Card content for a form, from its binding and the app projection. */
  static cardData(formId: string, appId: string, app: LocalGenUIDesktopCardApp | undefined,
    imageAvailable: boolean): LocalGenUIDesktopCardData {
    if (appId.length === 0) {
      return { formId, appId: '', state: LocalGenUIDesktopCardState.Pending, title: '', initial: 'AI', imageName: '' };
    }
    if (!app) {
      // Bound, but nothing written for the app yet: still an entry to it.
      return { formId, appId, state: LocalGenUIDesktopCardState.Pending, title: '', initial: 'AI', imageName: '' };
    }
    const state = app.available ? LocalGenUIDesktopCardState.Ready : LocalGenUIDesktopCardState.Missing;
    const imageName = app.available && imageAvailable ? LocalGenUIDesktopCards.imageName(app.thumbnailPath) : '';
    return { formId, appId, state, title: app.title, initial: LocalGenUIDesktopCards.initial(app.title), imageName };
  }
}
