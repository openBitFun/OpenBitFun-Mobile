const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

const services = path.join(__dirname, '../../entry/src/main/ets/services/local-genui');
function load(name, dependencies = {}) {
  const source = fs.readFileSync(path.join(services, `${name}.ets`), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText;
  const exports = {};
  new Function('require', 'exports', code)(dependency => dependencies[dependency] || {}, exports);
  return exports;
}

const editMode = load('LocalGenUIEditMode');
const models = load('LocalGenUIModels');
const repair = load('LocalGenUIRepairPolicy', { './LocalGenUIModels': models, './LocalGenUIEditMode': editMode });

test('edit-mode rules are lang-core\'s own section, verbatim', () => {
  const langCore = require.resolve('@openuidev/lang-core', { paths: [path.join(__dirname, '../../genui-runtime')] });
  const dist = fs.readFileSync(langCore.replace(/index\.(c|m)?js$/, 'index.mjs'), 'utf8');
  const section = dist.match(/function editModeSection\(\) \{\n\treturn `([\s\S]*?)`;\n\}/)[1];
  assert.equal(editMode.OPENUI_EDIT_MODE_RULES, section);
});

test('a follow-up asks for a patch over the running source and allows a rewrite on request', () => {
  const prompt = editMode.LocalGenUIEditMode.followUp('把对手改成客队', '计分板', 'root = Page([board])', '{"match":null}');
  assert.match(prompt, /^把对手改成客队/);
  assert.match(prompt, /edit mode/);
  assert.match(prompt, /complete program only when the person asks for a new version/);
  assert.ok(prompt.includes(editMode.OPENUI_EDIT_MODE_RULES));
  assert.ok(prompt.includes('root = Page([board])'));
});

test('a repair asks for a patch over the failed source', () => {
  const record = { repairAttempts: 0, repairErrorKeys: [], stateJson: '{}' };
  const verification = { checks: [{ name: 'actual-render', result: 'failed', detail: 'unknown component Foo' }] };
  const request = repair.nextLocalRepair(record, verification, 'root = Page([x])\nx = Foo()');
  assert.ok(request);
  assert.match(request.prompt, /edit mode/);
  assert.ok(request.prompt.includes(editMode.OPENUI_EDIT_MODE_RULES));
  assert.ok(request.prompt.endsWith('root = Page([x])\nx = Foo()'));
});

test('the controller merges a patch on the edited app before the owner commits it', () => {
  const controller = fs.readFileSync(path.join(services, 'LocalGenUISessionController.ets'), 'utf8');
  const merge = controller.indexOf('this.bridge.merge(editBase');
  assert.ok(merge > 0 && merge < controller.indexOf('this.owner.commitCandidate(sessionId'), 'merge precedes the commit');
  assert.match(controller, /base: failedSource/, 'a repair patches the failed candidate the checks measured');
  assert.match(controller, /event\.identity\.appId === target\.appId \? editBase : ''/, 'a new app streams without a base');
});
