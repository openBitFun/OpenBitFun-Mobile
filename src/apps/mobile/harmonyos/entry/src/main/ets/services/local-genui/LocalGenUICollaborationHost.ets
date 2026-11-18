import { LocalCollaborationKind, LocalCollaborationSnapshot } from './LocalCollaborationSession';
import { LocalRuntimeInbound } from './LocalGenUIRuntimeProtocol';

export interface LocalCollaborationRequest {
  appId: string;
  sourceRevision: number;
  requestId: string;
  token: number;
  kind: LocalCollaborationKind;
}
export interface LocalCollaborationReply {
  type: string;
  appId: string;
  sourceRevision: number;
  requestId: string;
  status: string;
  reason: string;
  asset: string;
}
export interface LocalCollaborationOwner { appId: string; sourceRevision: number; live: boolean; }
export interface LocalCollaborationHostPorts {
  owner: () => LocalCollaborationOwner;
  unavailable: () => string;
  changed: (request: LocalCollaborationRequest | undefined) => void;
  send: (reply: LocalCollaborationReply) => void;
  save: (appId: string, data: ArrayBuffer) => Promise<string>;
  discard: (appId: string, asset: string) => Promise<void>;
}

/** One native picker, bound to an accepted app/source revision and a request token. */
export class LocalGenUICollaborationHost {
  private active?: LocalCollaborationRequest;
  private serial: number = 0;
  private visible: boolean = false;
  private asset: string = '';
  private receiving: boolean = false;
  private readonly ports: LocalCollaborationHostPorts;
  constructor(ports: LocalCollaborationHostPorts) { this.ports = ports; }

  setVisible(visible: boolean): void {
    this.visible = visible;
    if (!visible) this.close();
  }

  invalidate(appId: string, sourceRevision: number, streaming: boolean): void {
    if (this.active && (streaming || this.active.appId !== appId || this.active.sourceRevision !== sourceRevision)) this.close();
  }

  handle(message: LocalRuntimeInbound): string {
    const owner = this.ports.owner();
    if (!owner.live || message.appId !== owner.appId || message.sourceRevision !== owner.sourceRevision) return 'stale collaboration owner';
    if (!message.requestId || !/^[a-zA-Z0-9_-]{1,64}$/.test(message.requestId)) return 'invalid collaboration request';
    if (message.op === 'cancel') {
      if (this.active?.requestId === message.requestId) this.close();
      return '';
    }
    if (message.op !== 'start' || !['photo', 'scan', 'gallery'].includes(message.kind || '')) return 'invalid collaboration operation';
    if (this.active && !this.current(this.active)) this.close();
    const request: LocalCollaborationRequest = { appId: owner.appId, sourceRevision: owner.sourceRevision,
      requestId: message.requestId, token: ++this.serial, kind: message.kind as LocalCollaborationKind };
    if (this.active) {
      if (this.active.requestId !== request.requestId) this.reply(request, 'failed', 'busy');
      return '';
    }
    const unavailable = this.ports.unavailable();
    if (!this.visible || unavailable) {
      this.reply(request, 'unavailable', unavailable || 'notVisible');
      return '';
    }
    this.active = request;
    this.asset = '';
    this.receiving = false;
    this.reply(request, 'pending', '');
    this.ports.changed(request);
    return '';
  }

  async receive(token: number, data: ArrayBuffer): Promise<void> {
    const request = this.active;
    if (!request || request.token !== token || !this.current(request) || this.receiving || this.asset) throw new Error('inactive collaboration receiver');
    this.receiving = true;
    const asset = await this.ports.save(request.appId, data);
    if (!this.current(request)) {
      await this.ports.discard(request.appId, asset);
      throw new Error('collaboration request closed while saving');
    }
    this.asset = asset;
  }

  result(token: number, snapshot: LocalCollaborationSnapshot): void {
    const request = this.active;
    if (!request || request.token !== token || !this.current(request)) return;
    if (snapshot.phase === 'completed') {
      const asset = this.asset;
      this.asset = '';
      this.reply(request, asset ? 'completed' : 'failed', asset ? '' : 'emptyResult', asset);
      this.clear();
    } else if (['cancelled', 'closed', 'failed', 'unavailable'].includes(snapshot.phase)) {
      this.reply(request, snapshot.phase === 'closed' ? 'cancelled' : snapshot.phase, snapshot.reason);
      this.clear();
    }
  }

  close(token?: number): void {
    if (!this.active || (token !== undefined && token !== this.active.token)) return;
    this.reply(this.active, 'cancelled', 'localCancelled');
    this.clear();
  }

  private current(request: LocalCollaborationRequest): boolean {
    const owner = this.ports.owner();
    return this.visible && this.active?.token === request.token && owner.live && owner.appId === request.appId && owner.sourceRevision === request.sourceRevision;
  }
  private clear(): void {
    const request = this.active;
    const asset = this.asset;
    this.active = undefined;
    this.asset = '';
    if (request && asset) void this.ports.discard(request.appId, asset);
    this.ports.changed(undefined);
  }
  private reply(request: LocalCollaborationRequest, status: string, reason: string, asset: string = ''): void {
    this.ports.send({ type: 'collaboration_result', appId: request.appId, sourceRevision: request.sourceRevision,
      requestId: request.requestId, status, reason, asset });
  }
}
