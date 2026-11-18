import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { OhosError } from '../OhosError';
import { RemoteLogger } from '../RemoteLogger';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { LocalGenUIModelStore } from './LocalGenUIModelStore';
import { ModelProviderGeneralChatAdapter, ModelProviderProtocol } from '../general-chat/ModelProviderGeneralChatAdapter';
import { LocalProviderFrame, LocalProviderProtocol, LocalProviderSseParser } from './LocalProviderSseParser';

/** Transport diagnostics go to the log; the person sees a plain reason. */
function localTransportError(operation: string, err: Object): Error {
  if (err instanceof Error) {
    return err;
  }
  RemoteLogger.warn(`${operation} failed: ${OhosError.reason(err).slice(0, 400)}`);
  return new Error(RemoteI18n.t('localGenui.networkUnavailable'));
}

/**
 * Reasoning models count their reasoning toward the output budget; an app
 * source after a long reasoning phase does not fit in 8k tokens.
 */
export const LOCAL_GENUI_MAX_OUTPUT_TOKENS: number = 32768;

export interface LocalGenUIPromptMessage {
  role: string;
  content: string;
}

export interface LocalGenUITurnRequest {
  /** Model profile of the session; resolved to credentials on the phone. */
  modelId: string;
  system: string;
  toolSchemaJson: string;
  messages: LocalGenUIPromptMessage[];
}

/** Receives provider frames in order; the session controller normalizes them. */
export interface LocalGenUIFrameSink {
  onFrames(frames: LocalProviderFrame[]): void;
}

/**
 * Model access for Local GenUI. The same interface is implemented by the
 * direct HTTP adapter now and an on-device provider later.
 */
export interface LocalGenUIModelProvider {
  isConfigured(modelId: string): Promise<boolean>;
  /** OpenAI-compatible model discovery for the model editor; [] when unsupported. */
  listRemoteModels(apiUrl: string, apiKey: string): Promise<string[]>;
  streamTurn(request: LocalGenUITurnRequest, sink: LocalGenUIFrameSink): Promise<void>;
  cancelTurn(): void;
}

/** Byte-level streaming transport; replaced by fixtures in native previews. */
export interface LocalGenUIStreamTransport {
  postStream(url: string, headers: Record<string, string>, body: string, onBytes: (bytes: ArrayBuffer) => void): Promise<number>;
  cancel(): void;
}

export class HarmonyLocalGenUIStreamTransport implements LocalGenUIStreamTransport {
  private active?: http.HttpRequest;

  async postStream(url: string, headers: Record<string, string>, body: string, onBytes: (bytes: ArrayBuffer) => void): Promise<number> {
    const request = http.createHttp();
    this.active = request;
    let bytes = 0;
    let ended = false;
    let markEnded: () => void = () => {};
    const endedSignal = new Promise<void>((resolve: () => void) => { markEnded = resolve; });
    const callback = (data: ArrayBuffer): void => {
      bytes += data.byteLength;
      onBytes(data);
    };
    const endCallback = (): void => {
      ended = true;
      markEnded();
    };
    request.on('dataReceive', callback);
    request.on('dataEnd', endCallback);
    try {
      const status = await request.requestInStream(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        connectTimeout: 15000,
        readTimeout: 180000
      });
      // The status can resolve before the last body chunks are delivered;
      // finishing early would truncate the tool-call arguments.
      if (!ended) {
        let timer = -1;
        await Promise.race([endedSignal, new Promise<void>((resolve: () => void) => { timer = setTimeout(resolve, 10000); })]);
        clearTimeout(timer);
      }
      RemoteLogger.info(`local genui stream bytes=${bytes} dataEnd=${ended}`);
      return status;
    } catch (err) {
      throw localTransportError('local genui stream request', err);
    } finally {
      request.off('dataReceive', callback);
      request.off('dataEnd', endCallback);
      request.destroy();
      if (this.active === request) {
        this.active = undefined;
      }
    }
  }

  cancel(): void {
    const request = this.active;
    this.active = undefined;
    if (request) {
      request.destroy();
    }
  }
}

interface AnthropicTool {
  name: string;
  description: string;
  input_schema: Object;
}

interface OpenAiFunction {
  name: string;
  description: string;
  parameters: Object;
}

interface OpenAiTool {
  type: string;
  function: OpenAiFunction;
}

interface AnthropicBody {
  model: string;
  max_tokens: number;
  stream: boolean;
  system: string;
  messages: LocalGenUIPromptMessage[];
  tools: AnthropicTool[];
}

interface OpenAiBody {
  model: string;
  max_tokens: number;
  stream: boolean;
  messages: LocalGenUIPromptMessage[];
  tools: OpenAiTool[];
}

interface OpenAiModelEntry {
  id?: string;
}

interface OpenAiModelList {
  data?: OpenAiModelEntry[];
}

export class HttpLocalGenUIModelProvider implements LocalGenUIModelProvider {
  private readonly models: LocalGenUIModelStore;
  private readonly transport: LocalGenUIStreamTransport;

  constructor(models: LocalGenUIModelStore, transport: LocalGenUIStreamTransport = new HarmonyLocalGenUIStreamTransport()) {
    this.models = models;
    this.transport = transport;
  }

  async isConfigured(modelId: string): Promise<boolean> {
    return this.models.hasKey(modelId);
  }

