import { Children, useEffect, useMemo, useState, type CSSProperties, type ReactNode } from 'react';
import type { GenUIComponentProps, GenUIImplementations } from '../genUILibrary';
import type { GenUIAsyncRuntime } from '../genUIAsyncCapabilities';
import { i18nService, useI18n } from '../local-runtime/i18n';
import { fluentEmoji3dUrl } from './vendor/fluentEmoji3d';

/**
 * Showcase blocks for the Harmony page kit: widget boards, rings and gauges,
 * spotlight and shelf cards, tickets, countdowns, rankings, bar lists, habit
 * heatmaps and statements. Like the page kit, the host owns every pixel: the
 * program only supplies content, and the markup (`.sc-*`) is styled by
 * harmonyShowcaseStyles.ts for every look. State and actions still go through
 * the OpenUI runtime.
 */

type Tone = 'success' | 'warning' | 'danger';
const text = (value: unknown): string => value == null ? '' : String(value);
const list = <T,>(value: unknown): T[] => Array.isArray(value) ? value as T[] : [];
const toneOf = (value: unknown): Tone | undefined => value === 'success' || value === 'warning' || value === 'danger' ? value : undefined;
const num = (value: unknown): number => {
  const parsed = typeof value === 'number' ? value : Number(String(value ?? '').replace(/[^\d.+-]/g, ''));
  return Number.isFinite(parsed) ? parsed : 0;
};
const numberText = (value: unknown): string => typeof value === 'number'
  ? i18nService.formatNumber(value, { minimumFractionDigits: 0, maximumFractionDigits: 2 })
  : text(value);
const clamp01 = (value: number): number => Math.max(0, Math.min(1, value));

function Pic({ emoji, className = '' }: { emoji: string; className?: string }) {
  const url = fluentEmoji3dUrl(emoji);
  const [failed, setFailed] = useState(false);
  if (!emoji) return null;
  return <span className={`sc-pic ${className}`} aria-hidden="true">
    {url && !failed ? <img src={url} alt="" decoding="async" draggable={false} referrerPolicy="no-referrer" onError={() => setFailed(true)} /> : <span>{emoji}</span>}
  </span>;
}

// ---------- Host photos ----------

const photoSearches = new WeakMap<object, Map<string, Promise<string[]>>>();
function photoUrls(value: unknown): string[] {
  const images = (value as { images?: unknown } | null)?.images;
  return Array.isArray(images) ? images.filter((src): src is string => typeof src === 'string' && src.length > 0) : [];
}

/** Photos the host finds for a subject query; [] while waiting or when search is unavailable. */
function useHostPhotos(query: string, runtime: GenUIAsyncRuntime | undefined, enabled: boolean): string[] {
  const [found, setFound] = useState<{ query: string; images: string[] }>({ query: '', images: [] });
  useEffect(() => {
    const subject = query.trim();
    if (!enabled || !subject || !runtime?.can('image.search')) return undefined;
    let cache = photoSearches.get(runtime);
    if (!cache) { cache = new Map(); photoSearches.set(runtime, cache); }
    let request = cache.get(subject);
    if (!request) {
      request = runtime.execute('image.search', { query: subject }, { kind: 'image-search' }).then(photoUrls).catch(() => []);
      request.then(images => { if (!images.length) cache?.delete(subject); });
      if (cache.size >= 200) cache.delete(cache.keys().next().value!);
      cache.set(subject, request);
    }
    let live = true;
    void request.then(images => { if (live) setFound({ query: subject, images }); });
    return () => { live = false; };
  }, [query, runtime, enabled]);
  return found.query === query.trim() ? found.images : [];
}

/** A real photo for the query, falling back to the emoji picture until one loads. */
function Photo({ query, emoji, runtime, enabled, className }: { query: string; emoji: string; runtime?: GenUIAsyncRuntime; enabled: boolean; className: string }) {
  const images = useHostPhotos(query, runtime, enabled);
  const [failed, setFailed] = useState<string[]>([]);
  const [loaded, setLoaded] = useState('');
  const src = images.find(image => !failed.includes(image));
  return <span className={className} data-photo={src && loaded === src ? 'ready' : undefined}>
    {src ? <img className="sc-photo" src={src} alt="" decoding="async" draggable={false} referrerPolicy="no-referrer"
      onLoad={() => setLoaded(src)} onError={() => setFailed(previous => [...previous, src])} /> : null}
    <Pic emoji={emoji} />
  </span>;
}

