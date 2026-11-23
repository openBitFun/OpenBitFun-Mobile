const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const root = path.resolve(__dirname,'../../entry/src/main/ets');
function load(name, deps={}) {
 const src=fs.readFileSync(path.join(root,name+'.ets'),'utf8').replace(/@ObservedV2\s*/g,'').replace(/@Trace\s*/g,'');
 const js=ts.transpileModule(src,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS}}).outputText;
 const exports={};new Function('require','exports',js)(name=>deps[name]||{},exports);return exports;
}
const tokens=load('generated/MobileDesignTokens');
const tokenDependency = { '../../generated/MobileDesignTokens': tokens };
const {MiniAppGalleryPolicy:P}=load('pages/policy/MiniAppGalleryPolicy',tokenDependency);
const dragState = load('pages/state/MiniAppDragState', tokenDependency);
test('swiping is bounded, a tap does not advance and a resize stays inside the live viewport',()=>{
 assert.equal(P.nextIndex(0,80,3),0); assert.equal(P.nextIndex(2,-80,3),2);
 assert.equal(P.nextIndex(0,-80,3),1); assert.equal(P.nextIndex(1,80,3),0);
 assert.equal(P.nextIndex(1,12,3),1); assert.equal(P.nextIndex(0,-80,0),0);
 for(const w of [280,393,600,707,839,840,1000]) {
  assert.ok(P.cardWidth(w)<w);
  for(const h of [240,480,700]) assert.ok(P.cardHeight(w,h)<=h-40);
  assert.equal(P.columns(w),w<840?1:2);
 }
});
const {MiniAppState}=load('pages/state/MiniAppState', {
 './MiniAppDragState':dragState
});
const {MiniAppViewModel}=load('pages/viewmodel/MiniAppViewModel',{
 '../state/MiniAppState':{MiniAppState},
 '../../services/MiniAppDocument':{MiniAppDocument:{build:x=>x}},
 '../../i18n/RemoteI18n':{RemoteI18n:{language:()=> 'zh-CN',t:x=>x}},
 '../../services/ConnectionErrorPolicy':{ConnectionErrorPolicy:{errorText:e=>e.message}}
});
test('opening and returning from an offline app preserves gallery mode/focus and fences a late document',async()=>{
 let resolve;
 const vm=new MiniAppViewModel({list:async()=>[{id:'one',name:'One',description:'Local'},{id:'two',name:'Two',description:'Local'}],
  document:async id=>id==='one'?'<html>one</html>':new Promise(r=>{resolve=r;})});
 await vm.open();vm.state.galleryMode='list';vm.state.galleryAppId='one';
 await vm.select('one');assert.equal(vm.state.appId,'one');
 await vm.open();assert.equal(vm.state.galleryMode,'list');assert.equal(vm.state.galleryAppId,'one');
 const pending=vm.select('two');vm.close();resolve('<html>late</html>');await pending;
 assert.equal(vm.state.visible,false);assert.equal(vm.state.document,'');
});

test('dropping on the measured hint or below it is accepted across window sizes', () => {
  const { MiniAppDragState } = dragState;
  const drag = new MiniAppDragState();
  for (const width of [360, 840]) {
    drag.windowX = 16;
    drag.windowY = 28;
    drag.windowWidth = width;
    drag.windowHeight = 660;
    drag.setTargetTop(undefined);
    drag.move(16 + width / 2, 575);
    assert.equal(drag.overEdge, false);
    drag.setTargetTop(567);
    assert.equal(drag.overEdge, true, 'layout includes a finger already resting on the hint');
    drag.move(16 + width, 688);
    assert.equal(drag.overEdge, true);
    drag.move(16 + width, 689);
    assert.equal(drag.overEdge, false);
    drag.move(15, 575);
    assert.equal(drag.overEdge, false);
    drag.move(16, 566);
    assert.equal(drag.overEdge, false);
    drag.move(16, 567);
    assert.equal(drag.overEdge, true);
  }
});

for (const cancelled of [true, false]) {
  test(cancelled ? 'a query arriving after cancellation cannot background the app' :
    'a new shortcut reveals the desktop only once across observation and confirmation', async (t) => {
    t.mock.timers.enable({ apis: ['setTimeout'] });
    const id = 'builtin-gomoku';
    const turn = () => new Promise(resolve => setImmediate(resolve));
    let finishConfirmation;
    let cancelConfirmation;
    const confirmation = new Promise((resolve, reject) => {
      finishConfirmation = resolve;
      cancelConfirmation = reject;
    });
    let finishQuery;
    let queries = 0;
    let moves = 0;
    const { MiniAppShortcut } = load('services/MiniAppShortcut', {
      './DeviceApiLevelService': { DeviceApiLevelService: { sdkApiVersion: () => 26 } },
      './RemoteLogger': { RemoteLogger: { info() {}, warn() {} } },
      '@kit.AppGalleryKit': { productViewManager: {
        getPinShortcutInfos: () => ++queries === 1 ? Promise.resolve([]) :
          new Promise(resolve => { finishQuery = resolve; }),
        requestNewPinShortcut: () => confirmation
      } }
    });
    const pin = MiniAppShortcut.pinAndReveal({
      moveAbilityToBackground: async () => { moves++; }
    }, id, 'verified');
    await turn();
    t.mock.timers.tick(250);
    await turn();
    assert.equal(queries, 2);
    if (cancelled) {
      cancelConfirmation(new Error('user cancelled'));
      await assert.rejects(pin, /user cancelled/);
    }
    finishQuery([{ shortcutId: id }]);
    await turn();
    assert.equal(moves, cancelled ? 0 : 1);
    if (!cancelled) {
      finishConfirmation();
      await pin;
      assert.equal(moves, 1);
    }
  });
}
