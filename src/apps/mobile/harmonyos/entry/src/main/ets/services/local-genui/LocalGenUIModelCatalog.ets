/**
 * Local GenUI model catalog policy. Pure: selection rules are tested without
 * preferences or HUKS.
 */
export interface LocalGenUIModelProfile {
  id: string;
  /** Display name; defaults to the model name. */
  name: string;
  apiUrl: string;
  modelName: string;
  createdAt: string;
}

export interface LocalGenUIModelChoice {
  /** The model a turn would use, if any. */
  model?: LocalGenUIModelProfile;
  /** The session names a model that no longer exists. */
  missing: boolean;
}

export class LocalGenUIModelCatalog {
  /**
   * A session keeps the model it was created with. A deleted model is reported
   * as missing instead of silently switching the session to another model.
   */
  static choose(models: LocalGenUIModelProfile[], sessionModelId: string, lastSelectedId: string): LocalGenUIModelChoice {
    if (sessionModelId.length > 0) {
      const pinned = models.find((model: LocalGenUIModelProfile) => model.id === sessionModelId);
      return pinned ? { model: pinned, missing: false } : { missing: true };
    }
    const last = models.find((model: LocalGenUIModelProfile) => model.id === lastSelectedId);
    if (last) {
      return { model: last, missing: false };
    }
    return models.length > 0 ? { model: models[0], missing: false } : { missing: false };
  }

  static displayName(model: LocalGenUIModelProfile): string {
    return model.name.trim().length > 0 ? model.name.trim() : model.modelName;
  }

  /** Returns an i18n key for the first invalid field, or ''. */
  static validate(apiUrl: string, modelName: string, apiKey: string, hasStoredKey: boolean): string {
    const url = apiUrl.trim().toLowerCase();
    if (!(url.startsWith('https://') || url.startsWith('http://')) || url.length <= 8) {
      return 'settings.modelService.invalidUrl';
    }
    if (modelName.trim().length === 0) {
      return 'settings.modelService.modelRequired';
    }
    if (apiKey.trim().length === 0 && !hasStoredKey) {
      return 'settings.modelService.apiKeyRequired';
    }
    return '';
  }

  static normalizeUrl(value: string): string {
    return value.trim().replace(/\/+$/, '');
  }
}