  async listRemoteModels(apiUrl: string, apiKey: string): Promise<string[]> {
    const base = apiUrl.trim().replace(/\/+$/, '');
    if (ModelProviderGeneralChatAdapter.resolveProtocol(base) === ModelProviderProtocol.Anthropic) {
      return [];
    }
    const root = base.replace(/\/chat\/completions$/, '').replace(/\/v1$/, '');
    const request = http.createHttp();
    try {
      const response = await request.request(`${root}/v1/models`, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': `Bearer ${apiKey.trim()}`, 'Accept': 'application/json' },
        connectTimeout: 10000,
        readTimeout: 15000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(HttpLocalGenUIModelProvider.statusError(response.responseCode, ''));
      }
      const list = JSON.parse(typeof response.result === 'string' ? response.result as string : '{}') as OpenAiModelList;
      return (list.data || []).map((entry: OpenAiModelEntry) => entry.id || '').filter((id: string) => id.length > 0);
    } catch (err) {
      throw localTransportError('local genui list models', err);
    } finally {
      request.destroy();
    }
  }

  async streamTurn(request: LocalGenUITurnRequest, sink: LocalGenUIFrameSink): Promise<void> {
    const config = await this.models.credentials(request.modelId);
    const apiKey = config ? config.apiKey.trim() : '';
    if (!config || config.apiUrl.length === 0 || config.modelName.length === 0 || apiKey.length === 0) {
      throw new Error(RemoteI18n.t('localGenui.modelNotConfigured'));
    }
    const generalProtocol = ModelProviderGeneralChatAdapter.resolveProtocol(config.apiUrl);
    const protocol = generalProtocol === ModelProviderProtocol.Anthropic ? LocalProviderProtocol.Anthropic : LocalProviderProtocol.OpenAi;
    const url = ModelProviderGeneralChatAdapter.resolveRequestUrl(config.apiUrl, generalProtocol);
    const body = HttpLocalGenUIModelProvider.body(config.modelName, request, protocol);
    const headers = HttpLocalGenUIModelProvider.headers(url, apiKey, protocol);
    const parser = new LocalProviderSseParser(protocol);
    // A multi-byte character can span two network chunks.
    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    let errorBody = '';
    RemoteLogger.info(`local genui request start protocol=${protocol}`);
    const status = await this.transport.postStream(url, headers, body, (bytes: ArrayBuffer): void => {
      const text = decoder.decodeToString(new Uint8Array(bytes), { stream: true });
      if (errorBody.length < 4096) {
        errorBody += text;
      }
      const frames = parser.feed(text);
      if (frames.length > 0) {
        sink.onFrames(frames);
      }
    });
    const tail = decoder.decodeToString(new Uint8Array(0), { stream: false });
    const frames = parser.feed(tail).concat(parser.finish());
    if (frames.length > 0) {
      sink.onFrames(frames);
    }
    RemoteLogger.info(`local genui response status=${status}`);
    if (status < 200 || status >= 300) {
      throw new Error(HttpLocalGenUIModelProvider.statusError(status, errorBody));
    }
  }

  cancelTurn(): void {
    this.transport.cancel();
  }

  static body(model: string, request: LocalGenUITurnRequest, protocol: LocalProviderProtocol): string {
    const tool = JSON.parse(request.toolSchemaJson) as AnthropicTool;
    if (protocol === LocalProviderProtocol.Anthropic) {
      const anthropic: AnthropicBody = {
        model,
        max_tokens: LOCAL_GENUI_MAX_OUTPUT_TOKENS,
        stream: true,
        system: request.system,
        messages: request.messages,
        tools: [tool]
      };
      return JSON.stringify(anthropic);
    }
    const messages: LocalGenUIPromptMessage[] = [{ role: 'system', content: request.system }];
    request.messages.forEach((message: LocalGenUIPromptMessage) => messages.push(message));
    const openAi: OpenAiBody = {
      model,
      max_tokens: LOCAL_GENUI_MAX_OUTPUT_TOKENS,
      stream: true,
      messages,
      tools: [{ type: 'function', function: { name: tool.name, description: tool.description, parameters: tool.input_schema } }]
    };
    return JSON.stringify(openAi);
  }

  private static headers(url: string, apiKey: string, protocol: LocalProviderProtocol): Record<string, string> {
    const headers: Record<string, string> = { 'Content-Type': 'application/json', 'Accept': 'text/event-stream' };
    if (protocol === LocalProviderProtocol.Anthropic) {
      headers['x-api-key'] = apiKey;
      headers['anthropic-version'] = '2023-06-01';
      if (url.indexOf('openbitfun.com') >= 0) {
        headers['X-Verification-Code'] = 'from_openbitfun';
      }
    } else {
      headers['Authorization'] = `Bearer ${apiKey}`;
    }
    return headers;
  }

  private static statusError(status: number, body: string): string {
    if (status === 401 || status === 403) {
      return RemoteI18n.t('generalChat.authenticationFailed');
    }
    if (status === 429) {
      return RemoteI18n.t('generalChat.rateLimited');
    }
    if (status >= 500) {
      return RemoteI18n.t('generalChat.serviceUnavailable');
    }
    const detail = body.replace(/\s+/g, ' ').trim().slice(0, 200);
    return `${RemoteI18n.f('generalChat.requestFailed', `${status}`)}${detail.length > 0 ? `: ${detail}` : ''}`;
  }
}
