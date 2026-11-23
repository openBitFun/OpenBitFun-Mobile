import { LocalGenUICalendarReceiptPort } from './LocalGenUICalendarActions';
import { relationalStore } from '@kit.ArkData';
import { OhosError } from '../OhosError';
import { HarmonyUpgradeIdentityContract } from '../HarmonyUpgradeIdentityContract';
import { LocalGenUIAppPort } from './LocalGenUIOwner';
import {
  LocalGenUIAppRecord,
  LocalGenUIAppStatus,
  LocalGenUIGalleryEntry,
  LocalGenUIIds,
  LocalGenUIMessage,
  LocalGenUISession
} from './LocalGenUIModels';

/**
 * Local GenUI persistence. It shares the `general_chat` database file but owns
 * separate tables; retired `general_chat_*` rows are never read or executed.
 */
const STORE_CONFIG: relationalStore.StoreConfig = {
  name: HarmonyUpgradeIdentityContract.GENERAL_CHAT_DATABASE,
  securityLevel: relationalStore.SecurityLevel.S1
};

const CREATE_SQL: string[] = [
  'CREATE TABLE IF NOT EXISTS local_genui_sessions (' +
    'id TEXT PRIMARY KEY, updated_at TEXT NOT NULL, payload TEXT NOT NULL)',
  'CREATE TABLE IF NOT EXISTS local_genui_messages (' +
    'id TEXT PRIMARY KEY, session_id TEXT NOT NULL, created_at TEXT NOT NULL, payload TEXT NOT NULL)',
  'CREATE INDEX IF NOT EXISTS idx_local_genui_messages_session ON local_genui_messages(session_id, created_at)',
  // Columns follow the design document; `payload` keeps the complete record so
  // fields added by newer builds survive older readers and writers.
  'CREATE TABLE IF NOT EXISTS local_genui_apps (' +
    'app_id TEXT PRIMARY KEY, session_id TEXT NOT NULL, message_id TEXT NOT NULL, schema_version INTEGER NOT NULL, ' +
    'title TEXT NOT NULL, template TEXT NOT NULL, library_id TEXT NOT NULL, library_revision INTEGER NOT NULL, ' +
    'design_spec TEXT NOT NULL, source_content TEXT NOT NULL, state_json TEXT NOT NULL, ' +
    'source_revision INTEGER NOT NULL, state_revision INTEGER NOT NULL, owner_revision INTEGER NOT NULL, ' +
    'status TEXT NOT NULL, updated_at TEXT NOT NULL, payload TEXT NOT NULL)',
  'CREATE INDEX IF NOT EXISTS idx_local_genui_apps_session ON local_genui_apps(session_id)',
  // Gallery membership is a user choice, separate from owner revisions.
  'CREATE TABLE IF NOT EXISTS local_genui_gallery (' +
    'app_id TEXT PRIMARY KEY, added_at TEXT NOT NULL, payload TEXT NOT NULL)',
  'CREATE TABLE IF NOT EXISTS local_genui_calendar_receipts (' +
    'app_id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY (app_id, payload))'
];

export class LocalGenUIRepository implements LocalGenUIAppPort, LocalGenUICalendarReceiptPort {
  private store?: relationalStore.RdbStore;

  async init(context: Context): Promise<void> {
    try {
      this.store = await relationalStore.getRdbStore(context, STORE_CONFIG);
      for (let i = 0; i < CREATE_SQL.length; i++) {
        await this.store.executeSql(CREATE_SQL[i]);
      }
    } catch (err) {
      throw OhosError.wrap('local genui store init', err);
    }
  }

  async calendarReceipts(appId: string): Promise<string[]> {
    return this.queryPayloads('SELECT payload FROM local_genui_calendar_receipts WHERE app_id = ?', [appId]);
  }

  async saveCalendarReceipt(appId: string, paramsJson: string): Promise<void> {
    LocalGenUIIds.require(appId, 'app');
    await this.insert('local_genui_calendar_receipts', { app_id: appId, payload: paramsJson });
  }

  async listSessions(): Promise<LocalGenUISession[]> {
    const rows = await this.queryPayloads('SELECT payload FROM local_genui_sessions ORDER BY updated_at DESC', []);
    const sessions: LocalGenUISession[] = [];
    rows.forEach((payload: string) => {
      const session = LocalGenUIRepository.parse<LocalGenUISession>(payload);
      if (session && LocalGenUIIds.isLocal(session.id)) {
        sessions.push(session);
      }
    });
    return sessions;
  }

  async upsertSession(session: LocalGenUISession): Promise<void> {
    LocalGenUIIds.require(session.id, 'session');
    await this.insert('local_genui_sessions', {
      id: session.id,
      updated_at: session.updatedAt,
      payload: JSON.stringify(session)
    });
  }

  async deleteSession(sessionId: string): Promise<void> {
    LocalGenUIIds.require(sessionId, 'session');
    try {
      const store = this.requireStore();
      await store.executeSql(
        'DELETE FROM local_genui_gallery WHERE app_id IN (SELECT app_id FROM local_genui_apps WHERE session_id = ?)', [sessionId]);
      await store.executeSql('DELETE FROM local_genui_apps WHERE session_id = ?', [sessionId]);
      await store.executeSql('DELETE FROM local_genui_messages WHERE session_id = ?', [sessionId]);
      await store.executeSql('DELETE FROM local_genui_sessions WHERE id = ?', [sessionId]);
    } catch (err) {
      throw OhosError.wrap('local genui delete session', err);
    }
  }

