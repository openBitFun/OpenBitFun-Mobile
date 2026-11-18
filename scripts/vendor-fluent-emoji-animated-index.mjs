#!/usr/bin/env node
/**
 * Pin the Microsoft Fluent Emoji animated set (MIT) for Harmony Local GenUI.
 *
 *   node scripts/vendor-fluent-emoji-animated-index.mjs [commit]
 *
 * The animated repository keeps one folder per emoji, named like the static
 * Fluent Emoji folders. Each animated asset is keyed by the code point key the
 * static 3D index already uses for that folder, so a cover only animates the
 * exact emoji it already shows. Skin-tone variants keep the Default tone, as
 * the static index does. The host fetches these files at the pinned commit.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const vendor = path.join(root, 'src/apps/mobile/harmonyos/genui-runtime/src/components/vendor');
const staticIndex = JSON.parse(readFileSync(path.join(vendor, 'fluent-emoji-3d-index.json'), 'utf8'));
const repo = 'microsoft/fluentui-emoji-animated';

async function json(url) {
  const response = await fetch(url, { headers: { Accept: 'application/vnd.github+json' } });
  if (!response.ok) throw new Error(`${url}: ${response.status}`);
  return response.json();
}

const sha = process.argv[2] ?? (await json(`https://api.github.com/repos/${repo}/commits/main`)).sha;
const tree = await json(`https://api.github.com/repos/${repo}/git/trees/${sha}?recursive=1`);
if (tree.truncated) throw new Error('GitHub tree listing was truncated');

const animatedByFolder = new Map();
for (const entry of tree.tree) {
  const match = /^assets\/(.+?)\/(Default\/)?animated\/([^/]+_animated(_default)?\.png)$/.exec(entry.path);
  if (entry.type === 'blob' && match) animatedByFolder.set(match[1], entry.path.slice('assets/'.length));
}

const icons = {};
for (const [key, asset] of Object.entries(staticIndex.icons)) {
  const animated = animatedByFolder.get(asset.split('/')[0]);
  if (animated) icons[key] = animated;
}
const sorted = Object.fromEntries(Object.entries(icons).sort(([a], [b]) => a.localeCompare(b)));
writeFileSync(path.join(vendor, 'fluent-emoji-animated-index.json'), JSON.stringify({ sha, icons: sorted }) + '\n');
console.log(`Pinned ${Object.keys(sorted).length} of ${animatedByFolder.size} animated Fluent Emoji at ${sha}`);
