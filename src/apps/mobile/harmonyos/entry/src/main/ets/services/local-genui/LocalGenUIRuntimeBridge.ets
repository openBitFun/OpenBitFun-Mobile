import { image } from '@kit.ImageKit';
import { LocalCollaborationReply } from './LocalGenUICollaborationHost';
import { LocalGenUIIdentity, LocalGenUIManifest } from './LocalGenUIModels';
import {
  LocalProbeReport,
  LocalRuntimeCalendarResultMessage,
  LocalRuntimeCalendarReceiptsMessage,
  LocalRuntimeCapabilityEventMessage,
  LocalRuntimeCapabilityStatusMessage,
  LocalRuntimeInbound,
  LocalRuntimeInitMessage,
  LocalRuntimeProbeMessage,
  LocalRuntimeSourceDeltaMessage,
  LocalRuntimeSourceResetMessage,
  LocalRuntimeStateMessage,
  LocalRuntimeInsetsMessage,
  LocalRuntimeMergeMessage,
  LocalRuntimeThemeMessage,
  runtimeIdentity
} from './LocalGenUIRuntimeProtocol';

export interface LocalRuntimeMount {
  identity: LocalGenUIIdentity;
  mode: string;
  source: string;
  streaming: boolean;
  sourceRevision: number;
  stateRevision: number;
  stateJson: string;
  /** The mounted source is an edit patch over this program while it streams. */
  base?: string;
}

/** Outcome of an edit merge; `error` is empty on success. */
export interface LocalRuntimeMergeResult {
  source: string;
  error: string;
}

interface PendingMerge {
  resolve: (result: LocalRuntimeMergeResult) => void;
  timer: number;
}

interface LocalCollaborationAvailability {
  type: string;
  appId: string;
  sourceRevision: number;
  available: boolean;
  reason: string;
}

interface PendingProbe {
  resolve: (report: LocalProbeReport | undefined) => void;
  timer: number;
}

/**
 * Host side of the ArkWeb runtime channel. The WebView component attaches a
 * sender; everything else talks to this object. It owns no product state:
 * the mount mirrors what the owner/controller decided to show.
 */
export class LocalGenUIRuntimeBridge {
  private sender?: (json: string) => void;
  private insetsJson: string = '';
  private pictureSource?: (url: string) => Promise<ArrayBuffer | undefined>;
  private snapshotter?: () => Promise<image.PixelMap | undefined>;
  private booted: boolean = false;
  private ready: boolean = false;
  private mount?: LocalRuntimeMount;
  private manifest?: LocalGenUIManifest;
  private scheme: string = 'light';
  private locale: string = 'zh-CN';
  private seq: number = 0;
  private probeSerial: number = 0;
  private readonly probes: Map<string, PendingProbe> = new Map<string, PendingProbe>();
  private readonly merges: Map<string, PendingMerge> = new Map<string, PendingMerge>();
  private inboundHandler?: (message: LocalRuntimeInbound) => void;
  private readyWaiters: (() => void)[] = [];

  setManifest(manifest: LocalGenUIManifest): void {
    this.manifest = manifest;
  }

  setInboundHandler(handler: (message: LocalRuntimeInbound) => void): void {
    this.inboundHandler = handler;
  }

  /** Called by the WebView component once its controller is attached. */
  attach(sender: (json: string) => void): void {
    this.sender = sender;
    this.booted = false;
    this.ready = false;
  }

  /** The WebView leaf provides a page snapshot of the mounted document. */
  attachSnapshot(snapshotter: () => Promise<image.PixelMap | undefined>): void {
    this.snapshotter = snapshotter;
  }

  async snapshot(): Promise<image.PixelMap | undefined> {
    if (!this.snapshotter || !this.ready) {
      return undefined;
    }
    try {
      return await this.snapshotter();
    } catch (_err) {
      return undefined;
    }
  }

  detach(): void {
    this.sender = undefined;
    this.snapshotter = undefined;
    this.booted = false;
    this.ready = false;
    this.probes.forEach((probe: PendingProbe) => {
      clearTimeout(probe.timer);
      probe.resolve(undefined);
    });
    this.probes.clear();
    this.merges.forEach((merge: PendingMerge) => {
      clearTimeout(merge.timer);
      merge.resolve({ source: '', error: 'runtime detached' });
    });
    this.merges.clear();
  }

  isAttached(): boolean {
    return this.sender !== undefined;
  }

