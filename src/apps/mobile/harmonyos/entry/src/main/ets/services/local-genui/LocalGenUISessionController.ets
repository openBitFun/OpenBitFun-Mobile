import { HarmonyCollaborationService } from './HarmonyCollaborationService';
import { LocalGenUICollaborationHost } from './LocalGenUICollaborationHost';
import { LocalGenUICalendarActions } from './LocalGenUICalendarActions';
import { util } from '@kit.ArkTS';
import { Encoding } from '../Encoding';
import { RemoteLogger } from '../RemoteLogger';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { LocalGenUIActionHost } from './LocalGenUIActionHost';
import { LocalGenUIContract } from './LocalGenUIContract';
import { LocalGenUIFrameSink, LocalGenUIModelProvider, LocalGenUIPromptMessage } from './LocalGenUIModelProvider';
import {
  LOCAL_GENUI_NAMESPACE,
  LocalGenUIAppRecord,
  LocalGenUIAppStatus,
  LocalGenUIEvent,
  LocalGenUIEventType,
  LocalGenUIGalleryEntry,
  LocalGenUIIdentity,
  LocalGenUIMessage,
  LocalGenUIMessageRole,
  LocalGenUIPresentation,
  LocalGenUISession,
  LocalGenUIVerification
} from './LocalGenUIModels';
import { LocalGenUIOwner, LocalStateSaveOutcome } from './LocalGenUIOwner';
import { LocalGenUIRepository } from './LocalGenUIRepository';
import { LocalGenUIRuntimeBridge } from './LocalGenUIRuntimeBridge';
import { evaluateLocalAcceptance, LocalProbeReport, LocalRuntimeInbound, verificationOf } from './LocalGenUIRuntimeProtocol';
import { LOCAL_GENUI_TRUNCATED, LocalGenUITurnNormalizer } from './LocalGenUITurnNormalizer';
import { nextLocalRepair } from './LocalGenUIRepairPolicy';
import { LocalGenUIEditMode } from './LocalGenUIEditMode';
import { LocalGenUIDesktopCardStore } from './LocalGenUIDesktopCardStore';
import { LocalGenUIDesktopCardApp } from './LocalGenUIDesktopCards';
import { LocalGenUIThumbnailStore } from './LocalGenUIThumbnailStore';
import { LocalGenUIDeviceCapabilityHost } from './LocalGenUIDeviceCapabilityHost';
import { HarmonyCalendarAction, HarmonyCalendarService } from './HarmonyCalendarService';
import { LocalProviderFrame } from './LocalProviderSseParser';
import { LocalGenUIModelStore, LocalGenUIModelUpdate } from './LocalGenUIModelStore';
import { LocalGenUIImageSearch } from './LocalGenUIImageSearch';
import { LocalGenUIModelCatalog, LocalGenUIModelChoice, LocalGenUIModelProfile } from './LocalGenUIModelCatalog';
import { LocalGenUIBackgroundKeepAlive } from './LocalGenUIBackgroundKeepAlive';

/** Projection of one app for the presentation layer. */
export interface LocalGenUIAppView {
  appId: string;
  title: string;
  status: string;
  detail: string;
  unverified: string[];
  sourceRevision: number;
  streaming: boolean;
}

/** Presentation callbacks; the ViewModel implements them. */
export interface LocalGenUIControllerListener {
  sessionsChanged(sessions: LocalGenUISession[], activeId: string): void;
  messagesChanged(sessionId: string, messages: LocalGenUIMessage[]): void;
  streamingText(sessionId: string, text: string): void;
  appChanged(app: LocalGenUIAppView | undefined): void;
  busyChanged(busy: boolean, turnSerial: number, showInTimeline?: boolean): void;
  notice(text: string): void;
  /** Models plus the model the current (or next new) session uses. */
  modelsChanged(models: LocalGenUIModelProfile[], currentId: string, missing: boolean): void;
  galleryChanged(entries: LocalGenUIGalleryEntry[]): void;
  orientationChanged(orientation: string): void;
}

export interface LocalGenUIPresentationSource {
  presentation(): LocalGenUIPresentation;
}

export interface LocalGenUIComposerSend {
  isCurrent: () => boolean;
  onAccepted: () => void;
  onModelRequired: () => void;
}

const PROBE_TIMEOUT_MS: number = 4000;
const READY_TIMEOUT_MS: number = 8000;
const MERGE_TIMEOUT_MS: number = 4000;
const HISTORY_LIMIT: number = 12;

/**
 * Gives the local model an explicit device-local clock for relative dates.
 * The model contract already defines @Today(), but generated calendar payloads
 * can otherwise drift when the provider has a stale or different system date.
 */
function localGenUIDateContext(): string {
  const now = new Date();
  const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
  const date = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
  const time = `${pad(now.getHours())}:${pad(now.getMinutes())}`;
  const offsetMinutes = -now.getTimezoneOffset();
  const offsetSign = offsetMinutes >= 0 ? '+' : '-';
  const offsetHours = Math.floor(Math.abs(offsetMinutes) / 60);
  const offsetRemainder = Math.abs(offsetMinutes) % 60;
  const offset = `UTC${offsetSign}${pad(offsetHours)}:${pad(offsetRemainder)}`;
  return `Device-local date: ${date}; local time: ${time}; time zone: ${offset}. `
    + `For relative dates such as “today” or “今天”, use @Today() and create calendar timestamps on ${date}. `
    + 'Do not substitute a stale or hard-coded date.';
}

interface LocalGenUIPendingRepair {
  /** The failed candidate the checks measured; the repair patch applies to it. */
  base: string;
  appId: string;
  prompt: string;
  messageId: string;
}

class TurnSink implements LocalGenUIFrameSink {
  private readonly onFramesCallback: (frames: LocalProviderFrame[]) => void;
  constructor(onFrames: (frames: LocalProviderFrame[]) => void) {
    this.onFramesCallback = onFrames;
  }
  onFrames(frames: LocalProviderFrame[]): void {
    this.onFramesCallback(frames);
  }
}

/**
 * Local GenUI session controller. Owns sessions and turns on the phone; it
 * never touches RemoteCommand, HostStream or remote identities.
 */
