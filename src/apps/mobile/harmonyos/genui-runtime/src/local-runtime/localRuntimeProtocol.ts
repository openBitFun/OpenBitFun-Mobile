/**
 * Harmony Local GenUI runtime protocol.
 *
 * The ArkTS host owns the session, the application owner and persistence. This
 * runtime only parses and renders OpenUI Lang with the pinned library. The
 * module is pure so the message contract can be tested without a WebView.
 */
import { mergeStatements } from '@openuidev/lang-core';
import type { GenUIAppState } from '../genUITypes';
import type { GenUICollaborationResult } from '../genUIDeviceCapabilities';

export interface LocalRuntimeManifest {
  contractVersion: number;
  profile: string;
  template: string;
  libraryId: string;
  libraryRevision: number;
  designSpec: { id: string; revision: number };
  sourceKinds: string[];
  catalogHash: string;
  promptHash: string;
  toolSchemaHash: string;
  rendererRevision: string;
}

export type LocalRuntimeMode = 'live' | 'checker';

export interface LocalRuntimeIdentity {
  appId: string;
  title: string;
  template: string;
  libraryId: string;
  libraryRevision: number;
  designSpec: { id: string; revision: number };
  sourceFormat: 'openui-lang';
}

export type LocalHostMessage =
  | { type: 'collaboration_availability'; appId: string; sourceRevision: number; available: boolean; reason: string }
  | ({ type: 'collaboration_result'; appId: string; sourceRevision: number; requestId: string } & GenUICollaborationResult)
  | { type: 'calendar_receipts'; appId: string; sourceRevision: number; params: Record<string, unknown>[] }
  | { type: 'calendar_result'; appId: string; sourceRevision: number; requestId: string; ok: boolean }
  /** `base` makes `source` an edit patch (OpenUI edit mode) applied on top of it. */
  | { type: 'init'; manifest: LocalRuntimeManifest; identity: LocalRuntimeIdentity; mode: LocalRuntimeMode; source: string; base?: string; streaming: boolean; sourceRevision: number; stateRevision: number; state: GenUIAppState; scheme: 'light' | 'dark'; look?: string; locale?: string }
  /** Owner request: the program an edit patch produces on its base. */
  | { type: 'merge'; requestId: string; base: string; patch: string }
  | { type: 'source_reset'; appId: string; text: string; streaming: boolean; sourceRevision: number }
  | { type: 'source_delta'; appId: string; seq: number; text: string }
  | { type: 'state'; appId: string; sourceRevision: number; stateRevision: number; state: GenUIAppState; conflict?: boolean }
  | { type: 'theme'; scheme: 'light' | 'dark'; look?: string }
  | { type: 'image_search_result'; appId: string; requestId: string; images: string[] }
  /** Space the native host keeps over the page: system bars, cutouts and its floating controls (vp). */
  | { type: 'insets'; top: number; left: number; right: number; bottom: number }
  | { type: 'probe'; requestId: string }
  /** A gesture subscription fired. */
  | { type: 'capability_event'; subscriptionId: string; gesture: string }
  | { type: 'capability_status'; subscriptionId: string; status: 'starting' | 'active' | 'paused' | 'denied' | 'unavailable' };

export interface LocalProbeReport {
  requestId: string;
  appId: string;
  sourceRevision: number;
  rendererRevision: string;
  viewport: { width: number; height: number; devicePixelRatio: number };
  canvasWidth: number;
  /** Uniform scale applied to the logical canvas to fit the device viewport. */
  canvasScale: number;
  contentBounds: { left: number; right: number; top: number; bottom: number };
  scrollWidth: number;
  visibleElements: number;
  componentCount: number;
  renderErrors: string[];
  unsupportedComponents: string[];
  /** Emulated host parts (device frame/status bar) found inside the document. */
  hostPartsInDocument: number;
  contractOk: boolean;
  /** Declared state keys of the mounted source and their default JSON types. */
  stateTypes: Record<string, string>;
  /** Geometry-only diagnostic: the right-most painted element. */
  widestElement: string;
}