// ---------- Bento board and tiles ----------

function Bento({ slots }: GenUIComponentProps) {
  return <div className="sc-bento">{Children.toArray(slots.children as ReactNode)}</div>;
}

function Tile({ view }: GenUIComponentProps) {
  const size = ['s', 'w', 't', 'l'].includes(text(view.props.size)) ? text(view.props.size) : 's';
  const style = ['glass', 'vivid', 'tint'].includes(text(view.props.style)) ? text(view.props.style) : 'glass';
  const progress = view.props.progress == null ? undefined : clamp01(num(view.props.progress));
  const trend = ['up', 'down', 'flat'].includes(text(view.props.trend)) ? text(view.props.trend) : undefined;
  const value = view.props.value;
  return <div className="sc-tile" data-size={size} data-style={style} data-tone={toneOf(view.props.tone)}>
    <div className="sc-tile-head">
      <span className="sc-tile-label">{text(view.props.label)}</span>
      <Pic emoji={text(view.props.picture).trim()} className="sc-tile-pic" />
    </div>
    {value != null && value !== '' ? <div className="sc-tile-value">{numberText(value)}{view.props.unit ? <small>{text(view.props.unit)}</small> : null}</div> : null}
    {trend || view.props.delta ? <span className="sc-tile-delta" data-trend={trend}>{trend === 'up' ? '↑' : trend === 'down' ? '↓' : trend === 'flat' ? '→' : ''}{text(view.props.delta)}</span> : null}
    {view.props.sub ? <p className="sc-tile-sub">{text(view.props.sub)}</p> : null}
    {progress !== undefined ? <i className="sc-tile-bar" style={{ '--sc-v': `${Math.round(progress * 1000) / 10}%` } as CSSProperties} /> : null}
  </div>;
}

// ---------- Rings and gauges ----------

type RingItem = { label: string; value: number | string; max?: number; unit?: string };
function Ring({ view }: GenUIComponentProps) {
  const items = list<RingItem>(view.props.items).slice(0, 3);
  const gauge = view.props.variant === 'gauge';
  const gaugeId = useMemo(() => Math.random().toString(36).slice(2, 8), []);
  const ratios = items.map(item => clamp01(num(item.value) / (num(item.max) || 100)));
  const center = text(view.props.center) || (items[0] ? `${Math.round(ratios[0] * 100)}%` : '');
  if (gauge) {
    const ratio = ratios[0] ?? 0;
    const R = 80, C = Math.PI * R;
    const angle = -90 + ratio * 180;
    const gradient = `sc-gauge-${gaugeId}`;
    return <div className="sc-ring" data-variant="gauge">
      <div className="sc-ring-label">{text(view.props.label)}</div>
      <div className="sc-gauge">
        <svg viewBox="0 0 200 116" role="img" aria-label={`${text(view.props.label)} ${center}`}>
          <defs><linearGradient id={gradient} x1="0" x2="1"><stop offset="0" className="sc-stop-a" /><stop offset="1" className="sc-stop-b" /></linearGradient></defs>
          <path className="sc-track" d="M20 100 A80 80 0 0 1 180 100" pathLength={C} />
          <path className="sc-arc" d="M20 100 A80 80 0 0 1 180 100" stroke={`url(#${gradient})`} style={{ strokeDasharray: `${ratio * C} ${C}` }} />
          {Array.from({ length: 11 }, (_, i) => {
            const a = Math.PI * (1 - i / 10);
            return <line key={i} className="sc-tick" x1={100 + Math.cos(a) * 62} y1={100 - Math.sin(a) * 62} x2={100 + Math.cos(a) * (i % 5 ? 56 : 52)} y2={100 - Math.sin(a) * (i % 5 ? 56 : 52)} />;
          })}
          <g className="sc-needle" style={{ transform: `rotate(${angle}deg)` }}><path d="M97 100 L100 34 L103 100 Z" /><circle cx="100" cy="100" r="7" /></g>
        </svg>
        <div className="sc-gauge-read"><b>{center}</b>{items[0] ? <span>{text(items[0].label)}</span> : null}</div>
      </div>
      {view.props.sub ? <p className="sc-ring-sub">{text(view.props.sub)}</p> : null}
    </div>;
  }
  const size = 168, stroke = items.length > 2 ? 13 : 16, gap = 3;
  return <div className="sc-ring" data-variant="rings">
    <div className="sc-ring-label">{text(view.props.label)}</div>
    <div className="sc-ring-body">
      <div className="sc-rings">
        <svg viewBox={`0 0 ${size} ${size}`} role="img" aria-label={text(view.props.label)}>
          {items.map((item, index) => {
            const r = size / 2 - stroke / 2 - index * (stroke + gap);
            const c = 2 * Math.PI * r;
            return <g key={index} data-ring={index}>
              <circle className="sc-track" cx={size / 2} cy={size / 2} r={r} strokeWidth={stroke} />
              <circle className="sc-arc" cx={size / 2} cy={size / 2} r={r} strokeWidth={stroke} style={{ strokeDasharray: `${ratios[index] * c} ${c}` }} />
            </g>;
          })}
        </svg>
        <div className="sc-rings-center"><b>{center}</b>{view.props.sub ? <span>{text(view.props.sub)}</span> : null}</div>
      </div>
      <ul className="sc-ring-legend">{items.map((item, index) => <li key={index} data-ring={index}>
        <i /><span>{text(item.label)}</span><b>{numberText(item.value)}{item.max ? <small>/{numberText(item.max)}</small> : null}{item.unit ? <small>{text(item.unit)}</small> : null}</b>
      </li>)}</ul>
    </div>
  </div>;
}

