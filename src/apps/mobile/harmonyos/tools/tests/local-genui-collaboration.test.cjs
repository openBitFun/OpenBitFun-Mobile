const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const mod = {};
const source = fs.readFileSync(path.join(__dirname,
  '../../entry/src/main/ets/services/local-genui/LocalCollaborationSession.ets'), 'utf8');
new Function('exports', ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS }
}).outputText)(mod);
const { LocalCollaborationSession: Session } = mod;
const empty = new ArrayBuffer(0);
const image = new Uint8Array([1, 2, 3]).buffer;

test('the adapter requires API 23; a declared capability is not a connected device', () => {
  assert.equal(Session.unavailableReason(21, 'phone', true), 'version');
  assert.equal(Session.unavailableReason(23, 'phone', true), '');
  assert.equal(Session.unavailableReason(21, 'tablet', true), 'version');
  assert.equal(Session.unavailableReason(24, 'phone', false), 'missingSyscap');
  assert.equal(Session.unavailableReason(26, 'wearable', true), 'deviceType');
  const s = new Session(() => {}, async () => {});
  assert.equal(s.begin('photo', 'missingSyscap'), false);
  assert.equal(s.snapshot().phase, 'unavailable');
});

test('connection and all-returned signals wait for successful decoding', async () => {
  let resolve;
  const s = new Session(() => {}, () => new Promise(r => { resolve = r; }));
  s.begin('gallery', '');
  await s.accept(1001202004, '', empty);
  assert.equal(s.snapshot().phase, 'active');
  const receiving = s.accept(0, 'general.image', image);
  await s.accept(1001202005, '', empty);
  assert.equal(s.snapshot().phase, 'receiving');
  resolve();
  await receiving;
  assert.equal(s.snapshot().phase, 'completed');
  assert.equal(s.snapshot().received, 1);
  await s.accept(1001202002, '', empty);
  assert.equal(s.snapshot().phase, 'completed');
});

test('cancellation and unmount invalidate outstanding image work', async () => {
  for (const cancel of [1001202001, 1001202003, null]) {
    let resolve;
    let generation;
    const s = new Session(() => {}, (_, token) => {
      generation = token;
      return new Promise(r => { resolve = r; });
    });
    s.begin('photo', '');
    const work = s.accept(0, 'general.image', image);
    if (cancel === null) s.close();
    else await s.accept(cancel, '', empty);
    assert.equal(s.isCurrent(generation), false);
    resolve();
    await work;
    await s.accept(1001202005, '', empty);
    assert.equal(s.snapshot().phase, cancel === null ? 'closed' : 'cancelled');
    assert.equal(s.snapshot().received, 0);
    assert.equal(s.begin('scan', ''), false, 'a new request needs a fresh native receiver');
  }
});

test('empty transfers, unknown status, non-image payloads and decode errors never report success', async () => {
  const cases = [
    [1001202005, '', empty, 'emptyResult'],
    [1001202002, '', empty, 'platformError'],
    [987654, '', empty, 'platformError'],
    [0, 'general.video', image, 'invalidImage'],
    [0, 'general.image', empty, 'invalidImage'],
  ];
  for (const [code, type, buffer, reason] of cases) {
    const s = new Session(() => {}, async () => { assert.fail('must not decode invalid payload'); });
    s.begin('scan', '');
    await s.accept(code, type, buffer);
    assert.equal(s.snapshot().phase, 'failed');
    assert.equal(s.snapshot().reason, reason);
  }
  const s = new Session(() => {}, async () => { throw new Error('bad image'); });
  s.begin('photo', '');
  await s.accept(0, 'general.image', image);
  await s.accept(1001202005, '', empty);
  assert.equal(s.snapshot().reason, 'decodeFailed');
});

test('extra images cannot turn a one-image request into unbounded decoding', async () => {
  let resolve;
  const s = new Session(() => {}, () => new Promise(r => { resolve = r; }));
  s.begin('gallery', '');
  const first = s.accept(0, 'general.image', image);
  await s.accept(0, 'general.image', image);
  resolve();
  await first;
  assert.equal(s.snapshot().reason, 'imageLimit');
});

function nativeService(imageKit) {
  const native = {};
  const source = fs.readFileSync(path.join(__dirname,
    '../../entry/src/main/ets/services/local-genui/HarmonyCollaborationService.ets'), 'utf8');
  new Function('require', 'exports', ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS }
  }).outputText)(name => name.includes('ImageKit') ? { image: imageKit } :
    name.includes('LocalCollaborationSession') ? mod : {}, native);
  return native.HarmonyCollaborationService;
}

test('native receiver releases a late PixelMap without publishing it after unmount', async () => {
  let finishDecode;
  let sourceReleases = 0;
  let mapReleases = 0;
  const published = [];
  const Service = nativeService({ createImageSource: () => ({
    getImageInfo: async () => ({ size: { width: 4000, height: 3000 } }),
    createPixelMap: options => {
      assert.deepEqual(options.desiredSize, { width: 1600, height: 1200 });
      return new Promise(resolve => { finishDecode = resolve; });
    },
    release: async () => { sourceReleases++; },
  }) });
  const s = new Service(() => {}, map => published.push(map));
  s.session.begin('photo', '');
  const work = s.session.accept(0, 'general.image', image);
  await Promise.resolve();
  s.dispose();
  finishDecode({ release: async () => { mapReleases++; } });
  await work;
  assert.deepEqual(published, [undefined]);
  assert.equal(sourceReleases, 1);
  assert.equal(mapReleases, 1);
  assert.equal(s.session.snapshot().phase, 'closed');
});

test('successful native preview retains its map until disposal and releases its image source', async () => {
  let sourceReleases = 0;
  let mapReleases = 0;
  const map = { release: async () => { mapReleases++; } };
  const published = [];
  const Service = nativeService({ createImageSource: () => ({
    getImageInfo: async () => ({ size: { width: 320, height: 240 } }),
    createPixelMap: async () => map,
    release: async () => { sourceReleases++; },
  }) });
  const s = new Service(() => {}, picture => published.push(picture));
  s.session.begin('scan', '');
  await s.session.accept(0, 'general.image', image);
  await s.session.accept(1001202005, '', empty);
  assert.equal(s.session.snapshot().phase, 'completed');
  assert.equal(sourceReleases, 1);
  assert.equal(mapReleases, 0);
  assert.deepEqual(published, [map]);
  s.dispose();
  s.dispose();
  assert.equal(mapReleases, 1);
});
