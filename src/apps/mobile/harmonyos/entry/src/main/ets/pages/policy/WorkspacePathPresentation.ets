import { RemoteWorkspaceIdentity } from '../../model/RemoteModels';

/** Display only: never normalize a runtime path using the controller's OS. */
export class WorkspacePathPresentation {
  static label(path: string, identity?: RemoteWorkspaceIdentity, fallback: string = ''): string {
    const location = identity?.path?.trim() || path.trim();
    if (!location) return fallback;
    const host = identity?.remoteSshHost?.trim() || '';
    const remote = !!identity?.remoteConnectionId || (host.length > 0 && host !== 'localhost');
    return remote && host ? `${host}:${location}` : location;
  }
}