// ---------- Spotlight and shelf ----------

function Spotlight({ view, asyncRuntime, isStreaming }: GenUIComponentProps) {
  const tags = list<string>(view.props.tags);
  const photo = text(view.props.photo).trim();
  return <div className="sc-spot" data-has-photo={photo ? '' : undefined}>
    <div className="sc-spot-glow" aria-hidden="true" />
    {photo ? <Photo query={photo} emoji={text(view.props.picture).trim()} runtime={asyncRuntime} enabled={!isStreaming} className="sc-spot-photo" /> : <Pic emoji={text(view.props.picture).trim()} className="sc-spot-pic" />}
    <div className="sc-spot-copy">
      {view.props.eyebrow ? <p className="sc-spot-eyebrow">{text(view.props.eyebrow)}</p> : null}
      <h3>{text(view.props.title)}</h3>
      {view.props.sub ? <p className="sc-spot-sub">{text(view.props.sub)}</p> : null}
      {view.props.value != null ? <p className="sc-spot-value">{numberText(view.props.value)}{view.props.unit ? <small>{text(view.props.unit)}</small> : null}</p> : null}
      {tags.length ? <div className="sc-spot-tags">{tags.map((tag, index) => <span key={index}>{text(tag)}</span>)}</div> : null}
    </div>
  </div>;
}

type ShelfItem = { id?: string; title: string; sub?: string; picture?: string; photo?: string; value?: string | number; tag?: string };
function Shelf({ view, emit, disabled, isStreaming, asyncRuntime }: GenUIComponentProps) {
  const items = list<ShelfItem>(view.props.items);
  const interactive = Boolean(view.props.action) && !disabled && !isStreaming;
  const size = ['s', 'm', 'l'].includes(text(view.props.size)) ? text(view.props.size) : 'm';
  return <div className="sc-shelf" data-size={size}>
    {view.props.label ? <div className="sc-shelf-label">{text(view.props.label)}</div> : null}
    <div className="sc-shelf-track">{items.map((item, index) => {
      const body = <>
        <div className="sc-shelf-stage">{item.photo ? <Photo query={text(item.photo)} emoji={text(item.picture).trim()} runtime={asyncRuntime} enabled={!isStreaming} className="sc-shelf-photo" /> : <Pic emoji={text(item.picture).trim()} />}{item.tag ? <span className="sc-shelf-tag">{text(item.tag)}</span> : null}</div>
        <div className="sc-shelf-copy">
          <b>{text(item.title)}</b>
          {item.sub ? <span>{text(item.sub)}</span> : null}
          {item.value != null ? <em>{numberText(item.value)}</em> : null}
        </div>
      </>;
      const key = item.id ?? String(index);
      return interactive
        ? <button key={key} type="button" className="sc-shelf-card" data-i={index % 4} data-sc-item={key} onClick={() => emit('select', item.id ?? item.title)}>{body}</button>
        : <div key={key} className="sc-shelf-card" data-i={index % 4} data-sc-item={key}>{body}</div>;
    })}</div>
  </div>;
}

