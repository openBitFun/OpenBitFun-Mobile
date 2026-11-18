import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { skeletonDetection } from '@kit.CoreVisionKit';
import { display } from '@kit.ArkUI';
import { OhosError } from '../OhosError';
import { RemoteLogger } from '../RemoteLogger';
import { LocalGestureClassifier, LocalGestureKeypoint, LocalGestureName } from './LocalGestureClassifier';

const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';
const FRAME_INTERVAL_MS: number = 200;
/** One diagnostic line every few seconds while running. */
const DIAGNOSTIC_EVERY: number = 15;
/** Preview surface size the camera profile is matched against (4:3). */
export const LOCAL_GESTURE_SURFACE_WIDTH: number = 640;
export const LOCAL_GESTURE_SURFACE_HEIGHT: number = 480;

export enum LocalGestureCameraStatus {
  Starting = 'starting',
  Active = 'active',
  Denied = 'denied',
  /** This device cannot serve gestures at all; retrying cannot help. */
  Unavailable = 'unavailable',
  /** A transient camera failure; the host retries a bounded number of times. */
  Failed = 'failed'
}

/**
 * The device lacks the capability itself (no front camera, no preview profile,
 * no skeleton detector). Distinct from camera-service errors, which are
 * transient and worth retrying.
 */
class GestureCapabilityError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'GestureCapabilityError';
  }
}

export interface LocalGestureCameraListener {
  onGesture: (gesture: LocalGestureName) => void;
  onStatus: (status: LocalGestureCameraStatus) => void;
}

/**
 * Front camera + on-device skeleton detection for Local GenUI gestures.
 * Frames never leave this object: only gesture names are reported.
 */
export class LocalGenUIGestureCamera {
  private readonly context: Context;
  private readonly listener: LocalGestureCameraListener;
  private readonly classifier: LocalGestureClassifier;
  private session?: camera.PhotoSession;
  private input?: camera.CameraInput;
  private preview?: camera.PreviewOutput;
  private detector?: skeletonDetection.SkeletonDetector;
  private timer: number = -1;
  private busy: boolean = false;
  private generation: number = 0;
  /** One attempt at a time; set before the first await so callers see it. */
  private starting: boolean = false;
  private surfaceId: string = '';
  private frames: number = 0;
  /** Sensor mounting angle of the front camera, in degrees. */
  private sensorOrientation: number = 0;

  constructor(context: Context, listener: LocalGestureCameraListener, mirrored: boolean) {
    this.context = context;
    this.listener = listener;
    this.classifier = new LocalGestureClassifier(mirrored);
  }

  isRunning(): boolean {
    return this.session !== undefined;
  }

  /**
   * The presenter starts the camera once per subscription, so several calls
   * arrive together. Every attempt opens the same physical device, and a
   * concurrent attempt tears down the session the previous one is still
   * configuring (7400102/7400201/7400103), so only one may run at a time.
   */
  async start(surfaceId: string): Promise<void> {
    if (this.starting && this.surfaceId === surfaceId) {
      return;
    }
    if (this.session && this.surfaceId === surfaceId) {
      return;
    }
    this.starting = true;
    this.surfaceId = surfaceId;
    const generation = ++this.generation;
    try {
      await this.releaseSession();
      if (generation !== this.generation) {
        return;
      }
      this.listener.onStatus(LocalGestureCameraStatus.Starting);
      if (!(await this.ensurePermission())) {
        if (generation === this.generation) {
          this.listener.onStatus(LocalGestureCameraStatus.Denied);
        }
        return;
      }
      this.detector = await LocalGenUIGestureCamera.createDetector();
      const manager = camera.getCameraManager(this.context);
      const front = manager.getSupportedCameras().find((device: camera.CameraDevice) =>
        device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT);
      if (!front) {
        throw new GestureCapabilityError('no front camera');
      }
      const capability = manager.getSupportedOutputCapability(front, camera.SceneMode.NORMAL_PHOTO);
      const profile = LocalGenUIGestureCamera.pickProfile(capability.previewProfiles);
      if (!profile) {
        throw new GestureCapabilityError('no preview profile');
      }
      this.sensorOrientation = front.cameraOrientation;
      const input = manager.createCameraInput(front);
      await input.open();
      if (generation !== this.generation) {
        await LocalGenUIGestureCamera.release(undefined, input, undefined);
        return;
      }
      this.input = input;
      const preview = manager.createPreviewOutput(profile, surfaceId);
      this.preview = preview;
      const session = manager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
      this.session = session;
      session.beginConfig();
      session.addInput(input);
      session.addOutput(preview);
      await session.commitConfig();
      if (generation !== this.generation) {
        return;
      }
      await session.start();
      if (generation !== this.generation) {
        return;
      }
      this.frames = 0;
      this.busy = false;
      this.classifier.reset();
      this.timer = setInterval(() => { void this.analyze(generation); }, FRAME_INTERVAL_MS);
      RemoteLogger.info(`local genui gesture camera started ${profile.size.width}x${profile.size.height} sensor=${this.sensorOrientation} upright=${this.uprightRotation()}`);
      this.listener.onStatus(LocalGestureCameraStatus.Active);
    } catch (err) {
      const missingCapability = err instanceof GestureCapabilityError;
      RemoteLogger.warn(`local genui gesture camera ${missingCapability ? 'unavailable' : 'failed'}: ${OhosError.reason(err).slice(0, 400)}`);
      // A newer start owns the fields now; releasing here would kill its session.
      if (generation === this.generation) {
        await this.releaseSession();
        this.listener.onStatus(missingCapability ? LocalGestureCameraStatus.Unavailable : LocalGestureCameraStatus.Failed);
      }
    } finally {
      if (generation === this.generation) {
        this.starting = false;
      }
    }
  }

