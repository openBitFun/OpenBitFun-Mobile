import { LocalGenUICollaborationAssets, LOCAL_GENUI_COLLABORATION_ROOT } from '../../services/local-genui/LocalGenUICollaborationAssets';
import { LocalGenUICollaborationHost, LocalCollaborationOwner, LocalCollaborationRequest, LocalCollaborationReply } from '../../services/local-genui/LocalGenUICollaborationHost';
import { LocalCollaborationSnapshot } from '../../services/local-genui/LocalCollaborationSession';
import { HarmonyCollaborationService } from '../../services/local-genui/HarmonyCollaborationService';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { RemoteLogger } from '../../services/RemoteLogger';
import { GeneralChatConfigStore } from '../../services/general-chat/GeneralChatConfigStore';
import { LocalGenUIContractLoader } from '../../services/local-genui/LocalGenUIContract';
import {
  HarmonyLocalGenUIStreamTransport,
  HttpLocalGenUIModelProvider,
  LocalGenUIStreamTransport
} from '../../services/local-genui/LocalGenUIModelProvider';
import {
  LocalGenUIGalleryEntry,
  LocalGenUIMessage,
  LocalGenUIPresentation,
  LocalGenUISession
} from '../../services/local-genui/LocalGenUIModels';
import { LocalGenUIModelProfile } from '../../services/local-genui/LocalGenUIModelCatalog';
import { LocalGenUIModelStore } from '../../services/local-genui/LocalGenUIModelStore';
import { LocalGenUIRepository } from '../../services/local-genui/LocalGenUIRepository';
import { LocalGenUIThumbnailStore } from '../../services/local-genui/LocalGenUIThumbnailStore';
import { LocalGenUIDesktopCardStore } from '../../services/local-genui/LocalGenUIDesktopCardStore';
import { LocalGenUIOrientation } from '../../services/local-genui/LocalGenUIOrientation';
import { LocalGenUIIcon3DStore } from '../../services/local-genui/LocalGenUIIcon3DStore';
import { LOCAL_GENUI_PHOTO_ROOT, LocalGenUIImageSearch } from '../../services/local-genui/LocalGenUIImageSearch';
import { LocalGenUIDeviceCapabilityHost } from '../../services/local-genui/LocalGenUIDeviceCapabilityHost';
import { LocalGenUIRuntimeBridge } from '../../services/local-genui/LocalGenUIRuntimeBridge';
import { HarmonyCalendarService } from '../../services/local-genui/HarmonyCalendarService';
import {
  LocalGenUIAppView,
  LocalGenUIControllerListener,
  LocalGenUIPresentationSource,
  LocalGenUISessionController
} from '../../services/local-genui/LocalGenUISessionController';
import { LocalGenUIBackgroundKeepAlive } from '../../services/local-genui/LocalGenUIBackgroundKeepAlive';
import { LocalGenUIActions, LocalGenUIModelEditorInput, LocalGenUIState } from '../state/LocalGenUIState';
import { ConversationIntent, ConversationIntentType, MessageCopyScope } from '../actions/ConversationIntent';
import { ConversationViewModel } from './ConversationViewModel';
import { ChatMessage, RemoteModelCatalog, RemoteModelConfig } from '../../model/RemoteModels';
import { ChatTimelineState } from '../../services/ChatTimelineStore';
import { RemoteUiState } from '../../services/RemoteUiState';
import { ClipboardService } from '../../services/ClipboardService';
import { MarkdownHtmlSerializer } from '../../services/MarkdownHtmlSerializer';
import { LocalGenUIConversationProjection } from './LocalGenUIConversationProjection';

/**
 * Local GenUI Mode entry. Local stores are created on first use (surface,
 * sidebar section or gallery); Remote Mode never constructs them.
 */