export type LocalRuntimeMessage =
  | { type: 'collaboration'; appId: string; sourceRevision: number; requestId: string; op: 'start' | 'cancel'; kind?: string }
  /** Photo search; the host answers with host-served photo addresses. */
  | { type: 'image_search'; appId: string; requestId: string; query: string }
  /** The receive hook is installed; the host may now send `init`. */
  | { type: 'boot'; rendererRevision: string }
  | { type: 'ready'; rendererRevision: string; catalogHash: string; contractOk: boolean; reason?: string }
  | { type: 'state'; appId: string; sourceRevision: number; baseStateRevision: number; state: GenUIAppState }
  | { type: 'action'; appId: string; sourceRevision: number; action: string; message: string; params: Record<string, unknown>; requestId?: string }
  | { type: 'query'; appId: string; capability: string; status: 'unsupported' }
  | { type: 'error'; appId: string; code: string; message: string }
  | { type: 'probe_result'; report: LocalProbeReport }
  | { type: 'merge_result'; requestId: string; source: string; error?: string }
  /** Device capability requests; the host decides whether and how to serve them. */
  | { type: 'capability'; appId: string; op: 'subscribe' | 'unsubscribe'; subscriptionId: string; capability: 'gesture'; gesture?: string }
  | { type: 'haptic'; appId: string; kind: string }
  | { type: 'orientation'; appId: string; sourceRevision: number; orientation: 'auto' | 'portrait' | 'landscape' };

/** Build-time identity of this runtime bundle. Injected by the bundle build. */
export interface LocalRuntimeBuild {
  catalogHash: string;
  rendererRevision: string;
  libraryId: string;
  libraryRevision: number;
}

export function verifyManifest(manifest: LocalRuntimeManifest | undefined, build: LocalRuntimeBuild): string | undefined {
  if (!manifest) return 'runtime manifest is missing';
  if (manifest.catalogHash !== build.catalogHash) return 'runtime bundle and rawfile catalog differ; regenerate the Harmony GenUI runtime';
  if (manifest.rendererRevision !== build.rendererRevision) return 'renderer revision mismatch';
  if (manifest.libraryId !== build.libraryId || manifest.libraryRevision !== build.libraryRevision) return 'library identity mismatch';
  if (!manifest.sourceKinds.includes('openui-lang')) return 'openui-lang is not enabled';
  return undefined;
}

export function verifyIdentity(identity: LocalRuntimeIdentity, manifest: LocalRuntimeManifest): string | undefined {
  if (identity.sourceFormat !== 'openui-lang') return 'unsupported source format ' + String(identity.sourceFormat);
  if (identity.libraryId !== manifest.libraryId || identity.libraryRevision !== manifest.libraryRevision) return `unsupported library ${identity.libraryId}@${identity.libraryRevision}`;
  if (identity.designSpec.id !== manifest.designSpec.id || identity.designSpec.revision !== manifest.designSpec.revision) return `unsupported design spec ${identity.designSpec.id}@${identity.designSpec.revision}`;
  if (identity.template !== manifest.template) return 'unsupported template ' + identity.template;
  return undefined;
}

export interface LocalRuntimeSnapshot {
  status: 'waiting' | 'ready' | 'unsupported';
  reason?: string;
  mode: LocalRuntimeMode;
  identity?: LocalRuntimeIdentity;
  source: string;
  /** Program an edit patch in `source` applies to; absent for a whole program. */
  base?: string;
  streaming: boolean;
  sourceRevision: number;
  stateRevision: number;
  /** Last owner-accepted state. */
  state: GenUIAppState;
  /** Local edits not yet acknowledged by the owner. */
  pending?: GenUIAppState;
  look?: string;
  scheme: 'light' | 'dark';
  locale?: string;
  nextSeq: number;
}

export function initialSnapshot(): LocalRuntimeSnapshot {
  return { status: 'waiting', mode: 'live', source: '', streaming: false, sourceRevision: 0, stateRevision: 0, state: {}, scheme: 'light', nextSeq: 0 };
}

export interface LocalReduction {
  snapshot: LocalRuntimeSnapshot;
  outbound: LocalRuntimeMessage[];
}

/**
 * Apply one host message. Messages for another app or out-of-order source
 * deltas never update the rendered source; they surface as errors instead.
 */
