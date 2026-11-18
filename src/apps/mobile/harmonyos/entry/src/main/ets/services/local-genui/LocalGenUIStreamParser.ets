/**
 * GenerativeUI tool-call argument parsing for Harmony Local GenUI.
 *
 * This mirrors the Desktop accumulator (agent-stream tool_call_accumulator.rs)
 * and is verified against the same fixtures in
 * src/shared/generative-ui/tool-call-fixtures.json. It is a JSON framing
 * scanner only: it locates the program (top-level `source` in the local tool
 * form, `source.content` in the shared envelope), decodes the JSON string
 * incrementally and never parses OpenUI Lang.
 */

export interface LocalGenUISourceChunk {
  text: string;
  reset: boolean;
}

interface DecodedDelta {
  text: string;
  next: number;
  closed: boolean;
}

const BACKSLASH: number = 92;
const QUOTE: number = 34;

function quotedStringEnd(input: string, start: number): number {
  if (input.charCodeAt(start) !== QUOTE) {
    return -1;
  }
  let index = start + 1;
  while (index < input.length) {
    const code = input.charCodeAt(index);
    if (code === BACKSLASH) {
      index += 2;
    } else if (code === QUOTE) {
      return index + 1;
    } else {
      index += 1;
    }
  }
  return -1;
}

function parseJsonString(encoded: string): string | undefined {
  try {
    const value: Object = JSON.parse(encoded) as Object;
    return typeof value === 'string' ? value as string : undefined;
  } catch (_err) {
    return undefined;
  }
}

function isHex(text: string): boolean {
  return /^[0-9a-fA-F]{4}$/.test(text);
}

/** Decode the JSON string body from `cursor`, stopping before an incomplete escape. */
function decodeJsonStringDelta(input: string, cursor: number): DecodedDelta | undefined {
  let index = cursor;
  while (index < input.length) {
    const code = input.charCodeAt(index);
    if (code === QUOTE) {
      const text = parseJsonString(`"${input.slice(cursor, index)}"`);
      return text === undefined ? undefined : { text, next: index + 1, closed: true };
    }
    if (code !== BACKSLASH) {
      index += 1;
      continue;
    }
    if (index + 1 >= input.length) {
      break;
    }
    const escape = input.charAt(index + 1);
    let end = index + 2;
    if (escape === 'u') {
      const digits = input.slice(index + 2, index + 6);
      if (digits.length < 4) {
        break;
      }
      if (!isHex(digits)) {
        return undefined;
      }
      const unit = parseInt(digits, 16);
      end = index + 6;
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (end + 2 > input.length) {
          break;
        }
        if (input.slice(end, end + 2) !== '\\u') {
          return undefined;
        }
        const low = input.slice(end + 2, end + 6);
        if (low.length < 4) {
          break;
        }
        if (!isHex(low)) {
          return undefined;
        }
        const lowUnit = parseInt(low, 16);
        if (lowUnit < 0xDC00 || lowUnit > 0xDFFF) {
          return undefined;
        }
        end += 6;
      }
    } else if ('"\\/bfnrt'.indexOf(escape) < 0) {
      return undefined;
    }
    index = end;
  }
  if (index === cursor) {
    return { text: '', next: cursor, closed: false };
  }
  const text = parseJsonString(`"${input.slice(cursor, index)}"`);
  return text === undefined ? undefined : { text, next: index, closed: false };
}

/** Value starts of `"wanted":` members of objects, tolerant of an unfinished document. */
function findObjectFieldStarts(input: string, wanted: string, topLevelOnly: boolean = false): number[] {
  const stack: string[] = [];
  const starts: number[] = [];
  let index = 0;
  while (index < input.length) {
    const ch = input.charAt(index);
    if (ch === '"') {
      const end = quotedStringEnd(input, index);
      if (end < 0) {
        break;
      }
      const key = parseJsonString(input.slice(index, end));
      if (key !== undefined && stack.length > 0 && stack[stack.length - 1] === '{' && key === wanted && (!topLevelOnly || stack.length === 1)) {
        let valueStart = end;
        while (valueStart < input.length && /\s/.test(input.charAt(valueStart))) {
          valueStart += 1;
        }
        if (input.charAt(valueStart) !== ':') {
          // A string value can equal the field name; keep scanning for the member.
          index = end;
          continue;
        }
        valueStart += 1;
        while (valueStart < input.length && /\s/.test(input.charAt(valueStart))) {
          valueStart += 1;
        }
        starts.push(valueStart);
      }
      index = end;
    } else if (ch === '{' || ch === '[') {
      stack.push(ch);
      index += 1;
    } else if (ch === '}') {
      if (stack.length > 0 && stack[stack.length - 1] === '{') {
        stack.pop();
      }
      index += 1;
    } else if (ch === ']') {
      if (stack.length > 0 && stack[stack.length - 1] === '[') {
        stack.pop();
      }
      index += 1;
    } else {
      index += 1;
    }
  }
  return starts;
}