export class LocalGenUIViewModel implements LocalGenUIControllerListener, LocalGenUIPresentationSource {
  readonly state: LocalGenUIState = new LocalGenUIState();
  readonly bridge: LocalGenUIRuntimeBridge = new LocalGenUIRuntimeBridge();
  private readonly context: () => Context;
  private readonly transport: () => LocalGenUIStreamTransport;
  private controller?: LocalGenUISessionController;
  private initializing?: Promise<void>;
  private facts: LocalGenUIPresentation = { posture: 'compact', deviceWidth: 0, deviceHeight: 0, safeTop: 0, safeBottom: 0, viewportScale: 1 };
  private noticeTimer: number = -1;
  /** The shared timeline store behind ConversationView. */
  private readonly timeline: ConversationViewModel = new ConversationViewModel();
  private readonly clipboard: ClipboardService = new ClipboardService();
  private messages: LocalGenUIMessage[] = [];
  private devices?: LocalGenUIDeviceCapabilityHost;
  private collaboration?: LocalGenUICollaborationHost;
  private foreground: boolean = true;
  private appOnScreen: boolean = false;
  private streaming: string = '';
  private activeTurnSerial: number = 0;
  private showActiveTurn: boolean = true;
  private readonly orientation: LocalGenUIOrientation;
  private preferredOrientation: string = 'auto';
  private backgroundKeepAlive?: LocalGenUIBackgroundKeepAlive;

  readonly actions: LocalGenUIActions = {
    open: (): void => {
      this.showSessions();
      void this.open();
    },
    close: (): void => this.close(),
    back: (): boolean => this.back(),
    newSession: (): void => { void this.newSession(); },
    openSession: (sessionId: string): void => { void this.openSession(sessionId); },
    deleteSession: (sessionId: string): void => { void this.withController((c) => c.deleteSession(sessionId)); },
    openApp: (appId: string): void => {
      this.state.view = 'app';
      void this.withController((c) => c.openApp(appId));
    },
    showSessions: (): void => this.showSessions(),
    showChat: (): void => {
      this.state.standalone = false;
      this.state.view = 'chat';
    },
    conversation: (intent: ConversationIntent): void => this.dispatch(intent),
    openModelManager: (): void => {
      if (this.state.currentModelId.length === 0) {
        this.openModelSetup();
        return;
      }
      this.state.editorOpen = false;
      this.state.showModelManager = true;
    },
    closeModelManager: (): void => this.closeModelManager(),
    editModel: (modelId: string): void => this.editModel(modelId),
    useModel: (modelId: string): void => { void this.useModelForSetup(modelId); },
    closeEditor: (): void => {
      if (this.state.configuringModel && this.state.models.length === 0) this.closeModelManager();
      else this.state.editorOpen = false;
    },
    saveModel: (input: LocalGenUIModelEditorInput): void => { void this.saveModel(input); },
    removeModel: (modelId: string): void => {
      this.state.editorOpen = false;
      void this.withController((c) => c.removeModel(modelId));
    },
    fetchRemoteModels: (apiUrl: string, apiKey: string): void => { void this.fetchRemoteModels(apiUrl, apiKey); },
    addToGallery: (appId: string): void => {
      void this.withController(async (c) => {
        await c.addToGallery(appId);
        this.notice(RemoteI18n.t('localGenui.addedToGallery'));
      });
    },
    removeFromGallery: (appId: string): void => { void this.withController((c) => c.removeFromGallery(appId)); },
    openGalleryApp: (appId: string): void => { void this.openGalleryApp(appId); },
    appOnScreen: (onScreen: boolean): void => this.setAppOnScreen(onScreen),
    cameraSurface: (surfaceId: string): void => this.attachCameraSurface(surfaceId),
    cameraSurfaceGone: (): void => this.detachCameraSurface(),
    collaborationClose: (token: number): void => this.collaboration?.close(token),
    collaborationResult: (token: number, result: LocalCollaborationSnapshot): void => this.collaboration?.result(token, result),
    collaborationReceive: async (token: number, data: ArrayBuffer): Promise<void> => {
      if (!this.collaboration) throw new Error('collaboration unavailable');
      await this.collaboration.receive(token, data);
    }
  };

  private showSessions(): void {
    this.state.standalone = false;
    this.state.view = 'sessions';
  }

  constructor(context: () => Context, transport: () => LocalGenUIStreamTransport = () => new HarmonyLocalGenUIStreamTransport()) {
    this.context = context;
    this.transport = transport;
    this.orientation = new LocalGenUIOrientation(context);
  }

  /** Read-only local data for the sidebar section and the gallery. */
  async load(): Promise<void> {
    await this.withController(async (c) => {
      await c.refreshSessions();
      await c.refreshGallery();
    });
  }

  async open(): Promise<void> {
    this.state.visible = true;
    this.state.standalone = false;
    this.state.error = '';
    try {
      await this.ensureController();
      if (this.controller) {
        await this.controller.refreshSessions();
        await this.controller.refreshModels();
        await this.controller.refreshGallery();
      }
    } catch (err) {
      this.state.error = err instanceof Error ? err.message : String(err);
      RemoteLogger.warn(`local genui open failed: ${this.state.error}`);
    }
  }

