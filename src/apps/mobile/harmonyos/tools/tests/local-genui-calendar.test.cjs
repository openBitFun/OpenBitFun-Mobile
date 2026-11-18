const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const exportsObject = {};
const source = fs.readFileSync(path.join(__dirname, '../../entry/src/main/ets/services/local-genui/LocalGenUICalendarActions.ets'), 'utf8');
new Function('exports', ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText)(exportsObject);
const { LocalGenUICalendarActions } = exportsObject;
function store() {
  const rows = new Map();
  return {
    calendarReceipts: async app => rows.get(app) || [],
    saveCalendarReceipt: async (app, payload) => rows.set(app, [...(rows.get(app) || []), payload]),
  };
}
test('double clicks share one pending OS write; receipts survive a new owner and distinguish apps/events', async () => {
  const receipts = store();
  const owner = new LocalGenUICalendarActions(receipts);
  let finish;
  let writes = 0;
  const execute = () => { writes++; return new Promise(resolve => { finish = resolve; }); };
  const event = { event: { title: 'Meeting', startTime: 123, endTime: 456 } };
  const first = owner.create('local-genui:a', event, execute);
  const second = owner.create('local-genui:a', event, execute);
  await Promise.resolve();
  assert.equal(writes, 1);
  finish('');
  assert.deepEqual(await Promise.all([first, second]), ['', '']);
  const reopened = new LocalGenUICalendarActions(receipts);
  const add = async () => { writes++; return ''; };
  await reopened.create('local-genui:a', event, add);
  assert.equal(writes, 1);
  await reopened.create('local-genui:a', { event: { title: 'Different' } }, add);
  await reopened.create('local-genui:b', event, add);
  assert.equal(writes, 3);
});
test('denial, platform rejection and unreadable receipts do not become success and allow retry', async () => {
  const receipts = store();
  const owner = new LocalGenUICalendarActions(receipts);
  let writes = 0;
  const denied = await owner.create('a', {}, async () => { writes++; return 'permission denied'; });
  assert.equal(denied, 'permission denied');
  assert.deepEqual(await receipts.calendarReceipts('a'), []);
  assert.equal(await owner.create('a', {}, async () => { throw new Error('OS failed'); }), 'Error: OS failed');
  assert.equal(await owner.create('a', {}, async () => { writes++; return ''; }), '');
  assert.equal(writes, 2);
  const broken = new LocalGenUICalendarActions({ ...receipts, calendarReceipts: async () => { throw new Error('storage unavailable'); } });
  assert.match(await broken.create('b', {}, async () => { assert.fail('must not write without checking receipts'); }), /storage unavailable/);
});
