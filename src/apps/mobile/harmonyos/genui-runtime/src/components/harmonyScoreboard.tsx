import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useI18n } from '../local-runtime/i18n';
import type { GenUIComponentProps, GenUIImplementations } from '../genUILibrary';
import { useGenUIDeviceCapabilities, type GenUIGesture, type GenUIGestureStatus } from '../genUIDeviceCapabilities';

/**
 * Managed two-participant scoreboard: a port of harmony-genui's `scoreboard`
 * block (apps/agent/src/scoreboard_block.py, scoreboard.js; vendored
 * scoreboard.css). The model declares participants and rules; the host owns
 * markup, scoring rules, undo, side swap, the settings dialog and the screen
 * fit. Configuration is data, never code.
 *
 * Differences from the reference are host facts only: the match state is an
 * OpenUI binding so the owner persists it across reopen and resize, and the
 * declared `camera.open-palm` input is served by the device capability port
 * (raise_left_hand / raise_right_hand) instead of the web camera plugin.
 */

type Participant = 0 | 1;
type Phase = 'playing' | 'game' | 'match';
/** `targetScore: null` is open scoring: points accumulate with no game or match end. */
interface Rules { targetScore: number | null; winBy: number; scoreCap: number | null; bestOf: number }
interface MatchState { names: [string, string]; scores: [number, number]; games: [number, number]; order: [Participant, Participant]; rules: Rules; phase: Phase }
type GestureBinding = { action: 'increment'; participantId: 'A' | 'B'; points?: number };
interface InputBinding { plugin: 'camera.open-palm'; version: 1; activation: 'manual' | 'on-open'; haptic?: 'none' | 'light' | 'medium' | 'heavy'; bindings: { left: GestureBinding; right: GestureBinding } }

const ID = ['A', 'B'] as const;
const int = (value: unknown, fallback: number): number => typeof value === 'number' && Number.isInteger(value) && value >= 1 && value <= 999 ? value : fallback;

/** normalize_scoreboard_config: invalid declarations fail loudly, like the reference compiler. */
export function normalizeScoreboard(props: Record<string, unknown>): { teams: [string, string]; rules: Rules; setupRequired: boolean; increments: number[] } {
  const teams = props.teams;
  if (!Array.isArray(teams) || teams.length !== 2 || teams.some(name => typeof name !== 'string' || !name.trim() || name.length > 60)) {
    throw new Error('Scoreboard teams must contain exactly two nonempty names (up to 60 characters)');
  }
  // Rally rules are the reference block's default; open scoring is explicit.
  const open = props.scoring === 'open';
  const rules: Rules = {
    targetScore: open ? null : int(props.targetScore, 21),
    winBy: int(props.winBy, 2),
    scoreCap: props.scoreCap == null ? null : int(props.scoreCap, 0) || null,
    bestOf: int(props.bestOf, 3),
  };
  if (rules.targetScore !== null && ((rules.scoreCap !== null && rules.scoreCap < rules.targetScore) || rules.bestOf % 2 !== 1 || rules.bestOf > 9)) {
    throw new Error('Scoreboard scoreCap must be at least targetScore and bestOf must be odd and at most 9');
  }
  const increments = props.increments === undefined || props.increments === null ? [1] : props.increments;
  if (!Array.isArray(increments) || increments.length < 1 || increments.length > 3 || new Set(increments).size !== increments.length
    || increments.some(step => typeof step !== 'number' || !Number.isInteger(step) || step < 1 || step > 100)) {
    throw new Error('Scoreboard increments must be 1-3 distinct positive integers up to 100');
  }
  return { teams: [teams[0] as string, teams[1] as string], rules, setupRequired: props.setupRequired === true, increments: increments as number[] };
}

