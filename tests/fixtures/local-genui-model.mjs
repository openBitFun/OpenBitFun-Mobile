import { createServer } from 'node:http';
import { setTimeout as delay } from 'node:timers/promises';

const port = Number(process.argv[2] ?? 39172);
const models = ['parity-fixture', 'parity-fast', 'parity-vision'];
const source = [
  'root = Page([Cover("三端创作核对", "GenUI 模拟器", "同一份 OpenUI 文档"), HeroStat("专注", 90, "min")], "三端创作核对")',
  '$done = false',
].join('\n');
const calendarEvent = '{title: "Parity fixture appointment", startTime: "2040-06-19T09:00:00Z", endTime: "2040-06-19T10:00:00Z", reminderMinutes: [10, 30]}';
const calendarSource = [
  '$eventId = 0',
  'heading = Cover("三端日历核对", "GenUI 模拟器", "验证 OpenBitFun 本机日历")',
  'add = Button("添加测试日程", @CreateCalendarEvent(' + calendarEvent + '))',
  'eventId = Input($eventId, "日程编号", "number")',
  'update = Button("更新测试日程", @UpdateCalendarEvent({id: $eventId, title: "Updated parity appointment", startTime: "2040-06-19T11:00:00Z", endTime: "2040-06-19T12:00:00Z"}))',
  'list = Button("查询测试日程", @ListCalendarEvents({startTime: "2040-06-19T00:00:00Z", endTime: "2040-06-20T00:00:00Z"}))',
  'remove = Button("删除测试日程", @DeleteCalendarEvent($eventId), "outline", "danger")',
  'root = Page([heading, add, eventId, update, list, remove], "三端日历核对")',
].join('\n');
const imageSource = [
  'heading = Cover("三端图片核对", "GenUI 模拟器", "同一份搜索图片与 3D 图标", "🍊")',
  'photo = SearchImage("Tangerine", 1.5)',
  'icon = Icon3D("🍊", "large")',
  'root = Page([heading, Section([photo], "图片搜索"), Section([icon], "3D 图标")], "三端图片核对")',
].join('\n');
const animationSource = [
  'heading = Cover("三端动效核对", "GenUI 模拟器", "固定版本的动画封面", "🚀")',
  'root = Page([heading, HeroStat("飞行时间", 90, "s")], "三端动效核对")',
].join('\n');

const gestureSource = [
  '$score = null',
  'heading = Cover("三端手势核对", "GenUI 模拟器", "同一份手势计分器")',
  'board = Scoreboard(["甲队", "乙队"], $score, {scoring: "open", increments: [1], input: {plugin: "camera.open-palm", version: 1, activation: "manual", bindings: {left: {action: "increment", participantId: "A", points: 1}, right: {action: "increment", participantId: "B", points: 1}}, haptic: "none"}})',
  'root = Page([heading, board], "三端手势核对")',
].join('\n');

const collaborationSource = [
  '$imported = ""',
  '$photo = ""',
  '$scan = ""',
  'heading = Cover("三端取材核对", "GenUI 模拟器", "同一份跨设备图片文档")',
  'gallery = CrossDeviceImage($imported, "gallery", "选择其他设备的图片")',
  'camera = CrossDeviceImage($photo, "photo", "从其他设备拍照")',
  'document = CrossDeviceImage($scan, "scan", "从其他设备扫描文档")',
  'root = Page([heading, gallery, camera, document], "三端取材核对")',
].join('\n');

const repairTitle = '三端修复核对';
const repairSource = [
  'root = UnknownRepairBlock([cover, repairBlock, saved, increment], "三端修复核对")',
  'cover = Cover("三端修复核对", "保留原有区块", "GenUI 校验与修复")',
  'repairBlock = Text("自动修复已完成")',
  '$count = 0',
  'saved = Text("保留计数 " + $count)',
  'increment = Button("计数加一", @Set($count, $count + 1))',
].join('\n');
const repairPatch = 'root = Page([cover, repairBlock, saved, increment], "三端修复核对")';
const repeatingBadPatch = 'root = BrokenRevisionOnly([cover, repairBlock, saved, increment], "三端修复核对")';
const firstFailureTitle = '三端首轮失败核对';
const firstFailureSource = [
  'root = UnknownFirstFailureRoot([cover], "三端首轮失败核对")',
  'cover = Cover("三端首轮失败核对", "可再次创作", "同一应用修正后可使用")',
].join('\n');
const firstFailureFix = 'root = Page([cover], "三端首轮失败核对")\ncover = Cover("三端首轮失败核对", "可再次创作", "同一应用修正后可使用")';

