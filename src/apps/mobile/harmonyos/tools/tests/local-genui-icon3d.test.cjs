const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

const file = path.join(__dirname, '../../entry/src/main/ets/services/local-genui/LocalGenUIIcon3DStore.ets');
const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText;
const moduleExports = {};
new Function("require", "exports", code)(() => ({}), moduleExports);
const { LocalGenUIIcon3DStore, LOCAL_GENUI_ICON3D_ROOT, LOCAL_GENUI_ICON3D_COMMIT } = moduleExports;
const index = require('../../genui-runtime/src/components/vendor/fluent-emoji-3d-index.json');

test('the host serves the same pinned Fluent commit the runtime index names', () => {
  assert.equal(LOCAL_GENUI_ICON3D_COMMIT, index.sha);
  const runtime = fs.readFileSync(path.join(__dirname, '../../entry/src/main/resources/rawfile/genui/runtime/runtime.js'), 'utf8');
  assert.ok(runtime.includes(LOCAL_GENUI_ICON3D_ROOT), 'the runtime bundle asks the host address');
  const html = fs.readFileSync(path.join(__dirname, '../../entry/src/main/resources/rawfile/genui/runtime/index.html'), 'utf8');
  assert.match(html, new RegExp(`img-src data: blob: ${LOCAL_GENUI_ICON3D_ROOT.replace(/\/fluent-emoji\/$/, '').replace(/\./g, '\\.')};`));
});

test('only index-shaped asset paths at the pinned commit are served', () => {
  const url = p => LOCAL_GENUI_ICON3D_ROOT + LOCAL_GENUI_ICON3D_COMMIT + '/' + p.split('/').map(encodeURIComponent).join('/');
  for (const asset of Object.values(index.icons)) {
    assert.equal(LocalGenUIIcon3DStore.assetPath(url(asset)), asset, asset);
  }
  assert.equal(LocalGenUIIcon3DStore.assetPath(url('Badminton/3D/badminton_3d.png')), 'Badminton/3D/badminton_3d.png');
  assert.equal(LocalGenUIIcon3DStore.assetPath(LOCAL_GENUI_ICON3D_ROOT + '0'.repeat(40) + '/Badminton/3D/badminton_3d.png'), '', 'other commits');
  assert.equal(LocalGenUIIcon3DStore.assetPath(url('../../secret/3D/x_3d.png')), '', 'traversal');
  assert.equal(LocalGenUIIcon3DStore.assetPath(url('Badminton/3D/badminton_3d.png') + '?x=1'), '', 'queries');
  assert.equal(LocalGenUIIcon3DStore.assetPath(url('Badminton/metadata.json')), '', 'non-picture files');
  assert.equal(LocalGenUIIcon3DStore.assetPath('https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@x/assets/a/3D/a_3d.png'), '', 'other hosts');
});

const animatedIndex = require('../../genui-runtime/src/components/vendor/fluent-emoji-animated-index.json');
const { LOCAL_GENUI_ICON3D_ANIMATED_COMMIT } = moduleExports;

test('animated cover pictures come from the pinned animated commit and match a static picture', () => {
  assert.equal(LOCAL_GENUI_ICON3D_ANIMATED_COMMIT, animatedIndex.sha);
  const runtime = fs.readFileSync(path.join(__dirname, '../../genui-runtime/src/components/fluentEmojiAnimated.ts'), 'utf8');
  assert.ok(runtime.includes(`'${LOCAL_GENUI_ICON3D_ROOT}animated/'`), 'the runtime asks the host animated address');
  const url = p => LOCAL_GENUI_ICON3D_ROOT + 'animated/' + LOCAL_GENUI_ICON3D_ANIMATED_COMMIT + '/' + p.split('/').map(encodeURIComponent).join('/');
  assert.ok(Object.keys(animatedIndex.icons).length > 500);
  for (const [key, asset] of Object.entries(animatedIndex.icons)) {
    assert.ok(index.icons[key], `animated ${key} has a static picture`);
    assert.equal(asset.split('/')[0], index.icons[key].split('/')[0], `animated ${key} is the same emoji`);
    assert.equal(LocalGenUIIcon3DStore.animatedAssetPath(url(asset)), asset, asset);
    assert.equal(LocalGenUIIcon3DStore.assetPath(url(asset)), '', 'an animation is not a static picture');
  }
});

test('only index-shaped animated paths at the pinned animated commit are served', () => {
  const url = (p, commit = LOCAL_GENUI_ICON3D_ANIMATED_COMMIT) => LOCAL_GENUI_ICON3D_ROOT + 'animated/' + commit + '/' + p.split('/').map(encodeURIComponent).join('/');
  assert.equal(LocalGenUIIcon3DStore.animatedAssetPath(url('Rocket/animated/rocket_animated.png')), 'Rocket/animated/rocket_animated.png');
  assert.equal(LocalGenUIIcon3DStore.animatedAssetPath(url('Rocket/animated/rocket_animated.png', LOCAL_GENUI_ICON3D_COMMIT)), '', 'the static commit');
  assert.equal(LocalGenUIIcon3DStore.animatedAssetPath(url('../../secret/animated/x_animated.png')), '', 'traversal');
  assert.equal(LocalGenUIIcon3DStore.animatedAssetPath(url('Rocket/animated/rocket_animated.png') + '?x=1'), '', 'queries');
  assert.equal(LocalGenUIIcon3DStore.animatedAssetPath(url('Rocket/metadata.json')), '', 'non-picture files');
  assert.equal(LocalGenUIIcon3DStore.animatedAssetPath(url('Rocket/3D/rocket_3d.png')), '', 'static shapes');
});
