export type LocalCollaborationKind = 'photo' | 'scan' | 'gallery';
export type LocalCollaborationPhase = 'ready' | 'selecting' | 'active' | 'receiving' |
  'completed' | 'cancelled' | 'failed' | 'closed' | 'unavailable';

export interface LocalCollaborationSnapshot {
  phase: LocalCollaborationPhase;
  kind: LocalCollaborationKind;
  received: number;
  code: number;
  reason: string;
}

/** Published by the SDK; a started service is not a completed transfer. */
export class LocalCollaborationSession {
  private generation: number = 0;
  private pending: number = 0;
  private ended: boolean = false;
  private state: LocalCollaborationSnapshot = {
    phase: 'ready', kind: 'photo', received: 0, code: 0, reason: ''
  };
  private readonly changed: (state: LocalCollaborationSnapshot) => void;
  private readonly receiveImage: (data: ArrayBuffer, generation: number) => Promise<void>;

  constructor(changed: (state: LocalCollaborationSnapshot) => void,
    receiveImage: (data: ArrayBuffer, generation: number) => Promise<void>) {
    this.changed = changed;
    this.receiveImage = receiveImage;
  }

  static unavailableReason(api: number, deviceType: string, syscap: boolean): string {
    if (!syscap) return 'missingSyscap';
    // The first adapter uses the API 23 device filters on every form factor.
    if (api < 23) return 'version';
    if (!['phone', 'tablet', '2in1', 'tv', 'pc'].includes(deviceType)) return 'deviceType';
    return '';
  }

  snapshot(): LocalCollaborationSnapshot {
    return { phase: this.state.phase, kind: this.state.kind, received: this.state.received,
      code: this.state.code, reason: this.state.reason };
  }

  begin(kind: LocalCollaborationKind, unavailable: string): boolean {
    // One native receiver per mount. Retry remounts it so callbacks cannot cross requests.
    if (this.state.phase !== 'ready') return false;
    this.generation += 1;
    this.state = { phase: unavailable ? 'unavailable' : 'selecting', kind, received: 0,
      code: 0, reason: unavailable };
    this.publish();
    return !unavailable;
  }

  isCurrent(generation: number): boolean {
    return generation === this.generation && this.accepting();
  }

  private accepting(): boolean {
    return ['selecting', 'active', 'receiving'].includes(this.state.phase);
  }

  async accept(code: number, type: string, buffer: ArrayBuffer): Promise<void> {
    if (!this.accepting()) return;
    this.state.code = code;
    if (code === 1001202001 || code === 1001202003) {
      this.finish('cancelled', code === 1001202001 ? 'peerCancelled' : 'localCancelled');
    } else if (code === 1001202004) {
      this.state.phase = 'active';
      this.publish();
    } else if (code === 1001202006) {
      this.state.phase = 'receiving';
      this.publish();
    } else if (code === 1001202005) {
      this.ended = true;
      this.completeIfReady();
    } else if (code === 0) {
      // This first adapter asks for one image, and never accepts video URIs as image bytes.
      if (type !== 'general.image' || !buffer || buffer.byteLength === 0) {
        this.finish('failed', 'invalidImage');
        return;
      }
      if (buffer.byteLength > 32 * 1024 * 1024 || this.pending + this.state.received >= 1) {
        this.finish('failed', 'imageLimit');
        return;
      }
      const generation = this.generation;
      this.pending += 1;
      this.state.phase = 'receiving';
      this.publish();
      try {
        await this.receiveImage(buffer, generation);
        if (!this.isCurrent(generation)) return;
        this.pending -= 1;
        this.state.received += 1;
        this.publish();
        this.completeIfReady();
      } catch (_err) {
        if (this.isCurrent(generation)) this.finish('failed', 'decodeFailed');
      }
    } else {
      this.finish('failed', 'platformError');
    }
  }

  close(): void {
    if (this.state.phase === 'closed') return;
    this.finish('closed', '');
  }

  private completeIfReady(): void {
    if (!this.ended || this.pending > 0 || !this.accepting()) return;
    this.finish(this.state.received > 0 ? 'completed' : 'failed', this.state.received > 0 ? '' : 'emptyResult');
  }

  private finish(phase: LocalCollaborationPhase, reason: string): void {
    this.generation += 1;
    this.state.phase = phase;
    this.state.reason = reason;
    this.publish();
  }

  private publish(): void { this.changed(this.snapshot()); }
}
