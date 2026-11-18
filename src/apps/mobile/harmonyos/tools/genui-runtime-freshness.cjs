// Local GenUI runtime freshness gate shared by entry/hvigorfile.ts and
// scripts/build-harmony-genui-runtime.mjs. The runtime bundle must be built
// for the exact contract revision in rawfile/genui/runtime-manifest.json.
const fs = require('node:fs');
const path = require('node:path');

const genuiDir = path.resolve(__dirname, '../entry/src/main/resources/rawfile/genui');

function runtimeFreshnessError() {
  const manifestPath = path.join(genuiDir, 'runtime-manifest.json');
  if (!fs.existsSync(manifestPath)) return 'rawfile/genui/runtime-manifest.json is missing';
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  for (const file of ['index.html', 'runtime.js', 'runtime.css', 'build.json', 'fonts/hm-symbol/HMSymbolVF.ttf']) {
    if (!fs.existsSync(path.join(genuiDir, 'runtime', file))) return `rawfile/genui/runtime/${file} is missing`;
  }
  const info = JSON.parse(fs.readFileSync(path.join(genuiDir, 'runtime/build.json'), 'utf8'));
  if (info.catalogHash !== manifest.catalogHash || info.rendererRevision !== manifest.rendererRevision) {
    return 'rawfile/genui/runtime was built for another contract revision';
  }
  return undefined;
}

function assertRuntimeFresh() {
  const error = runtimeFreshnessError();
  if (error) throw new Error(`Local GenUI runtime is not current: ${error}. Run: pnpm run harmony:genui-runtime`);
}

module.exports = { genuiDir, runtimeFreshnessError, assertRuntimeFresh };