/** normalize_input_binding: only the supported plugin, version and distinct A/B increments. */
export function normalizeInputBinding(value: unknown): InputBinding | null {
  if (value == null) return null;
  const record = value as Record<string, unknown>;
  const bindings = record.bindings as Record<string, Record<string, unknown>> | undefined;
  const side = (key: 'left' | 'right') => bindings?.[key];
  const valid = record.plugin === 'camera.open-palm' && record.version === 1 && (record.activation === 'manual' || record.activation === 'on-open')
    && (['left', 'right'] as const).every(key => side(key)?.action === 'increment' && (side(key)?.participantId === 'A' || side(key)?.participantId === 'B'))
    && side('left')?.participantId !== side('right')?.participantId
    && (['left', 'right'] as const).every(key => side(key)?.points === undefined || (typeof side(key)?.points === 'number' && Number.isInteger(side(key)?.points) && (side(key)?.points as number) >= 1 && (side(key)?.points as number) <= 100))
    && (record.haptic === undefined || ['none', 'light', 'medium', 'heavy'].includes(String(record.haptic)));
  if (!valid) throw new Error('Scoreboard input must be camera.open-palm v1 with distinct left/right increments for A and B');
  return record as unknown as InputBinding;
}

function freshState(teams: [string, string], rules: Rules): MatchState {
  return { names: [...teams] as [string, string], scores: [0, 0], games: [0, 0], order: [0, 1], rules: { ...rules }, phase: 'playing' };
}

/** Restore a bound state written by this renderer; anything else starts fresh. */
function restore(value: unknown, teams: [string, string], rules: Rules): MatchState {
  const v = value as Partial<MatchState> | null | undefined;
  const pair = (x: unknown) => Array.isArray(x) && x.length === 2 && x.every(n => typeof n === 'number' && Number.isFinite(n) && n >= 0);
  if (!v || typeof v !== 'object' || !pair(v.scores) || !pair(v.games) || !Array.isArray(v.order) || !Array.isArray(v.names) || !v.rules || !['playing', 'game', 'match'].includes(String(v.phase))) {
    return freshState(teams, rules);
  }
  return v as MatchState;
}

type Translate = (key: string, values?: Record<string, unknown>) => string;
function ruleSummary(rules: Rules, t: Translate): string {
  const k = (key: string, values?: Record<string, unknown>) => t(`toolCards.generativeUI.pageKit.scoreboard.${key}`, values);
  if (rules.targetScore === null) return k('openScoring');
  const cap = rules.scoreCap === null ? k('noCap') : k('cap', { cap: rules.scoreCap });
  const games = rules.bestOf === 1 ? k('oneGame') : k('bestOfGames', { count: rules.bestOf });
  return k('ruleSummary', { target: rules.targetScore, winBy: rules.winBy, cap, games });
}

