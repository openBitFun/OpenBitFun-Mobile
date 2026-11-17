const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const root = path.resolve(__dirname, '../../entry/src/main');
function load(name, deps = {}) {
  const source = fs.readFileSync(path.join(root, 'ets', name + '.ets'), 'utf8');
  const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText;
  const exported = {};
  new Function('require', 'exports', js)(name => deps[name] || {}, exported);
  return exported;
}
const network = load('services/NetworkErrorPolicy');
for (const locale of ['zh_CN', 'en_US']) {
  const catalog = new Map(JSON.parse(fs.readFileSync(path.join(root, 'resources', locale, 'element/string.json'))).string.map(e => [e.name, e.value]));
  const t = key => { const value = catalog.get(key.replaceAll('.', '_')); assert.ok(value, key); return value; };
  const { ConnectionErrorPolicy: policy } = load('services/ConnectionErrorPolicy', {
    './NetworkErrorPolicy': network,
    '../i18n/RemoteI18n': { RemoteI18n: {
      t, textEquals: (key, text) => t(key) === text,
      textContains: (key, text) => text.includes(t(key)),
      textHasTemplatePrefix: (key, text) => text.startsWith(t(key).split('%1$s')[0]),
    } },
  });
  test(`${locale}: HTTP SDK errors retain diagnostics but display actionable localized text`, () => {
    for (const [code, key] of [[2300006,'account.errorNetwork'], [2300007,'account.errorNetwork'], [2300028,'account.errorTimeout'], [2300035,'account.errorSecureConnection'], [2300060,'account.errorSecureConnection']]) {
      const raw = `Account transport failed (code=${code}).`;
      const structured = Object.assign(new Error(raw), { code });
      for (const error of [structured, { code }, new Error(raw)]) {
        assert.equal(policy.errorText(error), t(key));
        assert.equal(policy.failureKindFor(policy.errorText(error)), 'network');
      }
      assert.equal(structured.message, raw);
      assert.equal(structured.code, code);
    }
  });
  test(`${locale}: uncertain delivery is distinct from a request never submitted`, () => {
    for (const raw of ['RPC acknowledgement timed out; delivery outcome is unknown', 'Relay connection lost; delivery outcome is unknown']) {
      assert.equal(policy.errorText(new Error(raw)), t('errors.deliveryUnknown'));
    }
    assert.equal(policy.errorText(new Error('Relay disconnected; request was not submitted')), t('account.errorNetwork'));
    assert.equal(policy.errorText(new Error('Remote transport is not connected.')), t('account.errorNetwork'));
    assert.equal(policy.errorText(new Error('Remote health probe timed out')), t('account.errorTimeout'));
  });
  test(`${locale}: auth/server failures do not expose response bodies or turn into network failures`, () => {
    for (const [statusCode, key] of [[401,'remote.settings.accountExpired'], [429,'account.errorRateLimited'], [500,'errors.serviceUnavailable']]) {
      assert.equal(policy.errorText(Object.assign(new Error('internal response body'), { statusCode })), t(key));
    }
    assert.equal(policy.errorText(new Error('Relay codec timed out')), 'Relay codec timed out');
    assert.equal(policy.errorText(new Error('File changed during transfer')), 'File changed during transfer');
    assert.equal(policy.errorText(new Error(t('errors.accountPasswordRequired'))), t('errors.accountPasswordRequired'));
  });
}
const { AccountLoginErrorPolicy } = load('pages/policy/AccountLoginErrorPolicy', { '../../services/NetworkErrorPolicy': network });
test('sign-in uses the same network classification and protects unknown exceptions', () => {
  assert.equal(AccountLoginErrorPolicy.messageKey({ code: 2300006 }), 'account.errorNetwork');
  assert.equal(AccountLoginErrorPolicy.messageKey(new Error('raw SDK details')), 'remote.settings.accountLoginFailed');
});
