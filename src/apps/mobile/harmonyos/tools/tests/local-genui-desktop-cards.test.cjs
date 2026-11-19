const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const ts = require('typescript');

const main = path.join(__dirname, '../../entry/src/main');

function load(file, dependencies = {}) {
  const source = fs.readFileSync(path.join(main, 'ets', file), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText;
  const exports = {};
  new Function('require', 'exports', code)(dependency => dependencies[dependency] || {}, exports);
  return exports;
}

const models = load('services/local-genui/LocalGenUIModels.ets');
const cards = load('services/local-genui/LocalGenUIDesktopCards.ets', { './LocalGenUIModels': models });
const { LocalGenUIDesktopCards, LocalGenUIDesktopCardState } = cards;
const { LocalGenUILaunchInbox } = load('services/local-genui/LocalGenUILaunchInbox.ets');

/** Node-backed `fileIo` with the calls the store uses. */
function fakeFileIo() {
  const open = new Map();
  let next = 100;
  return {
    open,
    OpenMode: { READ_ONLY: 0, WRITE_ONLY: 1, CREATE: 64, TRUNC: 512 },
    accessSync: p => fs.existsSync(p),
    mkdirSync: p => fs.mkdirSync(p, { recursive: true }),
    listFileSync: p => fs.readdirSync(p),
    readTextSync: p => fs.readFileSync(p, 'utf8'),
    openSync(p, mode) {
      if (!(mode & 64) && !fs.existsSync(p)) throw new Error('ENOENT');
      const fd = next++;
      open.set(fd, p);
      if (mode & 64) fs.writeFileSync(p, '');
      return { fd };
    },
    writeSync(fd, text) { fs.appendFileSync(open.get(fd), text); },
    closeSync(file) { open.delete(typeof file === 'number' ? file : file.fd); },
    renameSync: (a, b) => fs.renameSync(a, b),
    unlinkSync: p => fs.unlinkSync(p)
  };
}

function storeWith(updates, failures = new Map()) {
  const fileIo = fakeFileIo();
  const formKit = {
    formBindingData: { createFormBindingData: obj => ({ data: obj }) },
    formProvider: {
      async updateForm(formId, binding) {
        if (failures.has(formId)) throw { code: failures.get(formId) };
        updates.push({ formId, data: binding.data, openFds: [...fileIo.open.keys()] });
      }
    }
  };
  const { LocalGenUIDesktopCardStore } = load('services/local-genui/LocalGenUIDesktopCardStore.ets', {
    '@kit.CoreFileKit': { fileIo },
    '@kit.FormKit': formKit,
    './LocalGenUIDesktopCards': cards
  });
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'genui-cards-'));
  return { store: new LocalGenUIDesktopCardStore(dir), dir, fileIo };
}

test('card taps and add wants only yield local app ids', () => {
  assert.equal(LocalGenUIDesktopCards.launchAppId({ params: JSON.stringify({ openbitfunLocalGenUIApp: 'local-genui:app-1' }) }), 'local-genui:app-1');
  assert.equal(LocalGenUIDesktopCards.launchAppId({ openbitfunLocalGenUIApp: 'local-genui:app-2' }), 'local-genui:app-2');
  assert.equal(LocalGenUIDesktopCards.launchAppId({ params: JSON.stringify({ openbitfunLocalGenUIApp: 'session-remote' }) }), '');
  assert.equal(LocalGenUIDesktopCards.launchAppId({ params: '{broken' }), '');
  assert.equal(LocalGenUIDesktopCards.launchAppId(undefined), '');
  assert.equal(LocalGenUIDesktopCards.launchAppId({ openbitfunLocalGenUIApp: 'local-genui:' }), '');
  const want = LocalGenUIDesktopCards.addWant('com.example.app', 'local-genui:app-1');
  assert.equal(want.abilityName, 'LocalGenUIFormAbility');
  assert.equal(want.parameters['ohos.extra.param.key.form_name'], 'local_genui_app');
  assert.equal(want.parameters['ohos.extra.param.key.form_dimension'], 2);
  assert.equal(LocalGenUIDesktopCards.appIdOfAddWant(want.parameters), 'local-genui:app-1');
  assert.equal(LocalGenUIDesktopCards.appIdOfAddWant({ openbitfunLocalGenUIAppId: 'other' }), '');
});

