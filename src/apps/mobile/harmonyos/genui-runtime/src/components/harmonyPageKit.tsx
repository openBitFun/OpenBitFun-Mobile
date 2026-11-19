import { AnimatedCoverContext } from './harmonyLooks';
import { useReducedMotion } from '../local-runtime/internal/useReducedMotion';
import { Children, useContext, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode, type Ref } from 'react';
import type { GenUIComponentProps, GenUIImplementations } from '../genUILibrary';
import { i18nService, useI18n } from '../local-runtime/i18n';
import { fluentEmoji3dUrl } from './vendor/fluentEmoji3d';
import { fluentEmojiAnimatedUrl } from './fluentEmojiAnimated';
import { useCalendarButtonStatus } from '../genUICalendarStatus';
import { useGenUIDeviceCapabilities } from '../genUIDeviceCapabilities';

/**
 * Harmony page block kit. Each renderer emits the markup of the matching
 * harmony-genui composePage block (`apps/agent/src/page_blocks.py`), so the
 * vendored `page_kit.css` and design-system styles apply unchanged. The
 * blocks are ordinary OpenUI components: state, bindings and actions still go
 * through the OpenUI runtime and the product owner, never through page
 * scripts.
 */

type Tone = 'success' | 'warning' | 'danger';
type Tag = string | { text: string; tone?: Tone };
const text = (value: unknown): string => value == null ? '' : String(value);
const toneOf = (value: unknown): Tone | undefined => value === 'success' || value === 'warning' || value === 'danger' ? value : undefined;
const list = <T,>(value: unknown): T[] => Array.isArray(value) ? value as T[] : [];
/** Numbers read as written: no padded decimals, no grouping inside a stat. */
const numberText = (value: number): string => i18nService.formatNumber(value, { minimumFractionDigits: 0, maximumFractionDigits: 2, useGrouping: false });
/** OpenUI child element nodes carry their component name. */
const typeNameOf = (node: unknown): string => (node && typeof node === 'object' && typeof (node as { typeName?: unknown }).typeName === 'string') ? (node as { typeName: string }).typeName : '';

/**
 * A 3D picture of a concrete thing; the emoji itself when the asset cannot
 * load. An animated picture, when asked for and available, fades in over the
 * static one once it has loaded and is dropped if it fails.
 */
function Picture({ emoji, large, animated, className = '' }: { emoji: string; large?: boolean; animated?: boolean; className?: string }) {
  const url = fluentEmoji3dUrl(emoji);
  const motionUrl = animated ? fluentEmojiAnimatedUrl(emoji) : undefined;
  const [failed, setFailed] = useState<string>();
  const [motion, setMotion] = useState<{ url: string; state: 'ready' | 'failed' }>();
  const image = url && failed !== url;
  const motionState = motion?.url === motionUrl ? motion?.state : undefined;
  return <span className={`hm-icon3d${large ? ' large' : ''}${className ? ' ' + className : ''}`} data-emoji={emoji} aria-hidden="true" data-hm-icon3d={image ? 'external' : 'fallback'}>
    {image ? <img src={url} alt="" decoding="async" draggable={false} referrerPolicy="no-referrer" onError={() => setFailed(url)} /> : <span className="hm-icon3d-glyph">{emoji}</span>}
    {image && motionUrl && motionState !== 'failed' ? <img className="hm-icon3d-motion" data-ready={motionState === 'ready' ? '' : undefined} src={motionUrl} alt="" decoding="async" draggable={false} referrerPolicy="no-referrer"
      onLoad={() => setMotion({ url: motionUrl, state: 'ready' })} onError={() => setMotion({ url: motionUrl, state: 'failed' })} /> : null}
  </span>;
}

function Icon({ name }: { name: string }) {
  return <span className="hm-icon" data-icon={name} aria-hidden="true" />;
}

function Tags({ tags }: { tags: Tag[] }) {
  if (!tags.length) return null;
  return <div className="pk-tags">{tags.map((tag, index) => {
    const label = typeof tag === 'string' || typeof tag === 'number' ? text(tag) : text(tag?.text);
    const tone = typeof tag === 'object' && tag ? toneOf(tag.tone) : undefined;
    // The reference host quiets accent-coloured tags to the secondary ink; a
    // status tag keeps its tone.
    return <span key={index} className="pk-tag" data-tone={tone} data-quiet={tone ? undefined : ''}>{label}</span>;
  })}</div>;
}

/** A number with its unit at the unit's size; words stay words. */
/** Motion is decoration: still pages for checkers and reduced-motion readers. */
function stillPage(): boolean {
  return typeof window === 'undefined' || Boolean(document.querySelector('[data-local-genui-mode="checker"]'))
    || Boolean(window.matchMedia?.('(prefers-reduced-motion: reduce)').matches);
}

/**
 * A number that rolls from its previous value to a new one. The first render
 * shows the real value, so readers, probes and tests never see a midway number.
 */
