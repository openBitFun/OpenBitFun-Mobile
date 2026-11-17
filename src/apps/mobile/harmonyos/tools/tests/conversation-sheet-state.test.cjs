const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const ROOT = path.join(__dirname, '../../entry/src/main/ets');
const cache = new Map();

function load(relative) {
  if (cache.has(relative)) return cache.get(relative);
  const source = fs.readFileSync(path.join(ROOT, relative + '.ets'), 'utf8')
    .replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const js = ts.transpileModule(source, {compilerOptions: {
    target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS
  }}).outputText;
  const exported = {};
  cache.set(relative, exported);
  new Function('require', 'exports', js)(name => {
    if (name.endsWith('RemoteLogger')) return {RemoteLogger: {info() {}}};
    if (name.endsWith('Encoding')) return {Encoding: {randomId: () => 'local-turn'}};
    if (name.endsWith('RemoteI18n')) return {RemoteI18n: {t: key => key, f2: (key, a, b) => `${key}:${a}:${b}`}};
    if (name.endsWith('ConversationRuntime')) return {requireRemoteRuntime: value => value, shortSessionId: value => value};
    if (!name.startsWith('.')) return {};
    return load(path.relative(ROOT, path.resolve(path.dirname(path.join(ROOT, relative)), name)));
  }, exported);
  return exported;
}


const {RemotePageState} = load('pages/state/RemotePageState');
const {ConversationViewState} = load('pages/state/ConversationViewState');
const {AppRoute} = load('pages/navigation/AppRouteContract');
function fixture() {
  const remote = new RemotePageState();
  remote.setActiveSession({sessionId: 'A', title: 'A', agentType: 'code'});
  const project = () => ConversationViewState.project(AppRoute.RemoteChat, remote, undefined, '');
  return {remote, project};
}

test('new compact/wide projections retain the same conversation sheet and full-text target', () => {
  const {project} = fixture();
  const compact = project();
  compact.sheetPresentation.open('remote:A:1', 'full_text', 'original text', 'turn-A');
  const wide = project();
  assert.notEqual(compact, wide);
  assert.equal(wide.sheetPresentation, compact.sheetPresentation);
  wide.sheetPresentation.synchronize('remote:A:1');
  assert.equal(wide.sheetPresentation.kind, 'full_text');
  assert.equal(wide.sheetPresentation.fullText, 'original text');
  assert.equal(wide.sheetPresentation.turnId, 'turn-A');
});

test('explicit dismissal is retained when the conversation view is rebuilt', () => {
  const {project} = fixture();
  project().sheetPresentation.open('remote:A:1', 'usage');
  project().sheetPresentation.close();
  assert.equal(project().sheetPresentation.kind, '');
});

test('a session change or clearing the active session cannot reopen the previous sheet', () => {
  const {remote, project} = fixture();
  project().sheetPresentation.open('remote:A:1', 'skills');
  remote.setActiveSession({sessionId: 'B', title: 'B', agentType: 'code'});
  assert.equal(project().sheetPresentation.kind, '');
  project().sheetPresentation.open('remote:B:2', 'usage');
  remote.clearActiveSession();
  assert.equal(project().sheetPresentation.kind, '');
});

test('another host/context generation clears full-text content even when the session ID is reused', () => {
  const {project} = fixture();
  const sheet = project().sheetPresentation;
  sheet.open('remote:A:1', 'full_text', 'private text', 'old-turn');
  sheet.synchronize('remote:A:2');
  assert.equal(sheet.kind, '');
  assert.equal(sheet.fullText, '');
  assert.equal(sheet.turnId, '');
});

test('skill filters survive a new view projection and reset only on dismissal or a context change', () => {
  const {project} = fixture();
  const original = project().sheetPresentation;
  original.open('remote:A:1', 'skills');
  original.skillPicker.query = 'review';
  original.skillPicker.filterId = 'custom';
  const remounted = project().sheetPresentation;
  remounted.synchronize('remote:A:1');
  assert.equal(remounted.kind, 'skills');
  assert.equal(remounted.skillPicker.query, 'review');
  assert.equal(remounted.skillPicker.filterId, 'custom');
  remounted.close();
  assert.equal(remounted.skillPicker.query, '');
  assert.equal(remounted.skillPicker.filterId, 'all');
});

test('sidebar details keep their selected device/session across host changes without changing the active session', () => {
  const {SessionDetailsState} = load('pages/state/SessionDetailsState');
  const {remote} = fixture();
  const details = new SessionDetailsState();
  const selected = {id: 'B', deviceId: 'peer-2', title: 'Read-only detail', agentType: 'code',
    status: 'idle', createdAt: '', updatedAt: '', messageCount: 2};
  details.open(selected);
  assert.equal(details.visible, true);
  assert.equal(details.session.deviceId, 'peer-2');
  assert.equal(details.session.id, 'B');
  assert.equal(remote.activeSession.sessionId, 'A');
  details.close();
  assert.equal(details.visible, false);
});
