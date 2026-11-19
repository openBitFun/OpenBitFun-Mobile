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
    });
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.evaluate(() => {
      const channel = new MessageChannel();
      channel.port1.onmessage = event => window.messages.push(JSON.parse(event.data));
      window.dispatchEvent(new MessageEvent('message', { data: 'local-genui-port', ports: [channel.port2] }));
    });
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
        source: 'root = Page([Cover("Test planner", "Daily log", "Seven blocks"), HeroStat("Focus", 90, "min"), Button("Add meeting", @CreateCalendarEvent({title: "Meeting", startTime: "2026-11-18T15:00:00+08:00", endTime: "2026-11-18T16:00:00+08:00"}))], "Test planner")',
        streaming: false,
        sourceRevision: 3,
        stateRevision: 0,
        state: {},
        scheme,
        locale: 'en-US',
      });
      await page.waitForFunction(expected => document.documentElement.dataset.colorScheme === expected &&
        document.body.innerText.includes('Add meeting'), { timeout: 5000 }, scheme);
      const cover = await page.waitForSelector('.pk-cover');
      assert.equal(await page.$eval('[data-gen-ui-look]', node => node.dataset.genUiLook), 'aurora');
      for (const look of ['blueprint', 'celadon', 'classic', 'unknown']) {
        await page.evaluate(message => window.__genuiHost.receive(JSON.stringify(message)), { type: 'theme', scheme, look });
        const expected = look === 'unknown' ? 'aurora' : look;
        await page.waitForFunction(value => document.querySelector('[data-gen-ui-look]')?.dataset.genUiLook === value, {}, expected);
        assert.ok(await cover.evaluate(node => node.isConnected), 'Changing style preserves the mounted cover');
        assert.equal(await page.$eval('.pk-hero-stat .pk-stat-value', node => node.textContent).then(text => text.includes('90')), true);
        assert.equal(await page.$$eval('[data-gen-ui-look-style]', nodes => nodes.length), look === 'classic' ? 0 : 1);
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      }
    }
    const loader = await readFile(new URL('html-view.html', resources), 'utf8');
    await page.setRequestInterception(true);
    page.on('request', request => {
      if (request.url() === 'https://genui-sandbox.openbitfun.invalid/view') {
        void request.respond({ status: 200, contentType: 'text/html', body: loader, headers: {
          'content-security-policy': "sandbox allow-scripts; default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'",
        } });
      } else {
        void request.continue();
      }
    });
    const mountHtml = async (html, revision) => {
      await page.evaluate(message => window.__genuiHost.receive(JSON.stringify(message)), {
        type: 'init', manifest, identity, mode: 'live', sourceRevision: revision,
        source: 'root = Page([game], "HTML test")\ngame = HtmlView(' + JSON.stringify(html) + ', 300, "Fixture")',
        stateRevision: 0, state: {}, streaming: false, scheme: 'light', locale: 'en-US',
      });
    };
    await mountHtml('<button>Draw</button><canvas width="8" height="8"></canvas><script>' +
      'document.querySelector("button").onclick = () => document.querySelector("canvas").getContext("2d").fillRect(0,0,8,8)' +
      '</script>', 4);
    await page.waitForSelector('iframe[data-html-view-status="ready"]', { timeout: 5000 });
    const game = await (await page.$('iframe.gen-ui-oi-html')).contentFrame();
    await game.$eval('button', button => button.click());
    assert.equal(await game.evaluate(() => document.querySelector('canvas').getContext('2d').getImageData(0,0,1,1).data[3]), 255);

    await mountHtml('<h1>Static chart</h1><div style="height:1600px">Chart details</div>', 5);
    const chart = await page.waitForFrame(frame => frame.url() === 'about:srcdoc', { timeout: 5000 });
    await chart.waitForSelector('h1', { timeout: 5000 });
    assert.equal(await chart.$eval('h1', node => node.textContent), 'Static chart');
    assert.ok(await chart.evaluate(() => { window.scrollTo(0, 80); return window.scrollY > 0; }));
    await mountHtml('<canvas></canvas><script>throw new Error("test game startup failed")</script>', 6);
    await page.waitForSelector('iframe[data-html-view-status="error"]', { timeout: 4000 });
    await page.evaluate(() => window.__genuiHost.receive(JSON.stringify({ type: 'probe', requestId: 'game-startup' })));
    const probe = await page.waitForFunction(() => window.messages.find(message => message.type === 'probe_result' &&
      message.report.requestId === 'game-startup'), { timeout: 4000 });
    assert.match((await probe.jsonValue()).report.renderErrors.join(' '), /HtmlView: .+/);
    assert.deepEqual(errors.filter(error => !error.includes("test game startup failed")), []);
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
});