  async openSession(sessionId: string): Promise<void> {
    await this.open();
    this.state.view = 'chat';
    // Opening a session shows its conversation; the app opens from its card.
    if (this.controller) await this.controller.openSession(sessionId);
  }

  async newSession(): Promise<void> {
    await this.open();
    this.state.view = 'chat';
    if (this.controller) this.controller.newSession();
  }

  async openGalleryApp(appId: string): Promise<void> {
    await this.open();
    this.state.standalone = true;
    this.state.view = 'app';
    if (this.controller) await this.controller.openGalleryApp(appId);
  }

  close(): void {
    if (this.controller && this.controller.isTurnActive()) {
      this.controller.cancel();
    }
    this.state.visible = false;
    this.state.standalone = false;
    this.appOnScreen = false;
    this.syncDeviceVisibility();
    this.closeModelManager();
  }

  /** Returns true when the back gesture was consumed inside the surface. */
  back(): boolean {
    if (!this.state.visible) return false;
    if (this.state.showModelManager) {
      if (!this.state.editorSaving) {
        if (this.state.editorOpen) this.actions.closeEditor();
        else this.closeModelManager();
      }
      return true;
    }
    if (this.state.view === 'app' && !this.state.standalone) {
      this.state.view = 'chat';
      return true;
    }
    if (this.state.view === 'chat') {
      this.showSessions();
      return true;
    }
    this.close();
    return true;
  }

  /** The page reports whether the app pane is on screen. */
  setAppOnScreen(onScreen: boolean): void {
    this.appOnScreen = onScreen;
    this.syncDeviceVisibility();
  }

  /** The phone app went to the background or came back. */
  setForeground(foreground: boolean): void {
    this.foreground = foreground;
    if (foreground) {
      this.controller?.onForeground();
    } else {
      this.controller?.onBackground();
    }
    this.syncDeviceVisibility();
  }

  setBackgroundKeepAlive(backgroundKeepAlive: LocalGenUIBackgroundKeepAlive): void {
    this.backgroundKeepAlive = backgroundKeepAlive;
    this.controller?.setBackgroundKeepAlive(backgroundKeepAlive);
  }

  /** Camera surface from the preview leaf; recognition starts once it exists. */
  attachCameraSurface(surfaceId: string): void {
    if (this.devices) this.devices.attachSurface(surfaceId);
  }

  detachCameraSurface(): void {
    if (this.devices) this.devices.detachSurface();
  }

  private syncDeviceVisibility(): void {
    this.collaboration?.setVisible(this.foreground && this.state.visible && this.appOnScreen);
    void this.orientation.sync(this.foreground && this.state.visible && this.appOnScreen, this.preferredOrientation);
    if (this.devices) {
      const wanted = this.foreground && this.state.visible && this.appOnScreen;
      RemoteLogger.info(`local genui device visibility wanted=${wanted} foreground=${this.foreground} visible=${this.state.visible} appOnScreen=${this.appOnScreen} view=${this.state.view}`);
      this.devices.setVisible(wanted);
    }
  }

  updatePresentation(facts: LocalGenUIPresentation): void {
    this.facts = facts;
  }

  presentation(): LocalGenUIPresentation {
    return this.facts;
  }

  orientationChanged(orientation: string): void {
    this.preferredOrientation = orientation;
    this.syncDeviceVisibility();
  }

  // LocalGenUIControllerListener
  sessionsChanged(sessions: LocalGenUISession[], activeId: string): void {
    this.state.localSessions = sessions;
    this.state.sessionId = activeId;
    const active = sessions.find((item: LocalGenUISession) => item.id === activeId);
    if (active) {
      this.state.conversation.setActiveSession(LocalGenUIConversationProjection.session(active));
    } else if (activeId.length === 0) {
      this.state.conversation.clearActiveSession();
    }
  }

  messagesChanged(sessionId: string, messages: LocalGenUIMessage[]): void {
    const switched = sessionId !== this.state.sessionId;
    this.state.sessionId = sessionId;
    this.messages = messages;
    if (switched) {
      this.timeline.reset(sessionId);
      this.streaming = '';
    }
    this.timeline.setPersistedMessages(LocalGenUIConversationProjection.messages(messages,
      (appId: string): string => this.controller ? this.controller.thumbnailFor(appId) : ''));
    this.syncTimeline();
  }

