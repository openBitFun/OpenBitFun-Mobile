import { createContext } from 'react';
import { HARMONY_AURORA_CSS } from './harmonyAuroraStyles';

export const AnimatedCoverContext = createContext(false);

const blueprint = '.gen-ui-application[data-gen-ui-look="blueprint"] .pk';
const celadon = '.gen-ui-application[data-gen-ui-look="celadon"] .pk';
const panels = ':is(.pk-stat,.pk-hero-stat,.pk-list,.pk-timeline,.pk-check,.pk-card:not([data-surface="plain"]),.pk-progress,.pk-chart,.pk-form,.pk-faq,.gen-ui-oi-card)';
const blueprintCss = `
${blueprint} { --pk-r-card: 8px; --drawing-ink: #163e71; }
${blueprint} > .pk-cover[data-plain] {
  background: linear-gradient(to bottom, #cedde9, var(--drawing-ink) 30%);
  border-radius: 0 0 8px 8px;
}
${blueprint} > .pk-cover[data-plain]::before {
  inset: 0; opacity: 1; pointer-events: none; mask-image: none;
  background: linear-gradient(90deg, transparent 97%, #d1eaff30 97%),
              linear-gradient(0deg, transparent 97%, #d1eaff30 97%);
  background-size: 24px 24px;
}
${blueprint} .pk-cover :is(h1,.pk-cover-meta,.pk-cover-eyebrow) { color: #f3f9ff; }
${blueprint} .pk-cover .pk-tag {
  color: var(--drawing-ink); background: #e0edf6;
}
${blueprint} .pk-cover .pk-tag[data-tone] { color: var(--pk-tone); background: var(--pk-card); }
${blueprint} .pk-cover h1 { font-weight: 800; letter-spacing: -.025em; }
${blueprint} ${panels} {
  border-radius: 8px; background-color: var(--pk-card);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--pk-ink) 18%, transparent);
}
${blueprint} :is(.pk-step-time,.pk-stat-value,.pk-cover-eyebrow) {
  font-family: ui-monospace, monospace; font-variant-numeric: tabular-nums;
}
${blueprint} .pk-hero-stat {
  background-image: repeating-linear-gradient(90deg,var(--pk-ink-2) 0 1px,transparent 1px 8px);
  background-size: calc(100% - 32px) 4px; background-position: center bottom; background-repeat: no-repeat;
}
${blueprint} .pk-sec-head h2 { border-inline-start: 4px solid var(--pk-accent); padding-inline-start: 8px; }
${blueprint} .pk-progress i { border-radius: 2px; }
`;
const celadonCss = `
.gen-ui-application[data-gen-ui-look="celadon"]:has(.pk) {
  background: color-mix(in srgb, var(--color-background-secondary) 82%, #9fc3b5);
}
${celadon} { --pk-r-card: 20px; --glaze-ink: #173e39; }
${celadon} > .pk-cover[data-plain] {
  background: linear-gradient(125deg,#eef8f3,#c6e4da 62%,#97c7ba);
  border-radius: 0 0 40px 12px;
}
${celadon} > .pk-cover[data-plain]::before {
  inset: 0; opacity: 1; pointer-events: none; mask-image: none;
  background: repeating-radial-gradient(ellipse at 112% -26%,transparent 0 32px,#ffffff70 33px,transparent 35px 52px);
}
${celadon} .pk-cover :is(h1,.pk-cover-meta,.pk-cover-eyebrow) { color: var(--glaze-ink); }
${celadon} :is(.pk-cover h1,.pk-sec-head h2,.pk-hero-stat .pk-stat-value) {
  font-family: "Noto Serif CJK SC", "Songti SC", serif; font-weight: 600;
}
${celadon} ${panels} {
  border-radius: 20px;
  background: color-mix(in srgb, var(--pk-card) 94%, #83baa8);
  box-shadow: inset 0 1px 0 #ffffff80, inset 0 -1px 0 #44847236, 0 4px 12px -10px #174c43aa;
}
${celadon} .pk-sec-head h2 { letter-spacing: .04em; }
${celadon} .pk-hero-stat { border-inline-start: 4px solid #81b5a2; }
${celadon} .pk-progress i { border-radius: 999px; }
`;
const looks = {
  classic: { id: 'classic', css: '' },
  aurora: { id: 'aurora', css: HARMONY_AURORA_CSS },
  blueprint: { id: 'blueprint', css: blueprintCss },
  celadon: { id: 'celadon', css: celadonCss },
} as const;

export function appearanceFor(value?: string) {
  return value === 'classic' || value === 'blueprint' || value === 'celadon' ? looks[value] : looks.aurora;
}
