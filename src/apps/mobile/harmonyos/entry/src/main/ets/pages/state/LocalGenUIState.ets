import { LocalCollaborationRequest } from '../../services/local-genui/LocalGenUICollaborationHost';
import { LocalCollaborationSnapshot } from '../../services/local-genui/LocalCollaborationSession';
import { LocalGenUIGalleryEntry, LocalGenUISession } from '../../services/local-genui/LocalGenUIModels';
import { Want } from '@kit.AbilityKit';
import { formBindingData } from '@kit.FormKit';
import { LocalGenUIDesktopCards } from '../../services/local-genui/LocalGenUIDesktopCards';
import { LocalGenUIModelProfile } from '../../services/local-genui/LocalGenUIModelCatalog';
import { ConversationCoreState } from './ConversationCoreState';
import { ConversationIntent } from '../actions/ConversationIntent';

/** Presentation projection of Local GenUI sessions, conversations and apps. */
@ObservedV2
export class LocalGenUIState {
  @Trace visible: boolean = false;
  /** Opened from the MiniApp gallery: the app alone, without the conversation. */
  @Trace standalone: boolean = false;
  /** The conversation pane is the shared ConversationView over this core. */
  @Trace conversation: ConversationCoreState = new ConversationCoreState('chat');
  @Trace loading: boolean = false;
  @Trace error: string = '';
  @Trace notice: string = '';
  @Trace localSessions: LocalGenUISession[] = [];
  @Trace sessionId: string = '';
  @Trace view: 'sessions' | 'chat' | 'app' = 'sessions';
  @Trace appId: string = '';
  @Trace appTitle: string = '';
  @Trace appStatus: string = '';
  @Trace appDetail: string = '';
  @Trace appUnverified: string[] = [];
  @Trace appStreaming: boolean = false;
  // Models
  @Trace models: LocalGenUIModelProfile[] = [];
  @Trace currentModelId: string = '';
  @Trace modelMissing: boolean = false;
  @Trace showModelManager: boolean = false;
  /** '' = list, 'new' = add form, otherwise the edited model id. */
  @Trace editingModelId: string = '';
  @Trace editorOpen: boolean = false;
  @Trace editorSaving: boolean = false;
  @Trace editorError: string = '';
  @Trace editorHasKey: boolean = false;
  @Trace remoteModelNames: string[] = [];
  @Trace fetchingModels: boolean = false;
  /** An app on screen holds a gesture subscription: show the camera preview. */
  @Trace showCollaboration: boolean = false;
  @Trace collaborationRequest: LocalCollaborationRequest | undefined = undefined;
  @Trace cameraWanted: boolean = false;
  // Gallery
  @Trace gallery: LocalGenUIGalleryEntry[] = [];
  /** Bundle of this app; empty until the context is known, which hides "Add to desktop". */
  @Trace bundleName: string = '';

  currentModelName(): string {
    const model = this.models.find((item: LocalGenUIModelProfile) => item.id === this.currentModelId);
    if (!model) return '';
    return model.name.trim().length > 0 ? model.name.trim() : model.modelName;
  }

  canAddToDesktop(appId: string): boolean {
    return this.bundleName.length > 0 && LocalGenUIDesktopCards.isAppId(appId);
  }

  /** Want of `AddFormMenuItem` for the app's home-screen card. */
  desktopCardWant(appId: string): Want {
    return LocalGenUIDesktopCards.addWant(this.bundleName, appId);
  }

  /**
   * First content of the new card. It carries the app id itself, so the card
   * opens its app even before the card host or the add callback binds it.
   */
  desktopCardInitialData(appId: string, title: string): formBindingData.FormBindingData {
    const data: Record<string, Object> = {};
    data['appId'] = appId;
    data['state'] = title.length > 0 ? 'ready' : 'pending';
    data['title'] = title;
    data['initial'] = LocalGenUIDesktopCards.initial(title);
    data['imageName'] = '';
    return formBindingData.createFormBindingData(data);
  }

  inGallery(appId: string): boolean {
    return this.gallery.some((entry: LocalGenUIGalleryEntry) => entry.appId === appId);
  }
}

export interface LocalGenUIModelEditorInput {
  name: string;
  apiUrl: string;
  modelName: string;
  apiKey: string;
}

export interface LocalGenUIActions {
  open: () => void;
  close: () => void;
  back: () => boolean;
  newSession: () => void;
  openSession: (sessionId: string) => void;
  deleteSession: (sessionId: string) => void;
  openApp: (appId: string) => void;
  showSessions: () => void;
  showChat: () => void;
  /** Intents from the shared ConversationView. */
  conversation: (intent: ConversationIntent) => void;
  // Models
  openModelManager: () => void;
  closeModelManager: () => void;
  editModel: (modelId: string) => void;
  closeEditor: () => void;
  saveModel: (input: LocalGenUIModelEditorInput) => void;
  removeModel: (modelId: string) => void;
  fetchRemoteModels: (apiUrl: string, apiKey: string) => void;
  // Gallery
  addToGallery: (appId: string) => void;
  removeFromGallery: (appId: string) => void;
  openGalleryApp: (appId: string) => void;
  // Desktop cards
  /** The add menu is about to show: make sure the card has content to show. */
  prepareDesktopCard: (appId: string) => void;
  /** Result of `AddFormMenuItem`; `error` is empty on success. */
  desktopCardAdded: (appId: string, formId: string, error: string) => void;
  // Device capabilities (presentation facts from the surface)
  appOnScreen: (onScreen: boolean) => void;
  cameraSurface: (surfaceId: string) => void;
  cameraSurfaceGone: () => void;
  collaborationClose: (token: number) => void;
  collaborationResult: (token: number, result: LocalCollaborationSnapshot) => void;
  collaborationReceive: (token: number, data: ArrayBuffer) => Promise<void>;
}

export function emptyLocalGenUIActions(): LocalGenUIActions {
  return {
    open: () => {},
    close: () => {},
    back: (): boolean => false,
    newSession: () => {},
    openSession: (_sessionId: string) => {},
    deleteSession: (_sessionId: string) => {},
    openApp: (_appId: string) => {},
    showSessions: () => {},
    showChat: () => {},
    conversation: (_intent: ConversationIntent) => {},
    openModelManager: () => {},
    closeModelManager: () => {},
    editModel: (_modelId: string) => {},
    closeEditor: () => {},
    saveModel: (_input: LocalGenUIModelEditorInput) => {},
    removeModel: (_modelId: string) => {},
    fetchRemoteModels: (_apiUrl: string, _apiKey: string) => {},
    addToGallery: (_appId: string) => {},
    removeFromGallery: (_appId: string) => {},
    openGalleryApp: (_appId: string) => {},
    prepareDesktopCard: (_appId: string) => {},
    desktopCardAdded: (_appId: string, _formId: string, _error: string) => {},
    appOnScreen: (_onScreen: boolean) => {},
    cameraSurface: (_surfaceId: string) => {},
    collaborationClose: (_token: number) => {},
    collaborationResult: (_token: number, _result: LocalCollaborationSnapshot) => {},
    collaborationReceive: async (_token: number, _data: ArrayBuffer): Promise<void> => { throw new Error('collaboration unavailable'); },
    cameraSurfaceGone: () => {}
  };
}