function useCountUp(target: number | undefined): number | undefined {
  const [shown, setShown] = useState<number | undefined>(target);
  const last = useRef(target ?? 0);
  useEffect(() => {
    if (target === undefined) { setShown(undefined); return undefined; }
    const from = last.current;
    last.current = target;
    if (from === target || stillPage()) { setShown(target); return undefined; }
    const started = performance.now();
    const duration = Math.min(1200, 500 + Math.abs(target - from) * 4);
    let frame = 0;
    const tick = (now: number) => {
      const t = Math.min(1, (now - started) / duration);
      const eased = 1 - Math.pow(1 - t, 3);
      setShown(from + (target - from) * eased);
      if (t < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [target]);
  return shown;
}

function StatValue({ value, unit, tone, id }: { value: unknown; unit?: unknown; tone?: Tone; id?: string }) {
  const isNumber = typeof value === 'number' || (typeof value === 'string' && /^[+\-−]?\d[\d.,:/]*%?$/.test(value.trim()));
  const target = typeof value === 'number' && Number.isFinite(value) ? value : undefined;
  const rolling = useCountUp(target);
  const decimals = target === undefined ? 0 : (String(target).split('.')[1] ?? '').length;
  const shown = target !== undefined && rolling !== undefined
    ? numberText(Number(rolling.toFixed(Math.min(2, decimals))) + 0)
    : typeof value === 'number' ? numberText(value) : text(value);
  return <span className={`pk-stat-value${isNumber ? '' : ' pk-stat-word'}`} id={id} data-tone={tone}>
    {shown}{unit ? <small data-pk-unit>{text(unit)}</small> : null}
  </span>;
}

// ---------- Containers ----------

function Page({ view, slots }: GenUIComponentProps) {
  const device = useGenUIDeviceCapabilities();
  const orientation = view.props.orientation === 'portrait' || view.props.orientation === 'landscape' ? view.props.orientation : 'auto';
  useEffect(() => {
    device?.setOrientation?.(orientation);
    return () => device?.setOrientation?.('auto');
  }, [device, orientation]);
  const nodes = list<unknown>(view.props.children);
  const children = Children.toArray(slots.children as ReactNode);
  // The page is opened by a Cover that comes first; it sits outside the flow so
  // its wash and picture reach the edges and wide screens keep it full width.
  const coverFirst = typeNameOf(nodes[0]) === 'Cover';
  const cover = coverFirst ? children[0] : null;
  const rest = coverFirst ? children.slice(1) : children;
  // Module tabs stay outside the flow too: they stick to the top and their
  // panels carry their own flows. Blocks around them flow as usual.
  const restNodes = coverFirst ? nodes.slice(1) : nodes;
  const tabsAt = restNodes.findIndex(node => typeNameOf(node) === 'Tabs');
  const before = tabsAt < 0 ? rest : rest.slice(0, tabsAt);
  const after = tabsAt < 0 ? [] : rest.slice(tabsAt + 1);
  return <main className="pk" data-hm-theme={text(view.props.theme) || 'blue'} data-hm-font={view.props.font && view.props.font !== 'default' ? text(view.props.font) : undefined} aria-label={text(view.props.title) || undefined} data-pk-page>
    {cover}
    {before.length ? <div className="pk-flow">{before}</div> : null}
    {tabsAt < 0 ? null : rest[tabsAt]}
    {after.length ? <div className="pk-flow">{after}</div> : null}
  </main>;
}

function Section({ view, slots }: GenUIComponentProps) {
  const title = text(view.props.title);
  const aside = text(view.props.aside);
  return <div className="pk-sec">
    {title ? <div className="pk-sec-head"><h2>{title}</h2>{aside ? <span>{aside}</span> : null}</div> : null}
    {slots.children}
  </div>;
}

function Layout({ view, slots }: GenUIComponentProps) {
  const mode = text(view.props.mode) || 'stack';
  return <div className="pk-layout" data-mode={mode} data-columns={view.props.columns ? text(view.props.columns) : undefined}>
    <div className="pk-layout-grid">{Children.toArray(slots.children as ReactNode).map((child, index) => <div key={index} className="pk-layout-cell">{child}</div>)}</div>
  </div>;
}

function TabPanel({ slots }: GenUIComponentProps) {
  return <div className="pk-flow">{slots.children}</div>;
}

function Tabs({ view, slots }: GenUIComponentProps) {
  const panels = list<unknown>(view.props.children);
  const labels = panels.map((node, index) => text((node as { props?: Record<string, unknown> })?.props?.label) || String(index + 1));
  const children = Children.toArray(slots.children as ReactNode);
  const [selected, setSelected] = useState(0);
  const current = Math.min(selected, Math.max(0, children.length - 1));
  const base = useRef(`pk-${Math.random().toString(36).slice(2, 8)}`).current;
  return <>
    <nav className="pk-tabs" role="tablist">{labels.map((label, index) => <button key={index} type="button" className="pk-tab" role="tab" id={`${base}-tab-${index}`} aria-controls={`${base}-panel-${index}`} aria-selected={index === current} tabIndex={index === current ? 0 : -1} onClick={() => setSelected(index)} onKeyDown={event => {
      if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') return;
      const next = (current + (event.key === 'ArrowRight' ? 1 : -1) + labels.length) % labels.length;
      setSelected(next);
      (event.currentTarget.parentElement?.children[next] as HTMLElement | undefined)?.focus();
    }}>{label}</button>)}</nav>
    {children.map((child, index) => <section key={index} className="pk-panel" role="tabpanel" id={`${base}-panel-${index}`} aria-labelledby={`${base}-tab-${index}`} hidden={index !== current}>{child}</section>)}
  </>;
}

// ---------- Blocks ----------

type CoverTag = Tag | { text: string; tone?: Tone; role?: 'context' | 'configuration' };

/** resolve_cover_presentation: tool headers fold away configuration tags only. */
function visibleCoverTags(tags: CoverTag[], purpose: string, display: string): Tag[] {
  return tags.filter(tag => display !== 'hide' && (display === 'show' || purpose === 'content'
    || typeof tag !== 'object' || tag === null || (tag as { role?: string }).role !== 'configuration')) as Tag[];
}

interface CoverWash { mode: 'gradient' | 'none'; colorSource: 'theme' | 'picture'; intensity: number; height: number }

/** cover_presentation: bounded atmosphere for a plain cover; anything else is ignored. */
function coverWash(value: unknown): CoverWash | undefined {
  const cover = (value as { cover?: Record<string, unknown> } | undefined)?.cover;
  if (!cover || (cover.mode !== 'gradient' && cover.mode !== 'none') || (cover.colorSource !== 'theme' && cover.colorSource !== 'picture')) return undefined;
  const intensity = typeof cover.intensity === 'number' && Number.isFinite(cover.intensity) && cover.intensity >= 0 && cover.intensity <= 0.3 ? cover.intensity : 0.22;
  const height = typeof cover.height === 'number' && Number.isInteger(cover.height) && cover.height >= 160 && cover.height <= 400 ? cover.height : 360;
  return { mode: cover.mode, colorSource: cover.colorSource, intensity, height };
}

/**
 * Port of the reference cover-picture-wash.js: the wash takes the dominant
 * saturated hue of the cover's 3D picture. Only host-served pictures are
 * sampled; a picture that cannot load leaves the theme wash.
 */
function usePictureWash(ref: React.RefObject<HTMLElement | null>, wash: CoverWash | undefined) {
  useEffect(() => {
    const cover = ref.current;
    if (!cover || !wash || wash.mode !== 'gradient' || wash.colorSource !== 'picture') return undefined;
    let cancelled = false;
    const sample = (source: HTMLImageElement) => {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = () => {
        if (cancelled || !source.isConnected) return;
        try {
          const canvas = document.createElement('canvas'); canvas.width = canvas.height = 32;
          const ctx = canvas.getContext('2d'); if (!ctx) return;
          ctx.drawImage(img, 0, 0, 32, 32);
          const px = ctx.getImageData(0, 0, 32, 32).data; const bins: Record<number, { w: number; r: number; g: number; b: number }> = {}; let best: { w: number; r: number; g: number; b: number } | null = null;
          for (let i = 0; i < px.length; i += 4) {
            const r = px[i], g = px[i + 1], b = px[i + 2], a = px[i + 3] / 255, max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
            if (a < .5 || d < 30 || max < 45 || min > 220) continue;
            const h = max === r ? ((g - b) / d + 6) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4, k = Math.floor(h * 3), w = a * d;
            const bin = bins[k] || (bins[k] = { w: 0, r: 0, g: 0, b: 0 });
            bin.w += w; bin.r += r * w; bin.g += g * w; bin.b += b * w; if (!best || bin.w > best.w) best = bin;
          }
          if (best) cover.style.setProperty('--pk-picture-wash', `rgb(${Math.round(best.r / best.w)} ${Math.round(best.g / best.w)} ${Math.round(best.b / best.w)})`);
        } catch { /* a tainted or failed sample keeps the theme wash */ }
      };
      img.src = source.src;
    };
    const find = () => cover.querySelector<HTMLImageElement>('.pk-cover-pic img[src]');
    const current = find();
    if (current) { sample(current); return () => { cancelled = true; }; }
    const observer = new MutationObserver(() => { const next = find(); if (next) { observer.disconnect(); sample(next); } });
    observer.observe(cover, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });
    const timer = window.setTimeout(() => observer.disconnect(), 10000);
    return () => { cancelled = true; observer.disconnect(); window.clearTimeout(timer); };
  }, [ref, wash?.mode, wash?.colorSource]); // eslint-disable-line react-hooks/exhaustive-deps
}

function Cover({ view }: GenUIComponentProps) {
  const animatedCover = useContext(AnimatedCoverContext);
  const reducedMotion = useReducedMotion();
  const compact = view.props.variant === 'compact';
  const picture = text(view.props.picture).trim();
  const eyebrow = text(view.props.eyebrow);
  const meta = text(view.props.meta);
  // The page decides the default purpose: a managed tool block makes it a tool header.
  const ref = useRef<HTMLElement>(null);
  const [toolPage, setToolPage] = useState(false);
  useLayoutEffect(() => { setToolPage(Boolean(ref.current?.closest('[data-pk-page]')?.querySelector('.pk-scoreboard'))); });
  const purpose = view.props.purpose === 'tool' || view.props.purpose === 'content' ? text(view.props.purpose) : toolPage ? 'tool' : 'content';
  const tags = visibleCoverTags(list<CoverTag>(view.props.tags), purpose, text(view.props.tagsDisplay) || 'auto');
  // As in the reference, a compact cover keeps its subject picture.
  const lead = picture ? <Picture emoji={picture} large animated={animatedCover && !reducedMotion} className="pk-cover-pic" /> : null;
  const wash = coverWash(view.props.presentation);
  usePictureWash(ref, wash);
  const copy = <>
    {eyebrow ? <p className={`pk-cover-eyebrow${/[A-Za-z]/.test(eyebrow) && !/[\u3000-\u9fff\uff00-\uffef]/.test(eyebrow) ? ' hm-latin' : ''}`}>{eyebrow}</p> : null}
    <h1>{text(view.props.title)}</h1>
    {meta ? <p className="pk-cover-meta">{meta}</p> : null}
    <Tags tags={tags} />
  </>;
  return <header ref={ref} className="pk-cover" data-plain="" data-hm-bleed-top="plain" data-variant={compact ? 'compact' : view.props.variant === 'immersive' ? 'immersive' : undefined}
    data-pk-wash-mode={wash?.mode} data-pk-wash-source={wash?.colorSource}
    style={wash ? { '--pk-wash-strength': `${wash.intensity * 100}%`, '--pk-wash-h': `${wash.height}px` } as CSSProperties : undefined}
    data-align={view.props.align === 'center' ? 'center' : undefined}
    data-pk-cover-layout={view.props.layout === 'stacked' ? 'stacked' : undefined}
    data-pk-cover-purpose={purpose === 'tool' ? 'tool' : undefined}>
    {lead}
    {lead ? <div className="pk-cover-copy">{copy}</div> : copy}
  </header>;
}

function HeroStat({ view }: GenUIComponentProps) {
  return <div className="pk-hero-stat">
    <span className="pk-stat-label">{text(view.props.label)}</span>
    <StatValue value={view.props.value} unit={view.props.unit} tone={toneOf(view.props.tone)} />
    <Tags tags={list<Tag>(view.props.tags)} />
  </div>;
}

type StatItem = { label: string; value: string | number; unit?: string; tone?: Tone };
function Stats({ view }: GenUIComponentProps) {
  return <div className="pk-stats">{list<StatItem>(view.props.items).map((item, index) => <div key={index} className="pk-stat">
    <StatValue value={item.value} unit={item.unit} tone={toneOf(item.tone)} />
    <span className="pk-stat-label">{text(item.label)}</span>
  </div>)}</div>;
}

type Row = { id?: string; title: string; sub?: string; lead?: string; picture?: string; value?: string | number; tone?: Tone; tag?: Tag; tags?: Tag[] };
function ItemList({ view, emit, disabled, isStreaming }: GenUIComponentProps) {
  const rows = list<Row>(view.props.rows);
  const label = text(view.props.label);
  const interactive = Boolean(view.props.action) && !disabled && !isStreaming;
  const layout = view.props.layout === 'cards' ? 'cards' : undefined;
  const { t } = useI18n('flow-chat');
  return <div className="pk-list" data-empty={text(view.props.emptyText) || t('toolCards.generativeUI.pageKit.empty')} data-layout={layout} data-pk-output-list={label ? '1' : undefined}>
    {label ? <div className="pk-list-label">{label}</div> : null}
    {rows.map((row, index) => {
      const tag = row.tag === undefined ? undefined : typeof row.tag === 'object' ? row.tag : { text: text(row.tag) };
      const body = <>
        {row.lead ? <span className="pk-row-lead">{text(row.lead)}</span> : null}
        {row.picture ? <Picture emoji={text(row.picture).trim()} /> : null}
        <div className="pk-row-text">
          <span className="pk-row-title">{text(row.title)}</span>
          {row.sub ? <span className="pk-row-sub">{text(row.sub)}</span> : null}
          <Tags tags={list<Tag>(row.tags)} />
        </div>
        {row.value !== undefined || tag ? <div className="pk-row-end">
          {tag ? <span className="pk-tag" data-tone={toneOf(tag.tone)}>{text(tag.text)}</span> : null}
          {row.value !== undefined ? <span className="pk-row-value" data-tone={toneOf(row.tone)}>{typeof row.value === 'number' ? numberText(row.value) : text(row.value)}</span> : null}
        </div> : null}
      </>;
      const key = row.id ?? `${index}`;
      return interactive
        ? <div key={key} className="pk-row" role="button" tabIndex={0} data-pk-row={key} onClick={() => emit('select', row.id ?? row.title)} onKeyDown={event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); emit('select', row.id ?? row.title); } }}>{body}</div>
        : <div key={key} className="pk-row" data-pk-row={key}>{body}</div>;
    })}
  </div>;
}