function Scoreboard({ view, emit, disabled, isStreaming }: GenUIComponentProps) {
  const { t } = useI18n('flow-chat');
  const k = (key: string, values?: Record<string, unknown>) => t(`toolCards.generativeUI.pageKit.scoreboard.${key}`, values);
  const configKey = JSON.stringify([view.props.teams, view.props.targetScore, view.props.winBy, view.props.scoreCap, view.props.bestOf, view.props.setupRequired, view.props.scoring, view.props.increments]);
  const config = useMemo(() => normalizeScoreboard(view.props), [configKey]); // eslint-disable-line react-hooks/exhaustive-deps
  const inputKey = JSON.stringify(view.props.input ?? null);
  const input = useMemo(() => normalizeInputBinding(view.props.input), [inputKey]); // eslint-disable-line react-hooks/exhaustive-deps
  const bound = view.props.value;
  const [state, setState] = useState<MatchState>(() => restore(bound, config.teams, config.rules));
  // The owner's state wins when it changes from outside (reopen, conflict replay).
  // Only a change of the bound value itself, other than our own write, is an
  // outside update; a render that still carries the previous value is not.
  const lastWritten = useRef<string>('');
  const lastBound = useRef<string>(JSON.stringify(bound ?? null));
  useEffect(() => {
    const json = JSON.stringify(bound ?? null);
    if (json === lastBound.current) return;
    lastBound.current = json;
    if (bound !== undefined && json !== lastWritten.current) setState(restore(bound, config.teams, config.rules));
  }, [bound, config]);
  const history = useRef<MatchState[]>([]);
  const [setupPending, setSetupPending] = useState(config.setupRequired);
  const [flash, setFlash] = useState<number | null>(null);
  const root = useRef<HTMLElement>(null);
  const dialog = useRef<HTMLDialogElement>(null);
  const off = disabled || Boolean(isStreaming);

  const commit = useCallback((next: MatchState, record = true, current?: MatchState) => {
    if (record && current) { history.current.push(JSON.parse(JSON.stringify(current)) as MatchState); if (history.current.length > 100) history.current.shift(); }
    setState(next);
    lastWritten.current = JSON.stringify(next);
    emit('change', next);
  }, [emit]);

  // fit(): the board takes the viewport space below its top edge.
  useLayoutEffect(() => {
    const element = root.current;
    if (!element) return undefined;
    let frame = 0;
    const fit = () => {
      frame = 0;
      const available = Math.max(180, Math.floor(window.innerHeight - Math.max(0, element.getBoundingClientRect().top) - 12));
      element.style.setProperty('--sb-available-height', `${available}px`);
      element.toggleAttribute('data-sb-tight', available < 280);
    };
    const schedule = () => { if (!frame) frame = requestAnimationFrame(fit); };
    const observer = typeof ResizeObserver === 'undefined' ? undefined : new ResizeObserver(schedule);
    observer?.observe(element.parentElement ?? element);
    window.addEventListener('resize', schedule);
    void document.fonts?.ready.then(schedule);
    schedule();
    return () => { cancelAnimationFrame(frame); observer?.disconnect(); window.removeEventListener('resize', schedule); };
  }, []);

  const add = useCallback((id: Participant, slot: number, points = 1) => {
    if (off || setupPending || state.phase !== 'playing' || dialog.current?.open) return;
    const next: MatchState = JSON.parse(JSON.stringify(state)) as MatchState;
    next.scores[id] += points;
    const score = next.scores[id];
    const opponent = next.scores[1 - id];
    const rules = next.rules;
    if (rules.targetScore !== null && ((rules.scoreCap !== null && score >= rules.scoreCap) || (score >= rules.targetScore && score - opponent >= rules.winBy))) {
      next.games[id] += 1;
      next.phase = next.games[id] > Math.floor(rules.bestOf / 2) ? 'match' : 'game';
    }
    commit(next, true, state);
    setFlash(slot);
    window.setTimeout(() => setFlash(current => current === slot ? null : current), 450);
  }, [commit, off, setupPending, state]);

  // Declared camera input: the host recognizes raised hands; identities follow
  // participants, not display slots, so a side swap keeps the binding.
  const port = useGenUIDeviceCapabilities();
  const [inputOn, setInputOn] = useState(input?.activation === 'on-open');
  const [inputStatus, setInputStatus] = useState<GenUIGestureStatus>('starting');
  const addRef = useRef(add);
  addRef.current = add;
  const orderRef = useRef(state.order);
  orderRef.current = state.order;
  useEffect(() => {
    if (!input || !port || !inputOn || off) return undefined;
    const subscribe = (gesture: GenUIGesture, side: 'left' | 'right') => {
      const binding = input.bindings[side];
      const participant: Participant = binding.participantId === 'A' ? 0 : 1;
      const points = binding.points ?? config.increments[0];
      const haptic = input.haptic ?? 'light';
      return port.subscribeGesture({
        gesture,
        label: `${side} → ${binding.participantId} +${points}`,
        onGesture: () => { if (haptic !== 'none') port.haptic(haptic); addRef.current(participant, orderRef.current.indexOf(participant), points); },
        onStatus: setInputStatus,
      });
    };
    const stops = [subscribe('raise_left_hand', 'left'), subscribe('raise_right_hand', 'right')];
    return () => stops.forEach(stop => stop());
  }, [input, port, inputOn, off, config]);

  const undo = () => { const previous = history.current.pop(); if (previous && !dialog.current?.open) commit(previous, false); };
  const nextGame = () => { if (state.phase !== 'game' || dialog.current?.open) return; commit({ ...state, scores: [0, 0], phase: 'playing' }, true, state); };

  // Settings dialog (data-sb-panel).
  const [draftNames, setDraftNames] = useState<[string, string]>(state.names);
  const [draftRules, setDraftRules] = useState<Record<keyof Rules, string>>({ targetScore: '', winBy: '', scoreCap: '', bestOf: '' });
  const [settingsError, setSettingsError] = useState('');
  const [confirm, setConfirm] = useState<{ text: string; run: () => void } | null>(null);
  const openSettings = useCallback(() => {
    setDraftNames([...state.names] as [string, string]);
    setDraftRules({ targetScore: state.rules.targetScore === null ? '' : String(state.rules.targetScore), winBy: String(state.rules.winBy), scoreCap: state.rules.scoreCap === null ? '' : String(state.rules.scoreCap), bestOf: String(state.rules.bestOf) });
    setSettingsError('');
    setConfirm(null);
    // The reference focuses the first name field; on a phone that raises the
    // keyboard over half the board. The dialog itself takes focus instead, so
    // keyboard and screen readers start inside it without a keyboard popping up.
    if (dialog.current && !dialog.current.open) { dialog.current.showModal(); dialog.current.focus(); }
  }, [state]);
  const closeSettings = () => { if (!setupPending) dialog.current?.close(); };
  useEffect(() => { if (config.setupRequired) openSettings(); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const save = () => {
    const names = draftNames.map(name => name.trim()) as [string, string];
    // An empty target is open scoring; the other rules then keep their values.
    const open = draftRules.targetScore.trim() === '';
    const rules: Rules = open ? { ...state.rules, targetScore: null } : {
      targetScore: Number(draftRules.targetScore), winBy: Number(draftRules.winBy),
      scoreCap: draftRules.scoreCap.trim() === '' ? null : Number(draftRules.scoreCap), bestOf: Number(draftRules.bestOf),
    };
    const bad = names.some(name => !name || name.length > 60) || (!open && (
      (Object.entries(rules) as Array<[keyof Rules, number | null]>).some(([key, v]) => !(key === 'scoreCap' && v === null) && (!Number.isInteger(v) || (v as number) < 1 || (v as number) > 999))
      || (rules.scoreCap !== null && rules.scoreCap < (rules.targetScore as number)) || rules.bestOf > 9 || rules.bestOf % 2 !== 1));
    if (bad) { setSettingsError(k('invalid')); return; }
    const changed = JSON.stringify(rules) !== JSON.stringify(state.rules);
    const apply = () => {
      const next: MatchState = { ...state, names, rules };
      if (changed) { next.scores = [0, 0]; next.games = [0, 0]; next.phase = 'playing'; }
      commit(next, true, state);
      setSetupPending(false);
      dialog.current?.close();
    };
    if (changed && (state.scores.some(Boolean) || state.games.some(Boolean))) setConfirm({ text: k('rulesConfirm'), run: apply });
    else apply();
  };
  const swap = () => commit({ ...state, order: [state.order[1], state.order[0]] }, true, state);
  const reset = () => setConfirm({ text: k('resetConfirm'), run: () => { commit({ ...state, scores: [0, 0], games: [0, 0], phase: 'playing' }, true, state); dialog.current?.close(); } });

  const status = setupPending ? k('setup') : state.phase === 'match' ? k('matchOver') : state.phase === 'game' ? k('gameOver') : k('playing');
  const locked = Boolean(confirm);
  return <section ref={root} className="pk-scoreboard" aria-label={k('label')} data-sb-phase={setupPending ? 'setup' : state.phase} data-sb-ready="1">
    <div className="sb-header">
      <span data-sb-status aria-live="polite">{status}</span>
      <span className="sb-header-actions">
        {input ? <button className="pk-btn" type="button" data-sb-input data-status={inputOn ? inputStatus : 'off'} aria-pressed={inputOn} disabled={off || !port} onClick={() => setInputOn(on => !on)}>
          {!port ? t('toolCards.generativeUI.gesture.unavailable') : inputOn ? (inputStatus === 'active' ? k('inputActive') : t(`toolCards.generativeUI.gesture.${inputStatus}`)) : k('inputOn')}
        </button> : null}
        <button className="pk-btn" type="button" data-sb-more disabled={off} onClick={openSettings}>{k('more')}</button>
      </span>
    </div>
    <div className="sb-teams">{[0, 1].map(slot => {
      const id = state.order[slot];
      return <div key={slot} className={`sb-team${flash === slot ? ' sb-flash' : ''}`} data-sb-slot={slot} data-sb-participant={ID[id]}>
        <span data-sb-name>{state.names[id]}</span>
        <strong data-sb-score>{state.scores[id]}</strong>
        <span className="sb-adds">{config.increments.map(points => <button key={points} className="pk-btn" type="button" data-sb-add data-sb-points={points} aria-label={k('addPoints', { name: state.names[id], points })} disabled={off || setupPending || state.phase !== 'playing'} onClick={() => add(id, slot, points)}>+{points}</button>)}</span>
      </div>;
    })}</div>
    <div className="sb-footer">
      {state.rules.targetScore === null ? <span data-sb-games /> : <span data-sb-games>{k('games', { a: state.games[state.order[0]], b: state.games[state.order[1]] })}</span>}
      <button className="pk-btn" type="button" data-sb-undo disabled={off || !history.current.length} onClick={undo}>{k('undo')}</button>
      <button className="pk-btn" type="button" data-sb-next hidden={state.phase !== 'game'} onClick={nextGame}>{k('next')}</button>
    </div>
    <dialog ref={dialog} className="sb-more" data-sb-panel tabIndex={-1} autoFocus aria-modal="true" aria-label={k('settings')} onCancel={event => { if (setupPending) event.preventDefault(); }} onClose={() => setConfirm(null)}>
      <h3>{k('settings')}</h3>
      <p data-sb-rule-summary>{ruleSummary(state.rules, t)}</p>
      {[0, 1].map(index => <label key={index}>{index ? k('teamTwo') : k('teamOne')} <input data-sb-team={index} maxLength={60} value={draftNames[index]} disabled={locked} onChange={event => { const next = [...draftNames] as [string, string]; next[index] = event.currentTarget.value; setDraftNames(next); }} /></label>)}
      {([['targetScore', k('targetScore'), {}], ['winBy', k('winBy'), {}], ['scoreCap', k('scoreCap'), {}], ['bestOf', k('bestOf'), { step: 2, max: 9 }]] as Array<[keyof Rules, string, { step?: number; max?: number }]>).filter(([key]) => key === 'targetScore' || draftRules.targetScore.trim() !== '').map(([key, label, extra]) =>
        <label key={key}>{label} <input data-sb-rule={key} type="number" min={1} max={extra.max ?? 999} step={extra.step} value={draftRules[key]} disabled={locked} onChange={event => setDraftRules({ ...draftRules, [key]: event.currentTarget.value })} /></label>)}
      <p data-sb-error role="alert">{settingsError}</p>
      <div className="sb-confirm" data-sb-confirm hidden={!confirm} role="group" aria-label={k('confirmGroup')}>
        <p data-sb-confirm-text>{confirm?.text}</p>
        <button className="pk-btn" type="button" data-sb-confirm-yes onClick={() => { const run = confirm?.run; setConfirm(null); run?.(); }}>{k('confirm')}</button>
        <button className="pk-btn" type="button" data-sb-confirm-no onClick={() => setConfirm(null)}>{k('cancel')}</button>
      </div>
      <div>
        <button className="pk-btn" type="button" data-sb-save disabled={locked} onClick={save}>{k('save')}</button>
        <button className="pk-btn" type="button" data-sb-swap disabled={locked} onClick={swap}>{k('swap')}</button>
        <button className="pk-btn" type="button" data-sb-reset disabled={locked} onClick={reset}>{k('reset')}</button>
        <button className="pk-btn" type="button" data-sb-close disabled={setupPending} onClick={closeSettings}>{k('close')}</button>
      </div>
    </dialog>
  </section>;
}

export const harmonyScoreboardComponents: GenUIImplementations['components'] = {
  Scoreboard: {
    render: Scoreboard,
    inspect: (element, view) => {
      const names = Array.from(element.querySelectorAll('[data-sb-name]')).map(node => node.textContent);
      const teams = view.props.teams as unknown[];
      return element.querySelectorAll('[data-sb-score]').length === 2 && Array.isArray(teams) && teams.every(name => names.includes(String(name)));
    },
    exercise: (element, event) => {
      if (event !== 'change') throw new Error('Scoreboard event is unavailable');
      element.querySelector<HTMLButtonElement>('[data-sb-add]')?.click();
    },
  },
};