function findObjectFieldStart(input: string, wanted: string): number {
  const starts = findObjectFieldStarts(input, wanted);
  return starts.length > 0 ? starts[0] : -1;
}

function closedStringAt(input: string, start: number): string | undefined {
  const end = quotedStringEnd(input, start);
  return end < 0 ? undefined : parseJsonString(input.slice(start, end));
}

function findOpenUIContentStart(raw: string): number {
  // Local tool form: `{"title": ..., "source": "<program>"}`.
  const flat = findObjectFieldStarts(raw, 'source', true);
  if (flat.length > 0 && raw.charAt(flat[0]) === '"') {
    return flat[0];
  }
  const sources = findObjectFieldStarts(raw, 'source');
  for (let i = 0; i < sources.length; i++) {
    const sourceStart = sources[i];
    if (raw.charAt(sourceStart) !== '{') {
      continue;
    }
    const scope = raw.slice(sourceStart);
    const kindStart = findObjectFieldStart(scope, 'kind');
    if (kindStart < 0) {
      continue;
    }
    if (closedStringAt(scope, kindStart) !== 'openui-lang') {
      // Free HTML documents stay on the completed-source path.
      continue;
    }
    const contentStart = findObjectFieldStart(scope, 'content');
    // Providers can split between `:` and the opening quote; wait for it.
    return contentStart < 0 || scope.charAt(contentStart) !== '"' ? -1 : sourceStart + contentStart;
  }
  return -1;
}

/**
 * Accumulates one GenerativeUI tool call. `apply` returns the newly decoded
 * OpenUI text for this provider frame, if any.
 */
export class GenerativeUIArgumentAccumulator {
  private raw: string = '';
  private contentStart: number = -1;
  private scanned: number = -1;
  private done: boolean = false;
  private resetNext: boolean = false;
  private seq: number = 0;
  private content: string = '';

  apply(chunk: string, snapshot: boolean): LocalGenUISourceChunk | undefined {
    if (chunk.length === 0) {
      return undefined;
    }
    const cumulative = this.raw.length > 0 && chunk.startsWith(this.raw);
    if (snapshot || cumulative) {
      if (chunk.startsWith(this.raw)) {
        this.raw = chunk;
      } else {
        this.replace(chunk);
      }
    } else {
      this.raw += chunk;
    }
    if (this.contentStart < 0) {
      this.contentStart = findOpenUIContentStart(this.raw);
    }
    if (this.scanned < 0 && this.contentStart >= 0) {
      this.scanned = this.contentStart + 1;
    }
    if (this.done || this.scanned < 0) {
      return undefined;
    }
    const decoded = decodeJsonStringDelta(this.raw, this.scanned);
    if (!decoded) {
      return undefined;
    }
    this.scanned = decoded.next;
    this.done = decoded.closed;
    if (decoded.text.length === 0) {
      return undefined;
    }
    const reset = this.resetNext;
    this.resetNext = false;
    this.content += decoded.text;
    this.seq += 1;
    return { text: decoded.text, reset };
  }

  rawArguments(): string {
    return this.raw;
  }

  source(): string {
    return this.content;
  }

  private replace(snapshot: string): void {
    const resetStream = this.seq > 0;
    this.raw = snapshot;
    this.contentStart = -1;
    this.scanned = -1;
    this.done = false;
    this.seq = 0;
    this.content = '';
    this.resetNext = resetStream;
  }
}

export interface LocalGenUIGeneration {
  ok: boolean;
  error: string;
  title: string;
  description: string;
  source: string;
  valuesJson: string;
}

/**
 * Close-only structural repair, used only after a normal tool-use completion
 * (Desktop applies JSON repair at the same boundary). It inserts closers a
 * provider omitted before a mismatched closer or at the end; it never
 * fabricates keys or values and refuses a dangling `,` or `:`.
 */
