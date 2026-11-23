const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

function loadLocalGenUI(name, dependencies = {}) {
  const source = fs.readFileSync(path.join(__dirname, '../../entry/src/main/ets/services/local-genui', `${name}.ets`), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText;
  const exports = {};
  new Function('require', 'exports', code)(dependency => dependencies[dependency] || {}, exports);
  return exports;
}

const models = loadLocalGenUI('LocalGenUIModels');
const { LocalGenUIOwner, LocalStateSaveOutcome, migrateLocalState } = loadLocalGenUI('LocalGenUIOwner', { './LocalGenUIModels': models });
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../../entry/src/main/resources/rawfile/genui/runtime-manifest.json'), 'utf8'));
const required = ['actual-render', 'declared-interactions', 'save-reopen'];

class MemoryPort {
  constructor() { this.apps = new Map(); this.casFailures = 0; }
  async loadApp(id) { const record = this.apps.get(id); return record && JSON.parse(JSON.stringify(record)); }
  async insertApp(record) { if (this.apps.has(record.appId)) throw new Error('exists'); this.apps.set(record.appId, JSON.parse(JSON.stringify(record))); }
  async compareAndSwapApp(record, expected) {
    if (this.casFailures > 0) { this.casFailures -= 1; return false; }
    const current = this.apps.get(record.appId);
    if (!current || current.ownerRevision !== expected) return false;
    this.apps.set(record.appId, JSON.parse(JSON.stringify(record)));
    return true;
  }
}

const generation = (source, values = {}) => ({ ok: true, error: '', title: 'Todo', description: '', source, valuesJson: JSON.stringify(values) });
const verification = results => ({ mode: 'local-runtime', rendererRevision: manifest.rendererRevision, catalogHash: manifest.catalogHash, promptHash: manifest.promptHash, checks: Object.entries(results).map(([name, result]) => ({ name, result, detail: '' })), unverified: Object.entries(results).filter(([, r]) => r === 'unverified').map(([n]) => n), sourceHash: 'h', stateHash: 'h', verifiedAt: 't' });

async function newApp(port) {
  const owner = new LocalGenUIOwner(port, manifest, () => 't');
  const identity = owner.newIdentity('local-genui:app-1', 'call-1', 'Todo');
  const record = await owner.commitCandidate('local-genui:session-1', 'm1', identity, generation('root = Col([])', { name: 'Ada' }));
  return { owner, identity, record };
}

test('identity is bound from the generated manifest and refuses non-local ids', () => {
  const owner = new LocalGenUIOwner(new MemoryPort(), manifest);
  const identity = owner.newIdentity('local-genui:a', 'c', 'T');
  assert.equal(identity.libraryId, manifest.libraryId);
  assert.deepEqual(identity.designSpec, manifest.designSpec);
  assert.throws(() => owner.newIdentity('chat-123', 'c', 'T'), /non-local/);
});

test('unverified required checks keep the app displayable, never accepted', async () => {
  const port = new MemoryPort();
  const { owner, record } = await newApp(port);
  assert.equal(record.status, 'candidate');
  const verified = await owner.recordVerification(record.appId, 1, verification({ 'actual-render': 'passed', 'declared-interactions': 'unverified', 'save-reopen': 'passed' }), required);
  assert.equal(verified.status, 'displayable');
  assert.equal(verified.acceptedSourceRevision, 0);
  const accepted = await owner.recordVerification(record.appId, 1, verification({ 'actual-render': 'passed', 'declared-interactions': 'passed', 'save-reopen': 'passed' }), required);
  assert.equal(accepted.status, 'accepted');
  assert.equal(accepted.acceptedSourceRevision, 1);
});

test('state saves are CAS against the state revision', async () => {
  const port = new MemoryPort();
  const { owner, record } = await newApp(port);
  const saved = await owner.saveState(record.appId, 1, 1, JSON.stringify({ name: 'Grace' }));
  assert.equal(saved.outcome, LocalStateSaveOutcome.Saved);
  assert.equal(saved.record.stateRevision, 2);
  assert.equal(saved.record.userEdited, true);
  const conflict = await owner.saveState(record.appId, 1, 1, JSON.stringify({ name: 'Linus' }));
  assert.equal(conflict.outcome, LocalStateSaveOutcome.Conflict);
  assert.equal(JSON.parse(conflict.record.stateJson).name, 'Grace');
  const stale = await owner.saveState(record.appId, 9, 2, '{}');
  assert.equal(stale.outcome, LocalStateSaveOutcome.StaleSource);
  port.casFailures = 1;
  const raced = await owner.saveState(record.appId, 1, 2, JSON.stringify({ name: 'x' }));
  assert.equal(raced.outcome, LocalStateSaveOutcome.Conflict);
});

test('model source changes migrate compatible user state and block removals', async () => {
  assert.deepEqual(JSON.parse(migrateLocalState('{"a":1}', false, '{"b":"x"}').stateJson), { b: 'x' });
  assert.deepEqual(JSON.parse(migrateLocalState('{"a":1}', true, '{"a":5,"b":"x"}').stateJson), { a: 1, b: 'x' });
  assert.match(migrateLocalState('{"a":1}', true, '{"b":"x"}').reason, /removed/);
  assert.match(migrateLocalState('{"a":1}', true, '{"a":"1"}').reason, /changed type/);
  // Keys declared in the new OpenUI source (parser-reported) still exist.
  assert.deepEqual(JSON.parse(migrateLocalState('{"a":1,"n":"x"}', true, '{}', { a: 'number', n: 'null' }).stateJson), { a: 1, n: 'x' });
  assert.match(migrateLocalState('{"a":1}', true, '{}', { a: 'string' }).reason, /changed type/);

  const port = new MemoryPort();
  const { owner, identity, record } = await newApp(port);
  await owner.recordVerification(record.appId, 1, verification({ 'actual-render': 'passed', 'declared-interactions': 'unverified', 'save-reopen': 'passed' }), required);
  await owner.saveState(record.appId, 1, 1, JSON.stringify({ name: 'Grace' }));
  const candidate = await owner.commitCandidate('local-genui:session-1', 'm2', identity, generation('root = Row([])', { other: 1 }));
  assert.equal(candidate.status, 'candidate');
  assert.equal(JSON.parse(candidate.stateJson).name, 'Grace', 'the checker runs on the current state copy');
  const blocked = await owner.recordVerification(record.appId, 2, verification({ 'actual-render': 'passed', 'declared-interactions': 'unverified', 'save-reopen': 'passed' }), required, { other: 'number' });
  assert.equal(blocked.status, 'state_migration_required');
  assert.equal(JSON.parse(blocked.stateJson).name, 'Grace', 'user data is retained');
  const runnable = LocalGenUIOwner.runnableRevision(blocked);
  assert.equal(runnable.source, 'root = Col([])');
  assert.equal(runnable.status, 'displayable');

  const again = await owner.commitCandidate('local-genui:session-1', 'm3', identity, generation('root = Col([Text("v3")])', {}));
  const migrated = await owner.recordVerification(record.appId, again.sourceRevision, verification({ 'actual-render': 'passed', 'declared-interactions': 'unverified', 'save-reopen': 'passed' }), required, { name: 'null' });
  assert.equal(migrated.status, 'displayable');
  assert.equal(JSON.parse(migrated.stateJson).name, 'Grace');
});

test('a failed candidate restores the previous runnable revision as a new revision', async () => {
  const port = new MemoryPort();
  const { owner, identity, record } = await newApp(port);
  await owner.recordVerification(record.appId, 1, verification({ 'actual-render': 'passed', 'declared-interactions': 'unverified', 'save-reopen': 'passed' }), required);
  const candidate = await owner.commitCandidate('local-genui:session-1', 'm2', identity, generation('root = Broken(', { name: 'Ada' }));
  assert.equal(candidate.sourceRevision, 2);
  const failed = await owner.recordVerification(record.appId, 2, verification({ 'actual-render': 'failed' }), required);
  assert.equal(failed.status, 'displayable');
  assert.equal(failed.sourceContent, 'root = Col([])');
  assert.equal(failed.sourceRevision, 3);
  assert.match(failed.verificationJson, /failed/);
});

test('unknown libraries and schema versions stay retained but not runnable', async () => {
  const port = new MemoryPort();
  const { owner, record } = await newApp(port);
  const stored = { ...record, libraryRevision: 99 };
  port.apps.set(record.appId, stored);
  assert.equal(owner.isRunnable(stored), false);
  assert.equal((await owner.saveState(record.appId, 1, 1, '{}')).outcome, LocalStateSaveOutcome.Rejected);
  assert.equal(port.apps.get(record.appId).libraryRevision, 99, 'record is not rewritten');
  assert.equal(owner.isRunnable({ ...record, schemaVersion: 7 }), false);
});

const { nextLocalRepair } = loadLocalGenUI('LocalGenUIRepairPolicy', { './LocalGenUIModels': models });
test('automatic repair changes strategy across repeated diagnostics and skips infrastructure gaps', async () => {
  const port = new MemoryPort();
  const { owner, record } = await newApp(port);
  const failed = verification({ 'actual-render': 'failed', 'declared-interactions': 'unverified' });
  failed.checks[0].detail = 'Unknown function "@Period"';
  const first = nextLocalRepair(record, failed, 'root = Col([@Period()])');
  assert.equal(first.attempt, 1);
  assert.match(first.prompt, /@Period/);
  assert.match(first.prompt, /root = Col\(\[@Period\(\)\]\)/);
  assert.equal(await owner.recordRepairAttempt(record.appId, first.errorKey), true);
  const stored = await port.loadApp(record.appId);
  assert.equal(nextLocalRepair(stored, failed, 'x').attempt, 2, 'same diagnostics get a strategy change while budget remains');
  const other = verification({ 'actual-render': 'failed' });
  other.checks[0].detail = 'Unknown component Foo';
  assert.equal(nextLocalRepair(stored, other, 'x').attempt, 2);
  await owner.recordRepairAttempt(record.appId, 'k2');
  assert.equal(nextLocalRepair(await port.loadApp(record.appId), verification({ 'actual-render': 'failed' }), 'x').attempt, 3);
  await owner.recordRepairAttempt(record.appId, 'k3');
  assert.equal(nextLocalRepair(await port.loadApp(record.appId), verification({ 'actual-render': 'failed' }), 'x'), undefined, 'budget of three');
  assert.equal(nextLocalRepair(record, verification({ 'actual-render': 'unverified' }), 'x'), undefined, 'probe timeouts are not source defects');
});

const { LocalGenUIModelCatalog } = loadLocalGenUI('LocalGenUIModelCatalog');
test('a session keeps its model; a deleted model is reported, not replaced', () => {
  const a = { id: 'a', name: '', apiUrl: 'https://x', modelName: 'A', createdAt: '1' };
  const b = { id: 'b', name: 'Fast', apiUrl: 'https://x', modelName: 'B', createdAt: '2' };
  assert.equal(LocalGenUIModelCatalog.choose([a, b], 'b', 'a').model.id, 'b');
  assert.deepEqual(LocalGenUIModelCatalog.choose([a], 'b', 'a'), { missing: true });
  assert.equal(LocalGenUIModelCatalog.choose([a, b], '', 'b').model.id, 'b', 'new sessions follow the last choice');
  assert.equal(LocalGenUIModelCatalog.choose([a, b], '', 'gone').model.id, 'a');
  assert.deepEqual(LocalGenUIModelCatalog.choose([], '', ''), { missing: false });
  assert.equal(LocalGenUIModelCatalog.displayName(b), 'Fast');
  assert.equal(LocalGenUIModelCatalog.displayName(a), 'A');
  assert.equal(LocalGenUIModelCatalog.validate('ftp://x', 'm', 'k', false), 'settings.modelService.invalidUrl');
  assert.equal(LocalGenUIModelCatalog.validate('https://api.x', 'm', '', true), '');
  assert.equal(LocalGenUIModelCatalog.validate('https://api.x', 'm', '', false), 'settings.modelService.apiKeyRequired');
});

test('a failure recorded by another renderer returns to candidate; one from this renderer stays failed', async () => {
  const port = new MemoryPort();
  const { owner, record } = await newApp(port);
  const failedBy = renderer => ({ ...verification({ 'actual-render': 'failed', 'declared-interactions': 'unverified', 'save-reopen': 'passed' }), rendererRevision: renderer });
  const failed = await owner.recordVerification(record.appId, 1, failedBy(manifest.rendererRevision), required);
  assert.equal(failed.status, 'failed');
  assert.equal(await owner.reconsiderFailure(record.appId), undefined, 'same renderer: the verdict stands');
  const stored = await port.loadApp(record.appId);
  stored.verificationJson = JSON.stringify(failedBy('openbitfun.harmony.v1@3+older'));
  port.apps.set(record.appId, stored);
  const again = await owner.reconsiderFailure(record.appId);
  assert.equal(again.status, 'candidate');
  assert.equal(again.sourceContent, record.sourceContent, 'the source is kept');
  assert.equal(again.ownerRevision, stored.ownerRevision + 1);
});