export class LocalGenUISessionController {
  private readonly repository: LocalGenUIRepository;
  private readonly provider: LocalGenUIModelProvider;
  private readonly contract: LocalGenUIContract;
  private readonly owner: LocalGenUIOwner;
  private readonly bridge: LocalGenUIRuntimeBridge;
  private readonly listener: LocalGenUIControllerListener;
  private readonly presentationSource: LocalGenUIPresentationSource;
  private readonly actions: LocalGenUIActionHost;
  private readonly modelStore: LocalGenUIModelStore;
  private readonly thumbnails: LocalGenUIThumbnailStore;
  private readonly devices: LocalGenUIDeviceCapabilityHost;
  private readonly calendar: HarmonyCalendarService;
  private readonly collaboration: LocalGenUICollaborationHost;
  private readonly calendarActions: LocalGenUICalendarActions;
  private readonly desktopCards: LocalGenUIDesktopCardStore;
  private backgroundKeepAlive?: LocalGenUIBackgroundKeepAlive;
  private backgrounded: boolean = false;
  private backgroundKeepAliveActive: boolean = false;
  private activeSessionId: string = '';
  private activeSession?: LocalGenUISession;
  /** Model for the next new session; follows the last explicit choice. */
  private draftModelId: string = '';
  private messages: LocalGenUIMessage[] = [];
  private turnActive: boolean = false;
  private turnSerial: number = 0;
  private mountedAppId: string = '';
  /** Automatic repair queued by the finished turn; runs after it releases the slot. */
  private pendingRepair?: LocalGenUIPendingRepair;
  private readonly imageSearch?: LocalGenUIImageSearch;

  constructor(
    repository: LocalGenUIRepository,
    provider: LocalGenUIModelProvider,
    contract: LocalGenUIContract,
    bridge: LocalGenUIRuntimeBridge,
    listener: LocalGenUIControllerListener,
    presentationSource: LocalGenUIPresentationSource,
    modelStore: LocalGenUIModelStore,
    thumbnails: LocalGenUIThumbnailStore,
    devices: LocalGenUIDeviceCapabilityHost,
    desktopCards: LocalGenUIDesktopCardStore,
    calendar: HarmonyCalendarService,
    collaboration: LocalGenUICollaborationHost,
    imageSearch?: LocalGenUIImageSearch,
    backgroundKeepAlive?: LocalGenUIBackgroundKeepAlive
  ) {
    this.imageSearch = imageSearch;
    this.backgroundKeepAlive = backgroundKeepAlive;
    this.devices = devices;
    this.calendar = calendar;
    this.collaboration = collaboration;
    this.calendarActions = new LocalGenUICalendarActions(repository);
    this.desktopCards = desktopCards;
    this.modelStore = modelStore;
    this.thumbnails = thumbnails;
    this.repository = repository;
    this.provider = provider;
    this.contract = contract;
    this.owner = new LocalGenUIOwner(repository, contract.manifest);
    this.bridge = bridge;
    this.listener = listener;
    this.presentationSource = presentationSource;
    this.bridge.setManifest(contract.manifest);
    this.bridge.setInboundHandler((message: LocalRuntimeInbound): void => {
      void this.onRuntimeMessage(message);
    });
    this.actions = new LocalGenUIActionHost({
      saveState: (appId: string, sourceRevision: number, base: number, stateJson: string): Promise<void> =>
        this.saveState(appId, sourceRevision, base, stateJson),
      modelTurn: (appId: string, message: string): Promise<void> => this.send(message, appId),
      isTurnActive: (): boolean => this.turnActive,
      unsupported: (_appId: string, capability: string, reason: string): void =>
        this.listener.notice(RemoteI18n.f2('localGenui.unsupportedAction', capability, reason)),
      subscribeGesture: (appId: string, subscriptionId: string, gesture: string): string =>
        this.devices.subscribeGesture(appId, subscriptionId, gesture),
      unsubscribeGesture: (subscriptionId: string): void => this.devices.unsubscribeGesture(subscriptionId),
      haptic: (kind: string): void => this.devices.haptic(kind),
      collaboration: (message: LocalRuntimeInbound): string => this.collaboration.handle(message),
      imageSearch: (appId: string, requestId: string, query: string): string => {
        const search = this.imageSearch;
        if (!search) return 'image search is unavailable';
        void search.search(query).then((images: string[]): void => this.bridge.sendImageSearchResult(appId, requestId, images));
        return '';
      },
      calendar: async (appId: string, action: string, params: Object): Promise<string> => action === 'CreateCalendarEvent'
        ? this.calendarActions.create(appId, params, () => this.runCalendar(action, params))
        : this.runCalendar(action, params)
    });
  }

  private async runCalendar(action: string, params: Object): Promise<string> {
    const result = await this.calendar.execute(action as HarmonyCalendarAction, params);
    if (!result.ok) {
      return result.error || 'calendar action failed';
    }
    if (result.kind === 'created') {
      this.listener.notice(RemoteI18n.f('localGenui.calendarCreated', String(result.eventId || '')));
    } else if (result.kind === 'updated') {
      this.listener.notice(RemoteI18n.f('localGenui.calendarUpdated', String(result.eventId || '')));
    } else if (result.kind === 'deleted') {
      this.listener.notice(RemoteI18n.f('localGenui.calendarDeleted', String(result.eventId || '')));
    } else if (result.kind === 'listed') {
      this.listener.notice(RemoteI18n.f('localGenui.calendarListed', String(result.count || 0)));
    }
    return '';
  }

  /** Device capabilities belong to the mounted app only. */
  private setMountedApp(appId: string): void {
    this.collaboration.close();
    this.listener.orientationChanged('auto');
    this.mountedAppId = appId;
    this.devices.releaseOtherApps(appId);
  }

  isTurnActive(): boolean {
    return this.turnActive;
  }

  setBackgroundKeepAlive(backgroundKeepAlive: LocalGenUIBackgroundKeepAlive): void {
    this.backgroundKeepAlive = backgroundKeepAlive;
  }

  /** Preserve the direct provider stream while Harmony suspends the UI ability. */
  onBackground(): void {
    this.backgrounded = true;
    this.ensureBackgroundKeepAlive();
  }

  /** Release the temporary background lease after the page is visible again. */
  onForeground(): void {
    this.backgrounded = false;
    this.releaseBackgroundKeepAlive();
  }

