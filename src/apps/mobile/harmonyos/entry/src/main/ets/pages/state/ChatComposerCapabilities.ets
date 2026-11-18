import { ChatSurface } from './ChatSurface';

export class ChatComposerCapabilities {
  readonly surface: ChatSurface;
  readonly supportsAttachments: boolean;
  readonly requiresRemoteConnection: boolean;
  readonly showAddButton: boolean;
  readonly showVoiceInput: boolean;
  // Whether a message typed while a turn is still running can be handed over
  // right away. The desktop relay queues it server-side and lets the current
  // turn yield to it, so on that surface the draft outranks the stop button.
  // Where nothing queues, holding the draft back is the honest behaviour.
  readonly supportsMidRunSend: boolean;
  // The surface owns its model profiles and offers a "manage models" entry in
  // the composer's model selector (Local GenUI). Host-owned catalogs do not.
  readonly supportsModelManagement: boolean;

  constructor(
    surface: ChatSurface,
    supportsAttachments: boolean,
    requiresRemoteConnection: boolean,
    showAddButton: boolean = true,
    showVoiceInput: boolean = true,
    supportsMidRunSend: boolean = false,
    supportsModelManagement: boolean = false
  ) {
    this.surface = surface;
    this.supportsAttachments = supportsAttachments;
    this.requiresRemoteConnection = requiresRemoteConnection;
    this.showAddButton = showAddButton;
    this.showVoiceInput = showVoiceInput;
    this.supportsMidRunSend = supportsMidRunSend;
    this.supportsModelManagement = supportsModelManagement;
  }
}

export const GENERAL_CHAT_COMPOSER_CAPABILITIES: ChatComposerCapabilities =
  new ChatComposerCapabilities(ChatSurface.General, true, false);

export const REMOTE_CHAT_COMPOSER_CAPABILITIES: ChatComposerCapabilities =
  new ChatComposerCapabilities(ChatSurface.Remote, true, true, true, true, true);

/** Local GenUI: phone-owned models, no attachments, voice or remote connection. */
export const LOCAL_GENUI_COMPOSER_CAPABILITIES: ChatComposerCapabilities =
  new ChatComposerCapabilities(ChatSurface.Local, false, false, false, false, false, true);