type Step = { time?: string; title: string; sub?: string };
function Timeline({ view }: GenUIComponentProps) {
  const steps = list<Step>(view.props.steps);
  const plain = steps.every(step => !step.time);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const root = ref.current;
    if (!root) return undefined;
    const pending = Array.from(root.querySelectorAll<HTMLElement>('.pk-step:not([data-seen])'));
    if (stillPage() || typeof IntersectionObserver === 'undefined') { pending.forEach(step => step.setAttribute('data-seen', '')); return undefined; }
    const observer = new IntersectionObserver(entries => entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      entry.target.setAttribute('data-seen', '');
      observer.unobserve(entry.target);
    }), { threshold: 0.35 });
    pending.forEach(step => observer.observe(step));
    return () => observer.disconnect();
  }, [steps.length]);
  return <div ref={ref} className="pk-timeline" data-plain={plain ? '' : undefined}>{steps.map((step, index) => <div key={index} className="pk-step">
    {plain ? null : <span className="pk-step-time">{text(step.time)}</span>}
    <div className="pk-step-body"><span className="pk-step-title">{text(step.title)}</span>{step.sub ? <span className="pk-step-sub">{text(step.sub)}</span> : null}</div>
    <span aria-hidden="true" />
  </div>)}</div>;
}

type CheckItem = { id: string; text: string; sub?: string };
function Checklist({ view, emit, disabled, isStreaming }: GenUIComponentProps) {
  const items = list<CheckItem>(view.props.items);
  // Bound to state, the checked ids belong to the owner; unbound, to this view.
  const bound = Array.isArray(view.props.value) ? (view.props.value as unknown[]).map(text) : undefined;
  const [local, setLocal] = useState<string[]>([]);
  const checked = bound ?? local;
  const { t } = useI18n('flow-chat');
  const [burst, setBurst] = useState('');
  useEffect(() => {
    if (!burst) return undefined;
    const timer = window.setTimeout(() => setBurst(''), 700);
    return () => window.clearTimeout(timer);
  }, [burst]);
  const toggle = (id: string) => {
    const adding = !checked.includes(id);
    const next = adding ? [...checked, id] : checked.filter(item => item !== id);
    setLocal(next);
    if (adding && !stillPage()) setBurst(id);
    emit('change', next);
  };
  const done = items.filter(item => checked.includes(item.id)).length;
  return <div className="pk-check" data-complete={items.length > 0 && done === items.length ? '' : undefined}>
    {items.length > 1 ? <div className="pk-check-head" aria-hidden="true">
      <span>{t('toolCards.generativeUI.showcase.done')}</span><b>{done}/{items.length}</b>
      <i style={{ '--pk-v': `${Math.round(done / items.length * 1000) / 10}%` } as CSSProperties} />
    </div> : null}
    {items.map(item => <label key={item.id} data-pk-check={item.id} data-burst={burst === item.id ? '' : undefined}>
    <input type="checkbox" checked={checked.includes(item.id)} disabled={disabled || Boolean(isStreaming)} onChange={() => toggle(item.id)} />
    <span>{text(item.text)}{item.sub ? <small>{text(item.sub)}</small> : null}</span>
  </label>)}
  </div>;
}