  private ensureBackgroundKeepAlive(): void {
    if (!this.backgrounded || !this.turnActive || this.backgroundKeepAliveActive || !this.backgroundKeepAlive) {
      return;
    }
    const keptAlive = this.backgroundKeepAlive.keepAlive((): void => {
      this.backgroundKeepAliveActive = false;
      if (this.backgrounded && this.turnActive) {
        RemoteLogger.warn('local genui background keep-alive expired; cancelling provider turn');
        this.cancel();
      }
    });
    this.backgroundKeepAliveActive = keptAlive;
    RemoteLogger.info(`local genui background keep-alive ${keptAlive ? 'started' : 'unavailable'}`);
  }

  private releaseBackgroundKeepAlive(): void {
    if (!this.backgroundKeepAliveActive || !this.backgroundKeepAlive) {
      return;
    }
    this.backgroundKeepAliveActive = false;
    this.backgroundKeepAlive.releaseKeepAlive();
    RemoteLogger.info('local genui background keep-alive released');
  }

  async refreshSessions(): Promise<void> {
    this.listener.sessionsChanged(await this.repository.listSessions(), this.activeSessionId);
  }

  newSession(): void {
    if (this.turnActive) {
      return;
    }
    this.activeSessionId = '';
    this.activeSession = undefined;
    this.messages = [];
    this.setMountedApp('');
    this.bridge.unmount();
    this.listener.messagesChanged('', []);
    this.listener.appChanged(undefined);
    void this.refreshSessions();
    void this.refreshModels();
  }

  async openSession(sessionId: string): Promise<void> {
    if (this.turnActive) {
      return;
    }
    this.activeSessionId = sessionId;
    this.activeSession = (await this.repository.listSessions()).find((item: LocalGenUISession) => item.id === sessionId);
    await this.refreshModels();
    this.messages = await this.repository.loadMessages(sessionId);
    this.listener.messagesChanged(sessionId, this.messages.slice());
    await this.refreshSessions();
    const pending = await this.repository.pendingAppOfSession(sessionId);
    if (this.activeSessionId !== sessionId) return;
    if (pending) {
      await this.openApp(pending.appId);
      return;
    }
    // Reopen shows the latest app of the session from the owner.
    for (let i = this.messages.length - 1; i >= 0; i--) {
      if (this.messages[i].appId.length > 0) {
        await this.openApp(this.messages[i].appId);
        return;
      }
    }
    this.setMountedApp('');
    this.bridge.unmount();
    this.listener.appChanged(undefined);
  }

  async renameSession(sessionId: string, title: string): Promise<void> {
    const session = (await this.repository.listSessions()).find((item: LocalGenUISession) => item.id === sessionId);
    const next = title.trim();
    if (!session || next.length === 0) {
      return;
    }
    session.title = next.slice(0, 60).replace(/[\uD800-\uDBFF]$/, '');
    if (session.title.length === 0) return;
    session.titleFromApp = true;
    await this.repository.upsertSession(session);
    if (this.activeSession && this.activeSession.id === sessionId) {
      this.activeSession.title = session.title;
      this.activeSession.titleFromApp = true;
    }
    await this.refreshSessions();
  }

  async deleteSession(sessionId: string): Promise<void> {
    if (this.turnActive) {
      return;
    }
    const appIds = await this.repository.appIdsOfSession(sessionId);
    await this.repository.deleteSession(sessionId);
    appIds.forEach((appId: string) => this.thumbnails.remove(appId));
    // Home-screen cards stay until the person removes them; they say the app is gone.
    for (let i = 0; i < appIds.length; i++) {
      await this.syncDesktopCards(appIds[i]);
    }
    await this.refreshGallery();
    if (sessionId === this.activeSessionId) {
      this.newSession();
    } else {
      await this.refreshSessions();
    }
  }

  /** Mount the runnable revision of an app read from the owner. */
  async openApp(appId: string): Promise<void> {
    let record = await this.repository.loadApp(appId);
    if (record?.status === LocalGenUIAppStatus.Candidate) {
      if (this.turnActive) return;
      const checkpoint = record;
      const serial = ++this.turnSerial;
      this.turnActive = true;
      this.listener.busyChanged(true, serial);
      const recovering = this.viewOf(record, false, '');
      recovering.status = 'recovering';
      this.listener.appChanged(recovering);
      try {
        record = await this.verify(record, serial);
        if (serial === this.turnSerial) await this.finalizeRecoveredMessage(checkpoint, record);
      } catch (error) {
        this.setMountedApp('');
        this.bridge.unmount();
        this.listener.appChanged(undefined);
        throw new Error(String(error));
      } finally {
        this.turnActive = false;
        this.listener.busyChanged(false, serial);
      }
      if (serial !== this.turnSerial) return;
    }
    if (record && record.status === LocalGenUIAppStatus.Failed && !this.turnActive) {
      // Checked by an older renderer: verify again with this one before showing it.
      const reconsidered = await this.owner.reconsiderFailure(appId);
      if (reconsidered) {
        RemoteLogger.info(`local genui reverify ${appId} r${reconsidered.sourceRevision}: failure came from another renderer`);
        record = await this.verify(reconsidered);
      }
    }
    if (!record) {
      this.listener.appChanged({ appId, title: '', status: 'unsupported', detail: RemoteI18n.t('localGenui.appMissing'), unverified: [], sourceRevision: 0, streaming: false });
      return;
    }
    if (!this.owner.isRunnable(record)) {
      this.setMountedApp('');
      this.bridge.unmount();
      this.listener.appChanged(this.viewOf(record, false, RemoteI18n.t('localGenui.appUnsupported')));
      return;
    }
    const runnable = LocalGenUIOwner.runnableRevision(record);
    if (!runnable) {
      this.setMountedApp('');
      this.bridge.unmount();
      this.listener.appChanged(this.viewOf(record, false, ''));
      return;
    }
    this.setMountedApp(record.appId);
    void this.bridge.mountApp({
      identity: this.identityOf(record),
      mode: 'live',
      source: runnable.source,
      streaming: false,
      sourceRevision: runnable.sourceRevision,
      stateRevision: runnable.stateRevision,
      stateJson: runnable.stateJson
    }).then(() => this.backfillThumbnail(appId));
    this.listener.appChanged(this.viewOf(record, false, ''));
  }

