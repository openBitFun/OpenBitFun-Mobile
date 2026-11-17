const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const root = path.join(__dirname, '../../entry/src/main/ets');
function load(name, dependencies) {
  const source = fs.readFileSync(path.join(root, name + '.ets'), 'utf8').replace(/@ObservedV2\s*|@Trace\s*/g, '');
  const js = ts.transpileModule(source, {compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS}}).outputText;
  const result = {};
  new Function('require', 'exports', js)(name => dependencies[name], result);
  return result;
}
const settle = () => new Promise(resolve => setImmediate(resolve));
function fixture() {
  const listeners = new Map();
  let status = 2;
  const orientation = {PORTRAIT: 1, AUTO_ROTATION_UNSPECIFIED: 12};
  const display = {
    FoldStatus: {FOLD_STATUS_UNKNOWN: 0, FOLD_STATUS_FOLDED: 2},
    getDefaultDisplaySync: () => ({width: 1080, height: 2444, densityPixels: 3.125}),
    isFoldable: () => true, getFoldStatus: () => status,
    on: (event, fn) => listeners.set(event, fn),
    off: (event, fn) => { if (listeners.get(event) === fn) listeners.delete(event); }
  };
  const {WindowOrientationService: Service} = load('services/WindowOrientationService', {
    '@kit.ArkUI': {display, window: {Orientation: orientation}},
    '@kit.BasicServicesKit': {deviceInfo: {deviceType: 'phone'}},
    './RemoteLogger': {RemoteLogger: {info() {}, warn() {}}}
  });
  const service = new Service();
  return {Service, service, listeners, change(value) { status = value; listeners.get('foldStatusChange')?.(value); }};
}
test('portrait lock distinguishes folded phone, expanded multi-fold and tablets', () => {
  const {Service} = fixture();
  assert.equal(Service.locksPortrait(true, 2, 'phone', 345), true);
  for (const status of [1, 3, 11, 12, 13, 21, 22, 23]) assert.equal(Service.locksPortrait(true, status, 'phone', 700), false);
  assert.equal(Service.locksPortrait(false, 0, 'phone', 345), true);
  assert.equal(Service.locksPortrait(false, 0, 'tablet', 800), false);
  assert.equal(Service.locksPortrait(true, 0, 'phone', 707), false);
  assert.equal(Service.locksPortrait(true, 0, 'phone', 345), true);
});
test('fold changes apply the latest preference serially without duplicate requests', async () => {
  const f = fixture(), calls = [], pending = [];
  f.service.start({setPreferredOrientation(value) { calls.push(value); return new Promise(resolve => pending.push(resolve)); }});
  f.change(1); f.service.refresh();
  assert.deepEqual(calls, [1]);
  pending.shift()(); await settle();
  assert.deepEqual(calls, [1, 12]);
  pending.shift()(); await settle();
  f.service.refresh(); assert.deepEqual(calls, [1, 12]);
  f.change(2); assert.deepEqual(calls, [1, 12, 1]);
  pending.shift()(); await settle(); f.service.stop();
  assert.equal(f.listeners.size, 0);
});
test('late completion from a destroyed window cannot mutate its replacement', async () => {
  const f = fixture(), calls = []; let oldResolve;
  f.service.start({setPreferredOrientation() { return new Promise(resolve => { oldResolve = resolve; }); }});
  f.service.stop(); f.change(1);
  f.service.start({async setPreferredOrientation(value) { calls.push(value); }});
  await settle(); oldResolve(); await settle();
  f.service.refresh(); await settle(); assert.deepEqual(calls, [12]);
  f.change(2); await settle(); assert.deepEqual(calls, [12, 1]);
  f.service.stop();
});
test('failed application retries on the next refresh without an infinite loop', async () => {
  const f = fixture(), calls = [];
  f.service.start({async setPreferredOrientation(value) { calls.push(value); if (calls.length === 1) throw Error('transient'); }});
  await settle(); assert.deepEqual(calls, [1]);
  f.service.refresh(); await settle(); assert.deepEqual(calls, [1, 1]);
  f.service.stop();
});
const {AppShellState} = load('pages/state/AppShellState', {
  '../navigation/AppRouteContract': {AppRoute: {RemoteHome: 'home'}},
  './SettingsSheetState': {SettingsSheetState: class {}}
});
test('unfolding transfers only an open compact drawer and keeps route/modal state', () => {
  const state = new AppShellState(); state.activeRoute = 'chat'; state.showSettings = true;
  state.setSidebarVisible(true);
  assert.equal(state.takeSidebarForWideLayout(false), false);
  assert.equal(state.showSidebar, true);
  assert.equal(state.takeSidebarForWideLayout(true), true);
  assert.equal(state.showSidebar, false);
  assert.equal(state.activeRoute, 'chat'); assert.equal(state.showSettings, true);
  state.setWideLayout(true);
  assert.equal(state.takeSidebarForWideLayout(true), false);
  state.setWideLayout(false);
  assert.equal(state.takeSidebarForWideLayout(true), false, 'closed phone drawer must not reveal wide pane');
  state.setSidebarVisible(true);
  assert.equal(state.takeSidebarForWideLayout(true), true);
});
