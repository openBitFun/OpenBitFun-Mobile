import {
  LocalGenUIEvent,
  LocalGenUIEventType,
  LocalGenUIIdentity
} from './LocalGenUIModels';
import {
  assembleLocalGeneration,
  extractClosedStringField,
  GenerativeUIArgumentAccumulator,
  LocalGenUIGeneration
} from './LocalGenUIStreamParser';
import { LocalProviderFrame, LocalProviderFrameKind } from './LocalProviderSseParser';

/** Stable failure code for a provider stop caused by the output budget. */
export const LOCAL_GENUI_TRUNCATED: string = 'output_truncated';

/** The owner binds identity; the provider never supplies it. */
export interface LocalGenUIIdentityBinder {
  bind: (toolCallId: string, title: string) => LocalGenUIIdentity;
}

interface PendingToolCall {
  id: string;
  name: string;
  accumulator: GenerativeUIArgumentAccumulator;
}

export interface LocalGenUITurnResult {
  events: LocalGenUIEvent[];
  identity?: LocalGenUIIdentity;
  generation?: LocalGenUIGeneration;
  assistantText: string;
  stopReason: string;
  warnings: string[];
}

/**
 * Normalizes provider frames into the Local GenUI event order:
 * turn.started, [genui.started], (genui.source.delta | message.delta)*, terminal.
 */
export class LocalGenUITurnNormalizer {
  private readonly turnId: string;
  private readonly toolName: string;
  private readonly binder: LocalGenUIIdentityBinder;
  private readonly calls: Map<number, PendingToolCall> = new Map<number, PendingToolCall>();
  private boundIndex: number = -1;
  private identity?: LocalGenUIIdentity;
  private seq: number = 0;
  private assistantText: string = '';
  private stopReason: string = '';
  private providerError: string = '';
  private readonly warnings: string[] = [];

  constructor(turnId: string, toolName: string, binder: LocalGenUIIdentityBinder) {
    this.turnId = turnId;
    this.toolName = toolName;
    this.binder = binder;
  }

  started(): LocalGenUIEvent {
    return { type: LocalGenUIEventType.TurnStarted, turnId: this.turnId };
  }

  accept(frames: LocalProviderFrame[]): LocalGenUIEvent[] {
    const events: LocalGenUIEvent[] = [];
    frames.forEach((item: LocalProviderFrame) => {
      if (item.kind === LocalProviderFrameKind.Text) {
        this.assistantText += item.text;
        events.push({ type: LocalGenUIEventType.MessageDelta, turnId: this.turnId, text: item.text });
      } else if (item.kind === LocalProviderFrameKind.Tool) {
        this.acceptTool(item, events);
      } else if (item.kind === LocalProviderFrameKind.Stop) {
        this.stopReason = item.stopReason;
      } else if (item.kind === LocalProviderFrameKind.Error) {
        this.providerError = item.text;
      }
    });
    return events;
  }

  /** Terminal step. Text-only turns complete without a generation. */
  finish(ownerFields: string[]): LocalGenUITurnResult {
    const events: LocalGenUIEvent[] = [];
    let generation: LocalGenUIGeneration | undefined = undefined;
    if (this.providerError.length > 0) {
      events.push({ type: LocalGenUIEventType.TurnFailed, turnId: this.turnId, error: this.providerError });
    } else {
      const bound = this.boundIndex >= 0 ? this.calls.get(this.boundIndex) : undefined;
      if (bound) {
        // Repair only after a normal tool-use completion, never after truncation.
        const normal = ['tool_calls', 'tool_use', 'stop', 'end_turn'].indexOf(this.stopReason) >= 0;
        generation = assembleLocalGeneration(bound.accumulator.rawArguments(), ownerFields, normal);
      }
      const truncated = this.stopReason === 'length' || this.stopReason === 'max_tokens';
      if (generation && !generation.ok && truncated) {
        events.push({ type: LocalGenUIEventType.TurnFailed, turnId: this.turnId, error: LOCAL_GENUI_TRUNCATED });
      } else if (generation && !generation.ok) {
        events.push({ type: LocalGenUIEventType.TurnFailed, turnId: this.turnId, error: generation.error });
      } else if (!bound && this.assistantText.trim().length === 0) {
        events.push({ type: LocalGenUIEventType.TurnFailed, turnId: this.turnId, error: 'the model returned an empty response' });
      } else {
        events.push({ type: LocalGenUIEventType.TurnCompleted, turnId: this.turnId });
      }
    }
    return {
      events,
      identity: this.identity,
      generation,
      assistantText: this.assistantText,
      stopReason: this.stopReason,
      warnings: this.warnings.slice()
    };
  }

  private acceptTool(item: LocalProviderFrame, events: LocalGenUIEvent[]): void {
    let call = this.calls.get(item.index);
    if (!call || (item.toolCallId.length > 0 && call.id.length > 0 && call.id !== item.toolCallId)) {
      call = { id: item.toolCallId, name: item.toolName, accumulator: new GenerativeUIArgumentAccumulator() };
      this.calls.set(item.index, call);
    }
    if (call.id.length === 0 && item.toolCallId.length > 0) {
      call.id = item.toolCallId;
    }
    if (call.name.length === 0 && item.toolName.length > 0) {
      call.name = item.toolName;
    }
    if (call.name !== this.toolName) {
      if (call.name.length > 0 && item.arguments.length === 0) {
        this.warnings.push(`ignored unsupported local tool ${call.name}`);
      }
      return;
    }
    if (this.boundIndex >= 0 && this.boundIndex !== item.index) {
      if (item.arguments.length === 0) {
        this.warnings.push('ignored a second GenerativeUI call in the same turn');
      }
      return;
    }
    this.boundIndex = item.index;
    const chunk = call.accumulator.apply(item.arguments, false);
    if (!chunk) {
      return;
    }
    if (!this.identity) {
      const toolCallId = call.id.length > 0 ? call.id : `${this.turnId}:tool`;
      this.identity = this.binder.bind(toolCallId, extractClosedStringField(call.accumulator.rawArguments(), 'title'));
      events.push({ type: LocalGenUIEventType.GenUIStarted, turnId: this.turnId, identity: this.identity });
    }
    if (chunk.reset) {
      this.seq = 0;
    }
    events.push({
      type: LocalGenUIEventType.GenUISourceDelta,
      turnId: this.turnId,
      delta: { appId: this.identity.appId, seq: this.seq, reset: chunk.reset, text: chunk.text }
    });
    this.seq += 1;
  }
}
