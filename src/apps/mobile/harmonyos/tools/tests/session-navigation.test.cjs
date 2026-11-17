const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const root = path.join(__dirname, '../../entry/src/main/ets');
const modules = new Map();
function load(name) {
  if (name === 'i18n/RemoteI18n') return {};
  if (modules.has(name)) return modules.get(name);
  const source = fs.readFileSync(path.join(root, name + '.ets'), 'utf8').replace(/@ObservedV2\s*|@Trace\s*/g, '');
  const out = {};
  modules.set(name, out);
  const js = ts.transpileModule(source, {compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS}}).outputText;
  new Function('require', 'exports', js)(dep => load(path.posix.normalize(path.posix.join(path.posix.dirname(name), dep))), out);
  return out;
}
const {RecentSessionPolicy} = load('pages/policy/RecentSessionPolicy');
const {WorkspacePathPresentation} = load('pages/policy/WorkspacePathPresentation');
const {ConversationHeaderPolicy} = load('pages/policy/ConversationHeaderPolicy');
const {ChatSurface} = load('pages/state/ChatSurface');
const {SessionActivityObserver, SessionActivityReducer} = load('services/SessionActivityObserver');
const {SessionActivityState} = load('pages/state/SessionActivityState');
const row = (id, updatedAt, extra={}) => ({id, deviceId:'host', title:id, updatedAt, createdAt:'', status:'idle', ...extra});

test('recent uses host activity before slicing, deduplicates within device and preserves input', () => {
  const rows = [row('old','1700000000'), row('new','1700000002000'), row('middle','2023-11-14T22:13:21Z'),
    row('new','1690000000'), row('new','1700000003',{deviceId:'other'}), row('archived','1900000000',{status:'archived'})];
  assert.deepEqual(RecentSessionPolicy.rows(rows,3).map(r=>[r.deviceId,r.id]), [['other','new'],['host','new'],['host','middle']]);
  assert.equal(rows[0].id,'old');
  assert.deepEqual(RecentSessionPolicy.rows([row('invalid','oops'),row('created','',{createdAt:'1700000000'})],2).map(r=>r.id),['created','invalid']);
});
test('workspace subtitles preserve host paths and distinguish SSH even for localhost connections', () => {
  assert.equal(WorkspacePathPresentation.label('/Users/me/project'), '/Users/me/project');
  assert.equal(WorkspacePathPresentation.label('C:\\work\\repo'), 'C:\\work\\repo');
  assert.equal(WorkspacePathPresentation.label('/repo',{path:'/srv/repo',remoteSshHost:'build',remoteConnectionId:'saved'}), 'build:/srv/repo');
  assert.equal(WorkspacePathPresentation.label('/repo',{path:'/repo',remoteSshHost:'localhost'}), '/repo');
  assert.equal(WorkspacePathPresentation.label('/repo',{path:'/repo',remoteSshHost:'localhost',remoteConnectionId:'tunnel'}), 'localhost:/repo');
  assert.equal(WorkspacePathPresentation.label('',undefined,'Project'), 'Project');
  assert.equal(ConversationHeaderPolicy.present(ChatSurface.Remote,'Title','/repo','main',true).subtitle,'/repo');
});
function event(sessionId, status, revision=1, extra={}) {
  return {session_id:sessionId,event:'session-record',payload:{sessionId,id:'turn/t',revision,
    turn:{sessionId,turnId:'t',turnIndex:1,status,timestamp:1700000000000},...extra}};
}
test('activity follows authoritative turns, rejects stale child headers and handles rollback tombstones', () => {
  const r = new SessionActivityReducer();
  r.apply(event('a','inprogress'));
  assert.equal(r.snapshot('host','a').status,'running');
  r.apply(event('a','completed',2));
  r.apply(event('a','inprogress',9,{id:'item/x',round:{id:'r'}}));
  assert.equal(r.snapshot('host','a').status,'idle');
  r.apply(event('a','error',3));
  assert.equal(r.snapshot('host','a').status,'failed');
  r.apply(event('a','completed',4,{deleted:true}));
  r.apply(event('a','inprogress',3));
  assert.equal(r.snapshot('host','a').status,'unknown');
});
function fixture() {
  const streams = [];
  const state = new SessionActivityState();
  const observer = new SessionActivityObserver({subscribeSession(id, callbacks) {
    const stream = {id,callbacks,closed:false,close(){this.closed=true;},isClosed(){return this.closed;}};
    streams.push(stream); return stream;
  }}, activity=>state.update(activity), ()=>state.clear());
  return {observer,streams,state};
}
test('switching away keeps the running session observed, completion clears it without reopening', async () => {
  const f=fixture(); f.observer.sync('host',['a','b']);
  const a=f.streams[0], b=f.streams[1];
  await a.callbacks.onEvent(event('a','inprogress')); await a.callbacks.onCaughtUp();
  f.observer.sync('host',['b']);
  await b.callbacks.onEvent(event('b','completed')); await b.callbacks.onCaughtUp();
  assert.equal(a.closed,false); assert.equal(f.state.running('host','a'),true);
  assert.equal(f.state.running('host','b'),false);
  await a.callbacks.onEvent(event('a','completed',2)); await a.callbacks.onCaughtUp();
  assert.equal(f.state.running('host','a'),false);
  f.observer.stop();
});
test('disconnect, epoch reset and target replacement cannot leave a stale green dot', async () => {
  const f=fixture(); f.observer.sync('old',['a']); const old=f.streams[0];
  await old.callbacks.onEvent(event('a','inprogress')); await old.callbacks.onCaughtUp();
  old.callbacks.onError(Error('offline')); assert.equal(f.state.running('old','a'),false);
  await old.callbacks.onGap(); await old.callbacks.onCaughtUp();
  assert.equal(f.state.get('old','a').status,'unknown');
  f.observer.sync('new',['a']);
  await old.callbacks.onEvent(event('a','inprogress',2)); await old.callbacks.onCaughtUp();
  assert.equal(old.closed,true); assert.equal(f.state.get('old','a'),undefined);
  await f.streams[1].callbacks.onEvent(event('a','interrupted')); await f.streams[1].callbacks.onCaughtUp();
  assert.equal(f.state.running('new','a'),false);
  f.observer.stop(); assert.deepEqual(f.state.entries,[]);
});
const {RecentSessionCatalog} = load('services/RecentSessionCatalog');
test('recent catalog includes unopened workspaces, keeps failed branches and fences target switches', async () => {
  let fail=false, pending;
  const publications=[];
  const source={async list(workspace, limit) {
    assert.equal(limit,5);
    if(workspace.path==='/slow') return new Promise(resolve=>{pending=resolve;});
    if(fail && workspace.path==='/b') throw Error('offline');
    return [row(workspace.path,workspace.path==='/b'?'1700000002':'1700000001')];
  }};
  const catalog=new RecentSessionCatalog(source, rows=>publications.push(rows));
  await catalog.refresh('host',[{path:'/a'},{path:'/b'}]);
  assert.deepEqual(RecentSessionPolicy.rows(publications.at(-1),5).map(r=>r.id),['/b','/a']);
  fail=true;
  await assert.rejects(catalog.refresh('host',[{path:'/a'},{path:'/b'}]), /offline/);
  assert.equal(publications.at(-1).length,2);
  const old=catalog.refresh('host',[{path:'/slow'}]);
  await catalog.refresh('new',[{path:'/a'}]);
  pending([row('old','1900000000')]); await old;
  assert.deepEqual(publications.at(-1).map(r=>[r.deviceId,r.id]),[['new','/a']]);
});
