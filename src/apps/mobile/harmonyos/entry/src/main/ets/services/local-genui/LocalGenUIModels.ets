/**
 * Local GenUI types. Local sessions are owned by the phone and live in the
 * `local-genui:` namespace; they never carry remote session or workspace ids.
 */
export const LOCAL_GENUI_NAMESPACE: string = 'local-genui:';
export const LOCAL_GENUI_SOURCE_FORMAT: string = 'openui-lang';
export const LOCAL_GENUI_SCHEMA_VERSION: number = 1;

export interface LocalGenUIDesignSpec {
  id: string;
  revision: number;
}

/** Generated from library.json; see rawfile/genui/runtime-manifest.json. */
export interface LocalGenUIManifest {
  contractVersion: number;
  profile: string;
  template: string;
  libraryId: string;
  libraryRevision: number;
  designSpec: LocalGenUIDesignSpec;
  sourceKinds: string[];
  ownerFields: string[];
  toolName: string;
  catalogHash: string;
  promptHash: string;
  toolSchemaHash: string;
  rendererRevision: string;
}

/** The identity the owner binds before any source delta. */
export interface LocalGenUIIdentity {
  appId: string;
  toolCallId: string;
  title: string;
  template: string;
  libraryId: string;
  libraryRevision: number;
  designSpec: LocalGenUIDesignSpec;
  sourceFormat: string;
}

export enum LocalGenUIAppStatus {
  /** Streaming or terminal-parsed but not verified; displayable, not accepted. */
  Candidate = 'candidate',
  /** Displayed, but one or more required checks are unverified. */
  Displayable = 'displayable',
  Accepted = 'accepted',
  Failed = 'failed',
  StateMigrationRequired = 'state_migration_required',
  /** Unknown schema/library/format: retained as-is and never executed. */
  Unsupported = 'unsupported'
}

export interface LocalGenUIVerificationCheck {
  name: string;
  result: string;
  detail: string;
}

/** Real device presentation recorded with local verification. */
export interface LocalGenUIPresentation {
  posture: string;
  deviceWidth: number;
  deviceHeight: number;
  safeTop: number;
  safeBottom: number;
  viewportScale: number;
}

export interface LocalGenUIVerification {
  mode: string;
  presentation?: LocalGenUIPresentation;
  rendererRevision: string;
  catalogHash: string;
  promptHash: string;
  checks: LocalGenUIVerificationCheck[];
  unverified: string[];
  sourceHash: string;
  stateHash: string;
  verifiedAt: string;
}

/** One persisted row of `local_genui_apps`. Unknown values are preserved. */
export interface LocalGenUIAppRecord {
  appId: string;
  sessionId: string;
  messageId: string;
  schemaVersion: number;
  title: string;
  template: string;
  libraryId: string;
  libraryRevision: number;
  designSpecId: string;
  designSpecRevision: number;
  sourceFormat: string;
  sourceContent: string;
  stateJson: string;
  sourceRevision: number;
  stateRevision: number;
  ownerRevision: number;
  status: string;
  /** Last accepted revision kept for fallback while a candidate is pending. */
  acceptedSourceContent: string;
  acceptedStateJson: string;
  acceptedSourceRevision: number;
  acceptedStateRevision: number;
  /**
   * Last runnable (accepted or displayable) revision before the current
   * candidate. Restored when a turn fails or a migration is required.
   */
  previousSourceContent: string;
  previousStateJson: string;
  previousSourceRevision: number;
  previousStateRevision: number;
  previousStatus: string;
  /** Automatic repair budget and the diagnostics already tried (Desktop parity). */
  repairAttempts?: number;
  repairErrorKeys?: string[];
  /** Initial values the model supplied with the current candidate source. */
  candidateValuesJson?: string;
  /** User edits since the source was created; drives migration rules. */
  userEdited: boolean;
  verificationJson: string;
  updatedAt: string;
}

export interface LocalGenUISession {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  /** Model profile pinned to the session. Absent in records from older builds. */
  modelId?: string;
  /** The title was taken from the first generated app; later apps keep it. */
  titleFromApp?: boolean;
}

/** A generated app the user explicitly added to the MiniApp gallery. */
export interface LocalGenUIGalleryEntry {
  appId: string;
  sessionId: string;
  title: string;
  addedAt: string;
  /** Projection only, never persisted: preview image of the rendered app. */
  thumbnailPath?: string;
}

export enum LocalGenUIMessageRole {
  User = 'user',
  Assistant = 'assistant'
}

/** Chat rows keep only text and a reference; app source/state live in the app table. */
export interface LocalGenUIMessage {
  id: string;
  sessionId: string;
  role: string;
  type: string;
  text: string;
  appId: string;
  appTitle: string;
  status: string;
  error: string;
  createdAt: string;
}

export enum LocalGenUIEventType {
  TurnStarted = 'turn.started',
  MessageDelta = 'message.delta',
  GenUIStarted = 'genui.started',
  GenUISourceDelta = 'genui.source.delta',
  TurnCompleted = 'turn.completed',
  TurnFailed = 'turn.failed'
}

export interface LocalGenUISourceDelta {
  appId: string;
  seq: number;
  reset: boolean;
  text: string;
}

export interface LocalGenUIEvent {
  type: LocalGenUIEventType;
  turnId: string;
  text?: string;
  identity?: LocalGenUIIdentity;
  delta?: LocalGenUISourceDelta;
  error?: string;
}

export class LocalGenUIIds {
  static isLocal(id: string): boolean {
    return id.startsWith(LOCAL_GENUI_NAMESPACE);
  }

  static require(id: string, kind: string): string {
    if (!LocalGenUIIds.isLocal(id)) {
      throw new Error(`refusing non-local ${kind} id`);
    }
    return id;
  }
}
