const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
function load(file, imports = {}) {
  const mod = {};
  const source = fs.readFileSync(path.join(__dirname, '../../entry/src/main/ets/services/local-genui', file), 'utf8');
  new Function('require', 'exports', ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS }
  }).outputText)(name => imports[name] || {}, mod);
  return mod;
}
const { LocalGenUICollaborationHost: Host } = load('LocalGenUICollaborationHost.ets');
const { LocalGenUICollaborationAssets: Assets } = load('LocalGenUICollaborationAssets.ets', {
  './LocalGenUIModels': { LocalGenUIIds: { require: id => { assert.ok(id.startsWith('local-genui:')); } } }
});
const asset = `https://genui-assets.openbitfun.invalid/collaboration/local-genui%3Aa/${'a'.repeat(32)}.jpg`;
const message = (extra = {}) => ({ type: 'collaboration', appId: 'local-genui:a', sourceRevision: 2, requestId: 'request-1', op: 'start', kind: 'scan', ...extra });
function setup(extra = {}) {
  const owner = { appId: 'local-genui:a', sourceRevision: 2, live: true };
  const sent = [], shown = [], discarded = [];
  const host = new Host({ owner: () => owner, unavailable: () => '', changed: r => shown.push(r),
    send: r => sent.push(r), save: async () => asset, discard: async (app, url) => discarded.push([app, url]), ...extra });
  host.setVisible(true);
  return { host, owner, sent, shown, discarded };
}

test('request is owner-bound; only a saved image and completed transfer become success', async () => {
  const { host, sent, shown } = setup();
  assert.notEqual(host.handle(message({ appId: 'local-genui:other' })), '');
  assert.notEqual(host.handle(message({ sourceRevision: 1 })), '');
  assert.notEqual(host.handle(message({ kind: 'shell' })), '');
  assert.equal(shown.length, 0);
  host.handle(message());
  host.handle(message());
  assert.equal(shown.length, 1);
  const token = shown[0].token;
  host.result(token, { phase: 'active' });
  assert.equal(sent.at(-1).status, 'pending');
  await host.receive(token, new ArrayBuffer(4));
  host.result(token, { phase: 'completed' });
  assert.equal(sent.at(-1).asset, asset);
  assert.equal(sent.at(-1).status, 'completed');
  assert.equal(shown.at(-1), undefined);
});

test('busy, no support, hidden app and checker never launch another picker', () => {
  const { host, shown, sent, owner } = setup();
  host.handle(message());
  host.handle(message({ requestId: 'request-2' }));
  assert.equal(sent.at(-1).reason, 'busy');
  assert.equal(shown.length, 1);
  host.setVisible(false);
  host.handle(message({ requestId: 'request-3' }));
  assert.equal(sent.at(-1).status, 'unavailable');
  owner.live = false;
  assert.notEqual(host.handle(message()), '');
  const denied = setup({ unavailable: () => 'missingSyscap' });
  denied.host.handle(message());
  assert.equal(denied.shown.length, 0);
  assert.equal(denied.sent.at(-1).reason, 'missingSyscap');
});

test('cancellation during save discards only the abandoned new file, never delivers it to a new owner', async () => {
  let finish;
  const { host, shown, sent, owner, discarded } = setup({ save: () => new Promise(resolve => { finish = resolve; }) });
  host.handle(message());
  const token = shown[0].token;
  const receiving = host.receive(token, new ArrayBuffer(4));
  host.close(token + 1);
  assert.equal(sent.at(-1).status, 'pending');
  owner.appId = 'local-genui:b';
  host.invalidate(owner.appId, 2, false);
  finish(asset);
  await assert.rejects(receiving, /closed/);
  host.result(token, { phase: 'completed' });
  assert.deepEqual(discarded, [['local-genui:a', asset]]);
  assert.equal(sent.some(r => r.status === 'completed'), false);
});

test('missing data and failure cannot replace a previously bound asset', () => {
  const { host, shown, sent } = setup();
  host.handle(message());
  host.result(shown[0].token, { phase: 'completed' });
  assert.equal(sent.at(-1).status, 'failed');
  assert.equal(sent.at(-1).asset, '');
});

test('opaque image references cannot traverse directories or read another app', () => {
  assert.equal(Assets.fileName('local-genui:a', asset), `${'a'.repeat(32)}.jpg`);
  assert.equal(Assets.fileName('local-genui:b', asset), '');
  assert.equal(Assets.fileName('local-genui:a', asset + '?x=1'), '');
  assert.equal(Assets.fileName('local-genui:a', Assets.prefix('local-genui:a') + '../secrets.jpg'), '');
  assert.equal(Assets.fileName('local-genui:a', Assets.prefix('local-genui:a') + '%2e%2e%2fsecrets.jpg'), '');
  assert.notEqual(Assets.prefix('local-genui:a/b'), Assets.prefix('local-genui:a_b'));
});

test('a saved image survives a fresh store and wrong-owner reads cannot consume it', async () => {
  const io = require('node:fs/promises');
  const directory = await io.mkdtemp(path.join(require('node:os').tmpdir(), 'genui-collaboration-'));
  const handles = new Map();
  const { LocalGenUICollaborationAssets: DiskAssets } = load('LocalGenUICollaborationAssets.ets', {
    './LocalGenUIModels': { LocalGenUIIds: { require: id => assert.ok(id.startsWith('local-genui:')) } },
    '@kit.ArkTS': { util: { generateRandomUUID: () => require('node:crypto').randomUUID() } },
    '@kit.CoreFileKit': { fileIo: {
      OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4, READ_ONLY: 0 },
      access: async name => { try { await io.access(name); return true; } catch { return false; } },
      mkdir: (name, recursive) => io.mkdir(name, { recursive }),
      open: async (name, mode) => { const handle = await io.open(name, mode ? 'w' : 'r'); handles.set(handle.fd, handle); return handle; },
      write: async (fd, data) => (await handles.get(fd).write(Buffer.from(data))).bytesWritten,
      read: async (fd, data) => (await handles.get(fd).read(Buffer.from(data))).bytesRead,
      stat: fd => handles.get(fd).stat(),
      close: handle => { handles.delete(handle.fd); return handle.close(); },
      unlink: io.unlink, rename: io.rename,
    } },
  });
  try {
    const oldState = JSON.parse('{"counter":3,"future":{"keep":true}}');
    const bytes = Uint8Array.from([0xff, 0xd8, 42, 0xff, 0xd9]).buffer;
    const store = new DiskAssets(directory);
    const ref = await store.save('local-genui:a', bytes);
    const persisted = JSON.stringify({ ...oldState, image: ref });
    const reopened = new DiskAssets(directory);
    assert.equal(await reopened.picture('local-genui:b', ref), undefined);
    await reopened.discard('local-genui:b', ref);
    assert.deepEqual(await reopened.picture('local-genui:a', JSON.parse(persisted).image), bytes);
    assert.deepEqual(JSON.parse(persisted).future, oldState.future);
    await assert.rejects(store.save('local-genui:a', new ArrayBuffer(2 * 1024 * 1024 + 1)), /size unsupported/);
    await reopened.discard('local-genui:a', ref);
    assert.equal(await reopened.picture('local-genui:a', ref), undefined);
  } finally { await io.rm(directory, { recursive: true, force: true }); }
});
