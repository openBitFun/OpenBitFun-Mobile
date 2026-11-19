/**
 * ArkTS mirror of the runtime message contract defined in
 * src/web-ui/src/tools/generative-ui/local-runtime/localRuntimeProtocol.ts.
 */
import { LocalGenUIDesignSpec, LocalGenUIIdentity, LocalGenUIManifest, LocalGenUIPresentation, LocalGenUIVerification, LocalGenUIVerificationCheck } from './LocalGenUIModels';

export interface LocalRuntimeCalendarResultMessage {
  type: string;
  appId: string;
  sourceRevision: number;
  requestId: string;
  ok: boolean;
}

export interface LocalRuntimeCalendarReceiptsMessage {
  type: string;
  appId: string;
  sourceRevision: number;
  params: Object[];
}

export interface LocalRuntimeIdentityMessage {
  appId: string;
  title: string;
  template: string;
  libraryId: string;
  libraryRevision: number;
  designSpec: LocalGenUIDesignSpec;
  sourceFormat: string;
}

export interface LocalRuntimeInitMessage {
  type: string;
  manifest: LocalGenUIManifest;
  identity: LocalRuntimeIdentityMessage;
  mode: string;
  source: string;
  /** Present while an edit patch streams: the program the patch applies to. */
  base?: string;
  streaming: boolean;
  sourceRevision: number;
  stateRevision: number;
  state: Object;
  scheme: string;
  look?: string;
  locale: string;
}

export interface LocalRuntimeSourceResetMessage {
  type: string;
  appId: string;
  text: string;
  streaming: boolean;
  sourceRevision: number;
}

export interface LocalRuntimeSourceDeltaMessage {
  type: string;
  appId: string;
  seq: number;
  text: string;
}

export interface LocalRuntimeStateMessage {
  type: string;
  appId: string;
  sourceRevision: number;
  stateRevision: number;
  state: Object;
  conflict: boolean;
}

export interface LocalRuntimeThemeMessage {
  type: string;
  scheme: string;
  look?: string;
}

/** Owner request: apply an OpenUI edit patch to its base program. */
export interface LocalRuntimeMergeMessage {
  type: string;
  requestId: string;
  base: string;
  patch: string;
}

/** Space the host keeps over the edge-to-edge page, in vp. */
export interface LocalRuntimeInsetsMessage {
  type: string;
  top: number;
  left: number;
  right: number;
  bottom: number;
}

export interface LocalRuntimeProbeMessage {
  type: string;
  requestId: string;
}

export interface LocalProbeBounds {
  left: number;
  right: number;
  top: number;
  bottom: number;
}

export interface LocalProbeViewport {
  width: number;
  height: number;
  devicePixelRatio: number;
}

export interface LocalProbeReport {
  requestId: string;
  appId: string;
  sourceRevision: number;
  rendererRevision: string;
  viewport: LocalProbeViewport;
  canvasWidth: number;
  canvasScale: number;
  contentBounds: LocalProbeBounds;
  scrollWidth: number;
  visibleElements: number;
  componentCount: number;
  renderErrors: string[];
  unsupportedComponents: string[];
  hostPartsInDocument: number;
  contractOk: boolean;
  stateTypes: Record<string, string>;
  widestElement: string;
}

/** Inbound runtime message; fields are present according to `type`. */
export interface LocalRuntimeInbound {
  type: string;
  rendererRevision?: string;
  catalogHash?: string;
  contractOk?: boolean;
  reason?: string;
  appId?: string;
  sourceRevision?: number;
  baseStateRevision?: number;
  state?: Object;
  action?: string;
  message?: string;
  params?: Object;
  capability?: string;
  code?: string;
  report?: LocalProbeReport;
  /** merge_result */
  requestId?: string;
  source?: string;
  error?: string;
  /** Device capability requests. */
  op?: string;
  subscriptionId?: string;
  gesture?: string;
  kind?: string;
  orientation?: string;
  /** image_search */
  query?: string;
}

export interface LocalRuntimeImageSearchResultMessage {
  type: string;
  appId: string;
  requestId: string;
  images: string[];
}

export interface LocalRuntimeCapabilityEventMessage {
  type: string;
  subscriptionId: string;
  gesture: string;
}

export interface LocalRuntimeCapabilityStatusMessage {
  type: string;
  subscriptionId: string;
  status: string;
}

export function runtimeIdentity(identity: LocalGenUIIdentity): LocalRuntimeIdentityMessage {
  return {
    appId: identity.appId,
    title: identity.title,
    template: identity.template,
    libraryId: identity.libraryId,
    libraryRevision: identity.libraryRevision,
    designSpec: identity.designSpec,
    sourceFormat: identity.sourceFormat
  };
}