const checkpointTitle = '三端恢复核对';
const checkpointSource = [
  'root = Page([heading, revision, saved, increment], "三端恢复核对")',
  'heading = Cover("三端恢复核对", "GenUI 模拟器", "校验检查点")',
  'revision = Text("原有版本")',
  '$count = 0',
  'saved = Text("保留计数 " + $count)',
  'increment = Button("计数加一", @Set($count, $count + 1))',
].join('\n');
const checkpointPatch = 'revision = Text("中断后恢复的版本")';

const launcherSource = [
  'root = Page([heading, score], "三端桌面甲", "blue")',
  'heading = Cover("三端桌面甲", "GenUI 模拟器", "初始桌面图标", "🚀")',
  'score = HeroStat("版本", 1, "")',
].join('\n');
const launcherPatch = [
  'root = Page([heading, score], "三端桌面乙", "purple")',
  'heading = Cover("三端桌面乙", "GenUI 模拟器", "更新后的桌面图标", "🍊")',
  'score = HeroStat("版本", 2, "")',
].join('\n');

const insetsTitle = '三端安全区核对';
const insetsSource = [
  'root = Page([cover, status, action], "三端安全区核对", "blue", null, {orientation: "landscape"})',
  'cover = Cover("三端安全区核对", "GenUI 模拟器", "横屏布局")',
  '$count = 0',
  'status = Text("窗口计数 " + $count)',
  'action = Button("窗口计数加一", @Set($count, $count + 1))',
].join('\n');

function sse(response, value) {
  response.write(`data: ${JSON.stringify(value)}\n\n`);
}

