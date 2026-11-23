const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

const repo = path.join(__dirname, '../../../../../..');
function loadLocalGenUI(name, dependencies = {}) {
  const source = fs.readFileSync(path.join(__dirname, '../../entry/src/main/ets/services/local-genui', `${name}.ets`), 'utf8');
  const code = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
  }).outputText;
  const exports = {};
  new Function('require', 'exports', code)(dependency => dependencies[dependency] || {}, exports);
  return exports;
}

const fixtures = JSON.parse(fs.readFileSync(path.join(repo, 'src/shared/generative-ui/tool-call-fixtures.json'), 'utf8'));
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../../entry/src/main/resources/rawfile/genui/runtime-manifest.json'), 'utf8'));
const { GenerativeUIArgumentAccumulator, assembleLocalGeneration } = loadLocalGenUI('LocalGenUIStreamParser');

test('a composer send that needs model setup never accepts the draft or starts a turn', async () => {
  const { LocalGenUISessionController } = loadLocalGenUI('LocalGenUISessionController', {
    './LocalGenUIModelCatalog': loadLocalGenUI('LocalGenUIModelCatalog')
  });
  const profile = { id: 'demo', modelName: 'demo' };
  for (const modelState of [
    { models: [], pinned: '' },
    { models: [profile], pinned: 'deleted' },
    { models: [profile], pinned: profile.id }
  ]) {
    const controller = Object.assign(Object.create(LocalGenUISessionController.prototype), {
      activeSessionId: 'local-genui:test',
      activeSession: { modelId: modelState.pinned },
      draftModelId: '',
      turnActive: false,
      modelStore: { list: () => modelState.models, lastSelectedId: async () => '' },
      provider: { isConfigured: async () => false }
    });
    let setupRequests = 0;
    await controller.send('Make a timer', '', '', '', {
      isCurrent: () => true,
      onAccepted: () => assert.fail('Model setup must leave the draft untouched'),
      onModelRequired: () => { setupRequests += 1; }
    });
    assert.equal(setupRequests, 1);
    assert.equal(controller.isTurnActive(), false);
  }
});

test('saving a mounted app preview refreshes the gallery and its message card', async () => {
  const { LocalGenUISessionController } = loadLocalGenUI('LocalGenUISessionController', {
    '../RemoteLogger': { RemoteLogger: { info: () => {} } }
  });
  const appId = 'local-genui:app-test-preview';
  let mount = { identity: { appId }, mode: 'live', streaming: false };
  let filename = 'previous.jpg';
  let galleryPath;
  let messageRefreshes = 0;
  const controller = Object.assign(Object.create(LocalGenUISessionController.prototype), {
    activeSessionId: 'local-genui:session-test-preview',
    messages: [{ appId }],
    bridge: {
      currentMount: () => mount,
      snapshot: async () => ({})
    },
    thumbnails: {
      existing: () => filename,
      save: async () => { filename = 'updated.jpg'; return filename; }
    },
    repository: { listGallery: async () => [{ appId, thumbnailPath: 'previous.jpg' }] },
    listener: {
      galleryChanged: (entries) => { galleryPath = entries[0].thumbnailPath; },
      messagesChanged: () => { messageRefreshes += 1; }
    },
    syncDesktopCards: async () => {}
  });

  assert.equal(await controller.captureThumbnail(appId), true);
  assert.equal(galleryPath, 'updated.jpg');
  assert.equal(messageRefreshes, 1);

  let released = false;
  controller.bridge.snapshot = async () => {
    mount = { ...mount, streaming: true };
    return { release: () => { released = true; } };
  };
  assert.equal(await controller.captureThumbnail(appId), false);
  assert.equal(released, true);
  assert.equal(messageRefreshes, 1);
});

