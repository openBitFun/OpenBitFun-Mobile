import {
  LOCAL_GENUI_SCHEMA_VERSION,
  LocalGenUIAppRecord,
  LocalGenUIAppStatus,
  LocalGenUIIdentity,
  LocalGenUIIds,
  LocalGenUIManifest,
  LocalGenUIVerification
} from './LocalGenUIModels';
import { LocalGenUIGeneration } from './LocalGenUIStreamParser';

/** Persistence port; the RDB repository implements it. */
export interface LocalGenUIAppPort {
  loadApp(appId: string): Promise<LocalGenUIAppRecord | undefined>;
  insertApp(record: LocalGenUIAppRecord): Promise<void>;
  /** Writes `record` only when the stored owner revision equals `expectedOwnerRevision`. */
  compareAndSwapApp(record: LocalGenUIAppRecord, expectedOwnerRevision: number): Promise<boolean>;
}

export interface LocalGenUIRunnableRevision {
  source: string;
  stateJson: string;
  sourceRevision: number;
  stateRevision: number;
  status: string;
}

export enum LocalStateSaveOutcome {
  Saved = 'saved',
  Conflict = 'conflict',
  StaleSource = 'stale_source',
  Rejected = 'rejected'
}

export interface LocalStateSaveResult {
  outcome: LocalStateSaveOutcome;
  record?: LocalGenUIAppRecord;
  error: string;
}

export interface LocalStateMigration {
  ok: boolean;
  stateJson: string;
  reason: string;
}

function typeOfValue(value: Object | null): string {
  if (value === null) {
    return 'null';
  }
  return Array.isArray(value) ? 'array' : typeof value;
}

function parseState(json: string): Record<string, Object> | undefined {
  try {
    const value = JSON.parse(json.length > 0 ? json : '{}') as Object;
    return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, Object> : undefined;
  } catch (_err) {
    return undefined;
  }
}

/**
 * State migration when the model replaces the source of an app.
 * The key set is the new source's declared state (reported by the OpenUI
 * parser in the runtime, `null` meaning no declared default) plus the
 * model's initial values. Untouched state follows the new initial values.
 * User-edited state keeps keys that still exist with a compatible type; any
 * removal or type change requires an explicit migration and leaves the
 * previous revision in place.
 */
export function migrateLocalState(previousJson: string, userEdited: boolean, initialJson: string, declaredTypes: Record<string, string> = {}): LocalStateMigration {
  const initial = parseState(initialJson);
  if (!initial) {
    return { ok: false, stateJson: previousJson, reason: 'candidate initial values are not an object' };
  }
  if (!userEdited) {
    return { ok: true, stateJson: JSON.stringify(initial), reason: '' };
  }
  const previous = parseState(previousJson);
  if (!previous) {
    return { ok: false, stateJson: previousJson, reason: 'stored user state is unreadable' };
  }
  const schema: Map<string, string> = new Map<string, string>();
  Object.keys(declaredTypes).forEach((key: string) => schema.set(key, declaredTypes[key]));
  Object.keys(initial).forEach((key: string) => schema.set(key, typeOfValue(initial[key])));
  const next: Record<string, Object> = {};
  const previousKeys = Object.keys(previous);
  for (let i = 0; i < previousKeys.length; i++) {
    const key = previousKeys[i];
    const declared = schema.get(key);
    if (declared === undefined) {
      return { ok: false, stateJson: previousJson, reason: `state key ${key} was removed` };
    }
    if (declared !== 'null' && previous[key] !== null && typeOfValue(previous[key]) !== declared) {
      return { ok: false, stateJson: previousJson, reason: `state key ${key} changed type` };
    }
    next[key] = previous[key];
  }
  Object.keys(initial).forEach((key: string) => {
    if (!previousKeys.includes(key)) {
      next[key] = initial[key];
    }
  });
  return { ok: true, stateJson: JSON.stringify(next), reason: '' };
}

/** Checks the local runtime can execute; required checks come from the design spec. */
export function requiredChecksSatisfied(verification: LocalGenUIVerification, required: string[]): boolean {
  for (let i = 0; i < required.length; i++) {
    const check = verification.checks.find((item) => item.name === required[i]);
    if (!check || check.result !== 'passed') {
      return false;
    }
  }
  return true;
}

/**
 * The single owner of Local GenUI source/state revisions. All durable writes
 * go through compare-and-swap on ownerRevision.
 */
export class LocalGenUIOwner {
  private readonly port: LocalGenUIAppPort;
  private readonly manifest: LocalGenUIManifest;
  private readonly now: () => string;

