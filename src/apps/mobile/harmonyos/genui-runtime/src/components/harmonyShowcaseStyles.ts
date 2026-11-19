/**
 * Layout and form of the Harmony showcase blocks (harmonyShowcase.tsx) and the
 * immersive cover. Unlike the looks in harmonyLooks.ts this sheet is always
 * applied to Harmony pages: it gives the blocks their shape, so they render in
 * every look. Colour comes from the page-kit tokens of the page theme plus a
 * companion and a third hue per theme. Motion stops under reduced motion and
 * in checker mode, and nothing starts fully transparent.
 */
const R = '.gen-ui-application.gen-ui-application--harmony-genui';
const P = `${R} .pk`;

const TRIADS: Record<string, [string, string]> = {
  blue: ['#8b5cf6', '#06b6d4'],
  indigo: ['#d946ef', '#38bdf8'],
  purple: ['#ec4899', '#f59e0b'],
  rose: ['#fb923c', '#a855f7'],
  orange: ['#f43f5e', '#eab308'],
  brown: ['#d6a24a', '#d97706'],
  green: ['#14b8a6', '#84cc16'],
  teal: ['#3b82f6', '#22c55e'],
  ink: ['#7c8594', '#475569'],
};
const triadRules = Object.entries(TRIADS)
  .map(([theme, [two, three]]) => `${R}:has(.pk[data-hm-theme="${theme}"]) { --sc-2: ${two}; --sc-3: ${three}; }`)
  .join('\n');

