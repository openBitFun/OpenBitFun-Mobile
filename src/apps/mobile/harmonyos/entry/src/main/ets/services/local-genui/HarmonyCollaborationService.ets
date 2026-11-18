import { deviceInfo } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { LocalCollaborationSession, LocalCollaborationSnapshot } from './LocalCollaborationSession';

export interface HarmonyCollaborationEnvironment {
  api: number;
  deviceType: string;
  syscap: boolean;
  unavailable: string;
}

/** Native image ownership stays here; no file, account or Remote Mode dependency. */
export class HarmonyCollaborationService {
  readonly session: LocalCollaborationSession;
  private picture?: image.PixelMap;
  private readonly onPicture: (picture: image.PixelMap | undefined) => void;
  private readonly onEncoded?: (data: ArrayBuffer) => Promise<void>;

  constructor(onState: (state: LocalCollaborationSnapshot) => void,
    onPicture: (picture: image.PixelMap | undefined) => void,
    onEncoded?: (data: ArrayBuffer) => Promise<void>) {
    this.onPicture = onPicture;
    this.onEncoded = onEncoded;
    this.session = new LocalCollaborationSession(onState,
      (data: ArrayBuffer, generation: number): Promise<void> => this.decode(data, generation));
  }

  static environment(): HarmonyCollaborationEnvironment {
    try {
      const api = deviceInfo.sdkApiVersion;
      const deviceType = deviceInfo.deviceType;
      const syscap = canIUse('SystemCapability.Collaboration.Service');
      return { api, deviceType, syscap,
        unavailable: LocalCollaborationSession.unavailableReason(api, deviceType, syscap) };
    } catch (_err) {
      return { api: 0, deviceType: '', syscap: false, unavailable: 'probeFailed' };
    }
  }

  private async decode(data: ArrayBuffer, generation: number): Promise<void> {
    const source = image.createImageSource(data);
    let decoded: image.PixelMap | undefined;
    try {
      const info = await source.getImageInfo();
      if (!this.session.isCurrent(generation)) return;
      const scale = Math.min(1, 1600 / Math.max(info.size.width, info.size.height));
      decoded = await source.createPixelMap({ desiredSize: {
        width: Math.max(1, Math.round(info.size.width * scale)),
        height: Math.max(1, Math.round(info.size.height * scale))
      } });
      if (!this.session.isCurrent(generation)) return;
      if (this.onEncoded) {
        const packer = image.createImagePacker();
        try {
          const bytes = await packer.packToData(decoded, { format: 'image/jpeg', quality: 85 });
          if (!this.session.isCurrent(generation)) return;
          await this.onEncoded(bytes);
        } finally { await packer.release(); }
        if (!this.session.isCurrent(generation)) return;
      }
      const previous = this.picture;
      this.picture = decoded;
      decoded = undefined;
      this.onPicture(this.picture);
      if (previous) void previous.release();
    } finally {
      if (decoded) void decoded.release();
      await source.release();
    }
  }

  dispose(): void {
    this.session.close();
    this.onPicture(undefined);
    const previous = this.picture;
    this.picture = undefined;
    if (previous) void previous.release();
  }
}