  currentMount(): LocalRuntimeMount | undefined {
    return this.mount;
  }

  /** Raw string from the `genuiNative.post` proxy. Treated as untrusted. */
  receive(raw: string): void {
    let message: LocalRuntimeInbound;
    try {
      message = JSON.parse(raw) as LocalRuntimeInbound;
    } catch (_err) {
      return;
    }
    if (message.type === 'boot') {
      this.booted = true;
      if (this.insetsJson.length > 0) {
        this.post(this.insetsJson);
      }
      this.sendInit();
      return;
    }
    if (message.type === 'ready') {
      this.ready = true;
      const waiters = this.readyWaiters;
      this.readyWaiters = [];
      waiters.forEach((resolve: () => void) => resolve());
    }
    if (message.type === 'merge_result' && message.requestId) {
      const pending = this.merges.get(message.requestId);
      if (pending) {
        clearTimeout(pending.timer);
        this.merges.delete(message.requestId);
        pending.resolve({ source: message.source || '', error: message.error || (message.source ? '' : 'empty merge result') });
      }
      return;
    }
    if (message.type === 'probe_result' && message.report) {
      const pending = this.probes.get(message.report.requestId);
      if (pending) {
        clearTimeout(pending.timer);
        this.probes.delete(message.report.requestId);
        pending.resolve(message.report);
      }
      return;
    }
    if (this.inboundHandler) {
      this.inboundHandler(message);
    }
  }

  /** Host-served pictures (3D icons) the runtime requests by URL. */
  setPictureSource(source: (url: string) => Promise<ArrayBuffer | undefined>): void {
    this.pictureSource = source;
  }

  picture(url: string): Promise<ArrayBuffer | undefined> {
    return this.pictureSource ? this.pictureSource(url) : Promise.resolve(undefined);
  }

  /** Host chrome over the page; resent after every boot so a reload keeps it. */
  setInsets(top: number, left: number, right: number, bottom: number): void {
    const next: LocalRuntimeInsetsMessage = { type: 'insets', top, left, right, bottom };
    const json = JSON.stringify(next);
    if (json === this.insetsJson) {
      return;
    }
    this.insetsJson = json;
    this.post(json);
  }

  setAppearance(scheme: string, locale: string): void {
    const changed = scheme !== this.scheme;
    this.scheme = scheme;
    this.locale = locale;
    if (changed && this.booted) {
      const theme: LocalRuntimeThemeMessage = { type: 'theme', scheme };
      this.post(JSON.stringify(theme));
    }
  }

  /** Replace the mounted app (new app, revision change, checker/live mode). */
  mountApp(mount: LocalRuntimeMount): Promise<void> {
    this.mount = mount;
    this.seq = 0;
    this.ready = false;
    const waiting = new Promise<void>((resolve: () => void) => {
      this.readyWaiters.push(resolve);
    });
    if (this.booted) {
      this.sendInit();
    }
    return waiting;
  }

  unmount(): void {
    this.mount = undefined;
  }

  appendSource(appId: string, text: string, reset: boolean): void {
    const mount = this.mount;
    if (!mount || mount.identity.appId !== appId) {
      return;
    }
    if (reset) {
      mount.source = text;
      this.seq = 0;
      const message: LocalRuntimeSourceResetMessage = { type: 'source_reset', appId, text, streaming: true, sourceRevision: mount.sourceRevision };
      this.post(JSON.stringify(message));
      return;
    }
    mount.source += text;
    const delta: LocalRuntimeSourceDeltaMessage = { type: 'source_delta', appId, seq: this.seq, text };
    this.seq += 1;
    this.post(JSON.stringify(delta));
  }

  sendState(appId: string, sourceRevision: number, stateRevision: number, stateJson: string, conflict: boolean): void {
    const mount = this.mount;
    if (!mount || mount.identity.appId !== appId || mount.sourceRevision !== sourceRevision) {
      return;
    }
    mount.stateRevision = stateRevision;
    mount.stateJson = stateJson;
    const message: LocalRuntimeStateMessage = { type: 'state', appId, sourceRevision, stateRevision, state: JSON.parse(stateJson) as Object, conflict };
    this.post(JSON.stringify(message));
  }

  sendCalendarResult(appId: string, sourceRevision: number, requestId: string, ok: boolean): void {
    const message: LocalRuntimeCalendarResultMessage = { type: 'calendar_result', appId, sourceRevision, requestId, ok };
    this.post(JSON.stringify(message));
  }