  streamingText(_sessionId: string, text: string): void {
    this.streaming = text;
    if (this.state.conversation.isBusy && this.showActiveTurn) {
      this.timeline.setActiveTurn(LocalGenUIConversationProjection.activeTurn(this.activeTurnSerial, text));
    }
    this.syncTimeline();
  }

  appChanged(app: LocalGenUIAppView | undefined): void {
    this.collaboration?.invalidate(app?.appId || '', app?.sourceRevision || 0, app?.streaming || false);
    if (!app) {
      this.state.appId = '';
      this.state.appTitle = '';
      this.state.appStatus = '';
      this.state.appDetail = '';
      this.state.appUnverified = [];
      this.state.appStreaming = false;
      if (this.state.view === 'app' && !this.state.standalone) this.state.view = 'chat';
      return;
    }
    this.state.appId = app.appId;
    this.state.appTitle = app.title;
    this.state.appStatus = app.status;
    this.state.appDetail = app.detail;
    this.state.appUnverified = app.unverified;
    this.state.appStreaming = app.streaming;
    if (app.streaming && this.state.view !== 'sessions') this.state.view = 'app';
  }

  busyChanged(busy: boolean, turnSerial: number, showInTimeline: boolean = true): void {
    this.state.conversation.setBusy(busy);
    if (busy) {
      this.activeTurnSerial = turnSerial;
      this.showActiveTurn = showInTimeline;
      if (showInTimeline) {
        this.timeline.setActiveTurn(LocalGenUIConversationProjection.activeTurn(turnSerial, this.streaming));
      } else {
        this.timeline.clearActiveTurn();
      }
    } else {
      this.streaming = '';
      this.showActiveTurn = true;
      this.timeline.clearActiveTurn();
    }
    this.syncTimeline();
  }

  notice(text: string): void {
    this.state.notice = text;
    if (this.noticeTimer >= 0) clearTimeout(this.noticeTimer);
    this.noticeTimer = setTimeout(() => { this.state.notice = ''; this.noticeTimer = -1; }, 5000);
  }

  modelsChanged(models: LocalGenUIModelProfile[], currentId: string, missing: boolean): void {
    this.state.models = models;
    this.state.currentModelId = currentId;
    this.state.modelMissing = missing;
    // The shared composer's model selector reads the core catalog.
    this.state.conversation.setModelCatalog(LocalGenUIConversationProjection.catalog(models, currentId), currentId);
    this.state.conversation.setStatusText(missing ? RemoteI18n.t('localGenui.modelMissing') : '');
  }

  galleryChanged(entries: LocalGenUIGalleryEntry[]): void {
    this.state.gallery = entries;
  }

  private openModelSetup(): void {
    if (!this.state.visible || this.state.view !== 'chat' ||
      this.state.showModelManager || this.state.editorSaving) return;
    this.state.configuringModel = true;
    this.state.editorOpen = false;
    this.state.editorError = '';
    const currentId = this.state.currentModelId;
    if (this.state.models.length === 0) this.editModel('new');
    else if (currentId.length > 0) this.editModel(currentId);
    this.state.showModelManager = true;
  }

  private closeModelManager(): void {
    this.state.showModelManager = false;
    this.state.editorOpen = false;
    this.state.configuringModel = false;
  }

  private async useModelForSetup(modelId: string): Promise<void> {
    if (!this.controller || this.state.editorSaving) return;
    if (!this.controller.hasStoredKey(modelId)) {
      this.editModel(modelId);
      return;
    }
    this.state.editorSaving = true;
    this.state.editorError = '';
    try {
      await this.controller.chooseModel(modelId);
      this.closeModelManager();
    } catch (err) {
      this.state.editorError = err instanceof Error ? err.message : String(err);
    } finally {
      this.state.editorSaving = false;
    }
  }

  private editModel(modelId: string): void {
    this.state.editingModelId = modelId;
    this.state.editorOpen = true;
    this.state.editorError = '';
    this.state.remoteModelNames = [];
    this.state.editorHasKey = modelId.length > 0 && modelId !== 'new' && this.controller !== undefined && this.controller.hasStoredKey(modelId);
  }

