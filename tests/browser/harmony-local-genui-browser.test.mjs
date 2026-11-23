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
      window.previewOpacity = new Map();
      window.genuiNative = { post: raw => {
        const message = JSON.parse(raw);
        if (message.type === 'preview_ready') {
          window.previewOpacity.set(message.sourceRevision,
            [...document.querySelectorAll('.pk-cover > *')].map(node => getComputedStyle(node).opacity));
        }
        window.messages.push(message);
      } };
    });
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.evaluate(() => {
      const channel = new MessageChannel();
      channel.port1.onmessage = event => {
        const message = JSON.parse(event.data);
        if (message.type === 'preview_ready') {
          window.previewOpacity.set(message.sourceRevision,
            [...document.querySelectorAll('.pk-cover > *')].map(node => getComputedStyle(node).opacity));
        }
        window.messages.push(message);
      };
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
    const htmlSandboxAddress = 'https://genui-sandbox.openbitfun.invalid/view';
    const imageAddress = 'https://genui-assets.openbitfun.invalid/photo/246813579abcdef0';
    const loader = await readFile(new URL('html-view.html', resources), 'utf8');
    await page.setRequestInterception(true);
    page.on('request', request => {
      if (request.url() === htmlSandboxAddress) {
        void request.respond({ status: 200, contentType: 'text/html', body: loader, headers: {
          'content-security-policy': "sandbox allow-scripts; default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'",
        } });
      } else if (request.url() === imageAddress) {
        void request.respond({
          contentType: 'image/png',
          body: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ZKpEAAAAASUVORK5CYII=', 'base64'),
        });
      } else void request.continue();
    });
    const mountHtml = async (html, revision) => {
      await page.evaluate(message => window.__genuiHost.receive(JSON.stringify(message)), {
        type: 'init', manifest, identity, mode: 'live', sourceRevision: revision,
        source: 'root = Page([game], "HTML test")\ngame = HtmlView(' + JSON.stringify(html) + ', 300, "Fixture")',
        stateRevision: 0, state: {}, streaming: false, scheme: 'light', locale: 'en-US',
      });
    };
    const waitForHtmlFrame = async selector => {
      const deadline = Date.now() + 15000;
      while (Date.now() < deadline) {
        for (const frame of page.frames()) {
          if (frame === page.mainFrame()) continue;
          if (await frame.$(selector)) return frame;
        }
        await new Promise(resolve => setTimeout(resolve, 50));
      }
      throw new Error(`Timed out waiting for HtmlView frame selector ${selector}`);
    };
    await mountHtml('<button>Draw</button><canvas width="8" height="8"></canvas><script>' +
      'document.querySelector("button").onclick = () => document.querySelector("canvas").getContext("2d").fillRect(0,0,8,8)' +
      '</script>', 9);
    await page.waitForSelector('iframe[data-html-view-status="ready"]', { timeout: 5000 });
    const game = await (await page.$('iframe.gen-ui-oi-html')).contentFrame();
    await game.$eval('button', button => button.click());
    assert.equal(await game.evaluate(() => document.querySelector('canvas').getContext('2d').getImageData(0,0,1,1).data[3]), 255);

    await mountHtml('<div data-openbitfun-game><button data-game-control="move">MOVE</button><button data-game-control="attack">ATTACK</button></div><script>' +
      'window.held = new Set(); for (const button of document.querySelectorAll("[data-game-control]")) {' +
      'button.addEventListener("pointerdown", event => { event.preventDefault(); window.held.add(button.dataset.gameControl); });' +
      'button.addEventListener("pointerup", event => window.held.delete(button.dataset.gameControl));' +
      'button.addEventListener("pointercancel", event => window.held.delete(button.dataset.gameControl));' +
      '}</script>', 9.5);
    const multitouch = await waitForHtmlFrame('[data-game-control="attack"]');
    const inputState = await multitouch.evaluate(() => {
      const move = document.querySelector('[data-game-control="move"]');
      const attack = document.querySelector('[data-game-control="attack"]');
      move.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, pointerId: 11, pointerType: 'touch' }));
      attack.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, pointerId: 12, pointerType: 'touch' }));
      const heldTogether = [...window.held].sort();
      move.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, pointerId: 11, pointerType: 'touch' }));
      return {
        heldTogether,
        heldAfterMoveRelease: [...window.held],
        gameMarker: document.documentElement.dataset.openbitfunGame,
        moveTouchAction: getComputedStyle(move).touchAction,
        activePointers: window.__openbitfunGameInput.activePointerCount(),
      };
    });
    assert.deepEqual(inputState.heldTogether, ['attack', 'move']);
    assert.deepEqual(inputState.heldAfterMoveRelease, ['attack']);
    assert.equal(inputState.gameMarker, 'true');
    assert.equal(inputState.moveTouchAction, 'none');
    assert.equal(inputState.activePointers, 1);
    assert.equal(await page.$eval('iframe.gen-ui-oi-html', frame => getComputedStyle(frame).touchAction), 'none');

    await mountHtml('<h1>Static chart</h1><div style="height:1600px">Chart details</div>', 10);
    const chart = await waitForHtmlFrame('h1');
    assert.equal(await chart.$eval('h1', node => node.textContent), 'Static chart');
    assert.ok(await chart.evaluate(() => { window.scrollTo(0, 80); return window.scrollY > 0; }));
    await mountHtml('<canvas></canvas><script>throw new Error("test game startup failed")</script>', 11);
    await page.waitForSelector('iframe[data-html-view-status="error"]', { timeout: 4000 });
    await page.evaluate(() => window.__genuiHost.receive(JSON.stringify({ type: 'probe', requestId: 'game-startup' })));
    const probe = await page.waitForFunction(() => window.messages.find(message => message.type === 'probe_result' &&
      message.report.requestId === 'game-startup'), { timeout: 4000 });
    assert.match((await probe.jsonValue()).report.renderErrors.join(' '), /HtmlView: .+/);

    await page.evaluate(message => window.__genuiHost.receive(JSON.stringify(message)), {
      type: 'init', manifest, identity, mode: 'live', streaming: false,
      sourceRevision: 4, stateRevision: 0, state: {}, scheme: 'light',
      source: '$id = 42\nroot = Page([Button("Positional", @DeleteCalendarEvent($id)), Button("Legacy", @DeleteCalendarEvent({id: $id}))], "Calendar")',
    });
    await page.waitForFunction(() => document.body.innerText.includes('Positional'));
    await page.evaluate(() => {
      for (const label of ['Positional', 'Legacy']) {
        [...document.querySelectorAll('button')].find(button => button.textContent.trim() === label).click();
      }
    });
    const deletions = await page.evaluate(() => window.messages.filter(message => message.action === 'DeleteCalendarEvent'));
    assert.deepEqual(deletions.map(message => message.params), [{ id: 42 }, { id: 42 }]);

    await page.evaluate(message => window.__genuiHost.receive(JSON.stringify(message)), {
      type: 'init', manifest, identity, mode: 'live', streaming: false,
      sourceRevision: 5, stateRevision: 0, state: {}, scheme: 'light', imageSearchAvailable: true,
      source: 'root = Page([SearchImage("Tangerine")], "Photos")',
    });
    await page.waitForFunction(() => window.messages.some(message => message.type === 'image_search' && message.query === 'Tangerine'));
    const photoRequest = await page.evaluate(() => window.messages.find(message => message.type === 'image_search'));
    await page.evaluate(message => window.__genuiHost.receive(JSON.stringify(message)), {
      type: 'image_search_result', appId: identity.appId, requestId: photoRequest.requestId, images: [imageAddress],
    });
    await page.waitForFunction(() => document.querySelector('img[alt="Tangerine"]')?.naturalWidth === 1);

    const broken = 'root = MissingProbeFixture([body])\nbody = Text("Recover this statement")';
    await page.evaluate(message => {
      for (const streaming of [true, false]) {
        window.__genuiHost.receive(JSON.stringify({ ...message, streaming, mode: streaming ? 'live' : 'checker' }));
      }
      window.__genuiHost.receive(JSON.stringify({ type: 'probe', requestId: 'bad-render' }));
    }, { type: 'init', manifest, identity, source: broken, sourceRevision: 6, stateRevision: 0, state: {}, scheme: 'light' });
    await page.waitForFunction(() => window.messages.some(message =>
      message.type === 'probe_result' && message.report.requestId === 'bad-render'));
    const badProbe = await page.evaluate(() => window.messages.find(message => message.report?.requestId === 'bad-render').report);
    assert.ok(badProbe.renderErrors.some(error => error.includes('MissingProbeFixture')));
    assert.equal(await page.evaluate(() => window.messages.some(message =>
      message.type === 'preview_ready' && message.sourceRevision === 6)), false);

    await page.evaluate(message => {
      window.__genuiHost.receive(JSON.stringify(message));
      window.__genuiHost.receive(JSON.stringify({ type: 'probe', requestId: 'fixed-render' }));
    }, { type: 'init', manifest, identity, mode: 'live', streaming: false,
      source: 'root = Page([cover, body], "Fixed probe")\ncover = Cover("Fixed probe", "Preview", "Ready to read")\nbody = Text("Recover this statement")',
      sourceRevision: 7, stateRevision: 0, state: {}, scheme: 'light', look: 'aurora' });
    await page.waitForFunction(() => window.messages.some(message =>
      message.type === 'probe_result' && message.report.requestId === 'fixed-render'));
    const fixedProbe = await page.evaluate(() => window.messages.find(message => message.report?.requestId === 'fixed-render').report);
    assert.deepEqual(fixedProbe.renderErrors, []);
    assert.ok(fixedProbe.visibleElements > 0);
    await page.waitForFunction(appId => window.messages.some(message =>
      message.type === 'preview_ready' && message.appId === appId && message.sourceRevision === 7), {}, identity.appId);
    const previewOpacity = await page.evaluate(() => window.previewOpacity.get(7));
    assert.ok(previewOpacity.length > 0 && previewOpacity.every(value => value === '1'), 'The preview includes the fully visible cover');
    for (const [appId, count] of [['local-genui:first', 15], ['local-genui:second', 42]]) {
      await page.evaluate(message => window.__genuiHost.receive(JSON.stringify(message)), {
        type: 'init', manifest, identity: { ...identity, appId }, mode: 'live', streaming: false,
        source: '$count = 0\nroot = Page([Text("Saved count " + $count)], "State")',
        sourceRevision: 8, stateRevision: 1, state: { count }, scheme: 'light',
      });
      await page.waitForFunction(expected => document.body.innerText.includes(`Saved count ${expected}`), {}, count);
    }
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
});
