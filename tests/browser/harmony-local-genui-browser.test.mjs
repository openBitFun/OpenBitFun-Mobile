import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { test } from 'node:test';
import { launchBrowser } from './browser.mjs';

const resources = new URL('../../src/apps/mobile/harmonyos/entry/src/main/resources/rawfile/genui/', import.meta.url);
const assets = new Map([
  ['/', ['index.html', 'text/html']],
  ['/runtime.js', ['runtime.js', 'text/javascript']],
  ['/runtime.css', ['runtime.css', 'text/css']],
  ['/fonts/hm-symbol/HMSymbolVF.ttf', ['fonts/hm-symbol/HMSymbolVF.ttf', 'font/ttf']],
]);

test('the standalone Harmony GenUI bundle boots and renders at phone and foldable widths', { timeout: 30000 }, async () => {
  const manifest = JSON.parse(await readFile(new URL('runtime-manifest.json', resources), 'utf8'));
  const browser = await launchBrowser();
  const server = createServer(async (request, response) => {
    const asset = assets.get(request.url);
    if (!asset) {
      response.writeHead(404).end();
      return;
    }
    try {
      const content = await readFile(new URL(`runtime/${asset[0]}`, resources));
      response.writeHead(200, { 'content-type': asset[1] }).end(content);
    } catch {
      response.writeHead(500).end();
    }
  });
  try {
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.evaluateOnNewDocument(() => {
      window.messages = [];
      window.genuiNative = { post: raw => window.messages.push(JSON.parse(raw)) };
    });
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.waitForFunction(revision => window.messages.some(message =>
      message.type === 'boot' && message.rendererRevision === revision), { timeout: 5000 }, manifest.rendererRevision);

    const identity = {
      appId: 'local-genui:fixture',
      title: 'Test planner',
      template: manifest.template,
      libraryId: manifest.libraryId,
      libraryRevision: manifest.libraryRevision,
      designSpec: manifest.designSpec,
      sourceFormat: 'openui-lang',
    };
    for (const [width, scheme] of [[390, 'light'], [780, 'dark']]) {
      await page.setViewport({ width, height: 820 });
      await page.evaluate(message => window.__genuiHost.receive(JSON.stringify(message)), {
        type: 'init',
        manifest,
        identity,
        mode: 'live',
        source: 'root = Page([Button("Add meeting", @CreateCalendarEvent({title: "Meeting", startTime: "2026-11-18T15:00:00+08:00", endTime: "2026-11-18T16:00:00+08:00"}))], "Test planner")',
        streaming: false,
        sourceRevision: 3,
        stateRevision: 0,
        state: {},
        scheme,
        locale: 'en-US',
      });
      await page.waitForFunction(expected => document.documentElement.dataset.colorScheme === expected &&
        document.body.innerText.includes('Add meeting'), { timeout: 5000 }, scheme);
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    }
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
});