export function repairToolArgumentClosers(raw: string): string | undefined {
  const stack: string[] = [];
  let out = '';
  let inString = false;
  let escape = false;
  let last = '';
  let changed = false;
  for (let i = 0; i < raw.length; i++) {
    const ch = raw.charAt(i);
    if (inString) {
      out += ch;
      if (escape) {
        escape = false;
      } else if (ch === '\\') {
        escape = true;
      } else if (ch === '"') {
        inString = false;
        last = '"';
      }
      continue;
    }
    if (ch === '"') {
      inString = true;
    } else if (ch === '{' || ch === '[') {
      stack.push(ch);
    } else if (ch === '}' || ch === ']') {
      const opener = ch === '}' ? '{' : '[';
      if (stack.indexOf(opener) < 0) {
        // Observed from DeepSeek: the value is already complete and the
        // provider appends stray closers. Drop them only when nothing but
        // closers and whitespace follows the closed root value.
        if (stack.length === 0 && out.trim().length > 0 && /^[\s\]}]*$/.test(raw.substring(i))) {
          return out;
        }
        return undefined;
      }
      while (stack.length > 0 && stack[stack.length - 1] !== opener) {
        if (last === ',' || last === ':') {
          return undefined;
        }
        out += stack.pop() === '{' ? '}' : ']';
        changed = true;
      }
      stack.pop();
    }
    out += ch;
    if (!/\s/.test(ch)) {
      last = ch;
    }
  }
  if (inString || last === ',' || last === ':') {
    return undefined;
  }
  while (stack.length > 0) {
    out += stack.pop() === '{' ? '}' : ']';
    changed = true;
  }
  return changed ? out : undefined;
}

const RESERVED_KEYS: string[] = ['__proto__', 'constructor', 'prototype'];
const SURFACE_FIELDS: string[] = ['title', 'description', 'source'];

function isPlainObject(value: Object | null | undefined): boolean {
  return value !== null && value !== undefined && typeof value === 'object' && !Array.isArray(value);
}

function rejected(error: string): LocalGenUIGeneration {
  return { ok: false, error, title: '', description: '', source: '', valuesJson: '{}' };
}

/**
 * Terminal assembly of a complete GenerativeUI tool call under the local
 * schema. Owner-bound identity fields from the provider are rejected.
 */
