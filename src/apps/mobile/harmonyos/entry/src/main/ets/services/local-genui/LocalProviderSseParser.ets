/**
 * Provider-specific SSE parsing for Local GenUI turns. Produces text deltas
 * and raw tool-call argument frames; GenerativeUI semantics live in
 * LocalGenUIStreamParser and the owner.
 */

export enum LocalProviderProtocol {
  Anthropic = 'anthropic',
  OpenAi = 'openai'
}

export enum LocalProviderFrameKind {
  Text = 'text',
  Tool = 'tool',
  Stop = 'stop',
  Error = 'error'
}

export interface LocalProviderFrame {
  kind: LocalProviderFrameKind;
  text: string;
  /** Provider stream index of the tool call. */
  index: number;
  toolCallId: string;
  toolName: string;
  arguments: string;
  stopReason: string;
}

interface OpenAiFunctionDelta {
  name?: string;
  arguments?: string;
}

interface OpenAiToolCallDelta {
  index?: number;
  id?: string;
  function?: OpenAiFunctionDelta;
}

interface OpenAiDelta {
  content?: string | null;
  tool_calls?: OpenAiToolCallDelta[];
}

interface OpenAiChoice {
  delta?: OpenAiDelta;
  finish_reason?: string | null;
}

interface OpenAiError {
  message?: string;
}

interface OpenAiEvent {
  choices?: OpenAiChoice[];
  error?: OpenAiError;
}

interface AnthropicContentBlock {
  type?: string;
  id?: string;
  name?: string;
}

interface AnthropicDelta {
  type?: string;
  text?: string;
  partial_json?: string;
  stop_reason?: string;
}

interface AnthropicError {
  message?: string;
}

interface AnthropicEvent {
  type?: string;
  index?: number;
  content_block?: AnthropicContentBlock;
  delta?: AnthropicDelta;
  error?: AnthropicError;
}

function frame(kind: LocalProviderFrameKind): LocalProviderFrame {
  return { kind, text: '', index: -1, toolCallId: '', toolName: '', arguments: '', stopReason: '' };
}

export class LocalProviderSseParser {
  private readonly protocol: LocalProviderProtocol;
  private buffer: string = '';

  constructor(protocol: LocalProviderProtocol) {
    this.protocol = protocol;
  }

  feed(chunk: string): LocalProviderFrame[] {
    const frames: LocalProviderFrame[] = [];
    if (chunk.length === 0) {
      return frames;
    }
    this.buffer = (this.buffer + chunk).replace(/\r\n/g, '\n');
    let separator = this.buffer.indexOf('\n\n');
    while (separator >= 0) {
      const event = this.buffer.slice(0, separator);
      this.buffer = this.buffer.slice(separator + 2);
      this.parseEvent(event, frames);
      separator = this.buffer.indexOf('\n\n');
    }
    return frames;
  }

  finish(): LocalProviderFrame[] {
    const frames: LocalProviderFrame[] = [];
    const remaining = this.buffer.trim();
    this.buffer = '';
    if (remaining.length > 0) {
      this.parseEvent(remaining, frames);
    }
    return frames;
  }

  private parseEvent(text: string, frames: LocalProviderFrame[]): void {
    let data = '';
    text.split('\n').forEach((line: string) => {
      if (line.startsWith('data:')) {
        const value = line.slice(5).trimStart();
        data += data.length > 0 ? `\n${value}` : value;
      }
    });
    if (data.length === 0 || data === '[DONE]') {
      return;
    }
    try {
      if (this.protocol === LocalProviderProtocol.OpenAi) {
        this.parseOpenAi(JSON.parse(data) as OpenAiEvent, frames);
      } else {
        this.parseAnthropic(JSON.parse(data) as AnthropicEvent, frames);
      }
    } catch (_err) {
      // Keepalive comments and partial provider metadata are not frames.
    }
  }

  private parseOpenAi(event: OpenAiEvent, frames: LocalProviderFrame[]): void {
    if (event.error) {
      const error = frame(LocalProviderFrameKind.Error);
      error.text = event.error.message || 'provider error';
      frames.push(error);
      return;
    }
    (event.choices || []).forEach((choice: OpenAiChoice) => {
      const delta = choice.delta;
      if (delta && typeof delta.content === 'string' && delta.content.length > 0) {
        const text = frame(LocalProviderFrameKind.Text);
        text.text = delta.content;
        frames.push(text);
      }
      (delta && delta.tool_calls ? delta.tool_calls : []).forEach((call: OpenAiToolCallDelta) => {
        const tool = frame(LocalProviderFrameKind.Tool);
        tool.index = typeof call.index === 'number' ? call.index : 0;
        tool.toolCallId = call.id || '';
        tool.toolName = call.function && call.function.name ? call.function.name : '';
        tool.arguments = call.function && call.function.arguments ? call.function.arguments : '';
        frames.push(tool);
      });
      if (choice.finish_reason) {
        const stop = frame(LocalProviderFrameKind.Stop);
        stop.stopReason = choice.finish_reason;
        frames.push(stop);
      }
    });
  }

  private parseAnthropic(event: AnthropicEvent, frames: LocalProviderFrame[]): void {
    if (event.type === 'error') {
      const error = frame(LocalProviderFrameKind.Error);
      error.text = event.error && event.error.message ? event.error.message : 'provider error';
      frames.push(error);
      return;
    }
    if (event.type === 'content_block_start' && event.content_block && event.content_block.type === 'tool_use') {
      const tool = frame(LocalProviderFrameKind.Tool);
      tool.index = event.index || 0;
      tool.toolCallId = event.content_block.id || '';
      tool.toolName = event.content_block.name || '';
      frames.push(tool);
      return;
    }
    if (event.type === 'content_block_delta' && event.delta) {
      if (event.delta.type === 'text_delta' && event.delta.text) {
        const text = frame(LocalProviderFrameKind.Text);
        text.text = event.delta.text;
        frames.push(text);
      } else if (event.delta.type === 'input_json_delta' && typeof event.delta.partial_json === 'string') {
        const tool = frame(LocalProviderFrameKind.Tool);
        tool.index = event.index || 0;
        tool.arguments = event.delta.partial_json;
        frames.push(tool);
      }
      return;
    }
    if (event.type === 'message_delta' && event.delta && event.delta.stop_reason) {
      const stop = frame(LocalProviderFrameKind.Stop);
      stop.stopReason = event.delta.stop_reason;
      frames.push(stop);
    }
  }
}