const NOTE_ICON: Record<Tone, string> = { danger: 'exclamationmark_triangle', warning: 'exclamationmark_circle', success: 'checkmark_circle' };
function Note({ view }: GenUIComponentProps) {
  const tone = toneOf(view.props.tone);
  return <div className="pk-note" role="note" data-tone={tone}>
    <Icon name={tone ? NOTE_ICON[tone] : 'info_circle'} />
    <p>{text(view.props.text)}{view.props.sub ? <small>{text(view.props.sub)}</small> : null}</p>
  </div>;
}

function Prose({ view }: GenUIComponentProps) {
  return <div className="pk-card" data-surface={view.props.surface === 'plain' ? 'plain' : undefined}>
    {list<string>(view.props.paragraphs).map((paragraph, index) => <p key={index}>{text(paragraph)}</p>)}
  </div>;
}

type Point = string | { title: string; sub?: string };
function ProCon({ view }: GenUIComponentProps) {
  const { t } = useI18n('flow-chat');
  const labels = (view.props.labels && typeof view.props.labels === 'object' ? view.props.labels : {}) as { pros?: string; cons?: string };
  const column = (tone: Tone, icon: string, label: string, points: Point[]) => <div data-tone={tone}>
    <h3><Icon name={icon} />{label}</h3>
    <ul>{points.map((point, index) => <li key={index}>{typeof point === 'object' && point ? <><b>{text(point.title)}</b>{point.sub ? <span>{text(point.sub)}</span> : null}</> : text(point)}</li>)}</ul>
  </div>;
  return <div className="pk-procon">
    {column('success', 'checkmark_circle', labels.pros || t('toolCards.generativeUI.pageKit.pros'), list<Point>(view.props.pros))}
    {column('warning', 'exclamationmark_circle', labels.cons || t('toolCards.generativeUI.pageKit.cons'), list<Point>(view.props.cons))}
  </div>;
}

