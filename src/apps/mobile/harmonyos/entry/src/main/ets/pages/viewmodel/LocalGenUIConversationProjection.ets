import { ChatMessage, RemoteModelCatalog, RemoteModelConfig, SessionSummary } from '../../model/RemoteModels';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { LocalGenUIMessage, LocalGenUISession } from '../../services/local-genui/LocalGenUIModels';
import { LocalGenUIModelProfile } from '../../services/local-genui/LocalGenUIModelCatalog';

/** Link scheme the shared timeline renders for a generated app. */
export const LOCAL_GENUI_APP_LINK: string = 'openbitfun-genui://app/';
const ACTIVE_TURN_ID: string = 'local-genui-active-turn';

/**
 * Projects Local GenUI records onto the shapes the shared ConversationView
 * already renders, so the local conversation reuses the remote timeline,
 * composer and model selector instead of a parallel UI.
 */
export class LocalGenUIConversationProjection {
  static session(session: LocalGenUISession): SessionSummary {
    return { sessionId: session.id, title: session.title, workspacePath: '', agentType: 'chat' };
  }

  static messages(messages: LocalGenUIMessage[], thumbnailFor: (appId: string) => string): ChatMessage[] {
    return messages.map((message: LocalGenUIMessage): ChatMessage => {
      const text = message.text.trim();
      const failed = message.error.length > 0;
      const projected: ChatMessage = {
        id: message.id,
        role: message.role,
        text,
        // The shared bubble draws its own failure block from `error`.
        status: failed ? 'failed' : 'completed',
        error: failed ? message.error : undefined,
        turnId: message.id,
        timestamp: message.createdAt,
        items: message.role === 'assistant' && text.length > 0 ? [{ type: 'text', content: text }] : undefined
      };
      if (message.appId.length > 0) {
        projected.appCard = {
          appId: message.appId,
          title: message.appTitle,
          status: message.status.length > 0 ? RemoteI18n.t(`localGenui.status.${message.status}`) : '',
          thumbnailPath: thumbnailFor(message.appId),
          link: `${LOCAL_GENUI_APP_LINK}${message.appId}`
        };
      }
      return projected;
    });
  }

  static activeTurn(text: string): ChatMessage {
    return {
      id: ACTIVE_TURN_ID,
      role: 'assistant',
      text,
      status: 'active',
      turnId: ACTIVE_TURN_ID,
      items: text.length > 0 ? [{ type: 'text', content: text }] : []
    };
  }

  /** Phone-owned model profiles as the composer's model catalog. */
  static catalog(models: LocalGenUIModelProfile[], selectedId: string): RemoteModelCatalog {
    return {
      version: 1,
      models: models.map((model: LocalGenUIModelProfile): RemoteModelConfig => ({
        id: model.id,
        name: model.name.trim().length > 0 ? model.name.trim() : model.modelName,
        provider: 'local',
        base_url: model.apiUrl,
        model_name: model.modelName,
        enabled: true,
        capabilities: ['text_chat']
      })),
      // No primary/fast roles: the session pins a concrete model profile.
      default_models: {},
      session_model_id: selectedId.length > 0 ? selectedId : undefined
    };
  }

  static latestAppId(messages: LocalGenUIMessage[]): string {
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i].appId.length > 0) {
        return messages[i].appId;
      }
    }
    return '';
  }

  static appIdFromLink(reference: string): string {
    return reference.startsWith(LOCAL_GENUI_APP_LINK) ? reference.slice(LOCAL_GENUI_APP_LINK.length) : '';
  }
}