// ---------- Ticket ----------

type Field = { label: string; value: string | number };
function Ticket({ view }: GenUIComponentProps) {
  const fields = list<Field>(view.props.fields).slice(0, 6);
  const kind = ['flight', 'train', 'bus', 'event', 'movie'].includes(text(view.props.kind)) ? text(view.props.kind) : 'flight';
  const glyph = kind === 'flight' ? '✈' : kind === 'train' ? '🚄' : kind === 'bus' ? '🚌' : kind === 'movie' ? '🎬' : '★';
  const code = text(view.props.code) || text(view.props.title);
  // A deterministic stripe pattern from the code: it only decorates.
  const bars = useMemo(() => Array.from(code.padEnd(24, '#')).slice(0, 36).map((c, i) => ((c.codePointAt(0) ?? 7) * (i + 3)) % 4 + 1), [code]);
  return <div className="sc-ticket" data-kind={kind}>
    <div className="sc-ticket-main">
      <div className="sc-ticket-head"><span>{text(view.props.title)}</span><Pic emoji={text(view.props.picture).trim()} className="sc-ticket-pic" /></div>
      <div className="sc-ticket-route">
        <div><b>{text(view.props.from)}</b>{view.props.fromLabel ? <span>{text(view.props.fromLabel)}</span> : null}</div>
        <div className="sc-ticket-path" aria-hidden="true"><i /><span>{glyph}</span><i /></div>
        <div><b>{text(view.props.to)}</b>{view.props.toLabel ? <span>{text(view.props.toLabel)}</span> : null}</div>
      </div>
      {fields.length ? <dl className="sc-ticket-fields">{fields.map((field, index) => <div key={index}><dt>{text(field.label)}</dt><dd>{numberText(field.value)}</dd></div>)}</dl> : null}
    </div>
    <div className="sc-ticket-stub">
      <div className="sc-ticket-bars" aria-hidden="true">{bars.map((w, i) => <i key={i} style={{ flexGrow: w }} />)}</div>
      {view.props.code ? <span>{text(view.props.code)}</span> : null}
    </div>
  </div>;
}

// ---------- Countdown ----------

function parseTarget(value: unknown): number | undefined {
  const raw = text(value).trim();
  if (!raw) return undefined;
  const time = /^\d{4}-\d{2}-\d{2}$/.test(raw) ? new Date(raw + 'T00:00:00').getTime() : new Date(raw).getTime();
  return Number.isFinite(time) ? time : undefined;
}

function Countdown({ view }: GenUIComponentProps) {
  const { t } = useI18n('flow-chat');
  const target = parseTarget(view.props.target);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (target === undefined) return undefined;
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [target]);
  const left = target === undefined ? 0 : Math.max(0, target - now);
  const done = target !== undefined && left === 0;
  const parts = [
    [Math.floor(left / 86400000), t('toolCards.generativeUI.showcase.days')],
    [Math.floor(left / 3600000) % 24, t('toolCards.generativeUI.showcase.hours')],
    [Math.floor(left / 60000) % 60, t('toolCards.generativeUI.showcase.minutes')],
    [Math.floor(left / 1000) % 60, t('toolCards.generativeUI.showcase.seconds')],
  ] as const;
  return <div className="sc-count" data-done={done ? '' : undefined}>
    <div className="sc-count-label">{text(view.props.label)}</div>
    {done
      ? <p className="sc-count-done">{text(view.props.done) || t('toolCards.generativeUI.showcase.arrived')}</p>
      : <div className="sc-count-cells" role="timer" aria-live="off">{parts.map(([value, unit], index) => <div key={index} className="sc-count-cell">
        <b>{index === 0 ? String(value) : String(value).padStart(2, '0')}</b><span>{unit}</span>
      </div>)}</div>}
    {view.props.sub ? <p className="sc-count-sub">{text(view.props.sub)}</p> : null}
  </div>;
}