export function reduceHostMessage(snapshot: LocalRuntimeSnapshot, message: LocalHostMessage, build: LocalRuntimeBuild): LocalReduction {
  switch (message.type) {
    case 'init': {
      const manifestError = verifyManifest(message.manifest, build);
      const identityError = manifestError ? undefined : verifyIdentity(message.identity, message.manifest);
      const reason = manifestError ?? identityError;
      const next: LocalRuntimeSnapshot = {
        ...initialSnapshot(),
        status: reason ? 'unsupported' : 'ready',
        reason,
        mode: message.mode,
        identity: message.identity,
        source: message.source,
        base: typeof message.base === 'string' && message.base.length > 0 ? message.base : undefined,
        streaming: message.streaming,
        sourceRevision: message.sourceRevision,
        stateRevision: message.stateRevision,
        state: message.state ?? {},
        scheme: message.scheme,
        look: message.look,
        locale: message.locale,
      };
      return { snapshot: next, outbound: [{ type: 'ready', rendererRevision: build.rendererRevision, catalogHash: build.catalogHash, contractOk: !manifestError, reason }] };
    }
    case 'source_reset': {
      if (!snapshot.identity || message.appId !== snapshot.identity.appId) return mismatch(snapshot, message.appId);
      // A new source revision invalidates unsent edits for the previous one;
      // the owner performs any state migration.
      const revisionChanged = message.sourceRevision !== snapshot.sourceRevision;
      return { snapshot: { ...snapshot, source: message.text, streaming: message.streaming, sourceRevision: message.sourceRevision, pending: revisionChanged ? undefined : snapshot.pending, nextSeq: 0 }, outbound: [] };
    }
    case 'source_delta': {
      if (!snapshot.identity || message.appId !== snapshot.identity.appId) return mismatch(snapshot, message.appId);
      if (message.seq !== snapshot.nextSeq) {
        return { snapshot, outbound: [{ type: 'error', appId: snapshot.identity.appId, code: 'source_seq', message: `expected seq ${snapshot.nextSeq}, received ${message.seq}` }] };
      }
      return { snapshot: { ...snapshot, source: snapshot.source + message.text, streaming: true, nextSeq: snapshot.nextSeq + 1 }, outbound: [] };
    }
    case 'state': {
      if (!snapshot.identity || message.appId !== snapshot.identity.appId) return mismatch(snapshot, message.appId);
      if (message.sourceRevision !== snapshot.sourceRevision) return { snapshot, outbound: [] };
      const accepted = { ...snapshot, stateRevision: message.stateRevision, state: message.state };
      if (message.conflict && snapshot.pending) {
        // Replay the uncommitted edit on top of the newest owner state.
        const replay = { ...message.state, ...snapshot.pending };
        return { snapshot: { ...accepted, pending: replay }, outbound: [{ type: 'state', appId: snapshot.identity.appId, sourceRevision: snapshot.sourceRevision, baseStateRevision: message.stateRevision, state: replay }] };
      }
      return { snapshot: { ...accepted, pending: undefined }, outbound: [] };
    }
    case 'theme':
      return { snapshot: { ...snapshot, scheme: message.scheme, look: message.look ?? snapshot.look }, outbound: [] };
    case 'merge':
      return { snapshot, outbound: [mergeReply(message.requestId, message.base, message.patch)] };
    case 'calendar_receipts':
    case 'calendar_result':
    case 'collaboration_availability':
    case 'collaboration_result':
    case 'probe':
    case 'insets':
    case 'capability_event':
    case 'capability_status':
      return { snapshot, outbound: [] };
  }
}

function mismatch(snapshot: LocalRuntimeSnapshot, appId: string): LocalReduction {
  return { snapshot, outbound: [{ type: 'error', appId, code: 'app_mismatch', message: 'message for an app that is not mounted' }] };
}

/** A user edit becomes a CAS request against the last owner-accepted revision. */
export function localStateEdit(snapshot: LocalRuntimeSnapshot, state: GenUIAppState): LocalReduction {
  if (snapshot.status !== 'ready' || !snapshot.identity || snapshot.mode === 'checker' || snapshot.streaming) return { snapshot, outbound: [] };
  return {
    snapshot: { ...snapshot, pending: state },
    outbound: [{ type: 'state', appId: snapshot.identity.appId, sourceRevision: snapshot.sourceRevision, baseStateRevision: snapshot.stateRevision, state }],
  };
}

/**
 * OpenUI edit mode: statements in the patch replace same-named ones, new names
 * append, `name = null` deletes, and statements nothing reaches are dropped.
 * A complete program merges to itself, so a full rewrite is still accepted.
 */
export function applyEditPatch(base: string, patch: string): string {
  return mergeStatements(base, patch);
}

function mergeReply(requestId: string, base: string, patch: string): LocalRuntimeMessage {
  try {
    const source = applyEditPatch(base, patch);
    if (!/^root\s*=/m.test(source)) return { type: 'merge_result', requestId, source: '', error: 'merged program has no root statement' };
    return { type: 'merge_result', requestId, source };
  } catch (error) {
    return { type: 'merge_result', requestId, source: '', error: error instanceof Error ? error.message : String(error) };
  }
}

/**
 * What the runtime renders for a snapshot. While an edit patch streams, only
 * its complete lines apply, so the app keeps its shape and changes in place
 * instead of being rebuilt from an empty page.
 */
export function displayedSource(snapshot: Pick<LocalRuntimeSnapshot, 'base' | 'source' | 'streaming'>): string {
  if (!snapshot.base) return snapshot.source;
  const complete = snapshot.streaming ? snapshot.source.slice(0, snapshot.source.lastIndexOf('\n') + 1) : snapshot.source;
  if (!complete.trim()) return snapshot.base;
  try {
    return applyEditPatch(snapshot.base, complete);
  } catch {
    return snapshot.base;
  }
}