  private async finalizeRecoveredMessage(checkpoint: LocalGenUIAppRecord, record: LocalGenUIAppRecord): Promise<void> {
    const messages = await this.repository.loadMessages(record.sessionId);
    const existing = messages.find((item: LocalGenUIMessage) => item.id === record.messageId);
    if (existing && existing.status !== LocalGenUIAppStatus.Candidate) return;
    const message = existing ?? this.message(record.sessionId, LocalGenUIMessageRole.Assistant, '', checkpoint.updatedAt);
    message.id = record.messageId;
    message.type = 'genui';
    message.appId = record.appId;
    message.appTitle = record.title;
    message.status = record.status;
    if (!existing) await this.titleSessionAfterApp(record.sessionId, record.title);
    if (record.sessionId === this.activeSessionId) {
      await this.appendMessage(message);
    } else {
      await this.repository.upsertMessage(message);
    }
  }

  // Models

  private async modelChoice(): Promise<LocalGenUIModelChoice> {
    const sessionModel = this.activeSession && this.activeSession.modelId ? this.activeSession.modelId : '';
    const last = this.draftModelId.length > 0 ? this.draftModelId : await this.modelStore.lastSelectedId();
    return LocalGenUIModelCatalog.choose(this.modelStore.list(), sessionModel, last);
  }

  async refreshModels(): Promise<void> {
    const choice = await this.modelChoice();
    this.listener.modelsChanged(this.modelStore.list(), choice.model ? choice.model.id : '', choice.missing);
  }

  /** Pin a model to the active session (or the next new one) and remember it. */
  async chooseModel(modelId: string): Promise<void> {
    if (!this.modelStore.list().some((model: LocalGenUIModelProfile) => model.id === modelId)) {
      return;
    }
    this.draftModelId = modelId;
    await this.modelStore.setLastSelected(modelId);
    if (this.activeSession) {
      this.activeSession.modelId = modelId;
      await this.repository.upsertSession(this.activeSession);
    }
    await this.refreshModels();
  }

  async saveModel(update: LocalGenUIModelUpdate): Promise<LocalGenUIModelProfile> {
    const saved = await this.modelStore.save(update);
    if (update.id.length === 0) {
      await this.chooseModel(saved.id);
    } else {
      await this.refreshModels();
    }
    return saved;
  }

  async removeModel(modelId: string): Promise<void> {
    await this.modelStore.remove(modelId);
    if (this.draftModelId === modelId) {
      this.draftModelId = '';
    }
    await this.refreshModels();
  }

  /** An edited model may reuse its stored key for discovery. */
  async listRemoteModels(apiUrl: string, apiKey: string, modelId: string): Promise<string[]> {
    let key = apiKey.trim();
    if (key.length === 0 && modelId.length > 0) {
      const stored = await this.modelStore.credentials(modelId);
      key = stored ? stored.apiKey : '';
    }
    return await this.provider.listRemoteModels(apiUrl, key);
  }

  hasStoredKey(modelId: string): boolean {
    return this.modelStore.hasKey(modelId);
  }

  // Gallery

  async refreshGallery(): Promise<void> {
    const entries = await this.repository.listGallery();
    entries.forEach((entry: LocalGenUIGalleryEntry) => {
      const path = this.thumbnails.existing(entry.appId);
      if (path.length > 0) {
        entry.thumbnailPath = path;
      }
    });
    this.listener.galleryChanged(entries);
  }