// ---------- Ranking and bar list ----------

type Ranked = { name: string; value?: string | number; sub?: string; picture?: string };
function Ranking({ view }: GenUIComponentProps) {
  const items = list<Ranked>(view.props.items);
  const unit = text(view.props.unit);
  const podium = items.slice(0, 3);
  const order = podium.length === 3 ? [1, 0, 2] : podium.map((_, index) => index);
  return <div className="sc-rank">
    {view.props.label ? <div className="sc-rank-label">{text(view.props.label)}</div> : null}
    <div className="sc-podium" data-count={podium.length}>{order.map(index => {
      const item = podium[index];
      return <div key={index} className="sc-podium-place" data-place={index + 1}>
        <div className="sc-podium-who">
          {item.picture ? <Pic emoji={text(item.picture).trim()} /> : <span className="sc-podium-initial">{Array.from(text(item.name))[0] ?? ''}</span>}
          <b>{text(item.name)}</b>
          {item.value != null ? <span>{numberText(item.value)}{unit}</span> : null}
        </div>
        <div className="sc-podium-step"><span>{index + 1}</span></div>
      </div>;
    })}</div>
    {items.length > 3 ? <ol className="sc-rank-rest" start={4}>{items.slice(3).map((item, index) => <li key={index}>
      <span className="sc-rank-no">{index + 4}</span>
      {item.picture ? <Pic emoji={text(item.picture).trim()} /> : null}
      <span className="sc-rank-name"><b>{text(item.name)}</b>{item.sub ? <small>{text(item.sub)}</small> : null}</span>
      {item.value != null ? <span className="sc-rank-value">{numberText(item.value)}{unit}</span> : null}
    </li>)}</ol> : null}
  </div>;
}

type Bar = { label: string; value: number; picture?: string; tone?: Tone; note?: string };
function BarList({ view }: GenUIComponentProps) {
  const items = list<Bar>(view.props.items);
  const unit = text(view.props.unit);
  const max = num(view.props.max) || Math.max(1, ...items.map(item => num(item.value)));
  const highlight = text(view.props.highlight);
  return <div className="sc-bars">
    {view.props.label ? <div className="sc-bars-label">{text(view.props.label)}</div> : null}
    {items.map((item, index) => <div key={index} className="sc-bar" data-tone={toneOf(item.tone)} data-highlight={highlight && highlight === item.label ? '' : undefined}>
      <div className="sc-bar-head">
        {item.picture ? <Pic emoji={text(item.picture).trim()} /> : null}
        <span>{text(item.label)}{item.note ? <small>{text(item.note)}</small> : null}</span>
        <b>{numberText(item.value)}{unit}</b>
      </div>
      <i style={{ '--sc-v': `${Math.round(clamp01(num(item.value) / max) * 1000) / 10}%`, '--sc-d': `${index * 70}ms` } as CSSProperties} />
    </div>)}
  </div>;
}

// ---------- Heatmap ----------

function Heatmap({ view }: GenUIComponentProps) {
  const { t } = useI18n('flow-chat');
  const values = list<unknown>(view.props.values).map(num);
  const unit = text(view.props.unit);
  const max = num(view.props.max) || Math.max(1, ...values);
  const total = values.reduce((sum, value) => sum + value, 0);
  let streak = 0;
  for (let i = values.length - 1; i >= 0 && values[i] > 0; i -= 1) streak += 1;
  const weeks = Math.max(1, Math.ceil(values.length / 7));
  return <div className="sc-heat">
    <div className="sc-heat-head">
      <span className="sc-heat-label">{text(view.props.label)}</span>
      <span className="sc-heat-meta"><b>{numberText(total)}</b>{unit} · {t('toolCards.generativeUI.showcase.streak', { count: streak })}</span>
    </div>
    <div className="sc-heat-grid" style={{ '--sc-weeks': weeks } as CSSProperties} role="img" aria-label={text(view.props.label)}>
      {Array.from({ length: weeks * 7 }, (_, index) => {
        const value = values[index];
        const level = value === undefined ? -1 : value <= 0 ? 0 : Math.min(4, Math.ceil(clamp01(value / max) * 4));
        return <i key={index} data-level={level} />;
      })}
    </div>
    <div className="sc-heat-legend" aria-hidden="true"><span>{t('toolCards.generativeUI.showcase.less')}</span>{[0, 1, 2, 3, 4].map(level => <i key={level} data-level={level} />)}<span>{t('toolCards.generativeUI.showcase.more')}</span></div>
  </div>;
}

