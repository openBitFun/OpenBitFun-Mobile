import { RemoteSession, RemoteWorkspaceIdentity } from '../model/RemoteModels';
import { mapInConcurrentBatches } from './ConcurrentWorkspaceListing';
import { remoteWorkspaceKey, stampRemoteSessionsDevice } from './RemoteSessionIdentity';

export interface RecentSessionCatalogSource {
  readonly list: (workspace: RemoteWorkspaceIdentity, limit: number) => Promise<RemoteSession[]>;
}

/** Navigation's cross-workspace catalog is independent of the active list's paging/filter. */
export class RecentSessionCatalog {
  private generation: number = 0;
  private target: string = '';
  private groups: Map<string, RemoteSession[]> = new Map();
  private readonly source: RecentSessionCatalogSource;
  private readonly publish: (sessions: RemoteSession[]) => void;

  constructor(source: RecentSessionCatalogSource, publish: (sessions: RemoteSession[]) => void) {
    this.source = source; this.publish = publish;
  }

  async refresh(target: string, workspaces: RemoteWorkspaceIdentity[]): Promise<void> {
    if (this.target !== target) { this.stop(); this.target = target; }
    if (!target) return;
    const generation = ++this.generation;
    const next: Map<string, RemoteSession[]> = new Map();
    let failure: Error | undefined;
    await mapInConcurrentBatches(workspaces, async (workspace: RemoteWorkspaceIdentity): Promise<void> => {
      if (generation !== this.generation) return;
      const key = remoteWorkspaceKey(workspace);
      try {
        // Five per workspace suffice for the global top five; the host sorts by last activity.
        const sessions = await this.source.list(workspace, 5);
        if (generation === this.generation) next.set(key, stampRemoteSessionsDevice(sessions, target));
      } catch (_error) {
        failure = _error instanceof Error ? _error : new Error(String(_error));
        const previous = this.groups.get(key);
        if (previous) next.set(key, previous);
      }
    });
    if (generation !== this.generation) return;
    this.groups = next;
    const sessions: RemoteSession[] = [];
    next.forEach((rows: RemoteSession[]) => sessions.push(...rows));
    this.publish(sessions);
    if (failure) throw failure;
  }

  stop(): void { this.generation++; this.target = ''; this.groups.clear(); this.publish([]); }
}