test('only a settled, accepted live revision can refresh its preview', async () => {
  const { LocalGenUISessionController } = loadLocalGenUI('LocalGenUISessionController', {
    './LocalGenUIOwner': { LocalGenUIOwner: {
      runnableRevision: (record) => record.runnable,
      isDisplayableStatus: (status) => status === 'ready'
    } }
  });
  const appId = 'local-genui:app-test-preview';
  const mount = { identity: { appId }, sourceRevision: 2, mode: 'live', streaming: false };
  const record = { runnable: { sourceRevision: 2, status: 'candidate' } };
  let captures = 0;
  const controller = Object.assign(Object.create(LocalGenUISessionController.prototype), {
    bridge: { currentMount: () => mount },
    repository: { loadApp: async () => record },
    captureThumbnail: async () => { captures += 1; }
  });
  const preview = { type: 'preview_ready', appId, sourceRevision: 2 };
  await controller.onRuntimeMessage(preview);
  assert.equal(captures, 0);
  record.runnable.status = 'ready';
  await controller.onRuntimeMessage({ ...preview, sourceRevision: 1 });
  assert.equal(captures, 0);
  await controller.onRuntimeMessage(preview);
  assert.equal(captures, 1);
});

for (const fixture of fixtures.cases) {
  test(`shared tool-call fixture: ${fixture.name}`, () => {
    const accumulator = new GenerativeUIArgumentAccumulator();
    const stream = [];
    let source = '';
    for (const delta of fixture.deltas) {
      const chunk = accumulator.apply(delta.arguments, Boolean(delta.snapshot));
      if (!chunk) continue;
      if (chunk.reset) source = '';
      source += chunk.text;
      stream.push({ text: chunk.text, reset: chunk.reset });
    }
    assert.deepEqual(stream, fixture.expect.stream);
    assert.equal(source, fixture.expect.source);
    const normal = ['tool_calls', 'tool_use', 'stop', 'end_turn'].includes(fixture.completion);
    const generation = assembleLocalGeneration(accumulator.rawArguments(), manifest.ownerFields, normal);
    assert.equal(generation.ok, fixture.expect.local.accepted, generation.error);
    if (fixture.expect.local.accepted) {
      assert.equal(generation.title, fixture.expect.local.title);
      assert.equal(generation.source, fixture.expect.source);
      assert.deepEqual(JSON.parse(generation.valuesJson), fixture.expect.local.values);
    } else {
      assert.match(generation.error, new RegExp(fixture.expect.local.error));
    }
  });
}

test('local tool schema never exposes owner-bound identity fields', () => {
  const schema = JSON.parse(fs.readFileSync(path.join(__dirname, '../../entry/src/main/resources/rawfile/genui/local-tool-schema.json'), 'utf8'));
  const input = schema.input_schema;
  for (const field of manifest.ownerFields) assert.equal(input.properties[field], undefined, field);
  assert.equal(input.additionalProperties, false);
});

test('a length stop is reported as truncation, not as malformed JSON', () => {
  const models = loadLocalGenUI('LocalGenUIModels');
  const parser = loadLocalGenUI('LocalGenUIStreamParser');
  const sse = loadLocalGenUI('LocalProviderSseParser');
  const { LocalGenUITurnNormalizer, LOCAL_GENUI_TRUNCATED } = loadLocalGenUI('LocalGenUITurnNormalizer', { './LocalGenUIModels': models, './LocalGenUIStreamParser': parser, './LocalProviderSseParser': sse });
  const n = new LocalGenUITurnNormalizer('t', 'GenerativeUI', { bind: (id, title) => ({ appId: 'local-genui:a', toolCallId: id, title }) });
  n.accept([{ kind: 'tool', index: 0, toolCallId: 'c', toolName: 'GenerativeUI', arguments: '{"protocol":"openbitfun.genui.v1","messages":[{"createSurface":{"title":"T","source":{"kind":"openui-lang","content":"root = Col(', text: '', stopReason: '' }, { kind: 'stop', stopReason: 'length', index: -1, toolCallId: '', toolName: '', arguments: '', text: '' }]);
  const result = n.finish(manifest.ownerFields);
  assert.equal(result.events.at(-1).error, LOCAL_GENUI_TRUNCATED);
});

