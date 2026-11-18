const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

function harness() {
  const calls = [];
  let lookup = async () => main;
  const main = {
    getPreferredOrientation: () => 9,
    setPreferredOrientation: async value => { calls.push(value); },
  };
  const window = {
    Orientation: { AUTO_ROTATION_LANDSCAPE: 2, AUTO_ROTATION_PORTRAIT: 1 },
    getLastWindow: () => lookup(),
  };
  const source = fs.readFileSync(path.join(__dirname, '../../entry/src/main/ets/services/local-genui/LocalGenUIOrientation.ets'), 'utf8');
  const exports = {};
  new Function('require', 'exports', ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText)(name => name === '@kit.ArkUI' ? { window } : { RemoteLogger: { warn() {} } }, exports);
  return { service: new exports.LocalGenUIOrientation(() => ({})), calls, main, setLookup: fn => { lookup = fn; } };
}

test('legacy pages with no preference do not rotate, regardless of viewport', async () => {
  const { service, calls } = harness();
  await service.sync(true);
  await service.sync(true, 'auto');
  await service.sync(true, 'unknown');
  assert.deepEqual(calls, []);
});

test('page choice switches in both directions and restores the original host preference', async () => {
  const { service, calls } = harness();
  await service.sync(true, 'landscape');
  await service.sync(true, 'landscape');
  await service.sync(true, 'portrait');
  await service.sync(false, 'portrait');
  assert.deepEqual(calls, [2, 1, 9]);
  await service.sync(true, 'portrait');
  await service.sync(true, 'auto');
  assert.deepEqual(calls, [2, 1, 9, 1, 9]);
});

test('closing during a pending window lookup does not apply stale orientation', async () => {
  const h = harness();
  let resolve;
  h.setLookup(() => new Promise(r => { resolve = r; }));
  const opening = h.service.sync(true, 'landscape');
  await Promise.resolve();
  const closing = h.service.sync(false, 'landscape');
  resolve(h.main);
  await Promise.all([opening, closing]);
  assert.deepEqual(h.calls, []);
});

test('failed rotations can be retried and restored', async () => {
  const h = harness();
  h.setLookup(async () => { throw new Error('temporarily unavailable'); });
  await h.service.sync(true, 'landscape');
  h.setLookup(async () => h.main);
  await h.service.sync(true, 'landscape');
  await h.service.sync(false);
  assert.deepEqual(h.calls, [2, 9]);
});