type Cell = string | number | { text: string | number; best?: boolean };
function CompareTable({ view }: GenUIComponentProps) {
  const head = list<string | number>(view.props.head);
  const rows = list<Cell[]>(view.props.rows);
  const label = text(view.props.label);
  const cell = (value: Cell) => typeof value === 'object' && value ? (value.best ? <b>{text(value.text)}</b> : text(value.text)) : text(value);
  const table = <div className="pk-table" tabIndex={0}>
    <table>
      <thead><tr>{head.map((column, index) => <th key={index} scope="col">{text(column)}</th>)}</tr></thead>
      <tbody>{rows.map((row, index) => <tr key={index}>{list<Cell>(row).map((value, column) => column === 0 ? <th key={column} scope="row">{cell(value)}</th> : <td key={column}>{cell(value)}</td>)}</tr>)}</tbody>
    </table>
  </div>;
  return label ? <div className="pk-group"><div className="pk-list-label">{label}</div>{table}</div> : table;
}

function Faq({ view }: GenUIComponentProps) {
  return <div className="pk-faq">{list<{ q: string; a: string }>(view.props.items).map((item, index) => <details key={index}>
    <summary>{text(item.q)}<Icon name="chevron_right" /></summary>
    <p>{text(item.a)}</p>
  </details>)}</div>;
}