test('messages encoded as a string with a dropped closer are repaired only after a normal completion', () => {
  // Observed from Qwen: the array arrives as a JSON string whose tail is `"}}]`, one `}` short.
  const inner = '[{"createSurface":{"title":"T","source":{"kind":"openui-lang","content":"root = Page([n])\\nn = Note(\\"hi\\")\\n"}}]';
  const raw = JSON.stringify({ protocol: 'openbitfun.genui.v1', messages: inner });
  const repaired = assembleLocalGeneration(raw, manifest.ownerFields, true);
  assert.equal(repaired.ok, true, repaired.error);
  assert.equal(repaired.title, 'T');
  assert.equal(repaired.source, 'root = Page([n])\nn = Note("hi")\n');
  assert.match(assembleLocalGeneration(raw, manifest.ownerFields, false).error, /messages must be an array/);
  const wellFormed = JSON.stringify({ protocol: 'openbitfun.genui.v1', messages: inner.replace(/\}\}\]$/, '}}}]') });
  assert.equal(assembleLocalGeneration(wellFormed, manifest.ownerFields, false).ok, true);
});

test('stray closers after a complete argument object are dropped only after a normal completion', () => {
  // Observed from DeepSeek: a complete object followed by an extra `]}`.
  const complete = JSON.stringify({ protocol: 'openbitfun.genui.v1', messages: [{ createSurface: { title: 'T', source: { kind: 'openui-lang', content: 'root = Page([n])\nn = Note("hi")\n' } } }] });
  const repaired = assembleLocalGeneration(complete + ']}', manifest.ownerFields, true);
  assert.equal(repaired.ok, true, repaired.error);
  assert.equal(repaired.source, 'root = Page([n])\nn = Note("hi")\n');
  assert.equal(assembleLocalGeneration(complete + ']}', manifest.ownerFields, false).ok, false);
  // Anything other than closers after the root is still rejected.
  assert.equal(assembleLocalGeneration(complete + ']} x', manifest.ownerFields, true).ok, false);
  assert.equal(assembleLocalGeneration(complete + ',{}', manifest.ownerFields, true).ok, false);
});

test('the local tool form streams and assembles a top-level source string', () => {
  const schema = JSON.parse(fs.readFileSync(path.join(__dirname, '../../entry/src/main/resources/rawfile/genui/local-tool-schema.json'), 'utf8'));
  assert.deepEqual(schema.input_schema.required, ['title', 'source']);
  assert.equal(schema.input_schema.properties.source.type, 'string');
  const raw = JSON.stringify({ title: '喝水', source: 'root = Page([n])\nn = Note("{a}")\n', values: { cups: 2 } });
  const accumulator = new GenerativeUIArgumentAccumulator();
  let streamed = '';
  for (let i = 0; i < raw.length; i += 7) {
    const chunk = accumulator.apply(raw.slice(i, i + 7), false);
    if (chunk) streamed += chunk.text;
  }
  assert.equal(streamed, 'root = Page([n])\nn = Note("{a}")\n');
  const generation = assembleLocalGeneration(accumulator.rawArguments(), manifest.ownerFields, true);
  assert.equal(generation.ok, true, generation.error);
  assert.equal(generation.title, '喝水');
  assert.deepEqual(JSON.parse(generation.valuesJson), { cups: 2 });
  // A state named source inside values is not the program.
  const nested = new GenerativeUIArgumentAccumulator();
  assert.equal(nested.apply('{"values": {"source": "x"}, "title": "T"', false), undefined);
  assert.match(assembleLocalGeneration(JSON.stringify({ title: 'T', source: 'root = Page([])', libraryId: 'x' }), manifest.ownerFields, true).error, /owner-bound/);
  assert.match(assembleLocalGeneration(JSON.stringify({ title: 'T', source: 'root = Page([])', extra: 1 }), manifest.ownerFields, true).error, /not part of the local schema/);
});