  async loadMessages(sessionId: string): Promise<LocalGenUIMessage[]> {
    LocalGenUIIds.require(sessionId, 'session');
    const rows = await this.queryPayloads(
      'SELECT payload FROM local_genui_messages WHERE session_id = ? ORDER BY created_at ASC, id ASC', [sessionId]);
    const messages: LocalGenUIMessage[] = [];
    rows.forEach((payload: string) => {
      const message = LocalGenUIRepository.parse<LocalGenUIMessage>(payload);
      if (message) {
        messages.push(message);
      }
    });
    return messages;
  }

  async upsertMessage(message: LocalGenUIMessage): Promise<void> {
    LocalGenUIIds.require(message.sessionId, 'session');
    await this.insert('local_genui_messages', {
      id: message.id,
      session_id: message.sessionId,
      created_at: message.createdAt,
      payload: JSON.stringify(message)
    });
  }

  async appIdsOfSession(sessionId: string): Promise<string[]> {
    const rows = await this.queryPayloads('SELECT payload FROM local_genui_apps WHERE session_id = ?', [sessionId]);
    const ids: string[] = [];
    rows.forEach((payload: string) => {
      const record = LocalGenUIRepository.parse<LocalGenUIAppRecord>(payload);
      if (record) ids.push(record.appId);
    });
    return ids;
  }

  async pendingAppOfSession(sessionId: string): Promise<LocalGenUIAppRecord | undefined> {
    const rows = await this.queryPayloads(
      'SELECT payload FROM local_genui_apps WHERE session_id = ? AND status = ? ORDER BY updated_at DESC LIMIT 1',
      [sessionId, LocalGenUIAppStatus.Candidate]);
    return rows.length > 0 ? LocalGenUIRepository.parse<LocalGenUIAppRecord>(rows[0]) : undefined;
  }

  async listGallery(): Promise<LocalGenUIGalleryEntry[]> {
    const rows = await this.queryPayloads('SELECT payload FROM local_genui_gallery ORDER BY added_at DESC', []);
    const entries: LocalGenUIGalleryEntry[] = [];
    rows.forEach((payload: string) => {
      const entry = LocalGenUIRepository.parse<LocalGenUIGalleryEntry>(payload);
      if (entry && LocalGenUIIds.isLocal(entry.appId)) {
        entries.push(entry);
      }
    });
    return entries;
  }

  async addToGallery(entry: LocalGenUIGalleryEntry): Promise<void> {
    LocalGenUIIds.require(entry.appId, 'app');
    await this.insert('local_genui_gallery', { app_id: entry.appId, added_at: entry.addedAt, payload: JSON.stringify(entry) });
  }

  async removeFromGallery(appId: string): Promise<void> {
    try {
      await this.requireStore().executeSql('DELETE FROM local_genui_gallery WHERE app_id = ?', [appId]);
    } catch (err) {
      throw OhosError.wrap('local genui remove gallery entry', err);
    }
  }

  async loadApp(appId: string): Promise<LocalGenUIAppRecord | undefined> {
    const rows = await this.queryPayloads('SELECT payload FROM local_genui_apps WHERE app_id = ?', [appId]);
    return rows.length > 0 ? LocalGenUIRepository.parse<LocalGenUIAppRecord>(rows[0]) : undefined;
  }

  async insertApp(record: LocalGenUIAppRecord): Promise<void> {
    LocalGenUIIds.require(record.appId, 'app');
    try {
      await this.requireStore().insert('local_genui_apps', LocalGenUIRepository.appValues(record),
        relationalStore.ConflictResolution.ON_CONFLICT_ABORT);
    } catch (err) {
      throw OhosError.wrap('local genui insert app', err);
    }
  }

  async compareAndSwapApp(record: LocalGenUIAppRecord, expectedOwnerRevision: number): Promise<boolean> {
    try {
      const predicates = new relationalStore.RdbPredicates('local_genui_apps');
      predicates.equalTo('app_id', record.appId).and().equalTo('owner_revision', expectedOwnerRevision);
      const changed = await this.requireStore().update(LocalGenUIRepository.appValues(record), predicates);
      return changed === 1;
    } catch (err) {
      throw OhosError.wrap('local genui compare-and-swap app', err);
    }
  }

  private static appValues(record: LocalGenUIAppRecord): relationalStore.ValuesBucket {
    return {
      app_id: record.appId,
      session_id: record.sessionId,
      message_id: record.messageId,
      schema_version: record.schemaVersion,
      title: record.title,
      template: record.template,
      library_id: record.libraryId,
      library_revision: record.libraryRevision,
      design_spec: `${record.designSpecId}@${record.designSpecRevision}`,
      source_content: record.sourceContent,
      state_json: record.stateJson,
      source_revision: record.sourceRevision,
      state_revision: record.stateRevision,
      owner_revision: record.ownerRevision,
      status: record.status,
      updated_at: record.updatedAt,
      payload: JSON.stringify(record)
    };
  }

  private async insert(table: string, values: relationalStore.ValuesBucket): Promise<void> {
    try {
      await this.requireStore().insert(table, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    } catch (err) {
      throw OhosError.wrap(`local genui write ${table}`, err);
    }
  }

  private async queryPayloads(sql: string, args: relationalStore.ValueType[]): Promise<string[]> {
    try {
      const result = await this.requireStore().querySql(sql, args);
      const rows: string[] = [];
      try {
        const column = result.getColumnIndex('payload');
        while (result.goToNextRow()) {
          rows.push(result.getString(column));
        }
      } finally {
        result.close();
      }
      return rows;
    } catch (err) {
      throw OhosError.wrap('local genui query', err);
    }
  }

  /** Corrupt rows are skipped for display but never deleted. */
  private static parse<T>(payload: string): T | undefined {
    try {
      return JSON.parse(payload) as T;
    } catch (_err) {
      return undefined;
    }
  }

  private requireStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('local genui store is not initialized');
    }
    return this.store;
  }
}