test('card data covers pending, ready, and deleted apps', () => {
  const app = { appId: 'local-genui:a', title: '番茄钟', thumbnailPath: '/f/thumbnails/local-genui_a-17.jpg', available: true, updatedAt: 't' };
  assert.equal(LocalGenUIDesktopCards.cardData('f1', '', undefined, false).state, LocalGenUIDesktopCardState.Pending);
  assert.equal(LocalGenUIDesktopCards.cardData('f1', 'local-genui:a', undefined, false).state, LocalGenUIDesktopCardState.Pending);
  const ready = LocalGenUIDesktopCards.cardData('f1', 'local-genui:a', app, true);
  assert.equal(ready.state, 'ready');
  assert.equal(ready.initial, '番');
  assert.equal(ready.imageName, 'genui_local-genui_a-17');
  assert.equal(LocalGenUIDesktopCards.cardData('f1', 'local-genui:a', app, false).imageName, '');
  const gone = LocalGenUIDesktopCards.cardData('f1', 'local-genui:a', { ...app, available: false }, true);
  assert.equal(gone.state, 'missing');
  assert.equal(gone.imageName, '');
});

test('store binds forms, pushes previews, and keeps deleted apps visible as missing', async () => {
  const updates = [];
  const { store, dir, fileIo } = storeWith(updates);
  const thumb = path.join(dir, 'local-genui_a-1.jpg');
  fs.writeFileSync(thumb, 'jpg');
  const app = { appId: 'local-genui:a', title: 'Todo', thumbnailPath: thumb, available: true, updatedAt: 't' };

  // Nothing bound and nothing shown yet: publish leaves no files behind.
  await store.publish(app);
  assert.equal(fs.existsSync(path.join(dir, 'local-genui/desktop-cards/apps')), false);

  store.saveApp(app);
  store.bind('101', 'local-genui:a');
  store.bind('102', 'local-genui:a');
  store.bind('103', 'remote-session');
  assert.deepEqual(store.formsOf('local-genui:a').sort(), ['101', '102']);
  assert.equal(store.appOf('103'), '');
  assert.equal(store.textData('101').title, 'Todo');
  assert.equal(store.textData('101').imageName, '');

  assert.equal(await store.refresh('101'), true);
  const pushed = updates.at(-1);
  assert.equal(pushed.data.state, 'ready');
  assert.equal(Object.keys(pushed.data.formImages)[0], pushed.data.imageName);
  assert.equal(pushed.openFds.length, 1, 'the preview fd is open while the update is sent');
  assert.equal(fileIo.open.size, 0, 'and closed afterwards');

  updates.length = 0;
  await store.publish({ ...app, available: false, thumbnailPath: '' });
  assert.equal(updates.length, 2);
  updates.forEach(u => { assert.equal(u.data.state, 'missing'); assert.equal(u.data.formImages, undefined); });

  store.unbind('102');
  assert.deepEqual(store.formsOf('local-genui:a'), ['101']);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('a card the launcher already removed drops its binding', async () => {
  const updates = [];
  const { store, dir } = storeWith(updates, new Map([['201', 16501001], ['202', 16500050]]));
  store.bind('201', 'local-genui:a');
  store.bind('202', 'local-genui:a');
  assert.equal(await store.refresh('201'), false);
  assert.equal(await store.refresh('202'), false);
  assert.deepEqual(store.formsOf('local-genui:a'), ['202'], 'only a missing form id is unbound');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('a staged add is claimed once, by the next card, within its window', () => {
  const { store, dir } = storeWith([]);
  store.stagePendingAdd('local-genui:a', 1000);
  assert.equal(store.claimPendingAdd(5000), 'local-genui:a');
  assert.equal(store.claimPendingAdd(5000), '', 'claimed only once');
  store.stagePendingAdd('local-genui:b', 1000);
  assert.equal(store.claimPendingAdd(1000 + 61000), '', 'a stale menu does not bind a later picker card');
  assert.equal(store.claimPendingAdd(1000 + 61000), '', 'and is cleared');
  store.stagePendingAdd('remote-session', 1000);
  assert.equal(store.claimPendingAdd(2000), '');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('card host binds from the staged add when the launcher drops want parameters', () => {
  const ability = fs.readFileSync(path.join(main, 'ets/genuiform/LocalGenUIFormAbility.ets'), 'utf8');
  assert.match(ability, /claimPendingAdd\(\)/);
});

test('mini app menus omit the desktop card export', () => {
  for (const file of ['LocalGenUISurface.ets', 'MiniAppGallery.ets']) {
    const source = fs.readFileSync(path.join(main, 'ets/pages/components', file), 'utf8');
    assert.doesNotMatch(source, /AddFormMenuItem|localGenui\.addToDesktop|prepareDesktopCard/);
  }
});

test('launch inbox parks a cold-start id until the page subscribes', () => {
  const seen = [];
  LocalGenUILaunchInbox.deliver('local-genui:cold');
  LocalGenUILaunchInbox.subscribe(id => seen.push(id));
  LocalGenUILaunchInbox.deliver('local-genui:warm');
  LocalGenUILaunchInbox.unsubscribe();
  LocalGenUILaunchInbox.subscribe(id => seen.push(`again:${id}`));
  LocalGenUILaunchInbox.unsubscribe();
  assert.deepEqual(seen, ['local-genui:cold', 'local-genui:warm']);
});

test('manifest, form config, card page, and copy stay in step', () => {
  const module = fs.readFileSync(path.join(main, 'module.json5'), 'utf8');
  assert.match(module, /"name": "LocalGenUIFormAbility"[\s\S]*?"srcEntry": "\.\/ets\/genuiform\/LocalGenUIFormAbility\.ets"[\s\S]*?"type": "form"[\s\S]*?"resource": "\$profile:local_genui_form_config"/);
  const config = JSON.parse(fs.readFileSync(path.join(main, 'resources/base/profile/local_genui_form_config.json'), 'utf8'));
  const form = config.forms[0];
  assert.equal(form.name, 'local_genui_app');
  assert.ok(form.supportDimensions.includes('2*2'));
  assert.ok(fs.existsSync(path.join(main, form.src)));
  const page = fs.readFileSync(path.join(main, form.src), 'utf8');
  assert.ok(page.includes(`'openbitfunLocalGenUIApp'`), 'card tap uses the launch parameter EntryAbility reads');
  for (const key of ['appId', 'state', 'title', 'initial', 'imageName']) {
    assert.ok(page.includes(`@LocalStorageProp('${key}')`), `card binds ${key}`);
  }
  const ability = fs.readFileSync(path.join(main, 'ets/entryability/EntryAbility.ets'), 'utf8');
  assert.match(ability, /onNewWant\(/);
  assert.match(ability, /LocalGenUIDesktopCards\.launchAppId/);
  const keys = ['genui_card_name', 'genui_card_desc', 'genui_card_pending', 'genui_card_missing',
    'localGenui_addToDesktop', 'localGenui_addedToDesktop', 'localGenui_addToDesktopFailed', 'localGenui_appActions'];
  for (const locale of ['zh_CN', 'en_US']) {
    const names = new Set(JSON.parse(fs.readFileSync(path.join(main, `resources/${locale}/element/string.json`), 'utf8')).string.map(s => s.name));
    keys.forEach(key => assert.ok(names.has(key), `${locale} has ${key}`));
  }
});
