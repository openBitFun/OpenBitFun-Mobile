import { preferences } from '@kit.ArkData';
import { huks } from '@kit.UniversalKeystoreKit';
import { util } from '@kit.ArkTS';
import { Encoding } from '../Encoding';
import { OhosError } from '../OhosError';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { GeneralChatConfigStore } from '../general-chat/GeneralChatConfigStore';
import { LocalGenUIModelCatalog, LocalGenUIModelProfile } from './LocalGenUIModelCatalog';

const STORE_NAME: string = 'openbitfun_local_genui_models';
const MODELS_KEY: string = 'models';
const LAST_SELECTED_KEY: string = 'last_selected_model_id';
const IMPORTED_KEY: string = 'imported_general_chat_config';
const HUKS_ALIAS: string = 'openbitfun_local_genui_model_keys';

/** Stored row. Unknown fields written by newer builds are preserved. */
interface StoredModel {
  id: string;
  name: string;
  apiUrl: string;
  modelName: string;
  createdAt: string;
  keyCipher: string;
  keyIv: string;
}

export interface LocalGenUIModelUpdate {
  /** Empty for a new model. */
  id: string;
  name: string;
  apiUrl: string;
  modelName: string;
  /** Empty keeps the stored key of an existing model. */
  apiKey: string;
}

export interface LocalGenUIModelCredentials {
  apiUrl: string;
  modelName: string;
  apiKey: string;
}

/**
 * Model profiles for Local GenUI Mode only. Keys never leave the phone and are
 * encrypted with a HUKS AES key. The legacy single General Chat configuration
 * is imported once as the first profile and left untouched.
 */
export class LocalGenUIModelStore {
  private store?: preferences.Preferences;
  private models: StoredModel[] = [];

