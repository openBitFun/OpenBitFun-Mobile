const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

const source = fs.readFileSync(path.join(__dirname, '../../entry/src/main/ets/services/local-genui/LocalGestureClassifier.ets'), 'utf8');
const mod = {};
new Function('require', 'exports', ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText)(() => ({}), mod);
const { LocalGestureClassifier, LocalGestureName } = mod;

// Image coordinates: y grows downwards. Person faces the camera; anatomical left is image right.
function body({ leftWrist = [260, 360], rightWrist = [140, 360], rotate = 0 } = {}) {
  const points = [
    [0, 200, 120], [5, 250, 200], [6, 150, 200], [11, 240, 380], [12, 160, 380],
    [9, ...leftWrist], [10, ...rightWrist],
  ];
  const rad = rotate * Math.PI / 180;
  return points.map(([type, x, y]) => ({
    type, score: 0.9,
    x: 200 + (x - 200) * Math.cos(rad) - (y - 250) * Math.sin(rad),
    y: 250 + (x - 200) * Math.sin(rad) + (y - 250) * Math.cos(rad),
  }));
}
const leftUp = opts => body({ leftWrist: [270, 100], ...opts });
const rightUp = opts => body({ rightWrist: [130, 100], ...opts });
const bothUp = opts => body({ leftWrist: [270, 100], rightWrist: [130, 100], ...opts });

function run(classifier, frames) {
  return frames.map(frame => classifier.accept(frame)).filter(Boolean);
}

test('a raised left hand fires once after it is stable, and re-arms when lowered', () => {
  const c = new LocalGestureClassifier(false);
  assert.deepEqual(run(c, [body(), leftUp(), leftUp(), leftUp(), leftUp()]), [LocalGestureName.RaiseLeft]);
  assert.deepEqual(run(c, [body(), body(), leftUp(), leftUp()]), [LocalGestureName.RaiseLeft]);
});

test('a single noisy frame does not fire', () => {
  const c = new LocalGestureClassifier(false);
  assert.deepEqual(run(c, [body(), rightUp(), body(), body()]), []);
});

test('both hands fire raise_both, not the single-hand gestures', () => {
  const c = new LocalGestureClassifier(false);
  assert.deepEqual(run(c, [bothUp(), bothUp(), bothUp()]), [LocalGestureName.RaiseBoth]);
});

test('the measurement is independent of camera rotation', () => {
  for (const rotate of [0, 90, 180, 270]) {
    const c = new LocalGestureClassifier(false);
    assert.deepEqual(run(c, [rightUp({ rotate }), rightUp({ rotate })]), [LocalGestureName.RaiseRight], `rotate ${rotate}`);
  }
});

test('a mirrored surface swaps sides; a missing person is not a gesture', () => {
  const c = new LocalGestureClassifier(true);
  assert.deepEqual(run(c, [leftUp(), leftUp()]), [LocalGestureName.RaiseRight]);
  const empty = new LocalGestureClassifier(false);
  assert.deepEqual(run(empty, [[], [], []]), []);
});