export function assembleLocalGeneration(raw: string, ownerFields: string[], normalCompletion: boolean = false): LocalGenUIGeneration {
  let input: Object;
  try {
    input = JSON.parse(raw) as Object;
  } catch (_err) {
    const repaired = normalCompletion ? repairToolArgumentClosers(raw) : undefined;
    if (repaired === undefined) {
      return rejected(`GenerativeUI arguments are incomplete or invalid JSON (length ${raw.length}, repair ${normalCompletion ? 'not applicable' : 'skipped'})`);
    }
    try {
      input = JSON.parse(repaired) as Object;
    } catch (repairErr) {
      return rejected(`GenerativeUI arguments are incomplete or invalid JSON after repair (${String(repairErr).slice(0, 120)})`);
    }
  }
  if (!isPlainObject(input)) {
    return rejected('GenerativeUI arguments must be an object');
  }
  const args = input as Record<string, Object>;
  if (typeof args['source'] === 'string' && args['messages'] === undefined && args['protocol'] === undefined) {
    return assembleFlatGeneration(args, ownerFields);
  }
  if (args['protocol'] !== 'openbitfun.genui.v1') {
    return rejected('generation.protocol must be openbitfun.genui.v1');
  }
  let messagesValue: Object = args['messages'];
  if (typeof messagesValue === 'string') {
    // Some providers (observed: Qwen) encode the array as a JSON string and
    // drop one closer inside it; the same close-only repair applies.
    const encoded = messagesValue as string;
    try {
      messagesValue = JSON.parse(encoded) as Object;
    } catch (_err) {
      const repaired = normalCompletion ? repairToolArgumentClosers(encoded) : undefined;
      if (repaired === undefined) {
        return rejected('generation.messages must be an array');
      }
      try {
        messagesValue = JSON.parse(repaired) as Object;
      } catch (_repairErr) {
        return rejected('generation.messages must be an array');
      }
    }
  }
  if (!Array.isArray(messagesValue)) {
    return rejected('generation.messages must be an array');
  }
  const messages = messagesValue as Object[];
  for (let i = 0; i < messages.length; i++) {
    const message = messages[i] as Record<string, Object>;
    if (!isPlainObject(messages[i])) {
      return rejected(`generation.messages[${i}] must be an object`);
    }
    if (message['updateComponents'] !== undefined || message['updateLogic'] !== undefined) {
      return rejected('GenUI graph messages were removed; send a complete source document in createSurface.source');
    }
    if (i > 0 && message['createSurface'] !== undefined) {
      return rejected('generation.messages: createSurface may occur only once');
    }
  }
  if (messages.length === 0 || !isPlainObject((messages[0] as Record<string, Object>)['createSurface'])) {
    return rejected('generation.messages[0]: createSurface is required and must be first');
  }
  const surface = (messages[0] as Record<string, Object>)['createSurface'] as Record<string, Object>;
  const keys = Object.keys(surface);
  for (let i = 0; i < keys.length; i++) {
    if (ownerFields.indexOf(keys[i]) >= 0) {
      return rejected(`createSurface.${keys[i]} is owner-bound and is not accepted from the provider`);
    }
    if (SURFACE_FIELDS.indexOf(keys[i]) < 0) {
      return rejected(`createSurface.${keys[i]} is not part of the local schema`);
    }
  }
  const title = surface['title'];
  if (typeof title !== 'string' || (title as string).trim().length === 0) {
    return rejected('createSurface.title is required');
  }
  const description = typeof surface['description'] === 'string' ? surface['description'] as string : '';
  if (!isPlainObject(surface['source'])) {
    return rejected('createSurface.source is required');
  }
  const source = surface['source'] as Record<string, Object>;
  if (source['kind'] !== 'openui-lang') {
    return rejected(`unsupported source kind ${String(source['kind'])}; local phase 1 accepts openui-lang only`);
  }
  const content = source['content'];
  if (typeof content !== 'string' || (content as string).trim().length === 0) {
    return rejected('createSurface.source.content is required');
  }
  const values: Record<string, Object> = {};
  for (let i = 1; i < messages.length; i++) {
    const message = messages[i] as Record<string, Object>;
    const update = message['updateDataModel'];
    if (!isPlainObject(update) || Object.keys(message).length !== 1) {
      return rejected(`generation.messages[${i}]: only updateDataModel is supported after createSurface`);
    }
    const updateFields = update as Record<string, Object>;
    const updateKeys = Object.keys(updateFields);
    if (updateKeys.length !== 1 || updateKeys[0] !== 'values' || !isPlainObject(updateFields['values'])) {
      return rejected(`generation.messages[${i}].updateDataModel accepts only values`);
    }
    const fields = updateFields['values'] as Record<string, Object>;
    const names = Object.keys(fields);
    for (let j = 0; j < names.length; j++) {
      if (RESERVED_KEYS.indexOf(names[j]) >= 0) {
        return rejected(`generation.messages[${i}].updateDataModel: reserved state ID`);
      }
      values[names[j]] = fields[names[j]];
    }
  }
  return { ok: true, error: '', title: (title as string).trim(), description, source: content as string, valuesJson: JSON.stringify(values) };
}

const FLAT_FIELDS: string[] = ['title', 'description', 'source', 'values'];

/** The local tool form: `{title, source, description?, values?}`. */
function assembleFlatGeneration(args: Record<string, Object>, ownerFields: string[]): LocalGenUIGeneration {
  const keys = Object.keys(args);
  for (let i = 0; i < keys.length; i++) {
    if (ownerFields.indexOf(keys[i]) >= 0) {
      return rejected(`${keys[i]} is owner-bound and is not accepted from the provider`);
    }
    if (FLAT_FIELDS.indexOf(keys[i]) < 0) {
      return rejected(`${keys[i]} is not part of the local schema`);
    }
  }
  const title = args['title'];
  if (typeof title !== 'string' || (title as string).trim().length === 0) {
    return rejected('title is required');
  }
  const content = args['source'] as string;
  if (content.trim().length === 0) {
    return rejected('source is required');
  }
  const description = typeof args['description'] === 'string' ? args['description'] as string : '';
  const values: Record<string, Object> = {};
  if (args['values'] !== undefined && args['values'] !== null) {
    if (!isPlainObject(args['values'])) {
      return rejected('values must be an object');
    }
    const fields = args['values'] as Record<string, Object>;
    const names = Object.keys(fields);
    for (let j = 0; j < names.length; j++) {
      if (RESERVED_KEYS.indexOf(names[j]) >= 0) {
        return rejected('values: reserved state ID');
      }
      values[names[j]] = fields[names[j]];
    }
  }
  return { ok: true, error: '', title: (title as string).trim(), description, source: content, valuesJson: JSON.stringify(values) };
}

/** A closed top-level-or-nested string member, used for early titles only. */
export function extractClosedStringField(raw: string, field: string): string {
  const start = findObjectFieldStart(raw, field);
  if (start < 0) {
    return '';
  }
  const value = closedStringAt(raw, start);
  return value === undefined ? '' : value;
}
