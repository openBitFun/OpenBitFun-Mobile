// A complete playable HtmlView fixture adapted from the Harmony GenUI gallery.
// Keep this example in the mobile prompt so the phone model has a concrete
// game-loop pattern with touch controls, restart behavior and a canvas.
const arcadeHtml = String.raw`<style>
html,body{touch-action:none;overscroll-behavior:none}body{padding:12px;display:flex;flex-direction:column;gap:10px;align-items:center;background:#0b0b1a;color:#e6e6ff;font-family:ui-monospace,Menlo,monospace}
.top{display:flex;justify-content:space-between;width:100%;max-width:400px;font-size:13px;letter-spacing:.06em}
canvas{width:100%;max-width:400px;aspect-ratio:4/5;border-radius:10px;background:#05050f;box-shadow:0 0 0 1px #2a2a55,0 0 24px #3b1d6e66;touch-action:none;outline:none}
.pad{display:flex;gap:8px;width:100%;max-width:400px}
.pad button{flex:1;padding:12px 0;font:600 14px ui-monospace,Menlo,monospace;color:#e6e6ff;background:#1a1a3a;border:1px solid #3a3a7a;border-radius:10px;user-select:none;-webkit-user-select:none;touch-action:none;cursor:pointer}
.pad button:active{background:#2c2c66}
#start{background:#ff2bd6;border-color:#ff2bd6;color:#0b0b1a}
p{margin:0;font-size:12px;opacity:.7}
</style>
<div data-openbitfun-game class="top"><span id="score">SCORE 0</span><span id="wave">WAVE 1</span><span id="lives">♥♥♥</span></div>
<canvas id="c" width="400" height="500" tabindex="0"></canvas>
<div class="pad"><button id="left" data-game-control="left" aria-label="Move left">◀</button><button id="fire" data-game-control="fire">FIRE</button><button id="right" data-game-control="right" aria-label="Move right">▶</button></div>
<div class="pad"><button id="start">START GAME</button></div>
<p>Arrow keys move, space fires. On a phone, use the buttons.</p>
<script>
const c=document.getElementById('c'),g=c.getContext('2d'),W=400,H=500,S=id=>document.getElementById(id),keys={},pointerActions=new Map(),actionPointers=new Map();
let ship,shots,bombs,aliens,dir,speed,score=0,lives=3,wave=1,running=false,over=false,last=0,cool=0;
const stars=Array.from({length:60},()=>[Math.random()*W,Math.random()*H,Math.random()*1.5+.3]);
const colors=['#ff2bd6','#ffb000','#2bf0ff','#7dff5a'];
function newWave(){aliens=[];for(let r=0;r<4;r++)for(let k=0;k<8;k++)aliens.push({x:40+k*42,y:50+r*34,r});dir=1;speed=20+wave*8}
function reset(){ship={x:W/2};shots=[];bombs=[];score=0;lives=3;wave=1;over=false;newWave();hud()}
function hud(){S('score').textContent='SCORE '+score;S('wave').textContent='WAVE '+wave;S('lives').textContent='♥'.repeat(Math.max(lives,0))||'-'}
function fire(){if(running&&cool<=0&&shots.length<3){shots.push({x:ship.x,y:H-48});cool=.28}}
function step(dt){
const mv=(keys.ArrowLeft||keys.left?-1:0)+(keys.ArrowRight||keys.right?1:0);
ship.x=Math.max(20,Math.min(W-20,ship.x+mv*240*dt));cool-=dt;if(keys[' ']||keys.fire)fire();
shots.forEach(s=>s.y-=420*dt);
let edge=false;aliens.forEach(a=>{a.x+=dir*speed*dt;if(a.x<16||a.x>W-16)edge=true});
if(edge){dir*=-1;aliens.forEach(a=>{a.y+=14;a.x+=dir*2})}
if(aliens.length&&Math.random()<dt*(.8+wave*.3)){const a=aliens[Math.floor(Math.random()*aliens.length)];bombs.push({x:a.x,y:a.y+10})}
bombs.forEach(b=>b.y+=(150+wave*15)*dt);
for(const s of shots)for(const a of aliens)if(!a.dead&&!s.hit&&Math.abs(s.x-a.x)<14&&Math.abs(s.y-a.y)<11){a.dead=s.hit=true;score+=10*(4-a.r)}
aliens=aliens.filter(a=>!a.dead);shots=shots.filter(s=>!s.hit&&s.y>-10);
for(const b of bombs)if(Math.abs(b.x-ship.x)<16&&b.y>H-46&&b.y<H-20){b.hit=true;lives--}
bombs=bombs.filter(b=>!b.hit&&b.y<H);
if(aliens.some(a=>a.y>H-70))lives=0;
if(!aliens.length){wave++;newWave()}
if(lives<=0){running=false;over=true;S('start').textContent='PLAY AGAIN'}
hud()}
function draw(){
g.fillStyle='#05050f';g.fillRect(0,0,W,H);g.fillStyle='#fff';
stars.forEach(s=>{g.globalAlpha=s[2]/2;g.fillRect(s[0],s[1],s[2],s[2])});g.globalAlpha=1;
aliens.forEach(a=>{g.fillStyle=colors[a.r];g.shadowColor=colors[a.r];g.shadowBlur=8;g.fillRect(a.x-12,a.y-7,24,14);g.shadowBlur=0;g.fillStyle='#05050f';g.fillRect(a.x-7,a.y-3,4,4);g.fillRect(a.x+3,a.y-3,4,4)});
g.shadowBlur=10;g.shadowColor='#2bf0ff';g.fillStyle='#2bf0ff';g.beginPath();g.moveTo(ship.x,H-46);g.lineTo(ship.x+16,H-24);g.lineTo(ship.x-16,H-24);g.closePath();g.fill();
g.fillStyle='#fff';shots.forEach(s=>g.fillRect(s.x-1.5,s.y-8,3,10));
g.fillStyle='#ff4d4d';g.shadowColor='#ff4d4d';bombs.forEach(b=>g.fillRect(b.x-2,b.y-6,4,9));g.shadowBlur=0;
if(!running){g.fillStyle='rgba(5,5,15,.75)';g.fillRect(0,H/2-50,W,100);g.textAlign='center';g.fillStyle='#ff2bd6';g.font='bold 28px ui-monospace,Menlo,monospace';g.fillText(over?'GAME OVER':'NEON INVADERS',W/2,H/2-5);g.fillStyle='#e6e6ff';g.font='13px ui-monospace,Menlo,monospace';g.fillText(over?'Score '+score+'. Press play again':'Press start to play',W/2,H/2+22)}}
function loop(t){const dt=Math.min(.05,(t-last)/1000||0);last=t;if(running)step(dt);draw();requestAnimationFrame(loop)}
addEventListener('keydown',e=>{if(['ArrowLeft','ArrowRight',' '].includes(e.key)){keys[e.key]=true;e.preventDefault()}});
addEventListener('keyup',e=>{keys[e.key]=false});
function press(id,event){event.preventDefault();pointerActions.set(event.pointerId,id);actionPointers.set(id,(actionPointers.get(id)||0)+1);keys[id]=true;try{event.currentTarget.setPointerCapture(event.pointerId)}catch{}}
function release(event){const id=pointerActions.get(event.pointerId);if(!id)return;pointerActions.delete(event.pointerId);const count=(actionPointers.get(id)||1)-1;if(count>0){actionPointers.set(id,count)}else{actionPointers.delete(id);keys[id]=false}}
for(const id of ['left','right','fire']){const b=S(id);b.addEventListener('pointerdown',event=>press(id,event),{passive:false});b.addEventListener('pointerup',release);b.addEventListener('pointercancel',release);b.addEventListener('lostpointercapture',release)}
addEventListener('blur',()=>{pointerActions.clear();actionPointers.clear();for(const id of ['left','right','fire'])keys[id]=false});
S('start').onclick=()=>{reset();running=true;S('start').textContent='RESTART';c.focus()};
reset();requestAnimationFrame(loop);
</script>`;

