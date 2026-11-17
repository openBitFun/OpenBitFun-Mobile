import { RemoteSession } from '../../model/RemoteModels';

/** Read-only details opened from a sidebar, independent of its responsive host. */
@ObservedV2
export class SessionDetailsState {
  @Trace visible: boolean = false;
  @Trace session: RemoteSession = {
    id: '', title: '', agentType: '', status: '', updatedAt: '', createdAt: '', messageCount: 0
  };

  open(session: RemoteSession): void {
    if (session.id.length === 0) return;
    this.session = session;
    this.visible = true;
  }

  close(): void {
    this.visible = false;
  }
}
