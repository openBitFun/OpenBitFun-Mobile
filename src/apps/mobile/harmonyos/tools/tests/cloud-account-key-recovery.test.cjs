const test = require('node:test');
const assert = require('node:assert/strict');
const { randomBytes } = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

function loadService(name, dependencies = {}) {
  const file = path.join(__dirname, '../../entry/src/main/ets/services', name + '.ets');
  const js = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
  }).outputText;
  const exports = {};
  new Function('require', 'exports', js)(key => dependencies[key], exports);
  return exports;
}

const legacyAlias = 'bitfun_cloud_account_session';
const previousSecret = randomBytes(32);
const previousSession = { masterKey: previousSecret.toString('base64'), userId: 'previous' };

function fixture() {
  // This stand-in copies bytes. Only the real-device test exercises encryption.
  const values = new Map([
    ['github_device_session_v1_cipher', Buffer.from(JSON.stringify(previousSession)).toString('base64')],
    ['github_device_session_v1_iv', randomBytes(16).toString('base64')],
  ]);
  const keys = new Set();
  const prefs = {
    get: async (key, fallback) => values.get(key) ?? fallback,
    put: async (key, value) => values.set(key, value),
    delete: async key => values.delete(key),
    flush: async () => {},
  };
  const huks = {
    HuksExceptionErrCode: { HUKS_ERR_CODE_ITEM_NOT_EXIST: 12000011 },
    HuksKeyPurpose: {}, HuksTag: {}, HuksKeyAlg: {}, HuksKeySize: {}, HuksCipherMode: {}, HuksKeyPadding: {},
    isKeyItemExist: async alias => keys.has(alias),
    generateKeyItem: async alias => keys.add(alias),
    initSession: async alias => {
      if (!keys.has(alias)) throw { code: 12000011 };
      return { handle: alias };
    },
    finishSession: async (_, options) => ({ outData: options.inData }),
  };
  const { CloudAccountSessionStore } = loadService('CloudAccountSessionStore', {
    '@kit.UniversalKeystoreKit': { huks },
    '@kit.ArkData': { preferences: { getPreferences: async () => prefs } },
    './HarmonyUpgradeIdentityContract': loadService('HarmonyUpgradeIdentityContract'),
    './RemoteLogger': { RemoteLogger: { warn() {} } },
    './OhosError': loadService('OhosError'),
    './Encoding': { Encoding: {
      randomBytes, bytesToBase64: b => Buffer.from(b).toString('base64'),
      base64ToBytes: s => Buffer.from(s, 'base64'), utf8ToBytes: s => Buffer.from(s),
      bytesToUtf8: b => Buffer.from(b).toString(),
    } },
  });
  async function open() {
    const store = new CloudAccountSessionStore();
    await store.init({});
    return store;
  }
  return { open, keys, values, huks };
}

test('an accessible legacy session keeps its key and device identity', async () => {
  const f = fixture();
  f.keys.add(legacyAlias);
  const store = await f.open();
  assert.deepEqual(await store.load(), previousSession);
  assert.deepEqual(Buffer.from(await store.deviceSecret()), previousSecret);
  assert.equal(f.values.has('active_key_generation'), false);
});

test('explicit sign-in recovers a missing key and preserves the previous encrypted records', async () => {
  const f = fixture();
  f.values.set('device_private_key_v1_cipher', 'old ciphertext');
  f.values.set('device_private_key_v1_iv', 'aXY=');
  const before = new Map(f.values);
  const store = await f.open();
  await assert.rejects(store.load(), /missing/);
  assert.deepEqual(f.values, before);
  const [identity, concurrent] = await Promise.all([store.deviceSecret(), store.deviceSecret()]);
  assert.equal(identity.length, 32);
  assert.deepEqual(identity, concurrent);
  assert.equal(await store.load(), undefined);
  const session = { masterKey: Buffer.from(identity).toString('base64'), userId: 'new' };
  await store.save(session);
  const reopened = await f.open();
  assert.deepEqual(await reopened.deviceSecret(), identity);
  assert.deepEqual(await reopened.load(), session);
  await reopened.clear();
  assert.equal(await reopened.load(), undefined);
  for (const [k, v] of before) assert.equal(f.values.get(k), v);
});

test('transient errors and contradictory key lookups leave the existing identity in place', async () => {
  for (const [initError, exists] of [[12000009, false], [12000011, true], [12000011, 'unavailable']]) {
    const f = fixture();
    f.huks.initSession = async () => { throw { code: initError }; };
    f.huks.isKeyItemExist = async () => {
      if (exists === 'unavailable') throw { code: 12000009 };
      return exists;
    };
    const before = new Map(f.values);
    const store = await f.open();
    await assert.rejects(store.deviceSecret());
    assert.deepEqual(f.values, before);
    assert.equal(f.keys.size, 0);
  }
});