  constructor(port: LocalGenUIAppPort, manifest: LocalGenUIManifest, now: () => string = () => new Date().toISOString()) {
    this.port = port;
    this.manifest = manifest;
    this.now = now;
  }

  /** Bind identity for a new app from the generated manifest only. */
  newIdentity(appId: string, toolCallId: string, title: string): LocalGenUIIdentity {
    return {
      appId: LocalGenUIIds.require(appId, 'app'),
      toolCallId,
      title,
      template: this.manifest.template,
      libraryId: this.manifest.libraryId,
      libraryRevision: this.manifest.libraryRevision,
      designSpec: { id: this.manifest.designSpec.id, revision: this.manifest.designSpec.revision },
      sourceFormat: 'openui-lang'
    };
  }

  /** Inherit identity from an existing app; a different contract is unsupported here. */
  inheritedIdentity(record: LocalGenUIAppRecord, toolCallId: string, title: string): LocalGenUIIdentity | undefined {
    if (!this.isRunnable(record)) {
      return undefined;
    }
    return {
      appId: record.appId,
      toolCallId,
      title: title.length > 0 ? title : record.title,
      template: record.template,
      libraryId: record.libraryId,
      libraryRevision: record.libraryRevision,
      designSpec: { id: record.designSpecId, revision: record.designSpecRevision },
      sourceFormat: record.sourceFormat
    };
  }

  /** Unknown schema, library, design spec or format is retained but never executed. */
  isRunnable(record: LocalGenUIAppRecord): boolean {
    return record.schemaVersion === LOCAL_GENUI_SCHEMA_VERSION &&
      record.sourceFormat === 'openui-lang' &&
      record.template === this.manifest.template &&
      record.libraryId === this.manifest.libraryId &&
      record.libraryRevision === this.manifest.libraryRevision &&
      record.designSpecId === this.manifest.designSpec.id &&
      record.designSpecRevision === this.manifest.designSpec.revision;
  }

  /**
   * Persist a terminal-parsed candidate. A new app starts at revision 1; an
   * existing app keeps its accepted revision as the fallback.
   */
  async commitCandidate(sessionId: string, messageId: string, identity: LocalGenUIIdentity, generation: LocalGenUIGeneration): Promise<LocalGenUIAppRecord> {
    const existing = await this.port.loadApp(identity.appId);
    if (!existing) {
      const record: LocalGenUIAppRecord = {
        appId: identity.appId,
        sessionId: LocalGenUIIds.require(sessionId, 'session'),
        messageId,
        schemaVersion: LOCAL_GENUI_SCHEMA_VERSION,
        title: generation.title,
        template: identity.template,
        libraryId: identity.libraryId,
        libraryRevision: identity.libraryRevision,
        designSpecId: identity.designSpec.id,
        designSpecRevision: identity.designSpec.revision,
        sourceFormat: identity.sourceFormat,
        sourceContent: generation.source,
        stateJson: generation.valuesJson,
        sourceRevision: 1,
        stateRevision: 1,
        ownerRevision: 1,
        status: LocalGenUIAppStatus.Candidate,
        acceptedSourceContent: '',
        acceptedStateJson: '',
        acceptedSourceRevision: 0,
        acceptedStateRevision: 0,
        previousSourceContent: '',
        previousStateJson: '',
        previousSourceRevision: 0,
        previousStateRevision: 0,
        previousStatus: '',
        userEdited: false,
        verificationJson: '',
        updatedAt: this.now()
      };
      await this.port.insertApp(record);
      return record;
    }
    if (!this.isRunnable(existing) || existing.libraryId !== identity.libraryId || existing.libraryRevision !== identity.libraryRevision ||
      existing.designSpecId !== identity.designSpec.id || existing.designSpecRevision !== identity.designSpec.revision) {
      throw new Error('candidate identity does not match the stored app');
    }
    const next: LocalGenUIAppRecord = this.copy(existing);
    if (LocalGenUIOwner.isDisplayableStatus(existing.status)) {
      next.previousSourceContent = existing.sourceContent;
      next.previousStateJson = existing.stateJson;
      next.previousSourceRevision = existing.sourceRevision;
      next.previousStateRevision = existing.stateRevision;
      next.previousStatus = existing.status;
    }
    next.title = generation.title;
    next.messageId = messageId;
    next.sourceContent = generation.source;
    next.sourceRevision = existing.sourceRevision + 1;
    next.ownerRevision = existing.ownerRevision + 1;
    next.updatedAt = this.now();
    next.verificationJson = '';
    // The checker runs on an isolated copy of the current state; migration
    // is decided with the parser-reported declarations at verification.
    next.candidateValuesJson = generation.valuesJson;
    next.status = LocalGenUIAppStatus.Candidate;
    if (!(await this.port.compareAndSwapApp(next, existing.ownerRevision))) {
      throw new Error('app changed while committing the candidate');
    }
    return next;
  }