function SegmentedButtons({ options, value, label, onPick, disabled, rootRef }: { options: string[]; value: string; label?: string; onPick: (value: string) => void; disabled?: boolean; rootRef?: Ref<HTMLDivElement> }) {
  return <div ref={rootRef} className="pk-seg" role="radiogroup" aria-label={label || undefined} data-value={value}>{options.map((option, index) => <button key={index} type="button" role="radio" aria-checked={option === value} tabIndex={option === value ? 0 : -1} data-value={option} disabled={disabled} onClick={() => onPick(option)} onKeyDown={event => {
    if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') return;
    const next = options[(index + (event.key === 'ArrowRight' ? 1 : -1) + options.length) % options.length];
    onPick(next);
  }}>{option}</button>)}</div>;
}

function Segmented({ view, emit, disabled, isStreaming }: GenUIComponentProps) {
  const options = list<unknown>(view.props.options).map(text);
  const [local, setLocal] = useState(options[0] ?? '');
  const value = typeof view.props.value === 'string' && view.props.value ? view.props.value : local;
  const label = text(view.props.label);
  const pick = (next: string) => { setLocal(next); emit('change', next); };
  // As in the reference, a standalone choice names itself only to assistive
  // technology; inside a form card the label is shown like a field label.
  const ref = useRef<HTMLDivElement>(null);
  const [inForm, setInForm] = useState(false);
  useLayoutEffect(() => { setInForm(Boolean(ref.current?.parentElement?.closest('.pk-form'))); }, []);
  const control = <SegmentedButtons rootRef={inForm && label ? undefined : ref} options={options} value={value} label={label} onPick={pick} disabled={disabled || Boolean(isStreaming)} />;
  return inForm && label ? <div ref={ref} className="pk-seg-field"><span>{label}</span>{control}</div> : control;
}

function FormCard({ view, slots }: GenUIComponentProps) {
  const label = text(view.props.label);
  return <form className="pk-form" noValidate data-pk-layout={view.props.layout === 'single' ? 'single' : 'auto'} onSubmit={event => event.preventDefault()} aria-label={label || undefined}>
    {label ? <div className="pk-list-label" style={{ padding: 0 }}>{label}</div> : null}
    {slots.children}
  </form>;
}

function Field({ view, emit, disabled, isStreaming }: GenUIComponentProps) {
  const { t } = useI18n('flow-chat');
  const type = text(view.props.type) || 'text';
  const label = text(view.props.label) + (view.props.unit ? ` (${text(view.props.unit)})` : '');
  const external = view.props.value == null ? '' : text(view.props.value);
  const [draft, setDraft] = useState(external);
  useEffect(() => setDraft(external), [external]);
  const [error, setError] = useState('');
  const off = disabled || Boolean(isStreaming);
  const commit = (raw: string) => {
    setDraft(raw);
    if (type === 'number') {
      const trimmed = raw.trim();
      if (!trimmed) { setError(''); emit('change', null); return; }
      const parsed = Number(trimmed);
      if (!Number.isFinite(parsed)) { setError(t('toolCards.generativeUI.pageKit.numberRequired')); return; }
      setError('');
      emit('change', parsed);
      return;
    }
    emit('change', raw);
  };
  const input = type === 'textarea'
    ? <textarea value={draft} placeholder={text(view.props.placeholder) || undefined} disabled={off} onChange={event => commit(event.currentTarget.value)} />
    : type === 'select'
      ? <select value={draft} disabled={off} onChange={event => commit(event.currentTarget.value)}>{list<unknown>(view.props.options).map(option => <option key={text(option)} value={text(option)}>{text(option)}</option>)}</select>
      : <input type={type === 'number' ? 'text' : type} inputMode={type === 'number' ? 'decimal' : undefined} value={draft} placeholder={text(view.props.placeholder) || undefined} aria-invalid={error ? true : undefined} disabled={off} onChange={event => commit(event.currentTarget.value)} />;
  return <label className="pk-field" data-span={view.props.span ? text(view.props.span) : undefined}><span>{label}</span>{input}<small aria-live="polite">{error}</small></label>;
}

function Progress({ view }: GenUIComponentProps) {
  const done = Number(view.props.done) || 0;
  const total = Number(view.props.total) || 0;
  const ratio = total > 0 ? Math.max(0, Math.min(1, done / total)) : 0;
  const unit = text(view.props.unit);
  return <div className="pk-progress" role="progressbar" aria-label={text(view.props.label)} aria-valuemin={0} aria-valuemax={total} aria-valuenow={done}>
    <span>{text(view.props.label)}</span><b>{numberText(done)}/{numberText(total)}{unit}</b><i style={{ '--pk-value': `${Math.round(ratio * 1000) / 10}%` } as CSSProperties} />
  </div>;
}

function nice(range: number): number {
  const power = Math.pow(10, Math.floor(Math.log10(range)));
  const mantissa = range / power;
  return (mantissa <= 1 ? 1 : mantissa <= 2 ? 2 : mantissa <= 5 ? 5 : 10) * power;
}

