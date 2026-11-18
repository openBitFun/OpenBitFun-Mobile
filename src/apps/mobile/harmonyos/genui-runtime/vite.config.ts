import path from 'node:path';
import { readFileSync } from 'node:fs';
import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import { createRequire } from 'node:module';

/**
 * Harmony Local GenUI runtime bundle.
 *
 * ArkWeb loads this bundle from HAP rawfile as one classic script plus one
 * stylesheet. It contains only the OpenUI runtime and the product GenUI
 * adapters; the contract identity comes from the generated runtime manifest.
 */
const requireFromWebUi = createRequire(path.join(__dirname, 'package.json'));
const outDir = path.resolve(__dirname, '../entry/src/main/resources/rawfile/genui/runtime');
const manifestPath = path.resolve(__dirname, '../entry/src/main/resources/rawfile/genui/runtime-manifest.json');

/**
 * Desktop serves the HM Symbol font from the WebUI public root. The phone
 * runtime document lives at rawfile/genui/runtime/index.html, so the bundle
 * resolves the font next to itself instead of at the origin root.
 */
function relativeHarmonyFontPlugin(): Plugin {
  return {
    name: 'openbitfun-local-genui-font-path',
    enforce: 'pre',
    transform(code, id) {
      if (!/components\/vendor\/(harmonyStyles|hm-icons)\.ts$/.test(id)) return null;
      return code.split('/fonts/hm-symbol/HMSymbolVF.ttf').join('fonts/hm-symbol/HMSymbolVF.ttf');
    },
  };
}

/**
 * The phone runtime loads no network images. Its 3D pictures use the host
 * asset address that LocalGenUIWebSurface serves (the reference app's
 * /api/icon3d proxy): the same pinned Fluent Emoji files, cached on device.
 */
export const LOCAL_GENUI_ICON3D_ROOT = 'https://genui-assets.openbitfun.invalid/fluent-emoji/';
function hostIcon3dPlugin(): Plugin {
  return {
    name: 'openbitfun-local-genui-icon3d',
    enforce: 'pre',
    transform(code, id) {
      if (!/components\/vendor\/fluentEmoji3d\.ts$/.test(id)) return null;
      const cdn = 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@${EMOJI_CDN_REVISION}/assets/';
      if (!code.includes(cdn)) throw new Error('fluentEmoji3d asset root moved; update the phone icon3d rewrite');
      // Keep the pinned revision in the path; the host fetches exactly that commit.
      return code.split(cdn).join(LOCAL_GENUI_ICON3D_ROOT + '${EMOJI_CDN_REVISION}/');
    },
  };
}

export default defineConfig(() => {
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const build = {
    catalogHash: manifest.catalogHash,
    rendererRevision: manifest.rendererRevision,
    libraryId: manifest.libraryId,
    libraryRevision: manifest.libraryRevision,
  };
  return {
    cacheDir: path.resolve(__dirname, 'node_modules/.vite', 'genui-local-runtime'),
    plugins: [relativeHarmonyFontPlugin(), hostIcon3dPlugin(), react()],
    // The WebUI public directory belongs to the desktop app, not this runtime.
    publicDir: false,
    define: {
      __LOCAL_GENUI_BUILD__: JSON.stringify(build),
      'process.env.NODE_ENV': JSON.stringify('production'),
    },
    resolve: {
      dedupe: ['react', 'react-dom', 'lucide-react'],
      alias: [
        { find: /^decode-named-character-reference$/, replacement: requireFromWebUi.resolve('decode-named-character-reference') },
      ],
    },
    build: {
      outDir,
      emptyOutDir: true,
      sourcemap: false,
      cssCodeSplit: false,
      assetsInlineLimit: 100_000_000,
      lib: {
        entry: path.resolve(__dirname, 'src/local-runtime/main.tsx'),
        formats: ['iife'],
        name: 'OpenBitFunLocalGenUI',
        fileName: () => 'runtime.js',
        cssFileName: 'runtime',
      },
      rollupOptions: {
        output: { inlineDynamicImports: true, assetFileNames: 'runtime.[ext]' },
      },
    },
  };
});
