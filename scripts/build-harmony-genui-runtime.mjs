#!/usr/bin/env node
/**
 * Build the Harmony Local GenUI contract projection and ArkWeb runtime bundle.
 *
 *   node scripts/build-harmony-genui-runtime.mjs          # regenerate + build
 *   node scripts/build-harmony-genui-runtime.mjs --check  # verify freshness only
 *
 * The contract files under rawfile/genui are checked in; the runtime bundle
 * under rawfile/genui/runtime is generated and verified by the HAP build.
 */
import { execFileSync } from 'node:child_process';
import { copyFileSync, cpSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const genuiDir = path.join(root, 'src/apps/mobile/harmonyos/entry/src/main/resources/rawfile/genui');
const runtimeDir = path.join(genuiDir, 'runtime');
const manifestPath = path.join(genuiDir, 'runtime-manifest.json');
const buildInfoPath = path.join(runtimeDir, 'build.json');
const { runtimeFreshnessError } = createRequire(import.meta.url)('../src/apps/mobile/harmonyos/tools/genui-runtime-freshness.cjs');

function run(command, args, cwd = root) {
  execFileSync(command, args, { cwd, stdio: 'inherit', windowsHide: true, shell: process.platform === 'win32' && command === 'pnpm', env: process.env });
}

const HTML = `<!doctype html>
<html lang="zh-CN" data-openbitfun-design-system-root data-density="compact" data-contrast="standard">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self' resource:; style-src 'self' resource: 'unsafe-inline'; img-src data: blob: https://genui-assets.openbitfun.invalid; font-src 'self' data: resource:; connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'">
<link rel="stylesheet" href="runtime.css">
<title>Local GenUI</title>
</head>
<body><div id="root"></div><script src="runtime.js"></script></body>
</html>
`;

if (process.argv.includes('--check')) {
  run(process.execPath, ['scripts/generate-genui-contract.mjs', '--check']);
  const error = runtimeFreshnessError();
  if (error) { console.error(`${error}; run pnpm run harmony:genui-runtime`); process.exit(1); }
  console.log('Harmony Local GenUI runtime is fresh');
} else {
  run(process.execPath, ['scripts/generate-genui-contract.mjs']);
  run('pnpm', ['exec', 'vite', 'build', '--logLevel', 'warn'], path.join(root, 'src/apps/mobile/harmonyos/genui-runtime'));
  writeFileSync(path.join(runtimeDir, 'index.html'), HTML);
  // HM Symbol icons; the license travels with the font.
  const fontDir = path.join(runtimeDir, 'fonts/hm-symbol');
  mkdirSync(fontDir, { recursive: true });
  for (const file of ['HMSymbolVF.ttf', 'LICENSE.txt']) copyFileSync(path.join(root, 'src/apps/mobile/harmonyos/genui-runtime/fonts/hm-symbol', file), path.join(fontDir, file));
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  writeFileSync(buildInfoPath, JSON.stringify({ catalogHash: manifest.catalogHash, rendererRevision: manifest.rendererRevision }, null, 2) + '\n');
  console.log('Built Harmony Local GenUI runtime for ' + manifest.rendererRevision);
  if (process.argv.includes('--stage-mobile-document')) {
    // Native shells package the existing product-owned OpenUI document. They
    // retain their own views, permission boundaries and WebView lifecycle.
    const output = path.join(root, 'src/shared/generative-ui/generated/mobile');
    mkdirSync(output, { recursive: true });
    cpSync(runtimeDir, path.join(output, 'genui/runtime'), { recursive: true });
    writeFileSync(path.join(output, 'genui/runtime/index.html'), HTML.replace('img-src data: blob:', 'img-src data: blob: openbitfun-genui:'));
    for (const file of ['runtime-manifest.json', 'harmony-prompt.txt', 'local-tool-schema.json', 'catalog.json']) {
      copyFileSync(path.join(genuiDir, file), path.join(output, 'genui', file));
    }
  }
}