type Series = { name: string; values: number[] };
/** Port of the reference chart(): same scale, grid, band, series and readout. */
function TrendChart({ view }: GenUIComponentProps) {
  const { t } = useI18n('flow-chat');
  const xs = list<unknown>(view.props.x).map(text);
  const series = list<Series>(view.props.series).slice(0, 2);
  const unit = text(view.props.unit);
  const band = view.props.band && typeof view.props.band === 'object' ? view.props.band as { from: number; to: number; label?: string } : undefined;
  const [hover, setHover] = useState<number>();
  const svgRef = useRef<SVGSVGElement>(null);
  const W = 320, H = 168, L = 32, R = 36, T = 10, B = 22;
  const geometry = useMemo(() => {
    const values: number[] = [];
    series.forEach(item => list<unknown>(item.values).forEach(value => { if (typeof value === 'number' && Number.isFinite(value)) values.push(value); }));
    if (band) values.push(band.from, band.to);
    const n = xs.length;
    if (!values.length || n < 2) return undefined;
    let lo = Math.min(...values), hi = Math.max(...values);
    if (lo === hi) { lo -= 1; hi += 1; }
    const step = nice((hi - lo) / 3); lo = Math.floor(lo / step) * step; hi = Math.ceil(hi / step) * step;
    const digits = Math.max(0, -Math.floor(Math.log10(step)));
    const x = (i: number) => L + i * (W - L - R) / (n - 1);
    const y = (v: number) => T + (hi - v) * (H - T - B) / (hi - lo);
    const grid: number[] = [];
    for (let g = lo; g <= hi + step / 2; g += step) grid.push(g);
    return { n, lo, hi, step, digits, x, y, grid, every: Math.ceil(n / 6) };
  }, [xs, series, band]);
  const cell = (value: unknown) => typeof value === 'number' ? `${value}${unit}` : '—';
  return <div className="pk-chart">
    {band?.label || series.length > 1 ? <div className="pk-legend">
      {series.length > 1 ? series.map((item, index) => <span key={index} data-series={index + 1}><i />{text(item.name)}</span>) : null}
      {band?.label ? <span><i data-band="" />{text(band.label)}</span> : null}
    </div> : null}
    <div className="pk-plot">
      <svg ref={svgRef} viewBox={`0 0 ${W} ${H}`} role="img" aria-label={t('toolCards.generativeUI.pageKit.chartLabel', { label: text(view.props.label) })}>
        {geometry ? <>
          {geometry.grid.map(g => <g key={g}><line className="grid" x1={L} x2={W - R} y1={geometry.y(g)} y2={geometry.y(g)} /><text className="axis" x={L - 6} y={geometry.y(g) + 3} textAnchor="end">{g.toFixed(geometry.digits)}</text></g>)}
          {band ? <rect className="band" x={L} width={W - L - R} y={geometry.y(band.to)} height={geometry.y(band.from) - geometry.y(band.to)} /> : null}
          {xs.map((label, index) => index % geometry.every === 0 || index === geometry.n - 1 ? <text key={index} className="axis" x={geometry.x(index)} y={H - 6} textAnchor="middle">{label}</text> : null)}
          {series.map((item, k) => {
            const values = list<unknown>(item.values);
            const runs: string[][] = [[]];
            let last = -1;
            values.forEach((value, index) => {
              if (typeof value !== 'number') { if (runs[runs.length - 1].length) runs.push([]); return; }
              runs[runs.length - 1].push(`${geometry.x(index)},${geometry.y(value)}`); last = index;
            });
            return <g key={k} data-series={k + 1}>
              {runs.filter(run => run.length > 1).map((run, index) => <polyline key={index} className="line" points={run.join(' ')} />)}
              {values.map((value, index) => typeof value === 'number' ? <circle key={index} className="dot" r={3.5} cx={geometry.x(index)} cy={geometry.y(value)} /> : null)}
              {last >= 0 && series.length > 1 ? <text className="label" x={geometry.x(last) + 8} y={geometry.y(values[last] as number) + 3}>{text(item.name)}</text> : null}
            </g>;
          })}
          {hover !== undefined ? <line className="cross" x1={geometry.x(hover)} x2={geometry.x(hover)} y1={T} y2={H - B} /> : null}
          <rect className="hit" x={L} y={0} width={W - L - R} height={H} fill="transparent"
            onPointerMove={event => {
              const rect = svgRef.current?.getBoundingClientRect();
              if (!rect) return;
              const px = (event.clientX - rect.left) / rect.width * W;
              setHover(Math.max(0, Math.min(geometry.n - 1, Math.round((px - L) / ((W - L - R) / (geometry.n - 1))))));
            }}
            onPointerLeave={() => setHover(undefined)} />
        </> : null}
      </svg>
      {geometry && hover !== undefined ? <div className="pk-tip" style={{ left: `${geometry.x(hover) / W * 100}%` }}>{xs[hover]}{series.map((item, index) => <span key={index}><br />{text(item.name)} {cell(list<unknown>(item.values)[hover])}</span>)}</div> : null}
    </div>
    <details><summary>{t('toolCards.generativeUI.pageKit.dataTable')}</summary>
      <div className="pk-table"><table>
        <thead><tr><th scope="col" />{series.map((item, index) => <th key={index} scope="col">{text(item.name)}</th>)}</tr></thead>
        <tbody>{xs.map((label, index) => <tr key={index}><th scope="row">{label}</th>{series.map((item, k) => <td key={k}>{cell(list<unknown>(item.values)[index])}</td>)}</tr>)}</tbody>
      </table></div>
    </details>
  </div>;
}