// ---------- Month calendar ----------

type Mark = { date: string; label?: string; tone?: Tone | 'accent' };
const DAY = /^(\d{4})-(\d{2})-(\d{2})$/;
const pad2 = (value: number) => String(value).padStart(2, '0');
const isoDay = (date: Date) => `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
function parseDay(value: unknown): Date | undefined {
  const match = DAY.exec(text(value).trim());
  if (!match) return undefined;
  const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  return Number.isNaN(date.getTime()) ? undefined : date;
}
function parseMonth(value: unknown): Date | undefined {
  const match = /^(\d{4})-(\d{2})$/.exec(text(value).trim());
  return match ? new Date(Number(match[1]), Number(match[2]) - 1, 1) : parseDay(value);
}

function MonthCalendar({ view, emit, disabled, isStreaming }: GenUIComponentProps) {
  const { t } = useI18n('flow-chat');
  const today = isoDay(new Date());
  const bound = parseDay(view.props.value) ? text(view.props.value).trim() : '';
  const [local, setLocal] = useState('');
  const selected = bound || local || today;
  const initial = parseMonth(view.props.month) ?? parseDay(selected) ?? new Date();
  const [shown, setShown] = useState(() => new Date(initial.getFullYear(), initial.getMonth(), 1));
  const mondayFirst = view.props.weekStart !== 'sunday';
  const marks = list<Mark>(view.props.marks).filter(mark => parseDay(mark.date));
  const byDay = new Map<string, Mark[]>();
  marks.forEach(mark => byDay.set(text(mark.date).trim(), [...(byDay.get(text(mark.date).trim()) ?? []), mark]));
  const year = shown.getFullYear();
  const month = shown.getMonth();
  const offset = (new Date(year, month, 1).getDay() + (mondayFirst ? 6 : 0)) % 7;
  const days = new Date(year, month + 1, 0).getDate();
  const cells: Array<string | null> = [...Array.from({ length: offset }, () => null), ...Array.from({ length: days }, (_, i) => isoDay(new Date(year, month, i + 1)))];
  while (cells.length % 7) cells.push(null);
  const weekdays = Array.from({ length: 7 }, (_, i) => i18nService.formatDate(new Date(2024, 0, (mondayFirst ? 1 : 7) + i), { weekday: 'narrow' }));
  const off = disabled || Boolean(isStreaming);
  const pick = (day: string) => { setLocal(day); emit('change', day); };
  const move = (delta: number) => setShown(current => new Date(current.getFullYear(), current.getMonth() + delta, 1));
  const goToday = () => { const now = new Date(); setShown(new Date(now.getFullYear(), now.getMonth(), 1)); pick(today); };
  const agenda = byDay.get(selected) ?? [];
  const selectedDate = parseDay(selected);
  return <div className="sc-cal" data-sc-calendar="">
    <div className="sc-cal-head">
      <b>{i18nService.formatDate(shown, { year: 'numeric', month: 'long' })}</b>
      <div className="sc-cal-nav">
        <button type="button" aria-label={t('toolCards.generativeUI.showcase.previousMonth')} onClick={() => move(-1)}>‹</button>
        <button type="button" className="sc-cal-today" onClick={goToday} disabled={off}>{t('toolCards.generativeUI.showcase.today')}</button>
        <button type="button" aria-label={t('toolCards.generativeUI.showcase.nextMonth')} onClick={() => move(1)}>›</button>
      </div>
    </div>
    <div className="sc-cal-grid" role="grid" aria-label={text(view.props.label) || undefined}>
      {weekdays.map((weekday, index) => <span key={`w${index}`} className="sc-cal-weekday" data-weekend={(mondayFirst ? index >= 5 : index === 0 || index === 6) ? '' : undefined}>{weekday}</span>)}
      {cells.map((day, index) => {
        if (!day) return <span key={`e${index}`} className="sc-cal-empty" />;
        const dayMarks = byDay.get(day) ?? [];
        const column = index % 7;
        return <button key={day} type="button" role="gridcell" className="sc-cal-day" data-day={day}
          data-today={day === today ? '' : undefined} aria-selected={day === selected}
          data-weekend={(mondayFirst ? column >= 5 : column === 0 || column === 6) ? '' : undefined}
          disabled={off} onClick={() => pick(day)}>
          <span>{Number(day.slice(8))}</span>
          {dayMarks.length ? <i className="sc-cal-dots">{dayMarks.slice(0, 3).map((mark, k) => <em key={k} data-tone={mark.tone && mark.tone !== 'accent' ? mark.tone : undefined} />)}</i> : null}
        </button>;
      })}
    </div>
    <div className="sc-cal-agenda">
      <div className="sc-cal-agenda-head">{selectedDate ? i18nService.formatDate(selectedDate, { month: 'long', day: 'numeric', weekday: 'short' }) : selected}</div>
      {agenda.length
        ? agenda.map((mark, index) => <div key={index} className="sc-cal-item" data-tone={mark.tone && mark.tone !== 'accent' ? mark.tone : undefined}><i />{text(mark.label) || selected}</div>)
        : <div className="sc-cal-free">{t('toolCards.generativeUI.showcase.noPlans')}</div>}
    </div>
  </div>;
}

// ---------- Statement ----------

function Statement({ view }: GenUIComponentProps) {
  return <figure className="sc-statement">
    <Pic emoji={text(view.props.picture).trim()} className="sc-statement-pic" />
    <blockquote>{text(view.props.text)}</blockquote>
    {view.props.cite ? <figcaption>{text(view.props.cite)}</figcaption> : null}
  </figure>;
}

const has = (selector: string) => (element: HTMLElement) => Boolean(element.querySelector(selector));
const count = (selector: string, prop: string, limit?: number) => (element: HTMLElement, view: { props: Record<string, unknown> }) => {
  const expected = list(view.props[prop]).length;
  return element.querySelectorAll(selector).length === (limit ? Math.min(limit, expected) : expected);
};

export const harmonyShowcaseComponents: GenUIImplementations['components'] = {
  Bento: { render: Bento, inspect: has('.sc-bento') },
  Tile: { render: Tile, inspect: (element, view) => element.querySelector('.sc-tile-label')?.textContent === text(view.props.label) },
  Ring: { render: Ring, inspect: (element, view) => view.props.variant === 'gauge' ? has('.sc-gauge svg')(element) : count('.sc-ring-legend li', 'items', 3)(element, view) },
  Spotlight: { render: Spotlight, inspect: (element, view) => element.querySelector('.sc-spot h3')?.textContent === text(view.props.title) },
  Shelf: {
    render: Shelf,
    inspect: count('.sc-shelf-card', 'items'),
    exercise: (element, event) => {
      if (event !== 'select') throw new Error('Shelf event is unavailable');
      element.querySelector<HTMLElement>('button.sc-shelf-card')?.click();
    },
  },
  Ticket: { render: Ticket, inspect: has('.sc-ticket-route') },
  Countdown: { render: Countdown, inspect: has('.sc-count') },
  Ranking: { render: Ranking, inspect: (element, view) => element.querySelectorAll('.sc-podium-place, .sc-rank-rest li').length === list(view.props.items).length },
  BarList: { render: BarList, inspect: count('.sc-bar', 'items') },
  Heatmap: { render: Heatmap, inspect: has('.sc-heat-grid') },
  MonthCalendar: {
    render: MonthCalendar,
    inspect: element => element.querySelectorAll('.sc-cal-weekday').length === 7 && Boolean(element.querySelector('.sc-cal-day')),
    exercise: (element, event, value) => {
      if (event !== 'change') throw new Error('MonthCalendar event is unavailable');
      const days = Array.from(element.querySelectorAll<HTMLButtonElement>('.sc-cal-day'));
      (days.find(day => day.dataset.day === String(value)) ?? days[0])?.click();
    },
  },
  Statement: { render: Statement, inspect: (element, view) => element.querySelector('.sc-statement blockquote')?.textContent === text(view.props.text) },
};