  async init(context: Context, legacy: GeneralChatConfigStore): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME);
      this.models = this.parse(await this.getString(MODELS_KEY));
      if (!(await this.requireStore().get(IMPORTED_KEY, false))) {
        await this.importLegacy(legacy);
      }
    } catch (err) {
      throw OhosError.wrap('local genui model store init', err);
    }
  }

  list(): LocalGenUIModelProfile[] {
    return this.models.map((model: StoredModel): LocalGenUIModelProfile => ({
      id: model.id, name: model.name, apiUrl: model.apiUrl, modelName: model.modelName, createdAt: model.createdAt
    }));
  }

  hasKey(id: string): boolean {
    const model = this.models.find((item: StoredModel) => item.id === id);
    return model !== undefined && model.keyCipher.length > 0 && model.keyIv.length > 0;
  }

  async lastSelectedId(): Promise<string> {
    return await this.getString(LAST_SELECTED_KEY);
  }

  async setLastSelected(id: string): Promise<void> {
    await this.requireStore().put(LAST_SELECTED_KEY, id);
    await this.requireStore().flush();
  }

  async save(update: LocalGenUIModelUpdate): Promise<LocalGenUIModelProfile> {
    const existing = this.models.find((item: StoredModel) => item.id === update.id);
    const error = LocalGenUIModelCatalog.validate(update.apiUrl, update.modelName, update.apiKey,
      existing !== undefined && existing.keyCipher.length > 0);
    if (error.length > 0) {
      throw new Error(RemoteI18n.t(error));
    }
    const row: StoredModel = existing ? JSON.parse(JSON.stringify(existing)) as StoredModel : {
      id: `model-${util.generateRandomUUID(false)}`,
      name: '', apiUrl: '', modelName: '', createdAt: new Date().toISOString(), keyCipher: '', keyIv: ''
    };
    row.name = update.name.trim();
    row.apiUrl = LocalGenUIModelCatalog.normalizeUrl(update.apiUrl);
    row.modelName = update.modelName.trim();
    if (update.apiKey.trim().length > 0) {
      const encrypted = await this.encrypt(update.apiKey.trim());
      row.keyCipher = encrypted[0];
      row.keyIv = encrypted[1];
    }
    const next = this.models.filter((item: StoredModel) => item.id !== row.id);
    next.push(row);
    next.sort((a: StoredModel, b: StoredModel) => a.createdAt.localeCompare(b.createdAt));
    await this.persist(next);
    if ((await this.lastSelectedId()).length === 0) {
      await this.setLastSelected(row.id);
    }
    return { id: row.id, name: row.name, apiUrl: row.apiUrl, modelName: row.modelName, createdAt: row.createdAt };
  }

  /** Deleting a model is explicit; sessions that used it then report it missing. */
  async remove(id: string): Promise<void> {
    await this.persist(this.models.filter((item: StoredModel) => item.id !== id));
    if ((await this.lastSelectedId()) === id) {
      await this.setLastSelected(this.models.length > 0 ? this.models[0].id : '');
    }
  }

  async credentials(id: string): Promise<LocalGenUIModelCredentials | undefined> {
    const model = this.models.find((item: StoredModel) => item.id === id);
    if (!model || model.keyCipher.length === 0) {
      return undefined;
    }
    return { apiUrl: model.apiUrl, modelName: model.modelName, apiKey: await this.decrypt(model.keyCipher, model.keyIv) };
  }

  private async importLegacy(legacy: GeneralChatConfigStore): Promise<void> {
    try {
      const snapshot = await legacy.snapshot();
      if (this.models.length === 0 && snapshot.apiUrl.length > 0 && snapshot.modelName.length > 0 && snapshot.hasApiKey) {
        const key = (await legacy.accessToken()).trim();
        if (key.length > 0) {
          await this.save({ id: '', name: '', apiUrl: snapshot.apiUrl, modelName: snapshot.modelName, apiKey: key });
        }
      }
    } finally {
      // Mark once; a failed import keeps the legacy configuration readable.
      await this.requireStore().put(IMPORTED_KEY, true);
      await this.requireStore().flush();
    }
  }

  private async persist(models: StoredModel[]): Promise<void> {
    await this.requireStore().put(MODELS_KEY, JSON.stringify(models));
    await this.requireStore().flush();
    this.models = models;
  }

  private parse(json: string): StoredModel[] {
    try {
      const value = JSON.parse(json.length > 0 ? json : '[]') as Object;
      return Array.isArray(value) ? (value as StoredModel[]).filter((item: StoredModel) => typeof item.id === 'string') : [];
    } catch (_err) {
      return [];
    }
  }

  private async encrypt(apiKey: string): Promise<string[]> {
    try {
      await this.ensureKey();
      const iv = Encoding.randomBytes(16);
      const options = LocalGenUIModelStore.options(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, iv);
      const session = await huks.initSession(HUKS_ALIAS, options);
      const result = await huks.finishSession(session.handle, { properties: options.properties, inData: Encoding.utf8ToBytes(apiKey) });
      if (!result.outData || result.outData.length === 0) {
        throw new Error(RemoteI18n.t('settings.modelService.encryptFailed'));
      }
      return [Encoding.bytesToBase64(result.outData), Encoding.bytesToBase64(iv)];
    } catch (err) {
      throw OhosError.wrap('local genui encrypt model key', err);
    }
  }

  private async decrypt(cipher: string, ivText: string): Promise<string> {
    try {
      const options = LocalGenUIModelStore.options(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, Encoding.base64ToBytes(ivText));
      const session = await huks.initSession(HUKS_ALIAS, options);
      const result = await huks.finishSession(session.handle, { properties: options.properties, inData: Encoding.base64ToBytes(cipher) });
      return result.outData ? Encoding.bytesToUtf8(result.outData) : '';
    } catch (err) {
      throw OhosError.wrap('local genui decrypt model key', err);
    }
  }

  private async ensureKey(): Promise<void> {
    let exists = false;
    try {
      exists = await huks.isKeyItemExist(HUKS_ALIAS, {});
    } catch (_err) {
      exists = false;
    }
    if (exists) {
      return;
    }
    await huks.generateKeyItem(HUKS_ALIAS, {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CBC },
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 }
      ]
    });
  }

  private static options(purpose: huks.HuksKeyPurpose, iv: Uint8Array): huks.HuksOptions {
    return {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CBC },
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 },
        { tag: huks.HuksTag.HUKS_TAG_IV, value: iv }
      ]
    };
  }

  private async getString(key: string): Promise<string> {
    const value = await this.requireStore().get(key, '');
    return typeof value === 'string' ? value : '';
  }

  private requireStore(): preferences.Preferences {
    if (!this.store) {
      throw new Error('local genui model store is not initialized');
    }
    return this.store;
  }
}
