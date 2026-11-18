/**
 * Aurora look for the Harmony GenUI page kit.
 *
 * A product-owned layer applied after the vendored HarmonyOS resources and the
 * generated page-kit stylesheet. It changes paint only: colour, light, depth
 * and motion. Markup, spacing contracts, wide-screen reflow and the generated
 * language contract stay with the page kit, so every selector here is scoped
 * under the Harmony application root and one page-kit class, which outranks
 * the vendored rule it refines without `!important`.
 *
 * Each page theme pairs its HarmonyOS brand colour with a companion hue; the
 * two drive the page aurora, gradient text, glowing marks and primary actions.
 * Motion is decorative and stops under reduced motion and in checker mode,
 * and entrance animations never start fully transparent so geometry probes
 * keep counting every block.
 */
const R = '.gen-ui-application.gen-ui-application--harmony-genui';
const P = `${R} .pk`;

const COMPANIONS: Record<string, string> = {
  blue: '#8b5cf6',
  indigo: '#d946ef',
  purple: '#ec4899',
  rose: '#fb923c',
  orange: '#f43f5e',
  brown: '#d6a24a',
  green: '#14b8a6',
  teal: '#3b82f6',
  ink: '#7c8594',
};

const companionRules = Object.entries(COMPANIONS)
  .map(([theme, color]) => `${R}:has(.pk[data-hm-theme="${theme}"]) { --ax-2: ${color}; }`)
  .join('\n');