  private async saveModel(input: LocalGenUIModelEditorInput): Promise<void> {
    if (!this.controller || this.state.editorSaving) return;
    this.state.editorSaving = true;
    this.state.editorError = '';
    try {
      const id = this.state.editingModelId === 'new' ? '' : this.state.editingModelId;
      const configuring = this.state.configuringModel;
      const saved = await this.controller.saveModel({ id, name: input.name, apiUrl: input.apiUrl,
        modelName: input.modelName, apiKey: input.apiKey });
      if (configuring) {
        if (id.length > 0) await this.controller.chooseModel(saved.id);
        this.closeModelManager();
      } else {
        this.state.editorOpen = false;
        this.notice(RemoteI18n.t('localGenui.saved'));
      }
    } catch (err) {
      this.state.editorError = err instanceof Error ? err.message : String(err);
    } finally {
      this.state.editorSaving = false;
    }
  }

  private async fetchRemoteModels(apiUrl: string, apiKey: string): Promise<void> {
    if (!this.controller || this.state.fetchingModels) return;
    this.state.fetchingModels = true;
    this.state.editorError = '';
    try {
      const editing = this.state.editingModelId === 'new' ? '' : this.state.editingModelId;
      const names = await this.controller.listRemoteModels(apiUrl, apiKey, editing);
      this.state.remoteModelNames = names;
      if (names.length === 0) this.state.editorError = RemoteI18n.t('localGenui.noRemoteModels');
    } catch (err) {
      this.state.editorError = err instanceof Error ? err.message : String(err);
    } finally {
      this.state.fetchingModels = false;
    }
  }

  /** Intents of the shared ConversationView. Unsupported ones are explicit. */
  private dispatch(intent: ConversationIntent): void {
    switch (intent.type) {
      case ConversationIntentType.ChatInputChanged:
        this.state.conversation.setChatInput(intent.value);
        return;
      case ConversationIntentType.Send:
        void this.send(this.state.conversation.chatInput, true);
        return;
      case ConversationIntentType.RetryMessage:
        void this.send(intent.value, false);
        return;
      case ConversationIntentType.Stop:
        if (this.controller) this.controller.cancel();
        return;
      case ConversationIntentType.SelectModel:
        void this.withController((c) => c.chooseModel(intent.value));
        return;
      case ConversationIntentType.ManageModels:
        this.actions.openModelManager();
        return;
      case ConversationIntentType.NewSession:
        void this.newSession();
        return;
      case ConversationIntentType.Back:
        this.back();
        return;
      case ConversationIntentType.Delete:
        if (this.state.sessionId.length > 0) this.actions.deleteSession(this.state.sessionId);
        return;
      case ConversationIntentType.RenameSession:
        void this.withController((c) => c.renameSession(this.state.sessionId, intent.value));
        return;
      case ConversationIntentType.CopyMessage:
        void this.copy(intent.value, intent.copyScope);
        return;
      case ConversationIntentType.OpenFilePreview: {
        const reference = intent.filePreviewRequest ? intent.filePreviewRequest.reference : '';
        const appId = LocalGenUIConversationProjection.appIdFromLink(reference);
        if (appId.length > 0) {
          this.actions.openApp(appId);
        } else {
          this.notice(RemoteI18n.t('localGenui.linkUnsupported'));
        }
        return;
      }
      default:
        return;
    }
  }

  private async copy(text: string, scope: MessageCopyScope): Promise<void> {
    if (text.trim().length === 0) return;
    try {
      if (scope === MessageCopyScope.Rich) {
        await this.clipboard.copyRich(text, MarkdownHtmlSerializer.toHtml(text));
      } else {
        await this.clipboard.writeText(text);
      }
      this.notice(RemoteI18n.t('status.messageCopied'));
    } catch (err) {
      this.notice(err instanceof Error ? err.message : String(err));
    }
  }

  private syncTimeline(): void {
    const snapshot: ChatTimelineState = this.timeline.snapshotState();
    this.state.conversation.setTimelineProjection(
      snapshot.persistedMessages,
      snapshot.optimisticMessages,
      snapshot.activeTurn || RemoteUiState.emptyActiveTurn(),
      false,
      this.timeline.viewState(false)
    );
  }

  /** Follow-up turns in a session refine its latest app. */
  private async send(text: string, fromDraft: boolean): Promise<void> {
    const prompt = text.trim();
    if (prompt.length === 0 || this.state.conversation.isBusy) return;
    const sessionId = this.state.sessionId;
    const submission = fromDraft ? this.state.conversation.prepareComposerSubmission(sessionId, text, []) : undefined;
    const isCurrent = (): boolean => this.state.visible && this.state.view === 'chat' && this.state.sessionId === sessionId;
    await this.withController(async (c) => {
      if (!isCurrent()) return;
      await c.send(prompt, LocalGenUIConversationProjection.latestAppId(this.messages), '', '', {
        isCurrent,
        onAccepted: (): void => { submission?.commit(); },
        onModelRequired: (): void => this.openModelSetup()
      });
    });
  }

