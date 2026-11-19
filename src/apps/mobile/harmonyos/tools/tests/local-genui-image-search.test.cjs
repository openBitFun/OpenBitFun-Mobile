const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

const services = path.join(__dirname, '../../entry/src/main/ets/services/local-genui');
function load(name, modules = {}) {
  const code = ts.transpileModule(fs.readFileSync(path.join(services, name), 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
  }).outputText;
  const exports = {};
  new Function('require', 'exports', code)(specifier => modules[specifier] ?? {}, exports);
  return exports;
}

const { LocalGenUIImageSearch, LOCAL_GENUI_PHOTO_ROOT } = load('LocalGenUIImageSearch.ets', { '../RemoteLogger': { RemoteLogger: { info() {}, warn() {} } } });
const { LocalGenUIIcon3DStore, LOCAL_GENUI_ICON3D_ROOT } = load('LocalGenUIIcon3DStore.ets', { '../RemoteLogger': { RemoteLogger: { info() {}, warn() {} } } });
const { LocalGenUIActionHost } = load('LocalGenUIActionHost.ets', {
  './LocalGenUIModels': { LocalGenUIIds: { isLocal: id => typeof id === 'string' && id.startsWith('local-genui:') } },
});

test('photo search accepts the desktop query bounds', () => {
  assert.equal(LocalGenUIImageSearch.queryOf('  浅草寺  '), '浅草寺');
  assert.equal(LocalGenUIImageSearch.queryOf('寺'), '', 'too short');
  assert.equal(LocalGenUIImageSearch.queryOf('x'.repeat(201)), '', 'too long');
  assert.equal(LocalGenUIImageSearch.queryOf('🍣寿司'), '🍣寿司');
});

test('only host photo ids are served, and they do not overlap the 3D picture address', () => {
  assert.equal(LocalGenUIImageSearch.photoIdOf(LOCAL_GENUI_PHOTO_ROOT + '0123456789abcdef'), '0123456789abcdef');
  assert.equal(LocalGenUIImageSearch.photoIdOf(LOCAL_GENUI_PHOTO_ROOT + '0123456789ABCDEF'), '', 'uppercase');
  assert.equal(LocalGenUIImageSearch.photoIdOf(LOCAL_GENUI_PHOTO_ROOT + '0123456789abcdef?x=1'), '', 'queries');
  assert.equal(LocalGenUIImageSearch.photoIdOf(LOCAL_GENUI_PHOTO_ROOT + 'https%3A%2F%2Fevil.example'), '', 'encoded addresses');
  assert.equal(LocalGenUIImageSearch.photoIdOf('https://evil.example/photo/0123456789abcdef'), '', 'other hosts');
  assert.ok(!LOCAL_GENUI_PHOTO_ROOT.startsWith(LOCAL_GENUI_ICON3D_ROOT));
  assert.equal(LocalGenUIIcon3DStore.assetPath(LOCAL_GENUI_PHOTO_ROOT + '0123456789abcdef'), '');
});

test('a photo the host never found is not fetched', async () => {
  const search = new LocalGenUIImageSearch('/nonexistent-genui-test-dir');
  assert.equal(await search.picture(LOCAL_GENUI_PHOTO_ROOT + '0123456789abcdef'), undefined);
});

function host(calls, now = () => 0) {
  return new LocalGenUIActionHost({
    saveState: async () => {}, modelTurn: async () => {}, isTurnActive: () => false, unsupported: () => {},
    subscribeGesture: () => '', unsubscribeGesture: () => {}, haptic: () => {}, calendar: async () => '',
    imageSearch: (appId, requestId, query) => { calls.push({ appId, requestId, query }); return ''; },
  }, now);
}

test('image searches are admitted only for the mounted local app', async () => {
  const calls = [];
  const actions = host(calls);
  const message = { type: 'image_search', appId: 'local-genui:a', requestId: 'image-1', query: '浅草寺' };
  assert.equal(await actions.handle(message, 'local-genui:a', 1), '');
  assert.deepEqual(calls, [{ appId: 'local-genui:a', requestId: 'image-1', query: '浅草寺' }]);
  assert.notEqual(await actions.handle(message, 'local-genui:b', 1), '', 'another mounted app');
  assert.notEqual(await actions.handle({ ...message, requestId: '' }, 'local-genui:a', 1), '', 'missing request id');
  assert.notEqual(await actions.handle({ ...message, query: 'x'.repeat(900) }, 'local-genui:a', 1), '', 'oversized query');
  assert.equal(calls.length, 1);
});

test('image searches are rate limited per app', async () => {
  const calls = [];
  const actions = host(calls);
  let refused = '';
  for (let i = 0; i < 61 && !refused; i += 1) {
    refused = await actions.handle({ type: 'image_search', appId: 'local-genui:a', requestId: `image-${i}`, query: '寿司' }, 'local-genui:a', 1);
  }
  assert.notEqual(refused, '');
  assert.equal(calls.length, 60);
});
