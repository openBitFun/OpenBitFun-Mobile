import { LocalCollaborationRequest } from '../../services/local-genui/LocalGenUICollaborationHost';
import { LocalCollaborationSnapshot } from '../../services/local-genui/LocalCollaborationSession';
import { LocalGenUIGalleryEntry, LocalGenUISession } from '../../services/local-genui/LocalGenUIModels';
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
  @Trace configuringModel: boolean = false;
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
  @Trace cameraActive: boolean = false;
  // Gallery
  @Trace gallery: LocalGenUIGalleryEntry[] = [];

  currentModelName(): string {
    const model = this.models.find((item: LocalGenUIModelProfile) => item.id === this.currentModelId);
    if (!model) return '';
    return model.name.trim().length > 0 ? model.name.trim() : model.modelName;
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
  useModel: (modelId: string) => void;
  closeEditor: () => void;
  saveModel: (input: LocalGenUIModelEditorInput) => void;
  removeModel: (modelId: string) => void;
  fetchRemoteModels: (apiUrl: string, apiKey: string) => void;
  // Gallery
  addToGallery: (appId: string) => void;
  removeFromGallery: (appId: string) => void;
  openGalleryApp: (appId: string) => void;
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
    useModel: (_modelId: string) => {},
    closeEditor: () => {},
    saveModel: (_input: LocalGenUIModelEditorInput) => {},
    removeModel: (_modelId: string) => {},
    fetchRemoteModels: (_apiUrl: string, _apiKey: string) => {},
    addToGallery: (_appId: string) => {},
    removeFromGallery: (_appId: string) => {},
    openGalleryApp: (_appId: string) => {},
    appOnScreen: (_onScreen: boolean) => {},
    cameraSurface: (_surfaceId: string) => {},
    collaborationClose: (_token: number) => {},
    collaborationResult: (_token: number, _result: LocalCollaborationSnapshot) => {},
    collaborationReceive: async (_token: number, _data: ArrayBuffer): Promise<void> => { throw new Error('collaboration unavailable'); },
    cameraSurfaceGone: () => {}
  };
}