/** Geometry the design specification fixes for the logical app canvas. */
export interface LocalCanvasSpec {
  width: number;
  insetLeft: number;
  insetRight: number;
}


export interface LocalAcceptanceInput {
  probe?: LocalProbeReport;
  reopenProbe?: LocalProbeReport;
  readbackMatches: boolean;
  readbackDetail: string;
  canvas: LocalCanvasSpec;
  presentation: LocalGenUIPresentation;
  requiredChecks: string[];
}

function check(name: string, passed: boolean, detail: string): LocalGenUIVerificationCheck {
  return { name, result: passed ? 'passed' : 'failed', detail };
}

function renderCheck(name: string, probe: LocalProbeReport | undefined): LocalGenUIVerificationCheck {
  if (!probe) {
    // Checker infrastructure unavailable is not a source defect.
    return { name, result: 'unverified', detail: 'runtime probe did not report' };
  }
  if (!probe.contractOk) {
    return check(name, false, 'runtime contract mismatch');
  }
  if (probe.renderErrors.length > 0) {
    return check(name, false, probe.renderErrors.slice(0, 3).join('; '));
  }
  const unsupported = probe.unsupportedComponents.length > 0 ? `; unsupported: ${probe.unsupportedComponents.join(',')}` : '';
  return check(name, probe.visibleElements > 0, `${probe.visibleElements} visible elements${unsupported}`);
}

/**
 * Local phase 1 acceptance. Checks the phone cannot execute stay
 * `unverified`; they are never reported as passed.
 */
export function evaluateLocalAcceptance(input: LocalAcceptanceInput): LocalGenUIVerificationCheck[] {
  const probe = input.probe;
  const checks: LocalGenUIVerificationCheck[] = [];
  const executable: Map<string, LocalGenUIVerificationCheck> = new Map<string, LocalGenUIVerificationCheck>();
  executable.set('actual-render', renderCheck('actual-render', probe));
  if (probe) {
    // The page fills the device viewport at scale 1 (narrow screens stack the
    // page blocks, wide ones set them side by side); the design-spec insets
    // are the page gutter on either side of whatever width the device has.
    const left = input.canvas.insetLeft;
    const right = probe.canvasWidth - input.canvas.insetRight;
    const bounds = probe.contentBounds;
    const fills = Math.abs(probe.canvasWidth - probe.viewport.width) <= 1 && probe.canvasScale === 1;
    executable.set('fixed-viewport', check('fixed-viewport', fills,
      `canvas ${probe.canvasWidth}px x ${probe.canvasScale.toFixed(3)} in viewport ${probe.viewport.width}px (dpr ${probe.viewport.devicePixelRatio}), ${input.presentation.posture} ${input.presentation.deviceWidth}x${input.presentation.deviceHeight}`));
    executable.set('content-boundary', check('content-boundary', probe.visibleElements > 0 && bounds.left >= left - 1 && bounds.right <= right + 1,
      `content ${bounds.left}..${bounds.right}, allowed ${left}..${right}, widest ${probe.widestElement}`));
    executable.set('no-horizontal-overflow', check('no-horizontal-overflow', probe.scrollWidth <= Math.ceil(probe.viewport.width) + 1,
      `document ${probe.scrollWidth}px, viewport ${probe.viewport.width}px`));
    executable.set('host-shell-duplication', check('host-shell-duplication', probe.hostPartsInDocument === 0,
      `${probe.hostPartsInDocument} emulated host parts in document`));
  }
  executable.set('host-shell', check('host-shell', true,
    `native ArkUI shell; safe area top ${input.presentation.safeTop}, bottom ${input.presentation.safeBottom}`));
  const reopen = renderCheck('save-reopen', input.reopenProbe);
  executable.set('save-reopen', input.readbackMatches
    ? { name: 'save-reopen', result: reopen.result, detail: `${input.readbackDetail}; reopen ${reopen.detail}` }
    : check('save-reopen', false, input.readbackDetail));
  input.requiredChecks.forEach((name: string) => {
    const result = executable.get(name);
    checks.push(result ? result : { name, result: 'unverified', detail: 'not executable on the local phone runtime in phase 1' });
  });
  return checks;
}

export function verificationOf(checks: LocalGenUIVerificationCheck[], manifest: LocalGenUIManifest, presentation: LocalGenUIPresentation, sourceHash: string, stateHash: string, now: string): LocalGenUIVerification {
  return {
    mode: 'local-runtime',
    presentation,
    rendererRevision: manifest.rendererRevision,
    catalogHash: manifest.catalogHash,
    promptHash: manifest.promptHash,
    checks,
    unverified: checks.filter((item: LocalGenUIVerificationCheck) => item.result === 'unverified').map((item: LocalGenUIVerificationCheck) => item.name),
    sourceHash,
    stateHash,
    verifiedAt: now
  };
}