export const HARMONY_SHOWCASE_CSS = String.raw`
${R} { --sc-2: #8b5cf6; --sc-3: #06b6d4; }
${triadRules}
${P} {
  --sc-1: var(--pk-accent);
  --sc-deep: color-mix(in srgb, var(--pk-accent) 72%, #070b1a);
  --sc-edge: color-mix(in srgb, var(--pk-ink) 7%, transparent);
  --sc-shadow: 0 16px 32px -22px color-mix(in srgb, var(--sc-1) 70%, transparent), 0 2px 6px -3px color-mix(in srgb, var(--pk-ink) 14%, transparent);
  --sc-r: 22px;
}
${P} :is(.sc-ring, .sc-ticket, .sc-rank, .sc-bars, .sc-heat, .sc-statement, .sc-tile[data-style="glass"]) {
  position: relative;
  background: radial-gradient(140% 90% at 0% 0%, color-mix(in srgb, var(--sc-1) 6%, transparent), transparent 55%), var(--pk-card);
  border-radius: var(--sc-r);
  box-shadow: inset 0 0 0 1px var(--sc-edge), var(--sc-shadow);
}
${P} .sc-pic { display: inline-grid; place-items: center; flex: none; line-height: 1; }
${P} .sc-pic > img { width: 100%; height: 100%; object-fit: contain; display: block; }
${P} .sc-pic > span { font-size: 0.8em; }
${P} :is(.sc-ring-label, .sc-shelf-label, .sc-rank-label, .sc-bars-label, .sc-heat-label, .sc-count-label) {
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.02em;
  color: var(--pk-ink);
}

/* ---------- Bento board ---------- */
${P} .sc-bento {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  grid-auto-rows: minmax(128px, auto);
  grid-auto-flow: row dense;
  gap: 10px;
}
${P} .sc-bento > * { min-width: 0; }
${P} .sc-bento > :is(.sc-ring, .sc-spot, .sc-count, .sc-bars, .sc-heat, .sc-statement, .sc-ticket, .sc-rank, .sc-shelf, .pk-hero-stat, .pk-chart, .pk-progress, .pk-note) { grid-column: 1 / -1; }
@media (min-width: 600px) {
  ${P} .sc-bento { grid-template-columns: repeat(4, minmax(0, 1fr)); }
  ${P} .sc-bento > :is(.sc-ring, .sc-count, .sc-bars, .sc-heat, .pk-hero-stat, .pk-progress) { grid-column: span 2; }
}

/* ---------- Tile ---------- */
${P} .sc-tile {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-height: 128px;
  padding: 14px 14px 16px;
  border-radius: var(--sc-r);
  overflow: hidden;
  isolation: isolate;
}
${P} .sc-tile[data-size="w"], ${P} .sc-tile[data-size="l"] { grid-column: span 2; }
${P} .sc-tile[data-size="t"], ${P} .sc-tile[data-size="l"] { grid-row: span 2; }
${P} .sc-tile-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 8px; }
${P} .sc-tile-label { font-size: 12px; font-weight: 700; letter-spacing: 0.04em; color: var(--pk-ink-2); line-height: 1.35; }
${P} .sc-tile-pic { width: 40px; height: 40px; margin: -4px -4px 0 0; filter: drop-shadow(0 6px 8px color-mix(in srgb, var(--pk-ink) 22%, transparent)); }
${P} .sc-tile[data-size="l"] .sc-tile-pic, ${P} .sc-tile[data-size="t"] .sc-tile-pic { width: 64px; height: 64px; }
${P} .sc-tile[data-size="l"] .sc-tile-pic { position: absolute; right: 12px; bottom: 12px; width: 108px; height: 108px; margin: 0; opacity: 0.95; z-index: -1; }
${P} .sc-tile-value {
  margin-top: auto;
  font-size: 30px;
  line-height: 1.05;
  font-weight: 800;
  letter-spacing: -0.03em;
  font-variant-numeric: tabular-nums;
  color: var(--pk-ink);
  overflow-wrap: anywhere;
}
${P} .sc-tile[data-size="l"] .sc-tile-value { font-size: 46px; }
${P} .sc-tile-value small { margin-left: 3px; font-size: 13px; font-weight: 600; letter-spacing: 0; color: var(--pk-ink-2); }
${P} .sc-tile[data-tone="success"] .sc-tile-value { color: var(--color-text-success); }
${P} .sc-tile[data-tone="warning"] .sc-tile-value { color: var(--color-text-warning); }
${P} .sc-tile[data-tone="danger"] .sc-tile-value { color: var(--color-text-danger); }
${P} .sc-tile-delta {
  align-self: flex-start;
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 700;
  background: color-mix(in srgb, var(--pk-ink) 7%, transparent);
  color: var(--pk-ink-2);
}
${P} .sc-tile-delta[data-trend="up"] { color: var(--color-text-success); background: color-mix(in srgb, var(--color-text-success) 13%, transparent); }
${P} .sc-tile-delta[data-trend="down"] { color: var(--color-text-danger); background: color-mix(in srgb, var(--color-text-danger) 13%, transparent); }
${P} .sc-tile-sub { margin: 0; font-size: 12px; line-height: 1.45; color: var(--pk-ink-2); }
${P} .sc-tile-bar { display: block; height: 6px; margin-top: 8px; border-radius: 3px; background: color-mix(in srgb, var(--pk-ink) 9%, transparent); overflow: hidden; }
${P} .sc-tile-bar::before { content: ""; display: block; width: var(--sc-v); height: 100%; border-radius: inherit; background: linear-gradient(90deg, var(--sc-1), var(--sc-2)); animation: sc-grow 0.9s cubic-bezier(0.2, 0.8, 0.2, 1) both; }
${P} .sc-tile[data-style="tint"] { background: linear-gradient(150deg, color-mix(in srgb, var(--sc-1) 16%, var(--pk-card)), color-mix(in srgb, var(--sc-2) 10%, var(--pk-card))); box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--sc-1) 14%, transparent); }
${P} .sc-tile[data-style="vivid"] {
  color: #fff;
  background:
    radial-gradient(120% 90% at 100% 0%, color-mix(in srgb, var(--sc-2) 75%, transparent), transparent 60%),
    linear-gradient(150deg, var(--sc-1), var(--sc-deep));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.25), 0 18px 30px -18px color-mix(in srgb, var(--sc-1) 90%, transparent);
}
${P} .sc-tile[data-style="vivid"] :is(.sc-tile-label, .sc-tile-sub, .sc-tile-value small) { color: rgba(255, 255, 255, 0.78); }
${P} .sc-tile[data-style="vivid"] .sc-tile-value { color: #fff; }
${P} .sc-tile[data-style="vivid"] .sc-tile-bar { background: rgba(255, 255, 255, 0.22); }
${P} .sc-tile[data-style="vivid"] .sc-tile-bar::before { background: #fff; }
${P} .sc-tile[data-style="vivid"] .sc-tile-delta { color: #fff; background: rgba(255, 255, 255, 0.2); }

/* ---------- Rings and gauge ---------- */
${P} .sc-ring { padding: 16px; display: flex; flex-direction: column; gap: 10px; }
${P} .sc-ring-body { display: flex; align-items: center; gap: 18px; }
${P} .sc-rings { position: relative; flex: none; width: 150px; height: 150px; }
${P} .sc-rings svg { width: 100%; height: 100%; transform: rotate(-90deg); overflow: visible; }
${P} .sc-ring .sc-track { fill: none; stroke: color-mix(in srgb, var(--sc-c) 16%, transparent); }
${P} .sc-ring .sc-arc { fill: none; stroke: var(--sc-c); stroke-linecap: round; filter: drop-shadow(0 0 6px color-mix(in srgb, var(--sc-c) 55%, transparent)); animation: sc-arc 1.1s cubic-bezier(0.2, 0.8, 0.2, 1) both; }
${P} .sc-ring [data-ring="0"] { --sc-c: var(--sc-1); }
${P} .sc-ring [data-ring="1"] { --sc-c: var(--sc-2); }
${P} .sc-ring [data-ring="2"] { --sc-c: var(--sc-3); }
${P} .sc-rings-center { position: absolute; inset: 0; display: grid; place-content: center; text-align: center; }
${P} .sc-rings-center b { font-size: 24px; font-weight: 800; letter-spacing: -0.02em; font-variant-numeric: tabular-nums; }
${P} .sc-rings-center span { font-size: 11px; color: var(--pk-ink-2); }
${P} .sc-ring-body:has([data-ring="2"]) .sc-rings-center b { font-size: 19px; }
${P} .sc-ring-legend { flex: 1; min-width: 0; margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column; gap: 12px; }
${P} .sc-ring-legend li { display: grid; grid-template-columns: 10px minmax(0, 1fr); column-gap: 8px; align-items: center; }
${P} .sc-ring-legend i { width: 10px; height: 10px; border-radius: 50%; background: var(--sc-c); box-shadow: 0 0 8px color-mix(in srgb, var(--sc-c) 70%, transparent); }
${P} .sc-ring-legend span { font-size: 12px; color: var(--pk-ink-2); }
${P} .sc-ring-legend b { grid-column: 2; font-size: 18px; font-weight: 800; font-variant-numeric: tabular-nums; color: var(--sc-c); }
${P} .sc-ring-legend small { margin-left: 2px; font-size: 11px; font-weight: 600; color: var(--pk-ink-3); }
${P} .sc-ring-sub { margin: 0; text-align: center; font-size: 12px; color: var(--pk-ink-2); }
${P} .sc-gauge { position: relative; width: min(100%, 260px); margin: 0 auto; }
${P} .sc-gauge svg { display: block; width: 100%; overflow: visible; }
${P} .sc-gauge .sc-track { fill: none; stroke: color-mix(in srgb, var(--pk-ink) 9%, transparent); stroke-width: 14; stroke-linecap: round; }
${P} .sc-gauge .sc-arc { fill: none; stroke-width: 14; stroke-linecap: round; filter: drop-shadow(0 0 8px color-mix(in srgb, var(--sc-1) 50%, transparent)); animation: sc-arc 1.2s cubic-bezier(0.2, 0.8, 0.2, 1) both; }
${P} .sc-gauge .sc-stop-a { stop-color: var(--sc-1); }
${P} .sc-gauge .sc-stop-b { stop-color: var(--sc-2); }
${P} .sc-gauge .sc-tick { stroke: color-mix(in srgb, var(--pk-ink) 28%, transparent); stroke-width: 1.5; stroke-linecap: round; }
${P} .sc-gauge .sc-needle { transform-origin: 100px 100px; transform-box: view-box; transition: transform 0.9s cubic-bezier(0.2, 0.9, 0.25, 1.15); animation: sc-needle 1.2s cubic-bezier(0.2, 0.9, 0.25, 1.15) both; }
${P} .sc-gauge .sc-needle path { fill: var(--pk-ink); }
${P} .sc-gauge .sc-needle circle { fill: var(--pk-card); stroke: var(--pk-ink); stroke-width: 3; }
${P} .sc-gauge-read { display: flex; flex-direction: column; align-items: center; margin-top: -2px; }
${P} .sc-gauge-read b { font-size: 30px; font-weight: 800; letter-spacing: -0.02em; font-variant-numeric: tabular-nums; }
${P} .sc-gauge-read span { font-size: 12px; color: var(--pk-ink-2); }

/* ---------- Spotlight ---------- */
${P} .sc-spot {
  position: relative;
  isolation: isolate;
  overflow: hidden;
  min-height: 196px;
  padding: 22px 20px;
  border-radius: 28px;
  color: #fff;
  background:
    radial-gradient(80% 90% at 95% 10%, color-mix(in srgb, var(--sc-2) 80%, transparent), transparent 62%),
    radial-gradient(70% 70% at 0% 100%, color-mix(in srgb, var(--sc-3) 45%, transparent), transparent 65%),
    linear-gradient(150deg, var(--sc-1), var(--sc-deep));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.25), 0 26px 40px -26px color-mix(in srgb, var(--sc-1) 95%, transparent);
}
${P} .sc-spot-glow { position: absolute; inset: auto -20% -50% auto; width: 70%; aspect-ratio: 1; border-radius: 50%; background: radial-gradient(closest-side, rgba(255, 255, 255, 0.28), transparent); z-index: -1; }
${P} .sc-spot-pic { position: absolute; right: -6px; top: 50%; width: 150px; height: 150px; margin-top: -75px; z-index: -1; filter: drop-shadow(0 18px 22px rgba(0, 0, 0, 0.32)); animation: sc-float 6s ease-in-out infinite; }
${P} .sc-spot-copy { position: relative; display: flex; flex-direction: column; gap: 6px; max-width: 64%; }
${P} .sc-spot-eyebrow { margin: 0; font-size: 11px; font-weight: 700; letter-spacing: 0.16em; text-transform: uppercase; color: rgba(255, 255, 255, 0.75); }
${P} .sc-spot h3 { margin: 0; font-size: 24px; line-height: 1.2; font-weight: 800; letter-spacing: -0.01em; text-wrap: balance; }
${P} .sc-spot-sub { margin: 0; font-size: 13px; line-height: 1.5; color: rgba(255, 255, 255, 0.85); }
${P} .sc-spot-value { margin: 4px 0 0; font-size: 34px; font-weight: 800; letter-spacing: -0.03em; font-variant-numeric: tabular-nums; }
${P} .sc-spot-value small { margin-left: 3px; font-size: 13px; font-weight: 600; color: rgba(255, 255, 255, 0.8); }
${P} .sc-spot-tags { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
${P} .sc-spot-tags span { padding: 3px 10px; border-radius: 999px; font-size: 11px; font-weight: 600; background: rgba(255, 255, 255, 0.18); box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.25); -webkit-backdrop-filter: blur(8px); backdrop-filter: blur(8px); }

/* ---------- Shelf ---------- */
${P} .sc-shelf { display: flex; flex-direction: column; gap: 10px; min-width: 0; }
${P} .sc-shelf-label { padding: 0 4px; }
${P} .sc-shelf-track {
  display: flex;
  gap: 12px;
  margin: 0 calc(-1 * var(--pk-gutter, 16px));
  padding: 4px var(--pk-gutter, 16px) 18px;
  overflow-x: auto;
  scroll-snap-type: x mandatory;
  scroll-padding-inline: var(--pk-gutter, 16px);
  scrollbar-width: none;
}
${P} .sc-shelf-track::-webkit-scrollbar { display: none; }
${P} .sc-shelf-card {
  flex: 0 0 156px;
  display: flex;
  flex-direction: column;
  padding: 0;
  border: 0;
  border-radius: var(--sc-r);
  overflow: hidden;
  background: var(--pk-card);
  color: inherit;
  font: inherit;
  text-align: start;
  scroll-snap-align: start;
  box-shadow: inset 0 0 0 1px var(--sc-edge), var(--sc-shadow);
  transition: transform 0.18s;
}
${P} .sc-shelf[data-size="s"] .sc-shelf-card { flex-basis: 124px; }
${P} .sc-shelf[data-size="l"] .sc-shelf-card { flex-basis: 232px; }
${P} button.sc-shelf-card { cursor: pointer; }
${P} button.sc-shelf-card:active { transform: scale(0.97); }
${P} .sc-shelf-stage { position: relative; display: grid; place-items: center; height: 116px; }
${P} .sc-shelf[data-size="l"] .sc-shelf-stage { height: 150px; }
${P} .sc-shelf-card[data-i="0"] .sc-shelf-stage { background: linear-gradient(150deg, color-mix(in srgb, var(--sc-1) 26%, var(--pk-card)), color-mix(in srgb, var(--sc-2) 16%, var(--pk-card))); }
${P} .sc-shelf-card[data-i="1"] .sc-shelf-stage { background: linear-gradient(150deg, color-mix(in srgb, var(--sc-2) 26%, var(--pk-card)), color-mix(in srgb, var(--sc-3) 16%, var(--pk-card))); }
${P} .sc-shelf-card[data-i="2"] .sc-shelf-stage { background: linear-gradient(150deg, color-mix(in srgb, var(--sc-3) 26%, var(--pk-card)), color-mix(in srgb, var(--sc-1) 16%, var(--pk-card))); }
${P} .sc-shelf-card[data-i="3"] .sc-shelf-stage { background: linear-gradient(150deg, color-mix(in srgb, var(--sc-1) 18%, var(--pk-card)), color-mix(in srgb, var(--sc-3) 22%, var(--pk-card))); }
${P} .sc-shelf-stage .sc-pic { width: 76px; height: 76px; font-size: 56px; filter: drop-shadow(0 12px 12px color-mix(in srgb, var(--pk-ink) 24%, transparent)); }
${P} .sc-shelf[data-size="l"] .sc-shelf-stage .sc-pic { width: 100px; height: 100px; }
${P} .sc-shelf-tag { position: absolute; top: 10px; left: 10px; padding: 2px 8px; border-radius: 999px; font-size: 10px; font-weight: 700; color: var(--pk-ink); background: color-mix(in srgb, var(--pk-card) 70%, transparent); -webkit-backdrop-filter: blur(8px); backdrop-filter: blur(8px); }
${P} .sc-shelf-copy { display: flex; flex-direction: column; gap: 3px; padding: 10px 12px 14px; }
${P} .sc-shelf-copy b { font-size: 15px; line-height: 1.3; font-weight: 700; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
${P} .sc-shelf-copy span { font-size: 12px; line-height: 1.4; color: var(--pk-ink-2); display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
${P} .sc-shelf-copy em { margin-top: 4px; font-style: normal; font-size: 15px; font-weight: 800; color: color-mix(in srgb, var(--sc-1) 85%, var(--pk-ink)); font-variant-numeric: tabular-nums; }

/* ---------- Host photos ---------- */
${P} :is(.sc-shelf-photo, .sc-spot-photo) { position: absolute; inset: 0; display: grid; place-items: center; overflow: hidden; }
${P} .sc-photo { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; opacity: 0; transition: opacity 0.5s ease-out, transform 6s ease-out; transform: scale(1.06); }
${P} [data-photo="ready"] > .sc-photo { opacity: 1; transform: none; }
${P} [data-photo="ready"] > .sc-pic { opacity: 0; }
${P} .sc-shelf-photo > .sc-pic { width: 76px; height: 76px; font-size: 56px; transition: opacity 0.3s; }
${P} .sc-shelf-stage:has([data-photo="ready"]) .sc-shelf-tag { background: rgba(0, 0, 0, 0.42); color: #fff; }
${P} .sc-spot[data-has-photo] { min-height: 230px; display: flex; align-items: flex-end; }
${P} .sc-spot-photo { z-index: -2; }
${P} .sc-spot-photo > .sc-pic { position: absolute; right: -6px; top: 50%; width: 150px; height: 150px; margin-top: -75px; filter: drop-shadow(0 18px 22px rgba(0, 0, 0, 0.32)); }
${P} .sc-spot[data-has-photo]:has([data-photo="ready"])::after { content: ""; position: absolute; inset: 0; z-index: -1; background: linear-gradient(100deg, color-mix(in srgb, var(--sc-deep) 82%, transparent) 0%, color-mix(in srgb, var(--sc-deep) 55%, transparent) 55%, transparent 100%), linear-gradient(180deg, rgba(0, 0, 0, 0.1), rgba(0, 0, 0, 0.35)); }
${P} .sc-spot[data-has-photo]:has([data-photo="ready"]) .sc-spot-copy { text-shadow: 0 1px 12px rgba(0, 0, 0, 0.35); }
${P} .sc-spot[data-has-photo]:has([data-photo="ready"]) .sc-spot-copy { max-width: 78%; }

/* ---------- Ticket ---------- */
${P} .sc-ticket { overflow: hidden; }
${P} .sc-ticket-main { padding: 16px 18px 18px; background: linear-gradient(180deg, color-mix(in srgb, var(--sc-1) 9%, transparent), transparent 70%); }
${P} .sc-ticket-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; font-size: 12px; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase; color: color-mix(in srgb, var(--sc-1) 75%, var(--pk-ink)); }
${P} .sc-ticket-pic { width: 34px; height: 34px; }
${P} .sc-ticket-route { display: grid; grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr); align-items: center; gap: 10px; margin-top: 12px; }
${P} .sc-ticket-route > div:first-child, ${P} .sc-ticket-route > div:last-child { display: flex; flex-direction: column; min-width: 0; }
${P} .sc-ticket-route > div:last-child { align-items: flex-end; text-align: end; }
${P} .sc-ticket-route b { font-size: 32px; line-height: 1.1; font-weight: 800; letter-spacing: -0.02em; overflow-wrap: anywhere; }
${P} .sc-ticket-route span { font-size: 12px; color: var(--pk-ink-2); }
${P} .sc-ticket-path { display: flex; align-items: center; gap: 6px; width: 84px; color: var(--sc-1); }
${P} .sc-ticket-path i { flex: 1; border-top: 2px dashed color-mix(in srgb, var(--sc-1) 45%, transparent); }
${P} .sc-ticket-path span { display: grid; place-items: center; width: 30px; height: 30px; border-radius: 50%; font-size: 15px; background: color-mix(in srgb, var(--sc-1) 13%, transparent); }
${P} .sc-ticket-fields { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px 10px; margin: 16px 0 0; }
${P} .sc-ticket-fields div { min-width: 0; }
${P} .sc-ticket-fields dt { font-size: 11px; color: var(--pk-ink-3); }
${P} .sc-ticket-fields dd { margin: 2px 0 0; font-size: 15px; font-weight: 700; font-variant-numeric: tabular-nums; overflow-wrap: anywhere; }
${P} .sc-ticket-stub { position: relative; display: flex; align-items: center; gap: 14px; padding: 14px 18px 16px; border-top: 2px dashed color-mix(in srgb, var(--pk-ink) 14%, transparent); }
${P} .sc-ticket-stub::before, ${P} .sc-ticket-stub::after { content: ""; position: absolute; top: -11px; width: 20px; height: 20px; border-radius: 50%; background: var(--color-background-secondary); box-shadow: inset 0 0 0 1px var(--sc-edge); }
${P} .sc-ticket-stub::before { left: -10px; }
${P} .sc-ticket-stub::after { right: -10px; }
${P} .sc-ticket-bars { flex: 1; display: flex; gap: 2px; height: 38px; }
${P} .sc-ticket-bars i { flex-basis: 0; border-radius: 1px; background: var(--pk-ink); opacity: 0.85; }
${P} .sc-ticket-bars i:nth-child(3n) { opacity: 0.35; }
${P} .sc-ticket-stub span { font-size: 12px; font-weight: 700; letter-spacing: 0.12em; font-family: ui-monospace, monospace; color: var(--pk-ink-2); }

/* ---------- Countdown ---------- */
${P} .sc-count {
  position: relative;
  overflow: hidden;
  isolation: isolate;
  padding: 18px 16px 20px;
  border-radius: 28px;
  color: #fff;
  background:
    radial-gradient(90% 80% at 100% 0%, color-mix(in srgb, var(--sc-2) 70%, transparent), transparent 60%),
    linear-gradient(160deg, var(--sc-deep), color-mix(in srgb, var(--sc-1) 55%, #050816));
  box-shadow: 0 26px 40px -26px color-mix(in srgb, var(--sc-1) 95%, transparent);
}
${P} .sc-count::after { content: ""; position: absolute; inset: 0; z-index: -1; background-image: radial-gradient(rgba(255, 255, 255, 0.5) 1px, transparent 1.3px); background-size: 22px 22px; -webkit-mask-image: linear-gradient(180deg, #000, transparent 75%); mask-image: linear-gradient(180deg, #000, transparent 75%); opacity: 0.35; }
${P} .sc-count-label { color: rgba(255, 255, 255, 0.82); }
${P} .sc-count-cells { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 8px; margin-top: 12px; }
${P} .sc-count-cell { position: relative; display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 12px 0 10px; border-radius: 16px; background: rgba(255, 255, 255, 0.12); box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.2), inset 0 0 0 1px rgba(255, 255, 255, 0.1); }
${P} .sc-count-cell::after { content: ""; position: absolute; left: 0; right: 0; top: 50%; height: 1px; background: rgba(0, 0, 0, 0.22); }
${P} .sc-count-cell b { font-size: 34px; line-height: 1; font-weight: 800; letter-spacing: -0.02em; font-variant-numeric: tabular-nums; }
${P} .sc-count-cell span { font-size: 11px; color: rgba(255, 255, 255, 0.7); }
${P} .sc-count-cell:last-child b { animation: sc-tick 1s steps(1) infinite; }
${P} .sc-count-done { margin: 12px 0 0; font-size: 28px; font-weight: 800; }
${P} .sc-count-sub { margin: 12px 0 0; font-size: 12px; color: rgba(255, 255, 255, 0.75); }

/* ---------- Ranking ---------- */
${P} .sc-rank { padding: 16px; display: flex; flex-direction: column; gap: 12px; }
${P} .sc-podium { display: flex; align-items: flex-end; justify-content: center; gap: 8px; padding-top: 6px; }
${P} .sc-podium-place { flex: 1; max-width: 120px; display: flex; flex-direction: column; align-items: stretch; gap: 8px; min-width: 0; }
${P} .sc-podium-who { display: flex; flex-direction: column; align-items: center; gap: 2px; text-align: center; min-width: 0; }
${P} .sc-podium-who .sc-pic { width: 46px; height: 46px; font-size: 34px; }
${P} .sc-podium-place[data-place="1"] .sc-podium-who .sc-pic { width: 60px; height: 60px; }
${P} .sc-podium-initial { display: grid; place-items: center; width: 44px; height: 44px; border-radius: 50%; font-weight: 800; color: #fff; background: linear-gradient(140deg, var(--sc-1), var(--sc-2)); }
${P} .sc-podium-who b { max-width: 100%; font-size: 13px; font-weight: 700; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
${P} .sc-podium-who > span:not(.sc-pic) { font-size: 12px; font-weight: 700; color: color-mix(in srgb, var(--sc-1) 80%, var(--pk-ink)); font-variant-numeric: tabular-nums; }
${P} .sc-podium-step { display: grid; place-items: start center; padding-top: 8px; border-radius: 14px 14px 6px 6px; color: #fff; font-size: 22px; font-weight: 800; animation: sc-rise-step 0.8s cubic-bezier(0.2, 0.9, 0.25, 1.1) both; transform-origin: bottom; }
${P} .sc-podium-place[data-place="1"] .sc-podium-step { height: 92px; background: linear-gradient(180deg, #fcd560, #e6a118); box-shadow: 0 10px 24px -10px #e6a118; }
${P} .sc-podium-place[data-place="2"] .sc-podium-step { height: 68px; background: linear-gradient(180deg, #e3e8ee, #a9b4c2); }
${P} .sc-podium-place[data-place="3"] .sc-podium-step { height: 52px; background: linear-gradient(180deg, #f0b98d, #c47a45); }
${P} .sc-rank-rest { margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column; }
${P} .sc-rank-rest li { display: flex; align-items: center; gap: 10px; padding: 10px 2px; }
${P} .sc-rank-rest li + li { border-top: 1px solid var(--sc-edge); }
${P} .sc-rank-no { width: 22px; text-align: center; font-size: 13px; font-weight: 800; color: var(--pk-ink-3); font-variant-numeric: tabular-nums; }
${P} .sc-rank-rest .sc-pic { width: 30px; height: 30px; font-size: 22px; }
${P} .sc-rank-name { flex: 1; min-width: 0; display: flex; flex-direction: column; }
${P} .sc-rank-name b { font-size: 14px; font-weight: 600; }
${P} .sc-rank-name small { font-size: 11px; color: var(--pk-ink-2); }
${P} .sc-rank-value { font-size: 14px; font-weight: 800; font-variant-numeric: tabular-nums; }

/* ---------- Bar list ---------- */
${P} .sc-bars { padding: 16px; display: flex; flex-direction: column; gap: 14px; }
${P} .sc-bar { display: flex; flex-direction: column; gap: 6px; --sc-c: var(--sc-1); }
${P} .sc-bar[data-tone="success"] { --sc-c: var(--color-text-success); }
${P} .sc-bar[data-tone="warning"] { --sc-c: var(--color-text-warning); }
${P} .sc-bar[data-tone="danger"] { --sc-c: var(--color-text-danger); }
${P} .sc-bar-head { display: flex; align-items: center; gap: 8px; min-width: 0; }
${P} .sc-bar-head .sc-pic { width: 26px; height: 26px; font-size: 20px; }
${P} .sc-bar-head > span:not(.sc-pic) { flex: 1; min-width: 0; font-size: 13px; font-weight: 600; }
${P} .sc-bar-head small { margin-left: 6px; font-size: 11px; font-weight: 400; color: var(--pk-ink-2); }
${P} .sc-bar-head b { font-size: 14px; font-weight: 800; font-variant-numeric: tabular-nums; }
${P} .sc-bar > i { display: block; height: 10px; border-radius: 5px; background: color-mix(in srgb, var(--sc-c) 12%, transparent); overflow: hidden; }
${P} .sc-bar > i::before { content: ""; display: block; width: var(--sc-v); height: 100%; border-radius: inherit; background: linear-gradient(90deg, color-mix(in srgb, var(--sc-c) 70%, var(--sc-2)), var(--sc-c)); animation: sc-grow 0.9s cubic-bezier(0.2, 0.8, 0.2, 1) var(--sc-d, 0ms) both; }
${P} .sc-bar[data-highlight] > i { height: 14px; border-radius: 7px; }
${P} .sc-bar[data-highlight] > i::before { background: linear-gradient(90deg, var(--sc-1), var(--sc-2)); box-shadow: 0 0 14px color-mix(in srgb, var(--sc-1) 60%, transparent); }
${P} .sc-bar[data-highlight] .sc-bar-head b { color: color-mix(in srgb, var(--sc-1) 85%, var(--pk-ink)); }

/* ---------- Heatmap ---------- */
${P} .sc-heat { padding: 16px; display: flex; flex-direction: column; gap: 12px; }
${P} .sc-heat-head { display: flex; align-items: baseline; justify-content: space-between; gap: 8px; }
${P} .sc-heat-meta { font-size: 12px; color: var(--pk-ink-2); white-space: nowrap; }
${P} .sc-heat-meta b { margin-right: 2px; font-size: 16px; font-weight: 800; color: var(--pk-ink); }
${P} .sc-heat-grid {
  display: grid;
  grid-auto-flow: column;
  grid-template-rows: repeat(7, auto);
  grid-template-columns: repeat(var(--sc-weeks), minmax(0, 1fr));
  gap: 4px;
  width: min(100%, calc(var(--sc-weeks) * 24px));
  margin-inline: auto;
}
${P} .sc-heat-grid i, ${P} .sc-heat-legend i { display: block; aspect-ratio: 1; border-radius: 4px; background: color-mix(in srgb, var(--pk-ink) 7%, transparent); }
${P} .sc-heat i[data-level="-1"] { background: transparent; }
${P} .sc-heat i[data-level="1"] { background: color-mix(in srgb, var(--sc-1) 28%, transparent); }
${P} .sc-heat i[data-level="2"] { background: color-mix(in srgb, var(--sc-1) 52%, transparent); }
${P} .sc-heat i[data-level="3"] { background: color-mix(in srgb, var(--sc-1) 78%, var(--sc-2)); }
${P} .sc-heat i[data-level="4"] { background: linear-gradient(140deg, var(--sc-1), var(--sc-2)); box-shadow: 0 0 8px color-mix(in srgb, var(--sc-1) 55%, transparent); }
${P} .sc-heat-legend { display: flex; align-items: center; justify-content: center; gap: 4px; font-size: 10px; color: var(--pk-ink-3); }
${P} .sc-heat-legend i { width: 11px; }

/* ---------- Statement ---------- */
${P} .sc-statement { margin: 0; padding: 30px 22px 22px; overflow: hidden; }
${P} .sc-statement::before {
  content: "\201C";
  position: absolute;
  top: -18px;
  left: 12px;
  font-size: 120px;
  line-height: 1;
  font-weight: 800;
  background: linear-gradient(140deg, var(--sc-1), var(--sc-2));
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
  opacity: 0.32;
}
${P} .sc-statement blockquote { position: relative; margin: 0; font-size: 21px; line-height: 1.5; font-weight: 700; letter-spacing: -0.005em; text-wrap: balance; }
${P} .sc-statement figcaption { position: relative; margin-top: 12px; font-size: 13px; color: var(--pk-ink-2); }
${P} .sc-statement figcaption::before { content: ""; display: inline-block; width: 18px; height: 2px; margin-right: 8px; vertical-align: middle; border-radius: 1px; background: linear-gradient(90deg, var(--sc-1), var(--sc-2)); }
${P} .sc-statement-pic { position: absolute; right: 14px; top: 14px; width: 44px; height: 44px; opacity: 0.9; }

/* ---------- Month calendar ---------- */
${P} .sc-cal { position: relative; padding: 16px 14px 14px; border-radius: var(--sc-r); background: radial-gradient(140% 90% at 0% 0%, color-mix(in srgb, var(--sc-1) 6%, transparent), transparent 55%), var(--pk-card); box-shadow: inset 0 0 0 1px var(--sc-edge), var(--sc-shadow); }
${P} .sc-cal-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 0 4px 12px; }
${P} .sc-cal-head b { font-size: 18px; font-weight: 800; letter-spacing: -0.01em; }
${P} .sc-cal-nav { display: flex; align-items: center; gap: 6px; }
${P} .sc-cal-nav button { display: grid; place-items: center; min-width: 34px; height: 34px; padding: 0 10px; border: 0; border-radius: 999px; background: color-mix(in srgb, var(--pk-ink) 6%, transparent); color: var(--pk-ink); font: inherit; font-size: 18px; line-height: 1; cursor: pointer; }
${P} .sc-cal-nav .sc-cal-today { font-size: 13px; font-weight: 700; color: color-mix(in srgb, var(--sc-1) 85%, var(--pk-ink)); background: color-mix(in srgb, var(--sc-1) 12%, transparent); }
${P} .sc-cal-grid { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); row-gap: 4px; }
${P} .sc-cal-weekday { padding-bottom: 6px; text-align: center; font-size: 12px; font-weight: 600; color: var(--pk-ink-3); }
${P} .sc-cal-weekday[data-weekend] { color: color-mix(in srgb, var(--sc-1) 60%, var(--pk-ink-3)); }
${P} .sc-cal-day { position: relative; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 3px; height: 46px; padding: 0; border: 0; background: none; color: var(--pk-ink); font: inherit; cursor: pointer; }
${P} .sc-cal-day > span { display: grid; place-items: center; width: 36px; height: 36px; border-radius: 50%; font-size: 15px; font-weight: 600; font-variant-numeric: tabular-nums; white-space: nowrap; transition: background-color 0.2s, color 0.2s, box-shadow 0.2s; }
${P} .sc-cal-day[data-weekend] > span { color: color-mix(in srgb, var(--pk-ink) 55%, transparent); }
${P} .sc-cal-day[data-today] > span { color: color-mix(in srgb, var(--sc-1) 90%, var(--pk-ink)); box-shadow: inset 0 0 0 2px color-mix(in srgb, var(--sc-1) 55%, transparent); }
${P} .sc-cal-day[aria-selected="true"] > span { color: #fff; background: linear-gradient(140deg, var(--sc-1), var(--sc-2)); box-shadow: 0 6px 14px -6px color-mix(in srgb, var(--sc-1) 90%, transparent); }
${P} .sc-cal-day:active > span { transform: scale(0.92); }
${P} .sc-cal-dots { position: absolute; bottom: 1px; display: flex; gap: 3px; }
${P} .sc-cal-dots em { width: 5px; height: 5px; border-radius: 50%; background: var(--sc-1); }
${P} .sc-cal-dots em[data-tone="success"] { background: var(--color-text-success); }
${P} .sc-cal-dots em[data-tone="warning"] { background: var(--color-text-warning); }
${P} .sc-cal-dots em[data-tone="danger"] { background: var(--color-text-danger); }
${P} .sc-cal-agenda { display: flex; flex-direction: column; gap: 8px; margin-top: 12px; padding: 12px 6px 2px; border-top: 1px solid var(--sc-edge); }
${P} .sc-cal-agenda-head { font-size: 13px; font-weight: 700; color: var(--pk-ink-2); }
${P} .sc-cal-item { display: flex; align-items: center; gap: 10px; padding: 10px 12px; border-radius: 14px; font-size: 14px; font-weight: 600; background: color-mix(in srgb, var(--sc-c, var(--sc-1)) 9%, transparent); }
${P} .sc-cal-item > i { width: 4px; align-self: stretch; border-radius: 2px; background: var(--sc-c, var(--sc-1)); }
${P} .sc-cal-item[data-tone="success"] { --sc-c: var(--color-text-success); }
${P} .sc-cal-item[data-tone="warning"] { --sc-c: var(--color-text-warning); }
${P} .sc-cal-item[data-tone="danger"] { --sc-c: var(--color-text-danger); }
${P} .sc-cal-free { font-size: 13px; color: var(--pk-ink-3); padding: 4px 0 6px; }
@media (min-width: 600px) {
  ${P} .sc-cal-day { height: 56px; }
  ${P} .sc-cal-day > span { width: 42px; height: 42px; font-size: 16px; }
}

/* Dense hand-built grids (calendars, matrices): short labels never split
   into one glyph per line, and cell padding yields to the column width. */
${P} .gen-ui-oi-grid :is(.gen-ui-oi-text, .gen-ui-oi-title, .gen-ui-oi-caption) { overflow-wrap: break-word; word-break: keep-all; }
${P} .gen-ui-oi-grid:has(> :nth-child(28)) > * { min-width: 0; }
${P} .gen-ui-oi-grid:has(> :nth-child(28)) :is(.gen-ui-oi-box, .gen-ui-oi-pressable) { padding-inline: clamp(2px, 8%, 10px) !important; }
${P} .gen-ui-oi-grid:has(> :nth-child(28)) .gen-ui-oi-pressable > .gen-ui-oi-box { align-self: stretch; }

/* ---------- Scoreboard: arena jumbotron (every look) ---------- */
${R}:has(.pk[data-hm-theme="blue"]), ${R}:has(.pk[data-hm-theme="indigo"]), ${R}:has(.pk[data-hm-theme="green"]), ${R}:has(.pk[data-hm-theme="teal"]) { --sb-b: #fb923c; }
${R}:has(.pk[data-hm-theme="purple"]), ${R}:has(.pk[data-hm-theme="rose"]) { --sb-b: #22d3ee; }
${R}:has(.pk[data-hm-theme="orange"]), ${R}:has(.pk[data-hm-theme="brown"]) { --sb-b: #38bdf8; }
${R}:has(.pk[data-hm-theme="ink"]) { --sb-b: #f43f5e; }
${P} .pk-scoreboard[data-sb-ready] {
  --sb-a: color-mix(in srgb, var(--pk-accent) 82%, #fff);
  --sb-b2: var(--sb-b, #22d3ee);
  position: relative;
  isolation: isolate;
  overflow: hidden;
  padding: 16px 14px 14px;
  border-radius: 28px;
  color: #fff;
  background:
    radial-gradient(60% 55% at 22% 0%, color-mix(in srgb, var(--sb-a) 38%, transparent), transparent 70%),
    radial-gradient(60% 55% at 78% 0%, color-mix(in srgb, var(--sb-b2) 34%, transparent), transparent 70%),
    linear-gradient(180deg, #121a33 0%, #0a0f1f 100%);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.12), inset 0 0 0 1px rgba(255, 255, 255, 0.06), 0 30px 50px -30px color-mix(in srgb, var(--sb-a) 80%, #000);
}
${P} .pk-scoreboard[data-sb-ready]::before {
  content: "";
  position: absolute;
  inset: 0;
  z-index: -1;
  pointer-events: none;
  background:
    linear-gradient(90deg, transparent calc(50% - 1px), rgba(255, 255, 255, 0.08) calc(50% - 1px) calc(50% + 1px), transparent calc(50% + 1px)),
    repeating-linear-gradient(90deg, rgba(255, 255, 255, 0.025) 0 1px, transparent 1px 34px);
}
${P} .pk-scoreboard[data-sb-ready] .sb-header { display: flex; align-items: center; justify-content: space-between; gap: 8px; color: rgba(255, 255, 255, 0.85); }
${P} .pk-scoreboard[data-sb-ready] [data-sb-status] { display: inline-flex; align-items: center; gap: 8px; padding: 5px 12px 5px 10px; border-radius: 999px; font-size: 12px; font-weight: 800; letter-spacing: 0.12em; background: rgba(255, 255, 255, 0.08); box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.12); }
${P} .pk-scoreboard[data-sb-ready] [data-sb-status]::before { content: ""; width: 8px; height: 8px; border-radius: 50%; background: #ff3b4f; box-shadow: 0 0 10px #ff3b4f; animation: sb-live 1.4s ease-in-out infinite; }
${P} .pk-scoreboard[data-sb-phase="match"] [data-sb-status]::before, ${P} .pk-scoreboard[data-sb-phase="game"] [data-sb-status]::before { background: #fcd34d; box-shadow: 0 0 10px #fcd34d; animation: none; }
${P} .pk-scoreboard[data-sb-ready] :is(.sb-header, .sb-footer) .pk-btn {
  height: 34px;
  padding: 0 14px;
  border-radius: 999px;
  color: #fff;
  font-size: 13px;
  font-weight: 700;
  background: rgba(255, 255, 255, 0.12);
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.16);
  -webkit-backdrop-filter: blur(8px);
  backdrop-filter: blur(8px);
}
${P} .pk-scoreboard[data-sb-ready] :is(.sb-header, .sb-footer) .pk-btn:disabled { opacity: 0.4; }
${P} .pk-scoreboard[data-sb-ready] [data-sb-input][aria-pressed="true"] { background: color-mix(in srgb, #34d399 30%, transparent); box-shadow: inset 0 0 0 1px #34d399, 0 0 14px -2px #34d399; }
${P} .pk-scoreboard[data-sb-ready] .sb-teams { position: relative; gap: 12px; margin: 18px 0 14px; }
${P} .pk-scoreboard[data-sb-ready] .sb-teams::before { content: ""; position: absolute; left: 50%; top: calc(50% - 6px); width: 150px; height: 150px; margin: -75px 0 0 -75px; border-radius: 50%; box-shadow: inset 0 0 0 2px rgba(255, 255, 255, 0.08); pointer-events: none; z-index: 1; }
${P} .pk-scoreboard[data-sb-ready] .sb-teams::after {
  content: "VS";
  position: absolute;
  left: 50%;
  top: calc(50% - 6px);
  display: grid;
  place-items: center;
  width: 46px;
  height: 46px;
  margin: -23px 0 0 -23px;
  border-radius: 50%;
  font-size: 15px;
  font-weight: 900;
  font-style: italic;
  letter-spacing: -0.02em;
  color: #fff;
  background: linear-gradient(135deg, var(--sb-a), var(--sb-b2));
  box-shadow: 0 0 0 5px #0d1328, 0 0 24px color-mix(in srgb, var(--sb-a) 60%, transparent);
  z-index: 2;
  pointer-events: none;
}
${P} .pk-scoreboard[data-sb-ready] .sb-team {
  --sb-c: var(--sb-a);
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 16px 8px 16px;
  border-radius: 22px;
  overflow: hidden;
  background: linear-gradient(180deg, color-mix(in srgb, var(--sb-c) 22%, transparent), color-mix(in srgb, var(--sb-c) 4%, transparent) 70%);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--sb-c) 30%, transparent);
}
${P} .pk-scoreboard[data-sb-ready] .sb-team + .sb-team { --sb-c: var(--sb-b2); background: linear-gradient(180deg, color-mix(in srgb, var(--sb-c) 22%, transparent), color-mix(in srgb, var(--sb-c) 4%, transparent) 70%); box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--sb-c) 30%, transparent); }
${P} .pk-scoreboard[data-sb-ready] .sb-team::before { content: ""; position: absolute; top: 0; left: 18%; right: 18%; height: 3px; border-radius: 0 0 3px 3px; background: var(--sb-c); box-shadow: 0 0 16px 2px var(--sb-c); }
${P} .pk-scoreboard[data-sb-ready] [data-sb-name] { padding: 4px 14px; border-radius: 999px; font-size: 13px; font-weight: 800; letter-spacing: 0.08em; color: #fff; background: color-mix(in srgb, var(--sb-c) 32%, transparent); }
${P} .pk-scoreboard[data-sb-ready] .sb-team strong[data-sb-score] {
  font-size: clamp(64px, min(26cqw, calc(var(--sb-available-height, 100svh) - 240px)), 190px);
  line-height: 1.05;
  font-weight: 900;
  letter-spacing: -0.05em;
  font-variant-numeric: tabular-nums;
  color: #fff;
  background: linear-gradient(180deg, #ffffff 35%, color-mix(in srgb, var(--sb-c) 55%, #fff));
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
  filter: drop-shadow(0 0 14px color-mix(in srgb, var(--sb-c) 55%, transparent));
}
${P} .pk-scoreboard[data-sb-ready] .sb-team[data-sb-lead] strong[data-sb-score] { filter: drop-shadow(0 0 22px var(--sb-c)) drop-shadow(0 0 6px color-mix(in srgb, var(--sb-c) 70%, transparent)); }
${P} .pk-scoreboard[data-sb-ready] .sb-team[data-sb-lead]::after { content: ""; position: absolute; inset: 0; border-radius: inherit; pointer-events: none; box-shadow: inset 0 0 0 2px color-mix(in srgb, var(--sb-c) 70%, transparent), inset 0 0 40px color-mix(in srgb, var(--sb-c) 25%, transparent); }
${P} .pk-scoreboard[data-sb-ready] .sb-team.sb-flash strong[data-sb-score] { animation: sb-score 0.55s cubic-bezier(0.2, 0.9, 0.25, 1.4); }
${P} .pk-scoreboard[data-sb-ready] .sb-adds { display: flex; flex-wrap: wrap; justify-content: center; gap: 8px; }
${P} .pk-scoreboard[data-sb-ready] .sb-adds .pk-btn {
  min-width: 58px;
  height: 46px;
  padding: 0 14px;
  border-radius: 999px;
  color: #fff;
  font-size: 17px;
  font-weight: 900;
  background: linear-gradient(180deg, color-mix(in srgb, var(--sb-c) 92%, #fff), color-mix(in srgb, var(--sb-c) 75%, #000));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35), 0 8px 18px -8px var(--sb-c);
}
${P} .pk-scoreboard[data-sb-ready] .sb-adds .pk-btn:active { transform: scale(0.9); }
${P} .pk-scoreboard[data-sb-ready] .sb-adds .pk-btn:disabled { opacity: 0.35; box-shadow: none; }
${P} .pk-scoreboard[data-sb-ready] .sb-footer { display: flex; align-items: center; gap: 8px; color: rgba(255, 255, 255, 0.7); font-size: 13px; font-weight: 700; }
${P} .pk-scoreboard[data-sb-ready] .sb-footer [data-sb-games] { flex: 1; letter-spacing: 0.06em; }
${P} .pk-scoreboard[data-sb-ready] .sb-more { color: var(--pk-ink); }
@media (max-width: 599px) {
  ${P} .pk-scoreboard[data-sb-ready] .sb-adds { gap: 5px; flex-wrap: nowrap; }
  ${P} .pk-scoreboard[data-sb-ready] .sb-adds .pk-btn { min-width: 40px; flex: none; height: 40px; padding: 0 8px; font-size: 14px; white-space: nowrap; }
  ${P} .pk-scoreboard[data-sb-ready] .sb-team { padding-inline: 10px; }
  ${P} .pk-scoreboard[data-sb-ready] .sb-teams::after { width: 36px; height: 36px; margin: -18px 0 0 -18px; font-size: 12px; box-shadow: 0 0 0 4px #0d1328, 0 0 18px color-mix(in srgb, var(--sb-a) 60%, transparent); }
  ${P} .pk-scoreboard[data-sb-ready] .sb-teams::before { width: 112px; height: 112px; margin: -56px 0 0 -56px; }
}
@keyframes sb-live { 0%, 100% { opacity: 1; } 50% { opacity: 0.35; } }
@keyframes sb-score { 0% { transform: scale(1.35); } 100% { transform: none; } }

/* ---------- Immersive cover ---------- */
${P} > .pk-cover[data-variant="immersive"] {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding-bottom: 30px;
  border-radius: 0 0 36px 36px;
  overflow: hidden;
  isolation: isolate;
  color: #fff;
  background:
    radial-gradient(60% 45% at 50% 28%, color-mix(in srgb, var(--sc-2) 55%, transparent), transparent 70%),
    radial-gradient(80% 60% at 100% 100%, color-mix(in srgb, var(--sc-3) 35%, transparent), transparent 70%),
    linear-gradient(170deg, var(--sc-deep), color-mix(in srgb, var(--sc-1) 45%, #050816) 70%);
  box-shadow: 0 24px 40px -30px color-mix(in srgb, var(--sc-1) 90%, transparent);
}
${P} > .pk-cover[data-variant="immersive"]::before { display: none; }
${P} > .pk-cover[data-variant="immersive"]::after {
  content: "";
  position: absolute;
  inset: 0;
  z-index: -1;
  pointer-events: none;
  background-image: radial-gradient(rgba(255, 255, 255, 0.55) 1px, transparent 1.4px), radial-gradient(rgba(255, 255, 255, 0.3) 1px, transparent 1.4px);
  background-size: 46px 46px, 29px 29px;
  background-position: 0 0, 13px 17px;
  -webkit-mask-image: radial-gradient(80% 60% at 50% 30%, #000, transparent 80%);
  mask-image: radial-gradient(80% 60% at 50% 30%, #000, transparent 80%);
  opacity: 0.5;
}
${P} > .pk-cover[data-variant="immersive"] .pk-cover-pic { width: 140px; height: 140px; margin: 4px auto 14px; filter: drop-shadow(0 22px 26px rgba(0, 0, 0, 0.4)); }
${P} > .pk-cover[data-variant="immersive"] .pk-cover-copy { display: flex; flex-direction: column; align-items: center; }
${P} > .pk-cover[data-variant="immersive"] h1 {
  font-size: 34px;
  font-weight: 800;
  letter-spacing: -0.02em;
  color: #fff;
  background: linear-gradient(180deg, #fff 30%, color-mix(in srgb, var(--sc-2) 35%, #fff));
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}
${P} > .pk-cover[data-variant="immersive"] :is(.pk-cover-eyebrow, .pk-cover-meta) { color: rgba(255, 255, 255, 0.78); justify-content: center; }
${P} > .pk-cover[data-variant="immersive"] .pk-tags { justify-content: center; }
${P} > .pk-cover[data-variant="immersive"] .pk-tag,
${P} > .pk-cover[data-variant="immersive"] .pk-tag[data-quiet] {
  color: #fff;
  background: rgba(255, 255, 255, 0.16);
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.24);
  -webkit-backdrop-filter: blur(10px);
  backdrop-filter: blur(10px);
}
@media (min-width: 600px) {
  ${P} > .pk-cover[data-variant="immersive"] { display: flex; flex-direction: column; align-items: center; }
  ${P} > .pk-cover[data-variant="immersive"] .pk-cover-pic { order: 0; }
}

/* ---------- Motion ---------- */
@keyframes sc-grow { from { width: 0; } }
@keyframes sc-arc { from { stroke-dasharray: 0 999; } }
@keyframes sc-needle { from { transform: rotate(-90deg); } }
@keyframes sc-float { 0%, 100% { transform: translateY(0) rotate(0deg); } 50% { transform: translateY(-8px) rotate(-3deg); } }
@keyframes sc-tick { 0% { opacity: 1; } 50% { opacity: 0.55; } }
@keyframes sc-rise-step { from { transform: scaleY(0.1); } }
[data-local-genui-mode="checker"] ${R} [class^="sc-"],
[data-local-genui-mode="checker"] ${R} [class^="sc-"]::before,
[data-local-genui-mode="checker"] ${R} [class^="sc-"] * { animation: none !important; }
[data-local-genui-mode="checker"] ${R} .pk-scoreboard *, [data-local-genui-mode="checker"] ${R} .pk-scoreboard *::before { animation: none !important; }
@media (prefers-reduced-motion: reduce) {
  ${R} [class^="sc-"], ${R} [class^="sc-"]::before, ${R} [class^="sc-"] * { animation: none !important; transition: none !important; }
  ${R} .pk-scoreboard *, ${R} .pk-scoreboard *::before { animation: none !important; }
}

/* ==========================================================================
   Harmony with the page: the look the person chose (data-gen-ui-look) and
   the mood the program chose (data-gen-ui-mood: calm, vivid or night; the
   look decides when the program does not). The rules above are the vivid
   stage; calm turns the stage blocks into light, theme-tinted surfaces,
   celadon and blueprint restyle them in their own material, and night keeps
   the dark stage on a dark page. Later and more specific rules win.
   ========================================================================== */

/* ---------- Calm: light stages tinted by the page theme ---------- */
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-count {
  color: var(--pk-ink);
  background:
    radial-gradient(90% 80% at 100% 0%, color-mix(in srgb, var(--sc-2) 14%, transparent), transparent 60%),
    linear-gradient(160deg, color-mix(in srgb, var(--sc-1) 13%, var(--pk-card)), var(--pk-card));
  box-shadow: inset 0 0 0 1px var(--sc-edge), var(--sc-shadow);
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-count::after { display: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-count-label { color: var(--pk-ink); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-count-cell { background: var(--pk-card); box-shadow: inset 0 0 0 1px var(--sc-edge), 0 8px 16px -12px color-mix(in srgb, var(--sc-1) 70%, transparent); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-count-cell::after { background: var(--sc-edge); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-count-cell b { color: color-mix(in srgb, var(--sc-1) 85%, var(--pk-ink)); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk :is(.sc-count-cell span, .sc-count-sub) { color: var(--pk-ink-2); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-spot:not([data-has-photo]) {
  color: var(--pk-ink);
  background:
    radial-gradient(80% 90% at 95% 10%, color-mix(in srgb, var(--sc-2) 18%, transparent), transparent 62%),
    linear-gradient(150deg, color-mix(in srgb, var(--sc-1) 15%, var(--pk-card)), var(--pk-card));
  box-shadow: inset 0 0 0 1px var(--sc-edge), var(--sc-shadow);
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-spot:not([data-has-photo]) .sc-spot-glow { display: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-spot:not([data-has-photo]) .sc-spot-eyebrow { color: color-mix(in srgb, var(--sc-1) 80%, var(--pk-ink)); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-spot:not([data-has-photo]) .sc-spot-sub, .gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-spot:not([data-has-photo]) .sc-spot-value small { color: var(--pk-ink-2); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-spot:not([data-has-photo]) .sc-spot-value { color: color-mix(in srgb, var(--sc-1) 85%, var(--pk-ink)); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-spot:not([data-has-photo]) .sc-spot-tags span { color: color-mix(in srgb, var(--sc-1) 85%, var(--pk-ink)); background: color-mix(in srgb, var(--sc-1) 10%, transparent); box-shadow: none; -webkit-backdrop-filter: none; backdrop-filter: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-spot:not([data-has-photo]) .sc-spot-pic { filter: drop-shadow(0 14px 16px color-mix(in srgb, var(--pk-ink) 22%, transparent)); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-tile[data-style="vivid"] {
  color: var(--pk-ink);
  background: linear-gradient(150deg, color-mix(in srgb, var(--sc-1) 24%, var(--pk-card)), color-mix(in srgb, var(--sc-2) 12%, var(--pk-card)));
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--sc-1) 18%, transparent), var(--sc-shadow);
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-tile[data-style="vivid"] :is(.sc-tile-label, .sc-tile-sub, .sc-tile-value small) { color: var(--pk-ink-2); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-tile[data-style="vivid"] .sc-tile-value { color: color-mix(in srgb, var(--sc-1) 85%, var(--pk-ink)); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-tile[data-style="vivid"] .sc-tile-bar { background: color-mix(in srgb, var(--pk-ink) 9%, transparent); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-tile[data-style="vivid"] .sc-tile-bar::before { background: linear-gradient(90deg, var(--sc-1), var(--sc-2)); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .sc-tile[data-style="vivid"] .sc-tile-delta { color: var(--pk-ink-2); background: color-mix(in srgb, var(--pk-ink) 7%, transparent); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk > .pk-cover[data-variant="immersive"] {
  color: var(--pk-ink);
  background:
    radial-gradient(60% 45% at 50% 28%, color-mix(in srgb, var(--sc-2) 20%, transparent), transparent 70%),
    linear-gradient(175deg, color-mix(in srgb, var(--sc-1) 20%, var(--pk-page)), var(--pk-page) 88%);
  box-shadow: none;
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk > .pk-cover[data-variant="immersive"]::after { background-image: radial-gradient(color-mix(in srgb, var(--pk-ink) 14%, transparent) 1px, transparent 1.4px); background-size: 20px 20px; opacity: 1; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk > .pk-cover[data-variant="immersive"] h1 { background: linear-gradient(100deg, color-mix(in srgb, var(--sc-1) 40%, var(--pk-ink)), color-mix(in srgb, var(--sc-1) 85%, var(--pk-ink)) 60%, var(--sc-2)); -webkit-background-clip: text; background-clip: text; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk > .pk-cover[data-variant="immersive"] :is(.pk-cover-eyebrow, .pk-cover-meta) { color: var(--pk-ink-2); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk > .pk-cover[data-variant="immersive"] .pk-cover-pic { filter: drop-shadow(0 18px 20px color-mix(in srgb, var(--pk-ink) 25%, transparent)); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk > .pk-cover[data-variant="immersive"] :is(.pk-tag, .pk-tag[data-quiet]) { color: var(--pk-ink-2); background: color-mix(in srgb, var(--pk-card) 70%, transparent); box-shadow: inset 0 0 0 1px var(--sc-edge); }

.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] {
  --sb-a: var(--pk-accent);
  --sb-b2: color-mix(in srgb, var(--sb-b, var(--sc-2)) 85%, var(--pk-ink));
  color: var(--pk-ink);
  background:
    radial-gradient(70% 60% at 20% 0%, color-mix(in srgb, var(--sb-a) 12%, transparent), transparent 70%),
    radial-gradient(70% 60% at 80% 0%, color-mix(in srgb, var(--sb-b2) 10%, transparent), transparent 70%),
    var(--pk-card);
  box-shadow: inset 0 0 0 1px var(--sc-edge), var(--sc-shadow);
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready]::before { background: linear-gradient(90deg, transparent calc(50% - 1px), color-mix(in srgb, var(--pk-ink) 7%, transparent) calc(50% - 1px) calc(50% + 1px), transparent calc(50% + 1px)); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] .sb-header, .gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] .sb-footer { color: var(--pk-ink-2); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] [data-sb-status] { background: color-mix(in srgb, var(--pk-ink) 6%, transparent); box-shadow: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] [data-sb-status]::before { box-shadow: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] :is(.sb-header, .sb-footer) .pk-btn { color: var(--pk-ink); background: color-mix(in srgb, var(--pk-ink) 6%, transparent); box-shadow: none; -webkit-backdrop-filter: none; backdrop-filter: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] .sb-teams::before { box-shadow: inset 0 0 0 2px color-mix(in srgb, var(--pk-ink) 7%, transparent); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] .sb-teams::after { box-shadow: 0 0 0 5px var(--pk-card), 0 6px 14px -6px color-mix(in srgb, var(--sb-a) 60%, transparent); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] .sb-team, .gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] .sb-team + .sb-team { background: linear-gradient(180deg, color-mix(in srgb, var(--sb-c) 10%, transparent), transparent 75%); box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--sb-c) 18%, transparent); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] .sb-team::before { box-shadow: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] [data-sb-name] { color: color-mix(in srgb, var(--sb-c) 85%, var(--pk-ink)); background: color-mix(in srgb, var(--sb-c) 12%, transparent); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] .sb-team strong[data-sb-score] { background: none; color: color-mix(in srgb, var(--sb-c) 88%, var(--pk-ink)); -webkit-text-fill-color: color-mix(in srgb, var(--sb-c) 88%, var(--pk-ink)); filter: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] .sb-team[data-sb-lead] strong[data-sb-score] { filter: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] .sb-team[data-sb-lead]::after { box-shadow: inset 0 0 0 2px color-mix(in srgb, var(--sb-c) 55%, transparent); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-scoreboard[data-sb-ready] .sb-adds .pk-btn { background: var(--sb-c); box-shadow: 0 6px 14px -8px var(--sb-c); }

/* ---------- Celadon: jade, cinnabar and ochre glaze, serif numerals ---------- */
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk { --sc-1: #2f7d6d; --sc-2: #b5523b; --sc-3: #b8873a; --sc-deep: #173e39; --sc-r: 20px; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk :is(.sc-tile-value, .sc-rings-center b, .sc-gauge-read b, .sc-count-cell b, .sc-spot-value, .sc-podium-step, .sc-ticket-route b, .sc-statement blockquote, .sc-cal-head b, .sc-spot h3, .sc-heat-meta b) {
  font-family: "Noto Serif CJK SC", "Source Han Serif SC", "Songti SC", "STSong", serif;
  font-weight: 700;
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk :is(.sc-ring, .sc-ticket, .sc-rank, .sc-bars, .sc-heat, .sc-statement, .sc-tile, .sc-cal, .sc-shelf-card, .sc-count, .sc-spot:not([data-has-photo])) {
  box-shadow: inset 0 1px 0 #ffffff80, inset 0 -1px 0 #44847236, 0 4px 12px -10px #174c43aa;
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk :is(.sc-ring .sc-arc, .sc-gauge .sc-arc, .sc-tile-bar::before) { filter: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk .pk-scoreboard[data-sb-ready] {
  --sb-a: #1f6f5f;
  --sb-b2: #b5523b;
  color: #173e39;
  border-radius: 28px 28px 40px 14px;
  background:
    radial-gradient(80% 60% at 50% 0%, rgba(255, 255, 255, 0.75), transparent 70%),
    linear-gradient(165deg, #f6fbf8, #d9ede4 55%, #b9d9cc);
  box-shadow: inset 0 1px 0 #fff, inset 0 0 0 1px rgba(23, 62, 57, 0.12), 0 18px 32px -24px rgba(23, 76, 67, 0.55);
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk .pk-scoreboard[data-sb-ready]::before { background: repeating-radial-gradient(ellipse at 112% -26%, transparent 0 32px, rgba(255, 255, 255, 0.5) 33px, transparent 35px 52px); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk .pk-scoreboard[data-sb-ready] [data-sb-status]::before { background: #b5523b; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk .pk-scoreboard[data-sb-ready] :is(.sb-header, .sb-footer) .pk-btn { color: #173e39; background: rgba(255, 255, 255, 0.6); box-shadow: inset 0 0 0 1px rgba(23, 62, 57, 0.15); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk .pk-scoreboard[data-sb-ready] .sb-team, .gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk .pk-scoreboard[data-sb-ready] .sb-team + .sb-team { background: linear-gradient(180deg, rgba(255, 255, 255, 0.7), rgba(255, 255, 255, 0.25)); box-shadow: inset 0 0 0 1px rgba(23, 62, 57, 0.1), inset 0 -1px 0 #44847236; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk .pk-scoreboard[data-sb-ready] .sb-team strong[data-sb-score] { font-family: "Noto Serif CJK SC", "Source Han Serif SC", "Songti SC", "STSong", serif; font-weight: 700; letter-spacing: -0.03em; filter: drop-shadow(0 2px 0 rgba(255, 255, 255, 0.9)); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk .pk-scoreboard[data-sb-ready] .sb-teams::before { box-shadow: inset 0 0 0 1.5px rgba(23, 62, 57, 0.1); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk .pk-scoreboard[data-sb-ready] .sb-teams::after {
  border-radius: 7px;
  transform: rotate(-6deg);
  font-family: "Noto Serif CJK SC", "Songti SC", serif;
  font-style: normal;
  color: #fff6ea;
  background: #b5523b;
  box-shadow: 0 0 0 4px #e6f2ec, 0 4px 10px -4px rgba(181, 82, 59, 0.7);
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk .pk-scoreboard[data-sb-ready] .sb-adds .pk-btn { color: var(--sb-c); background: linear-gradient(180deg, #ffffff, #eef6f2); box-shadow: inset 0 0 0 1.5px color-mix(in srgb, var(--sb-c) 45%, transparent), 0 4px 10px -6px var(--sb-c); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"][data-ogui-scheme="dark"] .pk .pk-scoreboard[data-sb-ready] {
  --sb-a: #5fd3b0;
  --sb-b2: #f08a6c;
  background:
    radial-gradient(60% 55% at 22% 0%, rgba(95, 211, 176, 0.28), transparent 70%),
    radial-gradient(60% 55% at 78% 0%, rgba(240, 138, 108, 0.24), transparent 70%),
    linear-gradient(180deg, #11302b, #071713);
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk > .pk-cover[data-variant="immersive"] { background: radial-gradient(60% 45% at 50% 28%, rgba(255, 255, 255, 0.6), transparent 70%), linear-gradient(125deg, #eef8f3, #c6e4da 62%, #97c7ba); border-radius: 0 0 40px 12px; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"]:not([data-ogui-scheme="dark"]) .pk > .pk-cover[data-variant="immersive"] h1 { background: none; color: #173e39; -webkit-text-fill-color: #173e39; font-family: "Noto Serif CJK SC", "Songti SC", serif; }

/* ---------- Blueprint: drawing sheet, monospaced figures, ruled frames ---------- */
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk { --sc-1: #1f5fa8; --sc-2: #d97706; --sc-3: #0e7490; --sc-deep: #163e71; --sc-r: 8px; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk :is(.sc-tile-value, .sc-rings-center b, .sc-gauge-read b, .sc-count-cell b, .sc-spot-value, .sc-podium-step, .sc-ticket-route b, .sc-cal-head b, .sc-heat-meta b, .sc-bar-head b, .sc-rank-value) { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-weight: 700; letter-spacing: -0.02em; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk :is(.sc-ring, .sc-ticket, .sc-rank, .sc-bars, .sc-heat, .sc-statement, .sc-tile, .sc-cal, .sc-shelf-card) { border-radius: 8px; box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--pk-ink) 18%, transparent); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk :is(.sc-ring .sc-arc, .sc-gauge .sc-arc, .sc-tile-bar::before, .sc-bar > i::before) { filter: none; box-shadow: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk :is(.sc-count, .sc-spot:not([data-has-photo]), .sc-tile[data-style="vivid"]),
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk > .pk-cover[data-variant="immersive"] {
  color: #f3f9ff;
  border-radius: 8px;
  background:
    linear-gradient(90deg, transparent 23px, rgba(209, 234, 255, 0.1) 24px) 0 0 / 24px 24px,
    linear-gradient(0deg, transparent 23px, rgba(209, 234, 255, 0.1) 24px) 0 0 / 24px 24px,
    #163e71;
  box-shadow: inset 0 0 0 1px rgba(209, 234, 255, 0.4);
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk > .pk-cover[data-variant="immersive"] { border-radius: 0 0 8px 8px; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk > .pk-cover[data-variant="immersive"] h1 { background: none; color: #f3f9ff; -webkit-text-fill-color: #f3f9ff; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk :is(.sc-count, .sc-spot:not([data-has-photo]), .sc-tile[data-style="vivid"]) :is(.sc-count-label, .sc-count-sub, .sc-count-cell span, .sc-spot-sub, .sc-spot-eyebrow, .sc-tile-label, .sc-tile-sub, .sc-tile-value small) { color: rgba(243, 249, 255, 0.75); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk :is(.sc-count-cell b, .sc-spot-value, .sc-tile[data-style="vivid"] .sc-tile-value) { color: #ffd166; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .sc-count::after, .gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .sc-spot-glow { display: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .sc-count-cell { border-radius: 4px; background: transparent; box-shadow: inset 0 0 0 1px rgba(209, 234, 255, 0.4); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .sc-spot-tags span { border-radius: 3px; color: #f3f9ff; background: transparent; box-shadow: inset 0 0 0 1px rgba(209, 234, 255, 0.45); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] {
  --sb-a: #ffd166;
  --sb-b2: #7dd3fc;
  color: #f3f9ff;
  border-radius: 8px;
  background:
    linear-gradient(90deg, transparent 23px, rgba(209, 234, 255, 0.1) 24px) 0 0 / 24px 24px,
    linear-gradient(0deg, transparent 23px, rgba(209, 234, 255, 0.1) 24px) 0 0 / 24px 24px,
    #163e71;
  box-shadow: inset 0 0 0 1px rgba(209, 234, 255, 0.4), 0 16px 28px -20px #0b2340;
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready]::before { background: repeating-linear-gradient(180deg, rgba(209, 234, 255, 0.35) 0 6px, transparent 6px 12px) center / 2px 100% no-repeat; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] .sb-header, .gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] .sb-footer { color: rgba(243, 249, 255, 0.85); font-family: ui-monospace, "SF Mono", Menlo, monospace; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] [data-sb-status] { border-radius: 4px; background: transparent; box-shadow: inset 0 0 0 1px rgba(209, 234, 255, 0.4); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] :is(.sb-header, .sb-footer) .pk-btn { border-radius: 4px; color: #f3f9ff; background: transparent; box-shadow: inset 0 0 0 1px rgba(209, 234, 255, 0.45); -webkit-backdrop-filter: none; backdrop-filter: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] .sb-team, .gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] .sb-team + .sb-team { border-radius: 4px; background: rgba(255, 255, 255, 0.03); box-shadow: none; outline: 1px dashed rgba(209, 234, 255, 0.35); outline-offset: -1px; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] .sb-team::before { border-radius: 0; box-shadow: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] [data-sb-name] { border-radius: 3px; color: var(--sb-c); background: transparent; box-shadow: inset 0 0 0 1px var(--sb-c); font-family: ui-monospace, "SF Mono", Menlo, monospace; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] .sb-team strong[data-sb-score] { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-weight: 700; letter-spacing: -0.04em; background: none; color: var(--sb-c); -webkit-text-fill-color: var(--sb-c); filter: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] .sb-team[data-sb-lead] strong[data-sb-score] { filter: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] .sb-team[data-sb-lead]::after { border-radius: 4px; box-shadow: inset 0 0 0 2px var(--sb-c); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] .sb-teams::before { box-shadow: none; border: 1.5px dashed rgba(209, 234, 255, 0.3); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] .sb-teams::after { border-radius: 4px; font-style: normal; font-family: ui-monospace, "SF Mono", Menlo, monospace; color: #d1eaff; background: #163e71; box-shadow: inset 0 0 0 1.5px #d1eaff, 0 0 0 4px #163e71; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-scoreboard[data-sb-ready] .sb-adds .pk-btn { border-radius: 4px; color: var(--sb-c); background: transparent; box-shadow: inset 0 0 0 1.5px var(--sb-c); }

/* Celadon at night: the glaze darkens to deep jade so the cover meets the dark page. */
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"][data-ogui-scheme="dark"] .pk > .pk-cover[data-plain] { background: linear-gradient(125deg, #17463e, #0d2a25 62%, #081a17); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"][data-ogui-scheme="dark"] .pk > .pk-cover[data-plain]::before { background: repeating-radial-gradient(ellipse at 112% -26%, transparent 0 32px, rgba(159, 216, 196, 0.16) 33px, transparent 35px 52px); }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"][data-ogui-scheme="dark"] .pk .pk-cover :is(h1, .pk-cover-meta, .pk-cover-eyebrow) { color: #e3f3ec; -webkit-text-fill-color: #e3f3ec; }

/* ==========================================================================
   Bold motion: hero numbers that roll and orbit, a story-path timeline that
   lights step by step, a checklist that bursts, and a staggered 3D entrance.
   ========================================================================== */

/* ---------- Hero number: orbit ring and rising sparks ---------- */
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-hero-stat { position: relative; isolation: isolate; overflow: hidden; }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-hero-stat::before {
  content: "";
  position: absolute;
  left: 50%;
  top: 50%;
  z-index: -1;
  height: calc(100% - 18px);
  max-height: 260px;
  aspect-ratio: 1;
  transform: translate(-50%, -50%);
  border-radius: 50%;
  background: conic-gradient(from 0deg, transparent 0 18%, color-mix(in srgb, var(--sc-1) 85%, transparent) 42%, var(--sc-2) 58%, transparent 80%);
  -webkit-mask: radial-gradient(farthest-side, transparent calc(100% - 7px), #000 calc(100% - 6px), #000 100%);
  mask: radial-gradient(farthest-side, transparent calc(100% - 7px), #000 calc(100% - 6px), #000 100%);
  opacity: 0.55;
  filter: drop-shadow(0 0 10px color-mix(in srgb, var(--sc-1) 60%, transparent));
  animation: sc-orbit 7s linear infinite;
  pointer-events: none;
}
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-hero-stat .pk-stat-value { font-variant-numeric: tabular-nums; }
.gen-ui-application.gen-ui-application--harmony-genui:is([data-gen-ui-mood="vivid"], [data-gen-ui-mood="night"]) .pk .pk-hero-stat {
  background-image:
    radial-gradient(circle, color-mix(in srgb, var(--sc-1) 70%, #fff) 1.4px, transparent 2px),
    radial-gradient(circle, color-mix(in srgb, var(--sc-2) 70%, #fff) 1.2px, transparent 1.8px),
    radial-gradient(circle, rgba(255, 255, 255, 0.9) 1px, transparent 1.5px),
    radial-gradient(55% 70% at 50% 42%, color-mix(in srgb, var(--sc-1) 16%, transparent), transparent 72%);
  background-size: 74px 92px, 118px 130px, 57px 71px, 100% 100%;
  background-position: 0 0, 30px 40px, 12px 20px, 0 0;
  background-color: var(--pk-card);
  animation: sc-sparks 14s linear infinite;
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood="calm"] .pk .pk-hero-stat::before { opacity: 0.22; filter: none; animation-duration: 20s; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"] .pk .pk-hero-stat::before { background: none; box-shadow: inset 0 0 0 1.5px color-mix(in srgb, var(--sc-1) 35%, transparent); opacity: 1; filter: none; animation: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-hero-stat::before { background: none; border: 1.5px dashed color-mix(in srgb, var(--pk-ink) 28%, transparent); -webkit-mask: none; mask: none; opacity: 1; filter: none; animation: none; }

/* ---------- Timeline: a lit path, steps light as they arrive ---------- */
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-step { transition: opacity 0.55s ease-out, transform 0.55s cubic-bezier(0.2, 0.9, 0.25, 1.1); }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-step:not([data-seen]) { opacity: 0.28; transform: translateX(-10px); }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-step[data-seen] .pk-step-body::before { animation: sc-dot-pop 0.6s cubic-bezier(0.2, 0.9, 0.25, 1.6) both; }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-step:nth-child(2)[data-seen] { transition-delay: 90ms; }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-step:nth-child(3)[data-seen] { transition-delay: 180ms; }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-step:nth-child(4)[data-seen] { transition-delay: 270ms; }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-step:nth-child(n + 5)[data-seen] { transition-delay: 360ms; }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-step-body::after {
  background:
    linear-gradient(180deg, transparent, rgba(255, 255, 255, 0.95), transparent) 0 -40px / 100% 40px no-repeat,
    linear-gradient(180deg, color-mix(in srgb, var(--sc-1) 60%, transparent), color-mix(in srgb, var(--sc-2) 35%, transparent));
  animation: sc-flow 2.6s linear infinite;
}
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-step:nth-child(2) .pk-step-body::after { animation-delay: 0.65s; }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-step:nth-child(3) .pk-step-body::after { animation-delay: 1.3s; }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-step:nth-child(4) .pk-step-body::after { animation-delay: 1.95s; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-step-body::after { background: repeating-linear-gradient(180deg, color-mix(in srgb, var(--pk-ink) 40%, transparent) 0 4px, transparent 4px 8px); animation: none; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="blueprint"] .pk .pk-step-body::before { border-radius: 2px; }

/* ---------- Checklist: progress head and a burst ---------- */
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-check { position: relative; }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-check-head { display: grid; grid-template-columns: 1fr auto; gap: 6px 8px; align-items: baseline; padding: 6px var(--pk-pad) 10px; }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-check-head span { font-size: 12px; font-weight: 700; letter-spacing: 0.06em; color: var(--pk-ink-2); }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-check-head b { font-size: 15px; font-weight: 800; font-variant-numeric: tabular-nums; color: color-mix(in srgb, var(--sc-1) 85%, var(--pk-ink)); }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-check-head i { grid-column: 1 / -1; display: block; height: 6px; border-radius: 3px; background: color-mix(in srgb, var(--pk-ink) 8%, transparent); overflow: hidden; }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-check-head i::before { content: ""; display: block; width: var(--pk-v); height: 100%; border-radius: inherit; background: linear-gradient(90deg, var(--sc-1), var(--sc-2)); transition: width 0.6s cubic-bezier(0.2, 0.9, 0.25, 1.1); }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-check label { position: relative; }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-check label[data-burst]::after {
  content: "";
  position: absolute;
  left: calc(var(--pk-pad) + 9px);
  top: calc(var(--hm-space-s) + 10px);
  width: 4px;
  height: 4px;
  border-radius: 50%;
  pointer-events: none;
  box-shadow:
    0 -22px 0 var(--sc-1), 16px -16px 0 var(--sc-2), 22px 0 0 var(--sc-3), 16px 16px 0 var(--sc-1),
    0 22px 0 var(--sc-2), -16px 16px 0 var(--sc-3), -22px 0 0 var(--sc-1), -16px -16px 0 var(--sc-2);
  animation: sc-burst 0.65s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-check label[data-burst] input { animation: sc-check-pop 0.5s cubic-bezier(0.2, 0.9, 0.25, 1.6); }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-check[data-complete] { box-shadow: inset 0 0 0 1.5px color-mix(in srgb, var(--sc-1) 55%, transparent), 0 0 24px -6px color-mix(in srgb, var(--sc-1) 55%, transparent); }
.gen-ui-application.gen-ui-application--harmony-genui .pk .pk-check[data-complete] .pk-check-head b { color: var(--color-text-success); }

/* ---------- Entrance: staggered 3D fly-in ---------- */
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood] .pk > .pk-flow, .gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood] .pk > .pk-panel > .pk-flow { perspective: 1400px; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood] .pk > .pk-flow > *, .gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood] .pk > .pk-panel > .pk-flow > * {
  transform-origin: 50% 0;
  animation: sc-enter 0.85s cubic-bezier(0.2, 0.9, 0.25, 1.05) both;
}
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood] .pk > .pk-flow > :nth-child(1) { animation-delay: 40ms; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood] .pk > .pk-flow > :nth-child(2) { animation-delay: 110ms; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood] .pk > .pk-flow > :nth-child(3) { animation-delay: 180ms; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood] .pk > .pk-flow > :nth-child(4) { animation-delay: 250ms; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood] .pk > .pk-flow > :nth-child(5) { animation-delay: 320ms; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood] .pk > .pk-flow > :nth-child(6) { animation-delay: 390ms; }
.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-mood] .pk > .pk-flow > :nth-child(n + 7) { animation-delay: 460ms; }

@keyframes sc-orbit { to { transform: translate(-50%, -50%) rotate(360deg); } }
@keyframes sc-sparks { to { background-position: 0 -920px, 30px -1260px, 12px -710px, 0 0; } }
@keyframes sc-flow { 0% { background-position: 0 -40px, 0 0; } 100% { background-position: 0 calc(100% + 40px), 0 0; } }
@keyframes sc-dot-pop { 0% { transform: scale(0.3); } 100% { transform: none; } }
@keyframes sc-burst { 0% { transform: scale(0.25); opacity: 1; } 70% { opacity: 1; } 100% { transform: scale(1.35); opacity: 0; } }
@keyframes sc-check-pop { 0% { transform: scale(0.7); } 100% { transform: none; } }
@keyframes sc-enter { from { opacity: 0.02; transform: translateY(34px) rotateX(16deg) scale(0.95); } to { opacity: 1; transform: none; } }

[data-local-genui-mode="checker"] .gen-ui-application.gen-ui-application--harmony-genui .pk-hero-stat, [data-local-genui-mode="checker"] .gen-ui-application.gen-ui-application--harmony-genui .pk-hero-stat::before, [data-local-genui-mode="checker"] .gen-ui-application.gen-ui-application--harmony-genui .pk-step, [data-local-genui-mode="checker"] .gen-ui-application.gen-ui-application--harmony-genui .pk-step-body::before, [data-local-genui-mode="checker"] .gen-ui-application.gen-ui-application--harmony-genui .pk-step-body::after, [data-local-genui-mode="checker"] .gen-ui-application.gen-ui-application--harmony-genui .pk-flow > *, [data-local-genui-mode="checker"] .gen-ui-application.gen-ui-application--harmony-genui .pk-check label::after, [data-local-genui-mode="checker"] .gen-ui-application.gen-ui-application--harmony-genui .pk-check input { animation: none !important; transition: none !important; }
[data-local-genui-mode="checker"] .gen-ui-application.gen-ui-application--harmony-genui .pk-step { opacity: 1 !important; transform: none !important; }
@media (prefers-reduced-motion: reduce) {
  .gen-ui-application.gen-ui-application--harmony-genui :is(.pk-hero-stat, .pk-step, .pk-flow > *, .pk-check input), .gen-ui-application.gen-ui-application--harmony-genui .pk-hero-stat::before, .gen-ui-application.gen-ui-application--harmony-genui .pk-step-body::before, .gen-ui-application.gen-ui-application--harmony-genui .pk-step-body::after, .gen-ui-application.gen-ui-application--harmony-genui .pk-check label::after { animation: none !important; transition: none !important; }
  .gen-ui-application.gen-ui-application--harmony-genui .pk-step { opacity: 1 !important; transform: none !important; }
}

.gen-ui-application.gen-ui-application--harmony-genui[data-gen-ui-look="celadon"] .pk .pk-check-head i::before { background: linear-gradient(90deg, var(--sc-1), color-mix(in srgb, var(--sc-1) 45%, var(--sc-3))); }
`;