  async stop(): Promise<void> {
    this.generation += 1;
    this.starting = false;
    this.surfaceId = '';
    await this.releaseSession();
  }

  /** Releases the device objects of the current (or a superseded) attempt. */
  private async releaseSession(): Promise<void> {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    const session = this.session;
    const input = this.input;
    const preview = this.preview;
    const detector = this.detector;
    this.session = undefined;
    this.input = undefined;
    this.preview = undefined;
    this.detector = undefined;
    if (session || input || preview) {
      await LocalGenUIGestureCamera.release(session, input, preview);
      RemoteLogger.info('local genui gesture camera stopped');
    }
    if (detector) {
      try {
        await detector.destroy();
      } catch (_err) {
        // Already released.
      }
    }
  }

  private async analyze(generation: number): Promise<void> {
    if (this.busy || !this.detector || generation !== this.generation || this.surfaceId.length === 0) {
      return;
    }
    this.busy = true;
    let pixels: image.PixelMap | undefined = undefined;
    try {
      pixels = await image.createPixelMapFromSurface(this.surfaceId);
      // Sensor frames are landscape; the detector needs an upright person.
      const rotation = this.uprightRotation();
      if (rotation !== 0) {
        await pixels.rotate(rotation);
      }
      const response = await this.detector.process({ inputData: { pixelMap: pixels } });
      if (generation !== this.generation) {
        return;
      }
      const skeleton = response.skeletons.length > 0 ? response.skeletons[0] : undefined;
      const points: LocalGestureKeypoint[] = skeleton ? skeleton.points.map((point: skeletonDetection.SkeletonPoint): LocalGestureKeypoint => ({
        type: point.type, x: point.point.x, y: point.point.y, score: point.score
      })) : [];
      this.frames += 1;
      if (this.frames % DIAGNOSTIC_EVERY === 1) {
        this.logFrame(pixels, response.skeletons.length, points);
      }
      const gesture = this.classifier.accept(points);
      if (gesture) {
        const frame = LocalGestureClassifier.measure(points);
        RemoteLogger.info(`local genui gesture recognized ${gesture} left=${frame.leftLift.toFixed(2)} right=${frame.rightLift.toFixed(2)}`);
        this.listener.onGesture(gesture);
      }
    } catch (_err) {
      // A dropped frame is not an error; the next one retries.
    } finally {
      if (pixels) {
        void pixels.release();
      }
      this.busy = false;
    }
  }

  /**
   * Clockwise degrees that turn a sensor frame upright for the current
   * display rotation. Rotation never mirrors, so left/right labels from the
   * detector are unaffected by it.
   */
  private uprightRotation(): number {
    let displayDegrees = 0;
    try {
      displayDegrees = display.getDefaultDisplaySync().rotation * 90;
    } catch (_err) {
      displayDegrees = 0;
    }
    return ((this.sensorOrientation + displayDegrees) % 360 + 360) % 360;
  }

  private logFrame(pixels: image.PixelMap, skeletons: number, points: LocalGestureKeypoint[]): void {
    const frame = LocalGestureClassifier.measure(points);
    const size = pixels.getImageInfoSync().size;
    const score = (type: number): string => {
      const point = points.find((item: LocalGestureKeypoint) => item.type === type);
      return point ? point.score.toFixed(2) : '-';
    };
    RemoteLogger.info(`local genui gesture frame ${size.width}x${size.height} skeletons=${skeletons} tracked=${frame.tracked} left=${frame.leftLift.toFixed(2)} right=${frame.rightLift.toFixed(2)} score lw=${score(9)} rw=${score(10)} le=${score(7)} re=${score(8)} ls=${score(5)} rs=${score(6)}`);
  }

  private async ensurePermission(): Promise<boolean> {
    try {
      const manager = abilityAccessCtrl.createAtManager();
      const result = await manager.requestPermissionsFromUser(this.context, [CAMERA_PERMISSION]);
      return result.authResults.length > 0 && result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (_err) {
      return false;
    }
  }

  /** The detector belongs to the platform capability, not to a runtime failure. */
  private static async createDetector(): Promise<skeletonDetection.SkeletonDetector> {
    try {
      return await skeletonDetection.SkeletonDetector.create();
    } catch (err) {
      throw new GestureCapabilityError(`no skeleton detector: ${OhosError.reason(err).slice(0, 200)}`);
    }
  }

  /** The 4:3 profile closest to the preview surface; detection needs little resolution. */
  private static pickProfile(profiles: camera.Profile[]): camera.Profile | undefined {
    const ratio = LOCAL_GESTURE_SURFACE_WIDTH / LOCAL_GESTURE_SURFACE_HEIGHT;
    let best: camera.Profile | undefined = undefined;
    let bestScore = Number.MAX_VALUE;
    profiles.forEach((profile: camera.Profile) => {
      const width = profile.size.width;
      const height = profile.size.height;
      if (width <= 0 || height <= 0 || Math.abs(width / height - ratio) > 0.02) {
        return;
      }
      const score = Math.abs(width - LOCAL_GESTURE_SURFACE_WIDTH);
      if (score < bestScore) {
        best = profile;
        bestScore = score;
      }
    });
    return best;
  }

  private static async release(session?: camera.PhotoSession, input?: camera.CameraInput, preview?: camera.PreviewOutput): Promise<void> {
    try {
      if (session) {
        await session.stop();
        await session.release();
      }
    } catch (_err) {
      // Releasing a stopped session.
    }
    try {
      if (preview) {
        await preview.release();
      }
      if (input) {
        await input.close();
      }
    } catch (_err) {
      // Releasing a closed input.
    }
  }
}