export const HARMONY_AURORA_CSS = String.raw`
@property --ax-angle { syntax: "<angle>"; inherits: false; initial-value: 0deg; }

${R} { --ax-2: #8b5cf6; }
${companionRules}

/* ---------- Page atmosphere ---------- */
${R}:has(.pk) {
  background:
    radial-gradient(130% 55% at 0% 0%, color-mix(in srgb, var(--hm-brand) 20%, transparent), transparent 62%),
    radial-gradient(100% 45% at 100% 6%, color-mix(in srgb, var(--ax-2) 17%, transparent), transparent 60%),
    radial-gradient(120% 40% at 50% 100%, color-mix(in srgb, var(--ax-2) 9%, transparent), transparent 70%),
    var(--color-background-secondary);
}
${P} {
  --ax-1: var(--pk-accent);
  --ax-grad: linear-gradient(120deg, var(--ax-1) 0%, color-mix(in srgb, var(--ax-1) 50%, var(--ax-2)) 55%, var(--ax-2) 100%);
  --ax-edge: color-mix(in srgb, var(--pk-ink) 7%, transparent);
  --ax-lift: 0 18px 36px -24px color-mix(in srgb, var(--ax-1) 55%, transparent), 0 2px 8px -4px color-mix(in srgb, var(--pk-ink) 10%, transparent);
  --ax-sheen: radial-gradient(140% 90% at 0% 0%, color-mix(in srgb, var(--ax-1) 7%, transparent), transparent 55%);
  --pk-r-card: 24px;
}

/* ---------- Cover ---------- */
${P} > .pk-cover[data-plain]::before {
  background:
    radial-gradient(60% 75% at 12% 18%, color-mix(in srgb, var(--ax-1) 34%, transparent), transparent 70%),
    radial-gradient(55% 65% at 92% 6%, color-mix(in srgb, var(--ax-2) 30%, transparent), transparent 70%),
    radial-gradient(45% 50% at 60% 70%, color-mix(in srgb, var(--ax-1) 12%, transparent), transparent 75%);
  animation: ax-drift 14s ease-in-out infinite alternate;
}
${P} > .pk-cover[data-plain]:not([data-variant="compact"])::after {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  background-image: radial-gradient(color-mix(in srgb, var(--pk-ink) 13%, transparent) 1px, transparent 1.4px);
  background-size: 18px 18px;
  -webkit-mask-image: radial-gradient(90% 70% at 85% 25%, #000, transparent 70%);
  mask-image: radial-gradient(90% 70% at 85% 25%, #000, transparent 70%);
}
${P} .pk-cover h1 {
  font-size: 34px;
  font-weight: 800;
  letter-spacing: -0.02em;
  background: linear-gradient(100deg, color-mix(in srgb, var(--ax-1) 30%, var(--pk-ink)) 0%, color-mix(in srgb, var(--ax-1) 88%, var(--pk-ink)) 45%, var(--ax-2) 90%);
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
  color: transparent;
}
${P} .pk-cover[data-variant="compact"] h1 { font-size: 26px; }
${P} .pk-cover-eyebrow,
${P} .pk-cover-eyebrow.hm-latin {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: color-mix(in srgb, var(--ax-1) 80%, var(--pk-ink));
}
${P} .pk-cover-eyebrow::before {
  content: "";
  width: 18px;
  height: 3px;
  border-radius: 2px;
  background: var(--ax-grad);
  box-shadow: 0 0 10px color-mix(in srgb, var(--ax-1) 60%, transparent);
}
${P} .pk-cover-meta { color: var(--pk-ink-2); }
${P} .pk-cover-pic {
  position: relative;
  isolation: isolate;
  animation: ax-float 6s ease-in-out infinite;
}
${P} .pk-cover-pic::before {
  content: "";
  position: absolute;
  inset: -28%;
  z-index: -1;
  border-radius: 50%;
  background:
    radial-gradient(closest-side, color-mix(in srgb, var(--ax-1) 34%, transparent), transparent),
    radial-gradient(closest-side at 70% 30%, color-mix(in srgb, var(--ax-2) 30%, transparent), transparent);
  filter: blur(6px);
  animation: ax-breathe 6s ease-in-out infinite;
}
${P} .pk-cover-pic > img { filter: drop-shadow(0 14px 16px color-mix(in srgb, var(--ax-1) 32%, transparent)); }
/* Animated cover picture: it replaces the static one once loaded, and only while motion is welcome. */
${P} .pk-cover-pic > .hm-icon3d-motion {
  position: absolute;
  inset: 0;
  opacity: 0;
  transition: opacity 0.45s ease-out;
}
${P} .pk-cover-pic > .hm-icon3d-motion[data-ready] { opacity: 1; }
${P} .pk-cover-pic:has(> .hm-icon3d-motion[data-ready]) > img:first-child { opacity: 0; transition: opacity 0.45s ease-out; }
[data-local-genui-mode="checker"] ${P} .pk-cover-pic > .hm-icon3d-motion { display: none; }
[data-local-genui-mode="checker"] ${P} .pk-cover-pic > img:first-child { opacity: 1 !important; }
@media (prefers-reduced-motion: reduce) {
  ${P} .pk-cover-pic > .hm-icon3d-motion { display: none; }
  ${P} .pk-cover-pic > img:first-child { opacity: 1 !important; }
}
${P} .pk-cover .pk-tag {
  height: 26px;
  padding: 0 11px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--pk-card) 62%, transparent);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--pk-ink) 8%, transparent), 0 4px 12px -8px color-mix(in srgb, var(--ax-1) 60%, transparent);
  -webkit-backdrop-filter: blur(10px) saturate(1.4);
  backdrop-filter: blur(10px) saturate(1.4);
  font-size: 12px;
}
${P} .pk-cover .pk-tag[data-tone] { background: color-mix(in srgb, var(--pk-tone) 12%, var(--pk-card)); }

/* ---------- Shared card surface ---------- */
${P} :is(.pk-hero-stat, .pk-stat, .pk-list, .pk-timeline, .pk-check, .pk-card:not([data-surface="plain"]), .pk-note, .pk-procon, .pk-faq, .pk-form, .pk-progress, .pk-chart, .pk-empty, .gen-ui-oi-card),
${P} .pk-flow > .pk-table,
${P} .pk-group > .pk-table {
  background: var(--ax-sheen), var(--pk-card);
  border-radius: var(--pk-r-card);
  box-shadow: inset 0 0 0 1px var(--ax-edge), var(--ax-lift);
}
${P} .pk-chart .pk-table { box-shadow: none; background: transparent; }
${P} .gen-ui-oi-card { border-color: transparent; }
${P} .gen-ui-oi-card.is-soft { background: color-mix(in srgb, var(--ax-1) 6%, var(--pk-card)); }
${P} .gen-ui-oi-card .gen-ui-oi-card { box-shadow: inset 0 0 0 1px var(--ax-edge); }

/* ---------- Section heads ---------- */
${P} .pk-sec-head h2 {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  font-weight: 800;
  letter-spacing: -0.01em;
}
${P} .pk-sec-head h2::before {
  content: "";
  flex: none;
  width: 4px;
  height: 1em;
  border-radius: 2px;
  background: linear-gradient(180deg, var(--ax-1), var(--ax-2));
  box-shadow: 0 0 10px color-mix(in srgb, var(--ax-1) 55%, transparent);
}
${P} .pk-sec-head > span {
  padding: 2px 10px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--ax-1) 10%, transparent);
  color: color-mix(in srgb, var(--ax-1) 80%, var(--pk-ink));
  font-weight: 600;
}

/* ---------- Hero number ---------- */
${P} .pk-hero-stat {
  position: relative;
  isolation: isolate;
  overflow: hidden;
  background:
    radial-gradient(55% 70% at 50% 42%, color-mix(in srgb, var(--ax-1) 16%, transparent), transparent 72%),
    radial-gradient(40% 55% at 88% 8%, color-mix(in srgb, var(--ax-2) 16%, transparent), transparent 72%),
    var(--pk-card);
}
${P} .pk-hero-stat::after {
  content: "";
  position: absolute;
  inset: 0;
  z-index: -1;
  padding: 1.5px;
  border-radius: inherit;
  background: conic-gradient(from var(--ax-angle), transparent 0 55%, color-mix(in srgb, var(--ax-1) 85%, transparent) 70%, var(--ax-2) 82%, transparent 92%);
  -webkit-mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0);
  -webkit-mask-composite: xor;
  mask: linear-gradient(#000 0 0) content-box exclude, linear-gradient(#000 0 0);
  animation: ax-orbit 6s linear infinite;
  pointer-events: none;
}
${P} .pk-hero-stat .pk-stat-label {
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.12em;
  color: var(--pk-ink-2);
}
${P} .pk-hero-stat .pk-stat-value { font-size: 60px; font-weight: 800; letter-spacing: -0.035em; line-height: 1.05; }
${P} .pk-hero-stat .pk-stat-word { font-size: 30px; letter-spacing: -0.01em; }
${P} :is(.pk-hero-stat, .pk-stat) .pk-stat-value {
  background: var(--ax-grad);
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
  color: transparent;
}
${P} :is(.pk-hero-stat, .pk-stat) .pk-stat-value[data-tone] {
  background: linear-gradient(120deg, var(--pk-tone), color-mix(in srgb, var(--pk-tone) 55%, var(--ax-2)));
  -webkit-background-clip: text;
  background-clip: text;
}
${P} .pk-stat-value[data-tone="success"] { --pk-tone: var(--color-text-success); }
${P} .pk-stat-value[data-tone="warning"] { --pk-tone: var(--color-text-warning); }
${P} .pk-stat-value[data-tone="danger"] { --pk-tone: var(--color-text-danger); }
${P} :is(.pk-hero-stat, .pk-stat) .pk-stat-value small { -webkit-text-fill-color: var(--pk-ink-2); }
${P} .pk-hero-stat .pk-stat-value { animation: ax-pop 0.7s cubic-bezier(0.2, 0.9, 0.25, 1.2) both; }

/* ---------- Stat grid ---------- */
${P} .pk-stat { position: relative; overflow: hidden; }
${P} .pk-stat::before {
  content: "";
  position: absolute;
  top: 0;
  left: 50%;
  width: 36px;
  height: 3px;
  margin-left: -18px;
  border-radius: 0 0 3px 3px;
  background: var(--ax-grad);
  box-shadow: 0 0 12px color-mix(in srgb, var(--ax-1) 70%, transparent);
}
${P} .pk-stat .pk-stat-value { font-size: 26px; font-weight: 800; letter-spacing: -0.02em; }

/* ---------- Tags ---------- */
${P} .pk-tag {
  height: 24px;
  padding: 0 10px;
  border-radius: 999px;
  background: color-mix(in srgb, currentColor 11%, transparent);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, currentColor 16%, transparent);
  font-weight: 600;
}

/* ---------- Item list ---------- */
${P} .pk-list { padding: 6px 0; }
${P} .pk-row { position: relative; transition: background-color 0.2s, transform 0.15s; }
${P} .pk-row + .pk-row::before {
  content: "";
  position: absolute;
  top: 0;
  left: var(--pk-pad);
  right: var(--pk-pad);
  height: 1px;
  background: linear-gradient(90deg, transparent, var(--ax-edge) 12%, var(--ax-edge) 88%, transparent);
}
${P} .pk-row[role="button"]:active { background: color-mix(in srgb, var(--ax-1) 8%, transparent); transform: scale(0.99); }
${P} .pk-row > .hm-icon3d {
  padding: 7px;
  border-radius: 16px;
  background: linear-gradient(140deg, color-mix(in srgb, var(--ax-1) 14%, transparent), color-mix(in srgb, var(--ax-2) 12%, transparent));
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--ax-1) 12%, transparent);
}
${P} .pk-row-lead {
  display: inline-grid;
  place-items: center;
  min-width: 26px;
  height: 26px;
  padding: 0 6px;
  border-radius: 999px;
  background: var(--ax-grad);
  color: var(--hm-on-brand, #fff);
  font-size: 12px;
  font-weight: 700;
  box-shadow: 0 6px 14px -6px color-mix(in srgb, var(--ax-1) 80%, transparent);
}
${P} .pk-row-title { font-weight: 600; }
${P} .pk-row-value { font-weight: 800; letter-spacing: -0.01em; }
${P} .pk-list-label { font-weight: 700; }

/* ---------- Timeline ---------- */
${P} .pk-step-body::before {
  left: -1px;
  top: 5px;
  width: 12px;
  height: 12px;
  background: var(--ax-grad);
  box-shadow: 0 0 0 4px color-mix(in srgb, var(--ax-1) 16%, transparent), 0 0 12px color-mix(in srgb, var(--ax-1) 55%, transparent);
}
${P} .pk-step:first-child .pk-step-body::before { animation: ax-pulse 2.4s ease-out infinite; }
${P} .pk-step-body::after {
  background: linear-gradient(180deg, color-mix(in srgb, var(--ax-1) 55%, transparent), color-mix(in srgb, var(--ax-2) 30%, transparent));
}
${P} .pk-step-time { color: color-mix(in srgb, var(--ax-1) 78%, var(--pk-ink)); font-weight: 700; }
${P} .pk-step-title { font-weight: 600; }

/* ---------- Checklist ---------- */
${P} .pk-check label { transition: background-color 0.2s; }
${P} .pk-check label:active { background: color-mix(in srgb, var(--ax-1) 7%, transparent); }
${P} .pk-check input { width: 22px; height: 22px; border-width: 2px; transition: box-shadow 0.25s, border-color 0.25s; }
${P} .pk-check input:checked {
  border-color: transparent;
  background: var(--ax-grad);
  box-shadow: 0 0 0 4px color-mix(in srgb, var(--ax-1) 16%, transparent), 0 6px 14px -6px color-mix(in srgb, var(--ax-1) 85%, transparent);
  animation: ax-tick 0.45s cubic-bezier(0.2, 0.9, 0.25, 1.4);
}

/* ---------- Progress ---------- */
${P} .pk-progress b {
  background: var(--ax-grad);
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
  font-weight: 800;
}
${P} .pk-progress i { height: 10px; border-radius: 5px; overflow: visible; }
${P} .pk-progress i::before {
  border-radius: 5px;
  background:
    linear-gradient(100deg, transparent 30%, rgba(255, 255, 255, 0.55) 50%, transparent 70%) -150% 0 / 60% 100% no-repeat,
    var(--ax-grad);
  box-shadow: 0 0 14px color-mix(in srgb, var(--ax-1) 55%, transparent);
  animation: ax-sheen 2.8s ease-in-out infinite;
}

/* ---------- Note ---------- */
${P} .pk-note {
  position: relative;
  overflow: hidden;
  background: linear-gradient(100deg, color-mix(in srgb, var(--pk-tone) 12%, var(--pk-card)), var(--pk-card) 70%);
  padding-left: calc(var(--pk-pad) + 6px);
}
${P} .pk-note::before {
  content: "";
  position: absolute;
  top: 14px;
  bottom: 14px;
  left: 9px;
  width: 3px;
  border-radius: 3px;
  background: linear-gradient(180deg, var(--pk-tone), color-mix(in srgb, var(--pk-tone) 40%, var(--ax-2)));
  box-shadow: 0 0 12px color-mix(in srgb, var(--pk-tone) 70%, transparent);
}
${P} .pk-note:not([data-tone])::before { background: var(--ax-grad); }
${P} .pk-note:not([data-tone]) { background: linear-gradient(100deg, color-mix(in srgb, var(--ax-1) 9%, var(--pk-card)), var(--pk-card) 70%); }
${P} .pk-note:not([data-tone]) > .hm-icon { color: var(--ax-1); }

/* ---------- Pros and cons ---------- */
${P} .pk-procon { gap: 10px; padding: 10px; }
${P} .pk-procon > div {
  padding: 14px;
  border-radius: 18px;
  background: linear-gradient(160deg, color-mix(in srgb, var(--pk-tone) 11%, transparent), color-mix(in srgb, var(--pk-tone) 3%, transparent));
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--pk-tone) 14%, transparent);
}

/* ---------- Tables ---------- */
${P} .pk-table thead th {
  color: color-mix(in srgb, var(--ax-1) 70%, var(--pk-ink-2));
  font-weight: 700;
  letter-spacing: 0.06em;
}
${P} .pk-table td b,
${P} .pk-table th b {
  display: inline-block;
  padding: 1px 9px;
  border-radius: 999px;
  background: var(--ax-grad);
  color: var(--hm-on-brand, #fff);
  box-shadow: 0 4px 12px -5px color-mix(in srgb, var(--ax-1) 85%, transparent);
}

/* ---------- FAQ ---------- */
${P} .pk-faq summary { font-weight: 600; }
${P} .pk-faq summary .hm-icon {
  display: inline-grid;
  place-items: center;
  width: 26px;
  height: 26px;
  border-radius: 50%;
  background: color-mix(in srgb, var(--ax-1) 9%, transparent);
  color: var(--ax-1);
}
${P} .pk-faq details[open] summary { color: color-mix(in srgb, var(--ax-1) 75%, var(--pk-ink)); }
${P} .pk-faq details[open] > p { animation: ax-rise 0.35s ease-out both; }

/* ---------- Forms and choices ---------- */
${P} .pk-field > span { font-weight: 600; }
${P} .pk-field :is(input, select, textarea) {
  box-shadow: inset 0 0 0 1px var(--ax-edge);
  transition: box-shadow 0.2s, background-color 0.2s;
}
${P} .pk-field :is(input, select, textarea):focus {
  outline: 2px solid color-mix(in srgb, var(--ax-1) 85%, transparent);
  background: color-mix(in srgb, var(--ax-1) 5%, var(--pk-card));
  box-shadow: 0 0 0 5px color-mix(in srgb, var(--ax-1) 14%, transparent);
}
${P} .pk-seg { box-shadow: inset 0 0 0 1px var(--ax-edge); padding: 3px; }
${P} .pk-seg button { height: calc(var(--hm-control-height-s) - 2px); transition: color 0.2s, background-color 0.25s, box-shadow 0.25s; }
${P} .pk-seg button[aria-checked="true"],
${P} .pk-seg button[aria-checked="true"]:hover {
  color: color-mix(in srgb, var(--ax-1) 85%, var(--pk-ink));
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--ax-1) 28%, transparent), 0 6px 16px -8px color-mix(in srgb, var(--ax-1) 80%, transparent);
}

/* ---------- Buttons ---------- */
${P} .pk-btn { position: relative; overflow: hidden; font-weight: 600; }
${P} .pk-btn[data-primary]:not([data-small]) {
  background: var(--ax-grad);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.28), 0 10px 22px -10px color-mix(in srgb, var(--ax-1) 90%, transparent);
}
${P} .pk-btn[data-primary]:not([data-small])::after,
${P} .gen-ui-oi-button-solid:not(.gen-ui-oi-button-danger):not(.gen-ui-oi-button-success)::after {
  content: "";
  position: absolute;
  inset: 0;
  background: linear-gradient(100deg, transparent 35%, rgba(255, 255, 255, 0.4) 50%, transparent 65%) -150% 0 / 60% 100% no-repeat;
  animation: ax-sheen 4.5s ease-in-out infinite;
  pointer-events: none;
}
${P} .pk-btn:disabled { box-shadow: none; filter: saturate(0.4); }
${P} .gen-ui-oi-button-solid:not(.gen-ui-oi-button-danger):not(.gen-ui-oi-button-success) {
  position: relative;
  overflow: hidden;
  background: var(--ax-grad);
  color: var(--hm-on-brand, #fff);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.28), 0 10px 22px -10px color-mix(in srgb, var(--ax-1) 90%, transparent);
}
${P} .gen-ui-oi-button-outline { box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--ax-1) 30%, transparent); }
${P} .gen-ui-oi-badge { box-shadow: inset 0 0 0 1px color-mix(in srgb, currentColor 16%, transparent); }

/* ---------- Scoreboard ---------- */
${P} .pk-scoreboard {
  background: var(--ax-sheen), var(--pk-card);
  box-shadow: inset 0 0 0 1px var(--ax-edge), var(--ax-lift);
}
${P} .sb-team {
  position: relative;
  border-radius: 20px;
  background: linear-gradient(170deg, color-mix(in srgb, var(--ax-1) 10%, transparent), transparent 70%);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--ax-1) 12%, transparent);
}
${P} .sb-team + .sb-team { background: linear-gradient(170deg, color-mix(in srgb, var(--ax-2) 11%, transparent), transparent 70%); box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--ax-2) 14%, transparent); }
${P} .sb-team strong {
  font-weight: 800;
  letter-spacing: -0.04em;
  background: linear-gradient(160deg, var(--ax-1), color-mix(in srgb, var(--ax-1) 40%, var(--ax-2)));
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
  filter: drop-shadow(0 8px 16px color-mix(in srgb, var(--ax-1) 30%, transparent));
}
${P} .sb-team + .sb-team strong { background: linear-gradient(160deg, var(--ax-2), color-mix(in srgb, var(--ax-2) 45%, var(--ax-1))); -webkit-background-clip: text; background-clip: text; }
${P} .sb-team.sb-flash strong { animation: ax-pop 0.5s cubic-bezier(0.2, 0.9, 0.25, 1.4); }
${P} .sb-adds .pk-btn:not([data-primary]) {
  background: color-mix(in srgb, var(--ax-1) 12%, var(--pk-card));
  color: color-mix(in srgb, var(--ax-1) 85%, var(--pk-ink));
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--ax-1) 22%, transparent);
  font-weight: 700;
}

/* ---------- OpenUI quote and chart ---------- */
${P} .gen-ui-oi-quote {
  border-inline-start: 0;
  position: relative;
  padding-inline-start: 20px;
  background: linear-gradient(100deg, color-mix(in srgb, var(--ax-1) 8%, var(--pk-card)), var(--pk-card) 75%);
}
${P} .gen-ui-oi-quote::before {
  content: "";
  position: absolute;
  top: 12px;
  bottom: 12px;
  left: 8px;
  width: 3px;
  border-radius: 3px;
  background: var(--ax-grad);
}
${P} .iui-chart-plot rect[fill] { filter: drop-shadow(0 6px 8px color-mix(in srgb, var(--ax-1) 28%, transparent)); }

/* ---------- Tabs ---------- */
${P} .pk-tab[aria-selected="true"]::after {
  width: 22px;
  margin-left: -11px;
  height: 4px;
  background: var(--ax-grad);
  box-shadow: 0 0 10px color-mix(in srgb, var(--ax-1) 75%, transparent);
}
${P} .pk-tabs[data-stuck] {
  background: color-mix(in srgb, var(--pk-page) 72%, transparent);
  -webkit-backdrop-filter: blur(18px) saturate(1.5);
  backdrop-filter: blur(18px) saturate(1.5);
  box-shadow: 0 1px 0 var(--ax-edge);
}

/* ---------- Trend chart ---------- */
${P} .pk-plot polyline.line { stroke-width: 2.75; filter: drop-shadow(0 4px 6px color-mix(in srgb, var(--ax-1) 40%, transparent)); }
${P} .pk-plot rect.band { fill: color-mix(in srgb, var(--ax-1) 9%, transparent); }
${P} .pk-tip {
  border-radius: 12px;
  background: color-mix(in srgb, var(--pk-card) 78%, transparent);
  -webkit-backdrop-filter: blur(12px);
  backdrop-filter: blur(12px);
  box-shadow: inset 0 0 0 1px var(--ax-edge), 0 12px 24px -12px color-mix(in srgb, var(--ax-1) 60%, transparent);
}

/* ---------- Empty state ---------- */
${P} .pk-empty > .hm-icon {
  display: grid;
  place-items: center;
  width: 72px;
  height: 72px;
  border-radius: 50%;
  font-size: 30px;
  color: var(--ax-1);
  background: radial-gradient(circle, color-mix(in srgb, var(--ax-1) 14%, transparent), color-mix(in srgb, var(--ax-2) 6%, transparent) 70%);
  box-shadow: 0 0 0 1px color-mix(in srgb, var(--ax-1) 18%, transparent), 0 0 0 10px color-mix(in srgb, var(--ax-1) 5%, transparent);
  animation: ax-breathe 4s ease-in-out infinite;
}

/* ---------- Entrance ---------- */
${P} > .pk-cover > *,
${P} > .pk-flow > *,
${P} > .pk-panel > .pk-flow > * {
  animation: ax-rise 0.6s cubic-bezier(0.2, 0.8, 0.2, 1) both;
}
${P} > .pk-cover > :nth-child(2), ${P} .pk-flow > :nth-child(2) { animation-delay: 60ms; }
${P} > .pk-cover > :nth-child(3), ${P} .pk-flow > :nth-child(3) { animation-delay: 120ms; }
${P} .pk-flow > :nth-child(4) { animation-delay: 180ms; }
${P} .pk-flow > :nth-child(5) { animation-delay: 240ms; }
${P} .pk-flow > :nth-child(6) { animation-delay: 300ms; }
${P} .pk-flow > :nth-child(n + 7) { animation-delay: 360ms; }
${P} > .pk-cover > .pk-cover-pic { animation: ax-rise 0.6s cubic-bezier(0.2, 0.8, 0.2, 1) both, ax-float 6s ease-in-out 0.6s infinite; }

/* ---------- Generation ---------- */
html[data-genui-generation-phase="wire"] ${R} [data-genui-generation-wire] {
  outline-color: color-mix(in srgb, var(--hm-brand) 38%, transparent) !important;
}
html[data-genui-generation-phase] ${R} [data-genui-generation-wire] small { -webkit-text-fill-color: transparent !important; }
html[data-genui-generation-phase="wire"] ${R} [data-genui-generation-wire] :is(h1, h2, h3, p, label, span) {
  background-image: linear-gradient(90deg, color-mix(in srgb, var(--hm-brand) 55%, transparent), color-mix(in srgb, var(--ax-2) 45%, transparent)) !important;
  background-size: 70% 2px !important;
}
html[data-genui-generation-phase="wire"] ${R}::after {
  content: "";
  position: fixed;
  left: 0;
  right: 0;
  top: 0;
  height: 140px;
  pointer-events: none;
  z-index: 2147483640;
  background: linear-gradient(180deg, transparent, color-mix(in srgb, var(--hm-brand) 10%, transparent) 70%, color-mix(in srgb, var(--ax-2) 45%, transparent) 99%, transparent);
  animation: ax-scan 2.2s cubic-bezier(0.45, 0, 0.55, 1) infinite;
}

@keyframes ax-rise { from { opacity: 0.02; transform: translateY(14px) scale(0.985); } to { opacity: 1; transform: none; } }
@keyframes ax-pop { 0% { transform: scale(0.82); } 100% { transform: none; } }
@keyframes ax-tick { 0% { transform: scale(0.6); } 100% { transform: none; } }
@keyframes ax-float { 0%, 100% { transform: translateY(0) rotate(0deg); } 50% { transform: translateY(-6px) rotate(-2deg); } }
@keyframes ax-breathe { 0%, 100% { opacity: 0.75; transform: scale(0.96); } 50% { opacity: 1; transform: scale(1.04); } }
@keyframes ax-drift { from { transform: translate3d(0, 0, 0) scale(1); } to { transform: translate3d(-3%, 2%, 0) scale(1.06); } }
@keyframes ax-orbit { to { --ax-angle: 360deg; } }
@keyframes ax-sheen { 0%, 55% { background-position: -150% 0, 0 0; } 100% { background-position: 250% 0, 0 0; } }
@keyframes ax-pulse {
  0% { box-shadow: 0 0 0 0 color-mix(in srgb, var(--ax-1) 45%, transparent), 0 0 12px color-mix(in srgb, var(--ax-1) 55%, transparent); }
  100% { box-shadow: 0 0 0 12px transparent, 0 0 12px color-mix(in srgb, var(--ax-1) 55%, transparent); }
}
@keyframes ax-scan { from { transform: translateY(-140px); } to { transform: translateY(100vh); } }

/* Checker mode measures a still page; reduced motion keeps the look without movement. */
[data-local-genui-mode="checker"] ${R} *,
[data-local-genui-mode="checker"] ${R} *::before,
[data-local-genui-mode="checker"] ${R} *::after { animation: none !important; }
@media (prefers-reduced-motion: reduce) {
  ${R} *, ${R} *::before, ${R} *::after, ${R}::after { animation: none !important; transition: none !important; }
}
`;
