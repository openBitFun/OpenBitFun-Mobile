import { RemoteSession } from '../../model/RemoteModels';
import { TimeFormat } from '../../services/TimeFormat';

/** Both landing and navigation use host activity, never selection or input order. */
export class RecentSessionPolicy {
  static time(session: RemoteSession): number {
    const updated = TimeFormat.timestampMs(session.updatedAt);
    if (Number.isFinite(updated) && updated > 0) return updated;
    const created = TimeFormat.timestampMs(session.createdAt);
    return Number.isFinite(created) ? created : 0;
  }

  static rows(source: RemoteSession[], limit: number): RemoteSession[] {
    const seen: Set<string> = new Set();
    return source.filter((row: RemoteSession): boolean => !!row.id.trim() && row.status !== 'archived')
      .sort((a: RemoteSession, b: RemoteSession): number => RecentSessionPolicy.time(b) - RecentSessionPolicy.time(a))
      .filter((row: RemoteSession): boolean => {
        const key = JSON.stringify([row.deviceId || '', row.id]);
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
      }).slice(0, limit);
  }
}