function EmptyState({ view }: GenUIComponentProps) {
  return <div className="pk-empty"><Icon name="photo" /><p>{text(view.props.text)}</p></div>;
}

/** Button as the page kit draws it: primary filled, others on the quiet fill. */
export function PageKitButton({ view, emit, disabled, isStreaming }: GenUIComponentProps) {
  const { t } = useI18n('flow-chat');
  const calendarStatus = useCalendarButtonStatus(view.props.action);
  const variant = text(view.props.variant ?? 'solid');
  const primary = variant === 'solid' && view.props.color !== 'danger';
  return <button type="button" className="pk-btn" data-primary={primary ? '' : undefined} data-small={view.props.size === 'sm' ? '' : undefined} data-tone={view.props.color === 'danger' ? 'danger' : undefined} disabled={disabled || Boolean(isStreaming) || Boolean(view.props.disabled) || Boolean(calendarStatus)} onClick={() => emit('click')}>
    {view.props.icon ? <Icon name={calendarStatus === 'added' ? 'checkmark' : text(view.props.icon)} /> : null}{calendarStatus === 'added' ? t('genuiCalendar.added') : calendarStatus === 'pending' ? t('genuiCalendar.adding') : text(view.props.label)}
  </button>;
}

const has = (selector: string) => (element: HTMLElement) => Boolean(element.querySelector(selector));
const count = (selector: string, prop: string) => (element: HTMLElement, view: { props: Record<string, unknown> }) => element.querySelectorAll(selector).length === list(view.props[prop]).length;

export const harmonyPageKitComponents: GenUIImplementations['components'] = {
  Page: { render: Page, inspect: has('main.pk') },
  Section: { render: Section, inspect: (element, view) => Boolean(element.querySelector('.pk-sec')) && (!view.props.title || element.querySelector('.pk-sec-head h2')?.textContent === text(view.props.title)) },
  Layout: { render: Layout, inspect: (element, view) => element.querySelector('.pk-layout')?.getAttribute('data-mode') === (text(view.props.mode) || 'stack') },
  TabPanel: { render: TabPanel, inspect: has('.pk-flow') },
  Tabs: { render: Tabs, inspect: (element, view) => element.querySelectorAll('.pk-tab').length === list(view.props.children).length },
  Cover: { render: Cover, inspect: (element, view) => element.querySelector('.pk-cover h1')?.textContent === text(view.props.title) },
  HeroStat: { render: HeroStat, inspect: (element, view) => element.querySelector('.pk-hero-stat .pk-stat-label')?.textContent === text(view.props.label) },
  StatGrid: { render: Stats, inspect: count('.pk-stat', 'items') },
  ItemList: {
    render: ItemList,
    inspect: count('.pk-row', 'rows'),
    exercise: (element, event) => {
      if (event !== 'select') throw new Error('ItemList event is unavailable');
      element.querySelector<HTMLElement>('.pk-row[role="button"]')?.click();
    },
  },
  Timeline: { render: Timeline, inspect: count('.pk-step', 'steps') },
  Checklist: {
    render: Checklist,
    inspect: count('.pk-check label', 'items'),
    exercise: (element, event) => {
      if (event !== 'change') throw new Error('Checklist event is unavailable');
      element.querySelector<HTMLInputElement>('.pk-check input')?.click();
    },
  },
  Note: { render: Note, inspect: (element, view) => (element.querySelector('.pk-note p')?.firstChild?.textContent ?? '') === text(view.props.text) },
  Prose: { render: Prose, inspect: count('.pk-card p', 'paragraphs') },
  ProCon: { render: ProCon, inspect: element => element.querySelectorAll('.pk-procon ul').length === 2 },
  CompareTable: { render: CompareTable, inspect: count('.pk-table tbody tr', 'rows') },
  Faq: { render: Faq, inspect: count('.pk-faq details', 'items') },
  Segmented: {
    render: Segmented,
    inspect: count('.pk-seg button', 'options'),
    exercise: (element, event, value) => {
      if (event !== 'change') throw new Error('Segmented event is unavailable');
      const buttons = Array.from(element.querySelectorAll<HTMLButtonElement>('.pk-seg button'));
      (buttons.find(button => button.dataset.value === String(value)) ?? buttons[1] ?? buttons[0])?.click();
    },
  },
  FormCard: { render: FormCard, inspect: has('form.pk-form') },
  Field: {
    render: Field,
    inspect: (element, view) => Boolean(element.querySelector('.pk-field')) && (element.querySelector('.pk-field > span')?.textContent ?? '').startsWith(text(view.props.label)),
    exercise: (element, event, value) => {
      if (event !== 'change') throw new Error('Field event is unavailable');
      const input = element.querySelector<HTMLInputElement | HTMLTextAreaElement>('.pk-field input, .pk-field textarea');
      if (!input) return;
      const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(input), 'value')?.set;
      setter?.call(input, String(value ?? '1'));
      input.dispatchEvent(new Event('input', { bubbles: true }));
    },
  },
  Progress: { render: Progress, inspect: has('.pk-progress') },
  TrendChart: { render: TrendChart, inspect: (element, view) => Boolean(element.querySelector('.pk-chart svg polyline')) || list(view.props.x).length < 2 },
  EmptyState: { render: EmptyState, inspect: (element, view) => element.querySelector('.pk-empty p')?.textContent === text(view.props.text) },
};
