import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { compileCatalog } from '../src/shared/generative-ui/library.mjs';
import { projectHarmonyLocalContract } from '../src/shared/generative-ui/harmony-local.mjs';
const path = new URL('../src/shared/generative-ui/', import.meta.url);
const catalog = compileCatalog(JSON.parse(readFileSync(new URL('library.json', path), 'utf8')));
const output = JSON.stringify(catalog, null, 2) + '\n';
const target = new URL('catalog.json', path);
// Harmony Local GenUI consumes a projection of the same catalog. Keep it next
// to the HAP resources so the phone never hand-writes prompts or schemas.
const harmonyDir = new URL('../src/apps/mobile/harmonyos/entry/src/main/resources/rawfile/genui/', import.meta.url);
const harmony = projectHarmonyLocalContract(catalog).files;
const check = process.argv.includes('--check');
const stale = [];
if (check) {
  if (readFileSync(target, 'utf8') !== output) stale.push('src/shared/generative-ui/catalog.json');
  for (const [name, text] of Object.entries(harmony)) {
    const file = new URL(name, harmonyDir);
    if (!existsSync(file) || readFileSync(file, 'utf8') !== text) stale.push('rawfile/genui/' + name);
  }
  if (stale.length) throw new Error('GenUI contract is stale (' + stale.join(', ') + '); run node scripts/generate-genui-contract.mjs');
} else {
  writeFileSync(target, output);
  mkdirSync(harmonyDir, { recursive: true });
  for (const [name, text] of Object.entries(harmony)) writeFileSync(new URL(name, harmonyDir), text);
}