  sendCollaboration(reply: LocalCollaborationReply): void {
    const mount = this.mount;
    if (!mount || mount.mode !== 'live' || mount.streaming || mount.identity.appId !== reply.appId || mount.sourceRevision !== reply.sourceRevision) return;
    this.post(JSON.stringify(reply));
  }

  sendCollaborationAvailability(available: boolean, reason: string): void {
    const mount = this.mount;
    if (!mount || mount.mode !== 'live' || mount.streaming) return;
    const message: LocalCollaborationAvailability = { type: 'collaboration_availability', appId: mount.identity.appId,
      sourceRevision: mount.sourceRevision, available, reason };
    this.post(JSON.stringify(message));
  }

  sendCalendarReceipts(appId: string, sourceRevision: number, params: Object[]): void {
    const message: LocalRuntimeCalendarReceiptsMessage = { type: 'calendar_receipts', appId, sourceRevision, params };
    this.post(JSON.stringify(message));
  }

  sendCapabilityEvent(subscriptionId: string, gesture: string): void {
    const message: LocalRuntimeCapabilityEventMessage = { type: 'capability_event', subscriptionId, gesture };
    this.post(JSON.stringify(message));
  }

  sendCapabilityStatus(subscriptionId: string, status: string): void {
    const message: LocalRuntimeCapabilityStatusMessage = { type: 'capability_status', subscriptionId, status };
    this.post(JSON.stringify(message));
  }

  /** Read-only geometry probe of the mounted document. */
  probe(timeoutMs: number): Promise<LocalProbeReport | undefined> {
    if (!this.sender) {
      return Promise.resolve(undefined);
    }
    this.probeSerial += 1;
    const requestId = `probe-${this.probeSerial}`;
    return new Promise<LocalProbeReport | undefined>((resolve: (report: LocalProbeReport | undefined) => void) => {
      const timer = setTimeout(() => {
        this.probes.delete(requestId);
        resolve(undefined);
      }, timeoutMs);
      this.probes.set(requestId, { resolve, timer });
      const message: LocalRuntimeProbeMessage = { type: 'probe', requestId };
      this.post(JSON.stringify(message));
    });
  }

  /**
   * The program an OpenUI edit patch produces on `base`, computed by the
   * runtime's own lang-core so the host and the renderer merge identically.
   */
  merge(base: string, patch: string, timeoutMs: number): Promise<LocalRuntimeMergeResult> {
    if (!this.sender || !this.booted) {
      const detached: LocalRuntimeMergeResult = { source: '', error: 'runtime is not attached' };
      return Promise.resolve(detached);
    }
    this.probeSerial += 1;
    const requestId = `merge-${this.probeSerial}`;
    return new Promise<LocalRuntimeMergeResult>((resolve: (result: LocalRuntimeMergeResult) => void) => {
      const timer = setTimeout(() => {
        this.merges.delete(requestId);
        resolve({ source: '', error: 'merge timed out' });
      }, timeoutMs);
      this.merges.set(requestId, { resolve, timer });
      const message: LocalRuntimeMergeMessage = { type: 'merge', requestId, base, patch };
      this.post(JSON.stringify(message));
    });
  }

  waitReady(timeoutMs: number): Promise<boolean> {
    if (this.ready) {
      return Promise.resolve(true);
    }
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      const timer = setTimeout(() => resolve(false), timeoutMs);
      this.readyWaiters.push(() => {
        clearTimeout(timer);
        resolve(true);
      });
    });
  }

  private sendInit(): void {
    const mount = this.mount;
    const manifest = this.manifest;
    if (!mount || !manifest || !this.sender) {
      return;
    }
    this.seq = 0;
    const message: LocalRuntimeInitMessage = {
      type: 'init',
      manifest,
      identity: runtimeIdentity(mount.identity),
      mode: mount.mode,
      source: mount.source,
      streaming: mount.streaming,
      sourceRevision: mount.sourceRevision,
      stateRevision: mount.stateRevision,
      state: JSON.parse(mount.stateJson.length > 0 ? mount.stateJson : '{}') as Object,
      scheme: this.scheme,
      locale: this.locale
    };
    if (mount.base !== undefined && mount.base.length > 0) {
      message.base = mount.base;
    }
    this.post(JSON.stringify(message));
  }

  private post(json: string): void {
    if (this.sender && this.booted) {
      this.sender(json);
    }
  }
}
