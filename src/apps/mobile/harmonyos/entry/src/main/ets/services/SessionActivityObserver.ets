import { HostSessionCallbacks, HostSessionEvent, HostSessionStream } from './HostSessionStream';
import { SessionRecord } from './DurableSessionReducer';

export interface SessionActivity {
  deviceId: string;
  sessionId: string;
  status: string;
  lastActiveAt: number;
}

interface ActivityTurn {
  id: string;
  index: number;
  revision: number;
  authoritative: boolean;
  status: string;
  timestamp: number;
}

/** Retains turn headers only; background navigation never renders/downloads history. */
export class SessionActivityReducer {
  private turns: Map<string, ActivityTurn> = new Map();
  private deleted: Map<string, number> = new Map();

  apply(event: HostSessionEvent): void {
    if (event.event !== 'session-record') return;
    const record = event.payload as SessionRecord;
    if (record.sessionId !== event.session_id || !record.id ||
      !Number.isSafeInteger(record.revision) || record.revision < 1) return;
    if (record.deleted) {
      if (!record.id.startsWith('turn/')) return;
      const id = record.id.slice(5);
      if (record.revision <= (this.deleted.get(id) || 0)) return;
      this.deleted.set(id, record.revision);
      if ((this.turns.get(id)?.revision || 0) < record.revision) this.turns.delete(id);
      return;
    }
    const turn = record.turn;
    if (!turn || turn.sessionId !== event.session_id || !Number.isFinite(turn.turnIndex) ||
      record.revision <= (this.deleted.get(turn.turnId) || 0)) return;
    const own = record.id === `turn/${turn.turnId}`;
    const previous = this.turns.get(turn.turnId);
    // Item records repeat parent headers; those cannot reopen a completed turn.
    if (previous && ((!own && previous.authoritative) ||
      (previous.authoritative === own && previous.revision >= record.revision))) return;
    this.turns.set(turn.turnId, { id: turn.turnId, index: turn.turnIndex,
      revision: record.revision, authoritative: own, status: turn.status, timestamp: turn.timestamp });
  }

  snapshot(deviceId: string, sessionId: string): SessionActivity {
    let latest: ActivityTurn | undefined;
    this.turns.forEach((turn: ActivityTurn) => { if (!latest || turn.index > latest.index) latest = turn; });
    const status = latest?.status.toLowerCase() || '';
    const running = ['inprogress', 'running', 'active', 'streaming'].indexOf(status) >= 0;
    const failed = status === 'error' || status === 'failed';
    return { deviceId, sessionId, status: running ? 'running' : failed ? 'failed' : status ? 'idle' : 'unknown',
      lastActiveAt: latest?.timestamp || 0 };
  }
}

export interface SessionActivitySource {
  readonly subscribeSession: (sessionId: string, callbacks: HostSessionCallbacks) => HostSessionStream;
}

class ActivitySubscription {
  reducer: SessionActivityReducer = new SessionActivityReducer();
  stream?: HostSessionStream;
}

/** Host-scoped ownership survives changing the selected conversation and layout. */
export class SessionActivityObserver {
  private target: string = '';
  private entries: Map<string, ActivitySubscription> = new Map();
  private readonly source: SessionActivitySource;
  private readonly publish: (activity: SessionActivity) => void;
  private readonly reset: () => void;

  constructor(source: SessionActivitySource, publish: (activity: SessionActivity) => void, reset: () => void) {
    this.source = source; this.publish = publish; this.reset = reset;
  }

  sync(target: string, sessionIds: string[]): void {
    if (target !== this.target) { this.stop(); this.target = target; }
    if (!target) return;
    const wanted = new Set<string>(sessionIds.filter((id: string): boolean => !!id));
    this.entries.forEach((entry: ActivitySubscription, id: string) => {
      if (!wanted.has(id) && entry.reducer.snapshot(target, id).status !== 'running') {
        entry.stream?.close(); this.entries.delete(id);
        this.publish({ deviceId: target, sessionId: id, status: 'unknown', lastActiveAt: 0 });
      }
    });
    wanted.forEach((id: string) => this.observe(id));
  }

  isObserving(target: string, sessionId: string): boolean {
    const stream = this.entries.get(sessionId)?.stream;
    return this.target === target && stream !== undefined && !stream.isClosed();
  }

  private observe(sessionId: string): void {
    const old = this.entries.get(sessionId);
    if (old?.stream && !old.stream.isClosed()) return;
    const entry = new ActivitySubscription();
    const target = this.target;
    this.entries.set(sessionId, entry);
    const current = (): boolean => this.target === target && this.entries.get(sessionId) === entry;
    const unknown = (): void => {
      if (current()) this.publish({ deviceId: target, sessionId, status: 'unknown', lastActiveAt: 0 });
    };
    try {
      entry.stream = this.source.subscribeSession(sessionId, {
        onEvent: async (event: HostSessionEvent): Promise<void> => {
          if (current() && event.session_id === sessionId) entry.reducer.apply(event);
        },
        onCaughtUp: async (): Promise<void> => {
          if (current()) this.publish(entry.reducer.snapshot(target, sessionId));
        },
        onGap: async (): Promise<void> => {
          if (current()) { entry.reducer = new SessionActivityReducer(); unknown(); }
        },
        onResumed: async (): Promise<void> => { unknown(); },
        onError: (_error: Error): void => { unknown(); }
      });
    } catch (_error) { unknown(); }
  }

  stop(): void {
    this.target = '';
    this.entries.forEach((entry: ActivitySubscription) => entry.stream?.close());
    this.entries.clear(); this.reset();
  }
}