  /** Record verification; only a fully verified candidate becomes accepted. */
  async recordVerification(appId: string, sourceRevision: number, verification: LocalGenUIVerification, required: string[],
    declaredTypes: Record<string, string> = {}): Promise<LocalGenUIAppRecord> {
    const current = await this.requireApp(appId);
    if (current.sourceRevision !== sourceRevision) {
      throw new Error('verification belongs to another source revision');
    }
    const next = this.copy(current);
    next.verificationJson = JSON.stringify(verification);
    next.ownerRevision = current.ownerRevision + 1;
    next.updatedAt = this.now();
    if (current.candidateValuesJson !== undefined && current.status === LocalGenUIAppStatus.Candidate) {
      const migration = migrateLocalState(current.stateJson, current.userEdited, current.candidateValuesJson, declaredTypes);
      next.candidateValuesJson = undefined;
      if (migration.ok) {
        next.stateJson = migration.stateJson;
        next.stateRevision = current.stateRevision + 1;
      } else {
        next.status = LocalGenUIAppStatus.StateMigrationRequired;
        next.verificationJson = JSON.stringify({ migration: migration.reason, checks: verification.checks });
      }
    }
    if (next.status !== LocalGenUIAppStatus.StateMigrationRequired) {
      if (requiredChecksSatisfied(verification, required)) {
        next.status = LocalGenUIAppStatus.Accepted;
        next.acceptedSourceContent = current.sourceContent;
        next.acceptedStateJson = next.stateJson;
        next.acceptedSourceRevision = current.sourceRevision;
        next.acceptedStateRevision = next.stateRevision;
      } else if (verification.checks.some((check) => check.result === 'failed')) {
        LocalGenUIOwner.restorePrevious(next);
      } else {
        next.status = LocalGenUIAppStatus.Displayable;
      }
    }
    if (!(await this.port.compareAndSwapApp(next, current.ownerRevision))) {
      throw new Error('app changed while recording verification');
    }
    return next;
  }

  /**
   * A failure recorded by another renderer is not a verdict from this one:
   * the checks themselves (or the components they measure) have changed since.
   * Such a source returns to candidate so the host verifies it again; nothing
   * is discarded. A failure from the current renderer stays failed.
   */
  async reconsiderFailure(appId: string): Promise<LocalGenUIAppRecord | undefined> {
    const current = await this.port.loadApp(appId);
    if (!current || current.status !== LocalGenUIAppStatus.Failed || !this.isRunnable(current) || current.sourceContent.length === 0) {
      return undefined;
    }
    if (LocalGenUIOwner.verifiedBy(current) === this.manifest.rendererRevision) {
      return undefined;
    }
    const next = this.copy(current);
    next.status = LocalGenUIAppStatus.Candidate;
    next.ownerRevision = current.ownerRevision + 1;
    next.updatedAt = this.now();
    if (!(await this.port.compareAndSwapApp(next, current.ownerRevision))) {
      return undefined;
    }
    return next;
  }

  /** Renderer revision recorded with the last verification; empty when unknown. */
  static verifiedBy(record: LocalGenUIAppRecord): string {
    try {
      const parsed = JSON.parse(record.verificationJson) as Record<string, Object>;
      const renderer = parsed ? parsed['rendererRevision'] : undefined;
      return typeof renderer === 'string' ? renderer : '';
    } catch (_err) {
      return '';
    }
  }

  /** User state CAS from the runtime. */
  async saveState(appId: string, sourceRevision: number, baseStateRevision: number, stateJson: string): Promise<LocalStateSaveResult> {
    const current = await this.port.loadApp(appId);
    if (!current || !this.isRunnable(current)) {
      return { outcome: LocalStateSaveOutcome.Rejected, error: 'app is not runnable' };
    }
    if (current.sourceRevision !== sourceRevision) {
      return { outcome: LocalStateSaveOutcome.StaleSource, record: current, error: 'source revision changed' };
    }
    if (current.stateRevision !== baseStateRevision) {
      return { outcome: LocalStateSaveOutcome.Conflict, record: current, error: 'state revision changed' };
    }
    if (!parseState(stateJson)) {
      return { outcome: LocalStateSaveOutcome.Rejected, error: 'state must be a JSON object' };
    }
    const next = this.copy(current);
    next.stateJson = stateJson;
    next.stateRevision = current.stateRevision + 1;
    next.ownerRevision = current.ownerRevision + 1;
    next.userEdited = true;
    next.updatedAt = this.now();
    if (current.status === LocalGenUIAppStatus.Accepted && current.acceptedSourceRevision === current.sourceRevision) {
      next.acceptedStateJson = stateJson;
      next.acceptedStateRevision = next.stateRevision;
    }
    if (!(await this.port.compareAndSwapApp(next, current.ownerRevision))) {
      const latest = await this.port.loadApp(appId);
      return { outcome: LocalStateSaveOutcome.Conflict, record: latest, error: 'concurrent owner write' };
    }
    return { outcome: LocalStateSaveOutcome.Saved, record: next, error: '' };
  }