  private async withController(work: (controller: LocalGenUISessionController) => Promise<void>): Promise<void> {
    try {
      await this.ensureController();
      if (this.controller) await work(this.controller);
    } catch (err) {
      this.notice(err instanceof Error ? err.message : String(err));
    }
  }

  private async ensureController(): Promise<void> {
    if (this.controller) return;
    if (!this.initializing) {
      this.initializing = this.createController();
    }
    try {
      await this.initializing;
    } catch (err) {
      this.initializing = undefined;
      throw err instanceof Error ? err : new Error(String(err));
    }
  }

  private async createController(): Promise<void> {
    this.state.loading = true;
    try {
      const context = this.context();
      const contract = await LocalGenUIContractLoader.load(context);
      const repository = new LocalGenUIRepository();
      await repository.init(context);
      const legacy = new GeneralChatConfigStore();
      await legacy.init(context);
      const models = new LocalGenUIModelStore();
      await models.init(context, legacy);
      const provider = new HttpLocalGenUIModelProvider(models, this.transport());
      const thumbnails = new LocalGenUIThumbnailStore(context.filesDir);
      const desktopCards = new LocalGenUIDesktopCardStore(context.filesDir);
      const icons = new LocalGenUIIcon3DStore(context.filesDir);
      const photos = new LocalGenUIImageSearch(context.filesDir);
      const assets = new LocalGenUICollaborationAssets(context.filesDir);
      this.bridge.setPictureSource(async (url: string): Promise<ArrayBuffer | undefined> => {
        if (url.startsWith(LOCAL_GENUI_PHOTO_ROOT)) return photos.picture(url);
        if (!url.startsWith(LOCAL_GENUI_COLLABORATION_ROOT)) return icons.picture(url);
        const mount = this.bridge.currentMount();
        if (!mount) return undefined;
        const bytes = await assets.picture(mount.identity.appId, url);
        return this.bridge.currentMount()?.identity.appId === mount.identity.appId ? bytes : undefined;
      });
      const collaboration = new LocalGenUICollaborationHost({
        owner: (): LocalCollaborationOwner => {
          const mount = this.bridge.currentMount();
          return { appId: mount?.identity.appId || '', sourceRevision: mount?.sourceRevision || 0,
            live: !!mount && mount.mode === 'live' && !mount.streaming };
        },
        unavailable: (): string => HarmonyCollaborationService.environment().unavailable,
        changed: (request: LocalCollaborationRequest | undefined): void => {
          this.state.collaborationRequest = request;
          this.state.showCollaboration = request !== undefined;
        },
        send: (reply: LocalCollaborationReply): void => this.bridge.sendCollaboration(reply),
        save: (appId: string, data: ArrayBuffer): Promise<string> => assets.save(appId, data),
        discard: (appId: string, asset: string): Promise<void> => assets.discard(appId, asset)
      });
      this.collaboration = collaboration;
      const devices = new LocalGenUIDeviceCapabilityHost(context, {
        gesture: (subscriptionId: string, gesture: string): void => this.bridge.sendCapabilityEvent(subscriptionId, gesture),
        status: (subscriptionId: string, status: string): void => this.bridge.sendCapabilityStatus(subscriptionId, status),
        cameraWanted: (wanted: boolean): void => { this.state.cameraWanted = wanted; },
        cameraActive: (active: boolean): void => { this.state.cameraActive = active; }
      });
      const calendar = new HarmonyCalendarService((): Context => context);
      this.devices = devices;
      this.syncDeviceVisibility();
      this.controller = new LocalGenUISessionController(repository, provider, contract, this.bridge, this, this, models, thumbnails, devices, desktopCards, calendar, collaboration, photos);
      if (this.backgroundKeepAlive) {
        this.controller.setBackgroundKeepAlive(this.backgroundKeepAlive);
      }
      await this.controller.refreshModels();
      RemoteLogger.info(`local genui ready renderer=${contract.manifest.rendererRevision} models=${models.list().length}`);
    } finally {
      this.state.loading = false;
    }
  }
}