createServer(async (request, response) => {
  if (request.method === 'GET' && request.url === '/v1/models') {
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ data: models.map(id => ({ id })) }));
    return;
  }
  const anthropic = request.url === '/v1/messages';
  if (request.method !== 'POST' || (!anthropic && request.url !== '/v1/chat/completions')) {
    response.writeHead(404).end();
    return;
  }
  try {
    const chunks = [];
    let size = 0;
    for await (const chunk of request) {
      size += chunk.length;
      if (size > 512 * 1024) {
        response.writeHead(413).end();
        return;
      }
      chunks.push(chunk);
    }
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!models.includes(body.model) || !body.tools?.length) {
      response.writeHead(400).end();
      return;
    }
    response.writeHead(200, { 'Content-Type': 'text/event-stream; charset=UTF-8' });
    const last = body.messages?.at(-1)?.content;
    const prompt = typeof last === 'string' ? last : last?.map(item => item.text || '').join('');
    if (/^ScrollFollow(?:Seed|StreamFixture|Resume)\b/.test(prompt ?? '')) {
      const streaming = prompt.includes('ScrollFollowStreamFixture');
      const resuming = prompt.startsWith('ScrollFollowResume');
      const sendText = text => sse(response, anthropic
        ? { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text } }
        : { choices: [{ delta: { content: text } }] });
      if (streaming) {
        sendText('ScrollStreamFirst\n\n');
        await delay(12000);
      }
      const paragraphCount = streaming || resuming ? 16 : 48;
      for (let index = 1; index <= paragraphCount && !response.destroyed; index += 1) {
        sendText(`第 ${index} 段。用相同内容核对新消息增长时的阅读位置。\n\n`);
        await delay(streaming ? 180 : 30);
      }
      if (response.destroyed) return;
      sendText(streaming ? 'ScrollStreamTail' : resuming ? 'ScrollResumeTail' : 'ScrollSeedTail');
      if (anthropic) sse(response, { type: 'message_delta', delta: { stop_reason: 'end_turn' } });
      else {
        sse(response, { choices: [{ delta: {}, finish_reason: 'stop' }] });
        response.write('data: [DONE]\n\n');
      }
      response.end();
      return;
    }
    const automaticRepair = prompt?.includes('Failed OpenUI Lang source:');
    const firstFailure = prompt?.includes('FirstFailureParity') || (automaticRepair && prompt.includes(firstFailureTitle));
    const repairDocument = automaticRepair && prompt.includes(repairTitle)
      ? { title: repairTitle, source: prompt.includes('BrokenRevisionOnly') ? repeatingBadPatch : repairPatch }
      : prompt?.includes('RepairParityMigration') ? { title: repairTitle, source: '$count = "新的格式"' }
        : prompt?.includes('RepairParityReject') ? { title: repairTitle, source: repeatingBadPatch }
        : prompt?.includes('RepairParityCreate') ? { title: repairTitle, source: repairSource } : null;
    const historyTitle = prompt?.includes('HistoryParityAlpha') ? '三端记录甲'
      : prompt?.includes('HistoryParityBeta') ? '三端记录乙'
      : prompt?.includes('GalleryReturnParity') ? '三端应用馆会话核对'
      : prompt?.includes('TranscriptParityFixture') ? '三端会话卡片核对'
      : prompt?.includes('LongMessageParityFixture') ? '三端长消息核对' : null;
    const checkpointDocument = prompt?.includes('CheckpointParityUpdate') ? { title: checkpointTitle, source: checkpointPatch }
      : prompt?.includes('CheckpointParityBase') ? { title: checkpointTitle, source: checkpointSource } : null;
    const launcherDocument = prompt?.includes('ShortcutParityUpdate') ? { title: '三端桌面乙', source: launcherPatch }
      : prompt?.includes('ShortcutParityCreate') ? { title: '三端桌面甲', source: launcherSource } : null;
    const thumbnailRequest = prompt?.match(/\bThumbnailParity(Create|Update)([A-Fa-f0-9]{6})\b/);
    const thumbnailDocument = thumbnailRequest && (() => {
      const title = `三端封面核对 ${thumbnailRequest[2]}`;
      const update = thumbnailRequest[1] === 'Update';
      return { title, source: update ? launcherPatch.replaceAll('三端桌面乙', title).replace('更新后的桌面图标', '更新后的封面')
        : launcherSource.replaceAll('三端桌面甲', title).replace('初始桌面图标', '初始封面') };
    })();
    const firstFailureDocument = firstFailure ? {
      title: firstFailureTitle,
      source: prompt.includes('FirstFailureParityRecover') ? firstFailureFix : firstFailureSource,
    } : null;
    const insetsDocument = prompt?.includes('InsetsParityLandscape') ? { title: insetsTitle, source: insetsSource } : null;
    const document = firstFailureDocument ?? repairDocument ?? checkpointDocument ?? launcherDocument ?? thumbnailDocument ?? insetsDocument ?? (historyTitle ? { title: historyTitle, source: source.replaceAll('三端创作核对', historyTitle) }
      : prompt?.includes('Verify calenda') ? { title: '三端日历核对', source: calendarSource }
      : prompt?.includes('PhotoParityFixtu') ? { title: '三端图片核对', source: imageSource }
        : prompt?.includes('MotionParityFixtu') ? { title: '三端动效核对', source: animationSource }
          : prompt?.includes('GestureParityFixtu') ? { title: '三端手势核对', source: gestureSource }
            : prompt?.includes('DeviceImageParity') ? { title: '三端取材核对', source: collaborationSource }
              : { title: '三端创作核对', source });
    if (repairDocument) {
      const name = automaticRepair ? (document.source === repairPatch ? 'repair' : 'repeat')
        : prompt.includes('RepairParityMigration') ? 'migration' : document.source === repairSource ? 'create' : 'reject';
      console.log(`GenUI repair fixture: ${name}`);
      if (automaticRepair) await delay(1300);
    }
    if (checkpointDocument) console.log(`GenUI recovery fixture: ${document.source === checkpointPatch ? 'update' : 'base'}`);
    if (prompt?.includes('HistoryParityAlphaFollowUp')) await delay(2600);
    const toolCall = JSON.stringify(document);
    const reply = firstFailure ? '已生成应用草稿。' : prompt?.includes('LongMessageParityFixture')
      ? ['小应用已准备好。', ...Array.from({ length: 16 }, (_, index) => `第 ${index + 1} 段。用相同内容核对滚动、顶部工具栏和底部输入区。`)].join('\n\n')
      : prompt?.includes('TranscriptParityFixture') ? '核对：**保留格式**与原文。' : '小应用已准备好。';
    if (anthropic) {
      sse(response, { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: reply } });
      sse(response, { type: 'content_block_start', index: 1, content_block: { type: 'tool_use', name: 'GenerativeUI', id: 'fixture-app' } });
    } else {
      sse(response, { choices: [{ delta: { content: reply } }] });
    }
    // Split inside JSON argument strings so tools exercise their streaming decoders.
    for (let index = 0; index < toolCall.length; index += 16) {
      if (response.destroyed) return;
      const argumentsDelta = toolCall.slice(index, index + 16);
      if (anthropic) {
        sse(response, { type: 'content_block_delta', index: 1, delta: { type: 'input_json_delta', partial_json: argumentsDelta } });
      } else {
        sse(response, { choices: [{ delta: { tool_calls: [{
          index: 0,
          function: { ...(index === 0 ? { name: 'GenerativeUI' } : {}), arguments: argumentsDelta },
        }] } }] });
      }
      await delay(40);
    }
    if (anthropic) sse(response, { type: 'message_delta', delta: { stop_reason: 'tool_use' } });
    else {
      sse(response, { choices: [{ delta: {}, finish_reason: 'tool_calls' }] });
      response.write('data: [DONE]\n\n');
    }
    response.end();
  } catch {
    if (!response.headersSent) response.writeHead(400);
    response.end();
  }
}).listen(port, '127.0.0.1', () => console.log(`Local GenUI model fixture on 127.0.0.1:${port}`));
