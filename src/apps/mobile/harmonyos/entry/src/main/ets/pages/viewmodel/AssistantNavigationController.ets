import { AssistantEntry, RemoteSession, SessionListResult } from '../../model/RemoteModels';
import { ConnectionErrorPolicy } from '../../services/ConnectionErrorPolicy';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { RemotePageState } from '../state/RemotePageState';

export interface AssistantNavigationHooks {
  reportError: (message: string) => void;
  loadAssistants: () => Promise<AssistantEntry[]>;
  loadSessions: (assistant: AssistantEntry) => Promise<SessionListResult>;
  publishSessions: (assistant: AssistantEntry, result: SessionListResult) => void;
  openSession: (session: RemoteSession) => Promise<void>;
  createSession: (assistant: AssistantEntry | undefined) => Promise<void>;
}

/** Resolves remote assistant history before deciding whether creation is needed. */
export class AssistantNavigationController {
  private pending: boolean = false;
  private readonly state: RemotePageState;
  private readonly hooks: AssistantNavigationHooks;

  constructor(state: RemotePageState, hooks: AssistantNavigationHooks) {
    this.state = state;
    this.hooks = hooks;
  }

  async open(forceNew: boolean = false): Promise<void> {
    if (this.pending || this.state.isBusy || this.state.connectionState !== 'connected') return;
    const deviceId = this.state.controlTargetDeviceId;
    const current = (): boolean => this.state.controlTargetDeviceId === deviceId &&
      this.state.connectionState === 'connected';
    this.pending = true;
    this.state.setError('');
    this.state.setBusy(true);
    this.state.setStatusText(RemoteI18n.t('status.loadingAssistants'));
    try {
      const assistants = await this.hooks.loadAssistants();
      if (!current()) return;
      this.state.setAssistants(assistants);
      if (!forceNew) {
        // A failed listing must never be mistaken for an empty assistant.
        for (const assistant of assistants) {
          const result = await this.hooks.loadSessions(assistant);
          if (!current()) return;
          this.hooks.publishSessions(assistant, result);
        }
        const rows = this.state.assistantSidebarSessions();
        const selected = rows.find((row: RemoteSession): boolean => row.id === this.state.activeSession.sessionId) || rows[0];
        if (selected) {
          this.state.setBusy(false);
          await this.hooks.openSession(selected);
          return;
        }
      }
      const selectedAssistant = assistants.find((assistant: AssistantEntry): boolean =>
        assistant.workspace_id ? assistant.workspace_id === this.state.activeSession.workspaceId :
          assistant.path === this.state.activeSession.workspacePath) || assistants[0];
      this.state.setBusy(false);
      await this.hooks.createSession(selectedAssistant);
    } catch (error) {
      if (current()) {
        const message = ConnectionErrorPolicy.errorText(error);
        this.state.setError(message);
        this.hooks.reportError(message);
      }
    } finally {
      this.pending = false;
      if (current()) this.state.setBusy(false);
    }
  }
}