const arcadeSource = [
  'root = Page([cover, game], "霓虹入侵者", "ink", null, {orientation: "landscape", mood: "night"})',
  'cover = Cover("霓虹入侵者", "Neon Invaders", "触控操作 · 波次推进", "👾", {variant: "immersive"})',
  `game = HtmlView(${JSON.stringify(arcadeHtml)}, 520, "Neon Invaders")`,
].join('\n');

export const HARMONY_LOCAL_GAME_PROMPT = [
  'Playable game generation for Harmony phones:',
  '- When the user asks for a video game, arcade game, shooter, platformer, real-time battle, or another game with movement and a loop, use HtmlView with a complete inline HTML/CSS/JavaScript implementation. The HTML must include a visible start or restart control and touch or pointer controls that work on a phone.',
  '- Mark the game root with data-openbitfun-game and each held-action control with data-game-control. Set touch-action:none on the game root, canvas and controls. For simultaneous actions such as moving and attacking, keep a Set or Map keyed by pointerId and release only that pointer on pointerup, pointercancel or lostpointercapture. Call preventDefault on pointerdown and use pointer capture inside try/catch. Do not use one activeButton variable, touches[0], or click handlers for held controls. Clear all held actions on window blur.',
  '- A game may show its own score, waves, lives and status inside HtmlView. Use Scoreboard only for a scorekeeping tool where the user wants to manually record two sides and no game loop is requested.',
  '- Keep the game offline. Do not load remote scripts, images or network resources. Prefer canvas or inline SVG, request landscape when the playfield benefits from width, and keep the complete HTML in one escaped HtmlView string.',
  '- This reference is adapted from the Harmony GenUI gallery example titled "A retro arcade game". Follow its structure and replace the theme, labels, sprites and rules to match the user request.',
  'Example — a playable arcade game:',
  '```',
  arcadeSource,
  '```',
].join('\n');
