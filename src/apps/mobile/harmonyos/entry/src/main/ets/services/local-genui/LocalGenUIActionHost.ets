import { LocalGenUIIds } from './LocalGenUIModels';
import { LocalRuntimeInbound } from './LocalGenUIRuntimeProtocol';

/**
 * Capability registry for messages coming out of the Local GenUI runtime.
 * The document never selects an execution target: the mounted app identity
 * comes from the host, and only registered capabilities run.
 */
export interface LocalGenUICapabilityHandlers {
  saveState: (appId: string, sourceRevision: number, baseStateRevision: number, stateJson: string) => Promise<void>;
  modelTurn: (appId: string, message: string) => Promise<void>;
  isTurnActive: () => boolean;
  unsupported: (appId: string, capability: string, reason: string) => void;
  /** Device capabilities; return '' when accepted or a refusal reason. */
  subscribeGesture: (appId: string, subscriptionId: string, gesture: string) => string;
  unsubscribeGesture: (subscriptionId: string) => void;
  haptic: (kind: string) => void;
  /** Calendar actions; return '' when accepted or a refusal reason. */
  calendar: (appId: string, action: string, params: Object) => Promise<string>;
  collaboration?: (message: LocalRuntimeInbound) => string;
}

interface LocalCapabilityPolicy {
  maxPayloadChars: number;
  perMinute: number;
}

const STATE_SAVE: string = 'state.save';
const MODEL_TURN: string = 'model.turn';
const DEVICE_GESTURE: string = 'device.gesture';
const DEVICE_HAPTIC: string = 'device.haptic';
const CALENDAR_ACTIONS: string[] = [
  'CreateCalendarEvent',
  'UpdateCalendarEvent',
  'DeleteCalendarEvent',
  'ListCalendarEvents'
];
const CALENDAR: string = 'calendar.event';

export class LocalGenUIActionHost {
  private readonly handlers: LocalGenUICapabilityHandlers;
  private readonly policies: Map<string, LocalCapabilityPolicy> = new Map<string, LocalCapabilityPolicy>();
  private readonly usage: Map<string, number[]> = new Map<string, number[]>();
  private readonly now: () => number;

  constructor(handlers: LocalGenUICapabilityHandlers, now: () => number = () => Date.now()) {
    this.handlers = handlers;
    this.now = now;
    this.policies.set(STATE_SAVE, { maxPayloadChars: 256 * 1024, perMinute: 240 });
    this.policies.set(MODEL_TURN, { maxPayloadChars: 2000, perMinute: 6 });
    this.policies.set(DEVICE_GESTURE, { maxPayloadChars: 64, perMinute: 30 });
    this.policies.set(DEVICE_HAPTIC, { maxPayloadChars: 16, perMinute: 120 });
    this.policies.set(CALENDAR, { maxPayloadChars: 16000, perMinute: 30 });
    this.policies.set('device.collaboration', { maxPayloadChars: 1024, perMinute: 30 });
  }

  /** Returns a short diagnostic when the message was refused. */
  async handle(message: LocalRuntimeInbound, mountedAppId: string, mountedSourceRevision: number): Promise<string> {
    const appId = message.appId || '';
    if (!LocalGenUIIds.isLocal(appId) || appId !== mountedAppId) {
      return 'message for an app that is not mounted';
    }
    if (message.type === 'state') {
      const stateJson = JSON.stringify(message.state === undefined ? {} : message.state);
      const refused = this.admit(appId, STATE_SAVE, stateJson.length);
      if (refused.length > 0) {
        return refused;
      }
      if (message.sourceRevision !== mountedSourceRevision || typeof message.baseStateRevision !== 'number') {
        return 'state update for another source revision';
      }
      await this.handlers.saveState(appId, mountedSourceRevision, message.baseStateRevision, stateJson);
      return '';
    }
    if (message.type === 'collaboration') {
      if (message.sourceRevision !== mountedSourceRevision) return 'collaboration for another source revision';
      if (!this.handlers.collaboration) return 'collaboration is unavailable';
      if (message.op === 'cancel') return this.handlers.collaboration(message);
      const refused = this.admit(appId, 'device.collaboration', JSON.stringify(message).length);
      return refused || this.handlers.collaboration(message);
    }
    if (message.type === 'action') {
      if (message.action === 'continue_conversation') {
        const text = (message.message || '').trim();
        if (text.length === 0) {
          return 'empty model action';
        }
        const refused = this.admit(appId, MODEL_TURN, text.length);
        if (refused.length > 0) {
          this.handlers.unsupported(appId, MODEL_TURN, refused);
          return refused;
        }
        if (this.handlers.isTurnActive()) {
          this.handlers.unsupported(appId, MODEL_TURN, 'a local turn is already running');
          return 'a local turn is already running';
        }
        await this.handlers.modelTurn(appId, text);
        return '';
      }
      if (message.sourceRevision !== mountedSourceRevision) return 'action for another source revision';
      if (CALENDAR_ACTIONS.indexOf(message.action || '') >= 0) {
        const params: Object = message.params || (JSON.parse('{}') as Object);
        const refused = this.admit(appId, CALENDAR, JSON.stringify(params).length);
        if (refused.length > 0) {
          this.handlers.unsupported(appId, message.action || CALENDAR, refused);
          return refused;
        }
        const result = await this.handlers.calendar(appId, message.action || '', params);
        if (result.length > 0) {
          this.handlers.unsupported(appId, message.action || CALENDAR, result);
        }
        return result;
      }
      const name = message.action || 'unknown';
      this.handlers.unsupported(appId, name, 'not a local phase 1 capability');
      return `unsupported action ${name}`;
    }
    if (message.type === 'capability') {
      const subscriptionId = message.subscriptionId || '';
      if (subscriptionId.length === 0 || subscriptionId.length > 64) {
        return 'invalid capability subscription';
      }
      if (message.op === 'unsubscribe') {
        this.handlers.unsubscribeGesture(subscriptionId);
        return '';
      }
      const gesture = message.gesture || '';
      const refused = this.admit(appId, DEVICE_GESTURE, gesture.length);
      return refused.length > 0 ? refused : this.handlers.subscribeGesture(appId, subscriptionId, gesture);
    }
    if (message.type === 'haptic') {
      const kind = message.kind || '';
      const refused = this.admit(appId, DEVICE_HAPTIC, kind.length);
      if (refused.length === 0) {
        this.handlers.haptic(kind);
      }
      return refused;
    }
    if (message.type === 'query') {
      const name = message.capability || 'query';
      this.handlers.unsupported(appId, name, 'not a local phase 1 capability');
      return `unsupported query ${name}`;
    }
    return '';
  }

  private admit(appId: string, capability: string, payloadChars: number): string {
    const policy = this.policies.get(capability);
    if (!policy) {
      return `capability ${capability} is not registered`;
    }
    if (payloadChars > policy.maxPayloadChars) {
      return `${capability} payload exceeds ${policy.maxPayloadChars} characters`;
    }
    const key = `${appId}|${capability}`;
    const now = this.now();
    const recent = (this.usage.get(key) || []).filter((at: number) => now - at < 60000);
    if (recent.length >= policy.perMinute) {
      this.usage.set(key, recent);
      return `${capability} quota of ${policy.perMinute} per minute reached`;
    }
    recent.push(now);
    this.usage.set(key, recent);
    return '';
  }
}
