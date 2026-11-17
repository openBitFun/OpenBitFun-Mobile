import { SessionActivity } from '../../services/SessionActivityObserver';

/** Transient host facts, deliberately excluded from the persisted session catalog. */
@ObservedV2
export class SessionActivityState {
  @Trace entries: SessionActivity[] = [];

  update(activity: SessionActivity): void {
    const old = this.get(activity.deviceId, activity.sessionId);
    if (old?.status === activity.status && old.lastActiveAt === activity.lastActiveAt) return;
    this.entries = this.entries.filter((row: SessionActivity): boolean =>
      row.deviceId !== activity.deviceId || row.sessionId !== activity.sessionId).concat([activity]);
  }

  get(deviceId: string, sessionId: string): SessionActivity | undefined {
    return this.entries.find((row: SessionActivity): boolean => row.deviceId === deviceId && row.sessionId === sessionId);
  }

  running(deviceId: string, sessionId: string): boolean { return this.get(deviceId, sessionId)?.status === 'running'; }
  clear(): void { this.entries = []; }
}