  /** Record that an automatic repair turn was started for these diagnostics. */
  async recordRepairAttempt(appId: string, errorKey: string): Promise<boolean> {
    const current = await this.port.loadApp(appId);
    if (!current) {
      return false;
    }
    const next = this.copy(current);
    next.repairAttempts = (current.repairAttempts || 0) + 1;
    next.repairErrorKeys = (current.repairErrorKeys || []).concat([errorKey]);
    next.ownerRevision = current.ownerRevision + 1;
    next.updatedAt = this.now();
    return await this.port.compareAndSwapApp(next, current.ownerRevision);
  }

  /**
   * A committed candidate whose verification could not run. Turn failures
   * before the terminal commit never reach the owner, so the stored app and
   * user data are untouched; this restores the previous runnable revision.
   */
  async failCandidate(appId: string, sourceRevision: number, error: string): Promise<LocalGenUIAppRecord | undefined> {
    const current = await this.port.loadApp(appId);
    if (!current || current.sourceRevision !== sourceRevision || current.status !== LocalGenUIAppStatus.Candidate) {
      return current;
    }
    const next = this.copy(current);
    next.ownerRevision = current.ownerRevision + 1;
    next.updatedAt = this.now();
    next.verificationJson = JSON.stringify({ error });
    LocalGenUIOwner.restorePrevious(next);
    if (!(await this.port.compareAndSwapApp(next, current.ownerRevision))) {
      return await this.port.loadApp(appId);
    }
    return next;
  }

  /**
   * Restore the previous runnable revision as a new monotonic revision so
   * revision numbers never name two different sources.
   */
  private static restorePrevious(next: LocalGenUIAppRecord): void {
    if (next.previousSourceRevision <= 0) {
      next.status = LocalGenUIAppStatus.Failed;
      return;
    }
    next.sourceContent = next.previousSourceContent;
    next.stateJson = next.previousStateJson;
    next.sourceRevision = next.sourceRevision + 1;
    next.stateRevision = next.stateRevision + 1;
    next.status = next.previousStatus;
    next.previousSourceRevision = next.sourceRevision;
    next.previousStateRevision = next.stateRevision;
    if (next.status === LocalGenUIAppStatus.Accepted) {
      next.acceptedSourceContent = next.sourceContent;
      next.acceptedStateJson = next.stateJson;
      next.acceptedSourceRevision = next.sourceRevision;
      next.acceptedStateRevision = next.stateRevision;
    }
  }

  static isDisplayableStatus(status: string): boolean {
    return status === LocalGenUIAppStatus.Accepted || status === LocalGenUIAppStatus.Displayable;
  }

  /** The revision a host should render: never a failed or migration-blocked candidate. */
  static runnableRevision(record: LocalGenUIAppRecord): LocalGenUIRunnableRevision | undefined {
    if (LocalGenUIOwner.isDisplayableStatus(record.status) || record.status === LocalGenUIAppStatus.Candidate) {
      return { source: record.sourceContent, stateJson: record.stateJson, sourceRevision: record.sourceRevision, stateRevision: record.stateRevision, status: record.status };
    }
    if (record.previousSourceRevision > 0) {
      return { source: record.previousSourceContent, stateJson: record.previousStateJson, sourceRevision: record.previousSourceRevision, stateRevision: record.previousStateRevision, status: record.previousStatus };
    }
    return undefined;
  }

  private async requireApp(appId: string): Promise<LocalGenUIAppRecord> {
    const record = await this.port.loadApp(appId);
    if (!record) {
      throw new Error('unknown local app');
    }
    return record;
  }

  private copy(record: LocalGenUIAppRecord): LocalGenUIAppRecord {
    return JSON.parse(JSON.stringify(record)) as LocalGenUIAppRecord;
  }
}