  /** Gallery apps from before previews existed get one the first time they are opened. */
  private async backfillThumbnail(appId: string): Promise<void> {
    if (this.thumbnails.existing(appId).length > 0) {
      return;
    }
    const inGallery = (await this.repository.listGallery()).some((entry: LocalGenUIGalleryEntry) => entry.appId === appId);
    if (!inGallery) {
      return;
    }
    // Let fonts and the first layout settle before the snapshot.
    await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 900); });
    if (this.thumbnails.existing(appId).length === 0) {
      await this.captureThumbnail(appId);
    }
  }

  thumbnailFor(appId: string): string {
    return this.thumbnails.existing(appId);
  }

  /** Capture the mounted live app and report whether the gallery was updated. */
  private async captureThumbnail(appId: string): Promise<boolean> {
    const mount = this.bridge.currentMount();
    if (!mount || mount.identity.appId !== appId || mount.mode !== 'live' || mount.streaming) {
      RemoteLogger.info('local genui thumbnail skipped: app is not the mounted live app');
      return false;
    }
    const pixels = await this.bridge.snapshot();
    if (pixels && this.bridge.currentMount() !== mount) {
      void pixels.release();
      return false;
    }
    const path = pixels ? await this.thumbnails.save(appId, pixels) : '';
    RemoteLogger.info(`local genui thumbnail ${path.length > 0 ? 'saved' : 'unavailable'}`);
    // A new preview follows every accepted revision; cards on the home screen
    // pick up its title and image here.
    await this.syncDesktopCards(appId);
    if (path.length === 0) return false;
    if (this.messages.some((item: LocalGenUIMessage) => item.appId === appId)) {
      this.listener.messagesChanged(this.activeSessionId, this.messages.slice());
    }
    try {
      await this.refreshGallery();
      return true;
    } catch (error) {
      RemoteLogger.warn(`local genui gallery preview refresh failed: ${String(error)}`);
      return false;
    }
  }

  async addToGallery(appId: string): Promise<void> {
    const record = await this.repository.loadApp(appId);
    if (!record || !this.owner.isRunnable(record)) {
      return;
    }
    await this.repository.addToGallery({ appId, sessionId: record.sessionId, title: record.title, addedAt: new Date().toISOString() });
    if (this.thumbnails.existing(appId).length > 0 || !(await this.captureThumbnail(appId))) {
      await this.refreshGallery();
    }
  }

  async removeFromGallery(appId: string): Promise<void> {
    await this.repository.removeFromGallery(appId);
    await this.refreshGallery();
  }

  // Desktop cards

  /** What a home-screen card shows for an app, from the owner's record. */
  private async desktopCardApp(appId: string): Promise<LocalGenUIDesktopCardApp> {
    const record = await this.repository.loadApp(appId);
    const available = record !== undefined && this.owner.isRunnable(record) &&
      LocalGenUIOwner.runnableRevision(record) !== undefined;
    return {
      appId,
      title: record ? record.title : '',
      thumbnailPath: available ? this.thumbnails.existing(appId) : '',
      available,
      updatedAt: new Date().toISOString()
    };
  }

  private async syncDesktopCards(appId: string): Promise<void> {
    try {
      await this.desktopCards.publish(await this.desktopCardApp(appId));
    } catch (err) {
      RemoteLogger.warn(`local genui desktop card sync failed: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  /** Open an app from the gallery together with the session that produced it. */
  async openGalleryApp(appId: string): Promise<void> {
    const record = await this.repository.loadApp(appId);
    if (record && record.sessionId !== this.activeSessionId && !this.turnActive) {
      await this.openSession(record.sessionId);
    }
    await this.openApp(appId);
  }

  cancel(): void {
    if (this.turnActive) {
      this.turnSerial += 1;
      this.provider.cancelTurn();
    }
  }

  /**
   * Send a user turn. `targetAppId` updates an existing app in place.
   * `modelPrompt` replaces the visible text for host-generated turns.
   * `repairBase` is the failed source a repair patch applies to.
   */
  async send(text: string, targetAppId: string = '', modelPrompt: string = '', repairBase: string = '',
    composer?: LocalGenUIComposerSend, repairMessageId: string = ''): Promise<void> {
    const prompt = text.trim();
    if (prompt.length === 0 || this.turnActive) {
      return;
    }
    const sessionIdAtSend = this.activeSessionId;
    const choice = await this.modelChoice();
    const configured = choice.model !== undefined && await this.provider.isConfigured(choice.model.id);
    if (this.turnActive || this.activeSessionId !== sessionIdAtSend || (composer && !composer.isCurrent())) return;
    if (!choice.model || !configured) {
      if (composer) composer.onModelRequired();
      else this.listener.notice(RemoteI18n.t(choice.missing ? 'localGenui.modelMissing' : 'localGenui.modelNotConfigured'));
      return;
    }
    const modelId = choice.model.id;
    this.turnActive = true;
    const serial = ++this.turnSerial;
    this.ensureBackgroundKeepAlive();
    const internalRepair = repairMessageId.length > 0;
    this.listener.busyChanged(true, serial, !internalRepair);
    composer?.onAccepted();
    try {
      const sessionId = await this.ensureSession(prompt, modelId);
      const now = new Date().toISOString();
      if (!internalRepair) {
        const userMessage: LocalGenUIMessage = this.message(sessionId, LocalGenUIMessageRole.User, prompt, now);
        await this.appendMessage(userMessage);
      }
      const target = targetAppId.length > 0 ? await this.repository.loadApp(targetAppId) : undefined;
      let assistant: LocalGenUIMessage | undefined = undefined;
      if (internalRepair) {
        assistant = this.messages.find((item: LocalGenUIMessage): boolean => item.id === repairMessageId);
        if (!assistant) {
          assistant = (await this.repository.loadMessages(sessionId)).find((item: LocalGenUIMessage): boolean => item.id === repairMessageId);
        }
      }
      if (!assistant) {
        assistant = this.message(sessionId, LocalGenUIMessageRole.Assistant, '', new Date(Date.now() + 1).toISOString());
        if (internalRepair) assistant.id = repairMessageId;
      }
      assistant.status = internalRepair ? 'recovering' : 'streaming';
      assistant.error = '';
      if (internalRepair) {
        await this.appendMessage(assistant);
      }
      // A change to an existing app is an edit patch over the program it changes:
      // the failed candidate for a repair, the running revision for a follow-up.
      const runnable = target && this.owner.isRunnable(target) ? LocalGenUIOwner.runnableRevision(target) : undefined;
      const editBase = repairBase.length > 0 ? repairBase : (runnable ? runnable.source : '');
      await this.runTurn(serial, sessionId, modelPrompt.length > 0 ? modelPrompt : prompt, assistant, target, modelPrompt.length > 0, modelId, editBase);
    } catch (err) {
      RemoteLogger.warn(`local genui turn failed: ${String(err)}`);
      this.listener.notice(String(err instanceof Error ? err.message : err));
    } finally {
      this.turnActive = false;
      this.releaseBackgroundKeepAlive();
      this.listener.busyChanged(false, serial, !internalRepair);
    }
    const repair = this.pendingRepair;
    this.pendingRepair = undefined;
    if (repair && serial === this.turnSerial) {
      await this.send(RemoteI18n.t('localGenui.autoRepair'), repair.appId, repair.prompt, repair.base, undefined, repair.messageId);
    }
  }

  private async runTurn(serial: number, sessionId: string, prompt: string, assistant: LocalGenUIMessage,
    target: LocalGenUIAppRecord | undefined, hostPrompt: boolean, modelId: string, editBase: string = ''): Promise<void> {
    const turnId = Encoding.randomId('turn');
    const owner = this.owner;
    const normalizer = new LocalGenUITurnNormalizer(turnId, this.contract.manifest.toolName, {
      bind: (toolCallId: string, title: string): LocalGenUIIdentity => {
        if (target) {
          const inherited = owner.inheritedIdentity(target, toolCallId, title);
          if (inherited) {
            return inherited;
          }
        }
        return owner.newIdentity(`${LOCAL_GENUI_NAMESPACE}app-${util.generateRandomUUID(false)}`, toolCallId, title);
      }
    });
    let streamingText = '';
    let identity: LocalGenUIIdentity | undefined = undefined;
    const repairTurn = assistant.status === 'recovering';
    const handle = (events: LocalGenUIEvent[]): void => {
      if (serial !== this.turnSerial) {
        return;
      }
      events.forEach((event: LocalGenUIEvent) => {
        if (event.type === LocalGenUIEventType.MessageDelta && event.text) {
          streamingText += event.text;
          this.listener.streamingText(sessionId, streamingText);
        } else if (event.type === LocalGenUIEventType.GenUIStarted && event.identity) {
          identity = event.identity;
          // An inherited identity edits the target; a new app has no base.
          this.mountStreaming(event.identity, target, target && event.identity.appId === target.appId ? editBase : '', repairTurn);
        } else if (event.type === LocalGenUIEventType.GenUISourceDelta && event.delta) {
          this.bridge.appendSource(event.delta.appId, event.delta.text, event.delta.reset);
        }
      });
    };
    handle([normalizer.started()]);
    let providerError = '';
    try {
      await this.provider.streamTurn({
        modelId,
        system: `${this.contract.prompt}\n\nRuntime date context:\n${localGenUIDateContext()}\n\nCross-device capability context:\n${JSON.stringify(HarmonyCollaborationService.environment())}\nThe environment reports local prerequisites only, not peer discovery. A nonempty unavailable field means CrossDeviceImage cannot start on this device.`,
        toolSchemaJson: this.contract.toolSchemaJson,
        messages: await this.history(sessionId, prompt, hostPrompt ? undefined : target)
      }, new TurnSink((frames: LocalProviderFrame[]): void => handle(normalizer.accept(frames))));
    } catch (err) {
      providerError = err instanceof Error ? err.message : String(err);
    }
    if (serial !== this.turnSerial) {
      providerError = RemoteI18n.t('localGenui.cancelled');
    }
    const result = normalizer.finish(this.contract.manifest.ownerFields);
    RemoteLogger.info(`local genui turn finished stop=${result.stopReason || 'none'} text=${result.assistantText.length} generation=${result.generation ? (result.generation.ok ? 'ok' : `rejected: ${result.generation.error.slice(0, 200)}`) : 'none'}`);
    result.warnings.forEach((warning: string) => RemoteLogger.warn(`local genui: ${warning}`));
    assistant.text = result.assistantText.trim();
    this.listener.streamingText(sessionId, '');
    const failedEvent = result.events.find((event: LocalGenUIEvent) => event.type === LocalGenUIEventType.TurnFailed);
    let failure = providerError.length > 0 ? providerError : (failedEvent && failedEvent.error ? failedEvent.error : '');
    if (failure === LOCAL_GENUI_TRUNCATED) {
      failure = RemoteI18n.t('localGenui.truncated');
    } else if (providerError.length === 0 && failure.length > 0) {
      // Contract/parser diagnostics are for the log, not for the person.
      RemoteLogger.warn(`local genui generation rejected: ${failure.slice(0, 300)}`);
      failure = RemoteI18n.t('localGenui.generationInvalid');
    }
    if (failure.length > 0 || !result.generation || !result.identity) {
      assistant.status = failure.length > 0 ? 'failed' : 'completed';
      assistant.error = failure;
      await this.appendMessage(assistant);
      if (result.identity) {
        // The candidate never reached the owner; show the stored app again.
        if (target) {
          await this.openApp(target.appId);
        } else {
          this.setMountedApp('');
          this.bridge.unmount();
          this.listener.appChanged(undefined);
        }
      }
      return;
    }
    const committedIdentity: LocalGenUIIdentity = result.identity;
    if (target && committedIdentity.appId === target.appId && editBase.length > 0) {
      // Edit mode: the tool carried a patch; the owner commits the program it produces.
      const merged = await this.bridge.merge(editBase, result.generation.source, MERGE_TIMEOUT_MS);
      if (merged.error.length > 0) {
        RemoteLogger.warn(`local genui edit merge failed: ${merged.error.slice(0, 200)}`);
        assistant.status = 'failed';
        assistant.error = RemoteI18n.t('localGenui.generationInvalid');
        await this.appendMessage(assistant);
        await this.openApp(target.appId);
        return;
      }
      RemoteLogger.info(`local genui edit merged ${committedIdentity.appId}: patch ${result.generation.source.split('\n').length} lines over base ${editBase.split('\n').length} -> ${merged.source.split('\n').length}`);
      result.generation.source = merged.source;
    }
    assistant.type = 'genui';
    assistant.appId = committedIdentity.appId;
    assistant.appTitle = result.generation.title;
    const record = await this.owner.commitCandidate(sessionId, assistant.id, committedIdentity, result.generation);
    await this.titleSessionAfterApp(sessionId, result.generation.title);
    assistant.status = record.status;
    await this.appendMessage(assistant);
    const failedSource = record.sourceContent;
    const verified = await this.verify(record, serial);
    if (serial !== this.turnSerial) return;
    const repairQueued = await this.queueRepair(verified, failedSource, assistant);
    assistant.status = repairQueued ? 'recovering' : verified.status;
    if (repairQueued) assistant.error = '';
    await this.appendMessage(assistant);
    if (repairQueued) {
      if (LocalGenUIOwner.runnableRevision(verified)) {
        await this.openApp(verified.appId);
      }
      const recovering = this.viewOf(verified, false, '');
      recovering.status = 'recovering';
      this.listener.appChanged(recovering);
    } else {
      await this.openApp(verified.appId);
    }
  }

  private async queueRepair(record: LocalGenUIAppRecord, failedSource: string, assistant: LocalGenUIMessage): Promise<boolean> {
    let verification: LocalGenUIVerification | undefined = undefined;
    try {
      const parsed = JSON.parse(record.verificationJson.length > 0 ? record.verificationJson : '{}') as LocalGenUIVerification;
      verification = Array.isArray(parsed.checks) ? parsed : undefined;
    } catch (_err) {
      verification = undefined;
    }
    if (!verification) {
      return false;
    }
    const repair = nextLocalRepair(record, verification, failedSource);
    if (!repair) {
      return false;
    }
    // Persist the attempt first so a restart cannot repeat the same repair.
    if (!(await this.owner.recordRepairAttempt(record.appId, repair.errorKey))) {
      return false;
    }
    RemoteLogger.info(`local genui automatic repair ${record.appId} attempt ${repair.attempt}`);
    this.pendingRepair = { appId: record.appId, prompt: repair.prompt, base: failedSource, messageId: assistant.id };
    return true;
  }

  /** Local acceptance: checker-mode probe, owner readback, then live reopen probe. */
  private async verify(record: LocalGenUIAppRecord, serial: number = this.turnSerial): Promise<LocalGenUIAppRecord> {
    if (record.status !== 'candidate') {
      return record;
    }
    const identity = this.identityOf(record);
    const host = this.presentationSource.presentation();
    const checkerReady = this.bridge.mountApp({
      identity, mode: 'checker', source: record.sourceContent, streaming: false,
      sourceRevision: record.sourceRevision, stateRevision: record.stateRevision, stateJson: record.stateJson
    });
    this.setMountedApp(record.appId);
    const checkerOk = await this.withTimeout(checkerReady, READY_TIMEOUT_MS);
    const checkerProbe = checkerOk ? await this.bridge.probe(PROBE_TIMEOUT_MS) : undefined;
    if (serial !== this.turnSerial) return record;
    // The runtime's measured canvas scale is the recorded truth.
    const presentation: LocalGenUIPresentation = {
      posture: host.posture, deviceWidth: host.deviceWidth, deviceHeight: host.deviceHeight,
      safeTop: host.safeTop, safeBottom: host.safeBottom,
      viewportScale: checkerProbe ? checkerProbe.canvasScale : host.viewportScale
    };
    const readback = await this.repository.loadApp(record.appId);
    const sourceHash = await Encoding.sha256(record.sourceContent);
    const stateHash = await Encoding.sha256(record.stateJson);
    const readbackMatches = readback !== undefined && readback.sourceRevision === record.sourceRevision &&
      readback.stateRevision === record.stateRevision && (await Encoding.sha256(readback.sourceContent)) === sourceHash &&
      (await Encoding.sha256(readback.stateJson)) === stateHash;
    let reopenProbe: LocalProbeReport | undefined = undefined;
    if (readback && readbackMatches) {
      if (serial !== this.turnSerial) return record;
      const liveReady = this.bridge.mountApp({
        identity, mode: 'live', source: readback.sourceContent, streaming: false,
        sourceRevision: readback.sourceRevision, stateRevision: readback.stateRevision, stateJson: readback.stateJson
      });
      if (await this.withTimeout(liveReady, READY_TIMEOUT_MS)) {
        reopenProbe = await this.bridge.probe(PROBE_TIMEOUT_MS);
      }
    }
    if (serial !== this.turnSerial) return record;
    const checks = evaluateLocalAcceptance({
      probe: checkerProbe,
      reopenProbe,
      readbackMatches,
      readbackDetail: readbackMatches ? `owner readback r${record.sourceRevision}/s${record.stateRevision}` : 'owner readback differs from the committed candidate',
      canvas: this.contract.canvas,
      presentation,
      requiredChecks: this.contract.requiredChecks
    });
    const verification = verificationOf(checks, this.contract.manifest, presentation, sourceHash, stateHash, new Date().toISOString());
    RemoteLogger.info(`local genui verification ${record.appId} r${record.sourceRevision}: ${checks.map((item) => `${item.name}=${item.result}`).join(',')}`);
    checks.filter((item) => item.result !== 'passed').forEach((item) => RemoteLogger.info(`local genui check ${item.name}: ${item.detail}`));
    const boundary = checks.find((item) => item.name === 'content-boundary');
    if (boundary) {
      RemoteLogger.info(`local genui geometry: ${boundary.detail}`);
    }
    const declared: Record<string, string> = checkerProbe && checkerProbe.stateTypes ? checkerProbe.stateTypes : {};
    return await this.owner.recordVerification(record.appId, record.sourceRevision, verification, this.contract.requiredChecks, declared);
  }

  private async withTimeout(promise: Promise<void>, ms: number): Promise<boolean> {
    let timer = -1;
    const timeout = new Promise<boolean>((resolve: (value: boolean) => void) => {
      timer = setTimeout(() => resolve(false), ms);
    });
    const done = promise.then((): boolean => true);
    const result = await Promise.race([done, timeout]);
    clearTimeout(timer);
    return result;
  }

  private mountStreaming(identity: LocalGenUIIdentity, target: LocalGenUIAppRecord | undefined, base: string, repairing: boolean = false): void {
    this.setMountedApp(identity.appId);
    void this.bridge.mountApp({
      identity, mode: 'live', source: '', streaming: true, base,
      sourceRevision: target ? target.sourceRevision + 1 : 1,
      stateRevision: target ? target.stateRevision : 1,
      stateJson: target ? target.stateJson : '{}'
    });
    this.listener.appChanged({ appId: identity.appId, title: identity.title, status: repairing ? 'recovering' : 'candidate', detail: RemoteI18n.t('localGenui.generating'), unverified: [], sourceRevision: 0, streaming: true });
  }

  private async onRuntimeMessage(message: LocalRuntimeInbound): Promise<void> {
    const mount = this.bridge.currentMount();
    if (message.type === 'error') {
      RemoteLogger.warn(`local genui runtime error ${message.code || ''}: ${message.message || ''}`);
      return;
    }
    if (message.type === 'ready' && message.contractOk === false) {
      this.listener.notice(RemoteI18n.f('localGenui.runtimeMismatch', message.reason || ''));
      return;
    }
    if (message.type === 'ready' && mount && mount.mode === 'live' && !mount.streaming) {
      const environment = HarmonyCollaborationService.environment();
      this.bridge.sendCollaborationAvailability(environment.unavailable.length === 0, environment.unavailable);
      try {
        const rows = await this.repository.calendarReceipts(mount.identity.appId);
        this.bridge.sendCalendarReceipts(mount.identity.appId, mount.sourceRevision, rows.map((row: string): Object => JSON.parse(row) as Object));
      } catch (error) {
        this.listener.notice(String(error));
      }
      return;
    }
    if (message.type === 'preview_ready') {
      if (!mount || mount.mode !== 'live' || mount.streaming || message.appId !== mount.identity.appId ||
        message.sourceRevision !== mount.sourceRevision) return;
      const record = await this.repository.loadApp(mount.identity.appId);
      const runnable = record ? LocalGenUIOwner.runnableRevision(record) : undefined;
      // The live reopen probe can finish painting before the candidate has been accepted.
      if (runnable && LocalGenUIOwner.isDisplayableStatus(runnable.status) &&
        runnable.sourceRevision === mount.sourceRevision && this.bridge.currentMount() === mount) {
        await this.captureThumbnail(mount.identity.appId);
      }
      return;
    }
    if (message.type === 'orientation') {
      if (mount && mount.mode === 'live' && !mount.streaming && message.appId === this.mountedAppId &&
        message.sourceRevision === mount.sourceRevision &&
        (message.orientation === 'auto' || message.orientation === 'portrait' || message.orientation === 'landscape')) {
        this.listener.orientationChanged(message.orientation);
      }
      return;
    }
    // Photo search is read-only, so a page may ask while its source still streams.
    if (message.type === 'image_search') {
      if (!mount || mount.mode !== 'live') return;
      const refusedSearch = await this.actions.handle(message, this.mountedAppId, mount.sourceRevision);
      if (refusedSearch.length > 0) {
        this.bridge.sendImageSearchResult(message.appId || '', message.requestId || '', []);
        RemoteLogger.warn(`local genui refused image search: ${refusedSearch}`);
      }
      return;
    }
    // Only capability-bearing messages reach the action host.
    if (message.type === 'capability' && message.op === 'unsubscribe') {
      // Releases are always honored, even while a turn streams or after a remount.
      void this.actions.handle(message, this.mountedAppId, mount ? mount.sourceRevision : 0);
      return;
    }
    if (message.type !== 'state' && message.type !== 'action' && message.type !== 'query' &&
      message.type !== 'capability' && message.type !== 'haptic' && message.type !== 'collaboration') {
      return;
    }
    if (!mount || mount.mode !== 'live' || mount.streaming) {
      return;
    }
    const refused = await this.actions.handle(message, this.mountedAppId, mount.sourceRevision);
    if (message.type === 'collaboration' && refused && message.requestId) {
      this.bridge.sendCollaboration({ type: 'collaboration_result', appId: message.appId || '',
        sourceRevision: message.sourceRevision || 0, requestId: message.requestId, status: 'failed', reason: refused, asset: '' });
    }
    if (message.type === 'action' && message.action === 'CreateCalendarEvent' && message.requestId) {
      this.bridge.sendCalendarResult(message.appId || '', message.sourceRevision || 0, message.requestId, refused.length === 0);
    }
    if (refused.length > 0) {
      RemoteLogger.warn(`local genui refused runtime message: ${refused}`);
    }
  }

  private async saveState(appId: string, sourceRevision: number, baseStateRevision: number, stateJson: string): Promise<void> {
    const result = await this.owner.saveState(appId, sourceRevision, baseStateRevision, stateJson);
    if (result.outcome === LocalStateSaveOutcome.Saved && result.record) {
      this.bridge.sendState(appId, sourceRevision, result.record.stateRevision, result.record.stateJson, false);
    } else if (result.outcome === LocalStateSaveOutcome.Conflict && result.record) {
      this.bridge.sendState(appId, sourceRevision, result.record.stateRevision, result.record.stateJson, true);
    } else {
      this.listener.notice(RemoteI18n.f('localGenui.saveFailed', result.error));
    }
  }

  /** A session still titled by its first prompt takes the first app's name. */
  private async titleSessionAfterApp(sessionId: string, appTitle: string): Promise<void> {
    const session = (await this.repository.listSessions()).find((item: LocalGenUISession) => item.id === sessionId);
    if (!session || appTitle.trim().length === 0 || session.titleFromApp) {
      return;
    }
    session.title = appTitle.trim();
    session.titleFromApp = true;
    await this.repository.upsertSession(session);
    if (this.activeSession && this.activeSession.id === sessionId) {
      this.activeSession.title = session.title;
      this.activeSession.titleFromApp = true;
    }
    await this.refreshSessions();
  }

  private async ensureSession(prompt: string, modelId: string): Promise<string> {
    if (this.activeSessionId.length > 0) {
      return this.activeSessionId;
    }
    const now = new Date().toISOString();
    const title = prompt.replace(/\s+/g, ' ').slice(0, 24);
    const session: LocalGenUISession = { id: `${LOCAL_GENUI_NAMESPACE}${util.generateRandomUUID(false)}`, title, createdAt: now, updatedAt: now, modelId };
    await this.repository.upsertSession(session);
    this.activeSessionId = session.id;
    this.activeSession = session;
    this.messages = [];
    await this.refreshSessions();
    return session.id;
  }

  private async appendMessage(message: LocalGenUIMessage): Promise<void> {
    await this.repository.upsertMessage(message);
    const index = this.messages.findIndex((item: LocalGenUIMessage) => item.id === message.id);
    if (index >= 0) {
      this.messages[index] = message;
    } else {
      this.messages.push(message);
    }
    if (message.sessionId === this.activeSessionId) {
      this.listener.messagesChanged(message.sessionId, this.messages.slice());
    }
    const sessions = await this.repository.listSessions();
    const session = sessions.find((item: LocalGenUISession) => item.id === message.sessionId);
    if (session) {
      session.updatedAt = message.createdAt > session.updatedAt ? message.createdAt : new Date().toISOString();
      await this.repository.upsertSession(session);
    }
  }

  /** Prompt history: recent text plus the current source of the targeted app. */
  private async history(sessionId: string, prompt: string, target: LocalGenUIAppRecord | undefined): Promise<LocalGenUIPromptMessage[]> {
    const history: LocalGenUIPromptMessage[] = [];
    const recent = this.messages.filter((item: LocalGenUIMessage) => item.sessionId === sessionId && item.status !== 'failed');
    // The last entry is the current user prompt; it is appended below.
    recent.slice(Math.max(0, recent.length - 1 - HISTORY_LIMIT), recent.length - 1).forEach((item: LocalGenUIMessage) => {
      let content = item.text;
      if (item.appId.length > 0) {
        content = `${content}\n[Created mini app "${item.appTitle}"]`.trim();
      }
      if (content.length > 0) {
        history.push({ role: item.role === LocalGenUIMessageRole.User ? 'user' : 'assistant', content });
      }
    });
    let current = prompt;
    if (target && this.owner.isRunnable(target)) {
      const runnable = LocalGenUIOwner.runnableRevision(target);
      if (runnable) {
        current = LocalGenUIEditMode.followUp(prompt, target.title, runnable.source, runnable.stateJson);
      }
    }
    history.push({ role: 'user', content: current });
    return history;
  }

  private message(sessionId: string, role: string, text: string, createdAt: string): LocalGenUIMessage {
    return { id: Encoding.randomId('local-msg'), sessionId, role, type: 'text', text, appId: '', appTitle: '', status: 'completed', error: '', createdAt };
  }

  private identityOf(record: LocalGenUIAppRecord): LocalGenUIIdentity {
    return {
      appId: record.appId,
      toolCallId: '',
      title: record.title,
      template: record.template,
      libraryId: record.libraryId,
      libraryRevision: record.libraryRevision,
      designSpec: { id: record.designSpecId, revision: record.designSpecRevision },
      sourceFormat: record.sourceFormat
    };
  }

  private viewOf(record: LocalGenUIAppRecord, streaming: boolean, detail: string): LocalGenUIAppView {
    let unverified: string[] = [];
    let summary = detail;
    try {
      const verification = JSON.parse(record.verificationJson.length > 0 ? record.verificationJson : '{}') as Record<string, Object>;
      if (Array.isArray(verification['unverified'])) {
        unverified = verification['unverified'] as string[];
      }
      if (summary.length === 0 && typeof verification['error'] === 'string') {
        summary = verification['error'] as string;
      }
      if (summary.length === 0 && typeof verification['migration'] === 'string') {
        summary = verification['migration'] as string;
      }
    } catch (_err) {
      // Unknown verification payloads are preserved and not interpreted.
    }
    return { appId: record.appId, title: record.title, status: record.status, detail: summary, unverified, sourceRevision: record.sourceRevision, streaming };
  }
}
