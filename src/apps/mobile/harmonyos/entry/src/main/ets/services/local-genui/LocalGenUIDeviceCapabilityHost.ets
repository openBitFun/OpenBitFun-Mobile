import { RemoteLogger } from '../RemoteLogger';
import { LocalGenUIGestureCamera, LocalGestureCameraStatus } from './LocalGenUIGestureCamera';
import { LocalGenUIHaptics } from './LocalGenUIHaptics';
import { LocalGestureName } from './LocalGestureClassifier';

/** Gestures a GenUI app may subscribe to; anything else is refused. */
const SUPPORTED_GESTURES: string[] = [LocalGestureName.RaiseLeft, LocalGestureName.RaiseRight, LocalGestureName.RaiseBoth];
const MAX_SUBSCRIPTIONS: number = 4;
/**
 * A camera-service failure is usually transient (device released late, another
 * app still closing it), so retry before telling the person it cannot work.
 */
const MAX_START_RETRIES: number = 2;
const RETRY_DELAY_MS: number = 1200;

interface GestureSubscription {
  appId: string;
  gesture: string;
}

export interface LocalGenUIDeviceCapabilityEvents {
  /** Runtime delivery: one gesture for one subscription. */
  gesture: (subscriptionId: string, gesture: string) => void;
  status: (subscriptionId: string, status: string) => void;
  /** Presentation: whether the camera preview surface should exist. */
  cameraWanted: (wanted: boolean) => void;
  cameraActive: (active: boolean) => void;
}

/**
 * Device capabilities served to Local GenUI apps. The camera runs only while
 * an app holds a subscription, that app is on screen, and the phone app is in
 * the foreground; otherwise subscribers see `paused`.
 */
export class LocalGenUIDeviceCapabilityHost {
  private readonly events: LocalGenUIDeviceCapabilityEvents;
  private readonly camera: LocalGenUIGestureCamera;
  private readonly subscriptions: Map<string, GestureSubscription> = new Map<string, GestureSubscription>();
  private visible: boolean = false;
  private surfaceId: string = '';
  private lastStatus: string = 'starting';
  /** Retries spent in the current visibility episode. */
  private retries: number = 0;
  private retryTimer: number = -1;

  // CoreVisionKit labels skeleton points by the person's anatomical sides for
  // the front-camera stream. The preview is not mirrored at the classifier
  // input, so swapping the sides here would turn right-hand input into left.
  constructor(context: Context, events: LocalGenUIDeviceCapabilityEvents, mirrored: boolean = false) {
    this.events = events;
    this.camera = new LocalGenUIGestureCamera(context, {
      onGesture: (gesture: LocalGestureName): void => this.dispatch(gesture),
      onStatus: (status: LocalGestureCameraStatus): void => this.onCameraStatus(status)
    }, mirrored);
  }

  private onCameraStatus(status: LocalGestureCameraStatus): void {
    this.events.cameraActive(status === LocalGestureCameraStatus.Active);
    if (status === LocalGestureCameraStatus.Active) {
      this.retries = 0;
    }
    this.broadcast(status);
    if (status === LocalGestureCameraStatus.Failed) {
      this.scheduleRetry();
    }
  }

  /** Bounded, so a genuinely broken camera still settles on a final answer. */
  private scheduleRetry(): void {
    if (this.retryTimer >= 0 || this.retries >= MAX_START_RETRIES) {
      return;
    }
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1;
      if (!this.visible || this.subscriptions.size === 0) {
        return;
      }
      this.retries += 1;
      RemoteLogger.info(`local genui gesture camera retry ${this.retries}/${MAX_START_RETRIES}`);
      this.update();
    }, RETRY_DELAY_MS);
  }

  private clearRetry(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    this.retries = 0;
  }

  /** Returns a refusal reason, or '' when accepted. */
  subscribeGesture(appId: string, subscriptionId: string, gesture: string): string {
    if (SUPPORTED_GESTURES.indexOf(gesture) < 0) {
      this.events.status(subscriptionId, 'unavailable');
      return `unsupported gesture ${gesture}`;
    }
    if (!this.subscriptions.has(subscriptionId) && this.subscriptions.size >= MAX_SUBSCRIPTIONS) {
      this.events.status(subscriptionId, 'unavailable');
      return 'too many gesture subscriptions';
    }
    this.subscriptions.set(subscriptionId, { appId, gesture });
    this.events.status(subscriptionId, this.visible ? this.lastStatus : 'paused');
    this.update();
    return '';
  }

  unsubscribeGesture(subscriptionId: string): void {
    if (this.subscriptions.delete(subscriptionId)) {
      this.update();
    }
  }

  haptic(kind: string): void {
    LocalGenUIHaptics.play(kind);
  }

  /** A different app is mounted (or none): its subscriptions end. */
  releaseOtherApps(appId: string): void {
    const stale: string[] = [];
    this.subscriptions.forEach((sub: GestureSubscription, id: string) => {
      if (sub.appId !== appId) {
        stale.push(id);
      }
    });
    stale.forEach((id: string) => this.subscriptions.delete(id));
    if (stale.length > 0) {
      this.update();
    }
  }

  /** App view on screen and phone app in the foreground. */
  setVisible(visible: boolean): void {
    if (this.visible === visible) {
      return;
    }
    this.visible = visible;
    if (!visible) {
      this.clearRetry();
      this.broadcast('paused');
    }
    this.update();
  }

  /** The preview surface the camera renders into (from the presentation leaf). */
  attachSurface(surfaceId: string): void {
    this.surfaceId = surfaceId;
    this.update();
  }

  detachSurface(): void {
    this.surfaceId = '';
    this.events.cameraActive(false);
    this.clearRetry();
    void this.camera.stop();
  }

  shutdown(): void {
    this.subscriptions.clear();
    this.surfaceId = '';
    this.clearRetry();
    void this.camera.stop();
    this.events.cameraActive(false);
    this.events.cameraWanted(false);
  }

  private update(): void {
    const wanted = this.visible && this.subscriptions.size > 0;
    this.events.cameraWanted(wanted);
    if (!wanted) {
      this.events.cameraActive(false);
      void this.camera.stop();
      return;
    }
    if (this.surfaceId.length > 0 && !this.camera.isRunning()) {
      void this.camera.start(this.surfaceId);
    }
  }

  private dispatch(gesture: LocalGestureName): void {
    RemoteLogger.info(`local genui gesture ${gesture}`);
    this.subscriptions.forEach((sub: GestureSubscription, id: string) => {
      if (sub.gesture === gesture) {
        this.events.gesture(id, gesture);
      }
    });
  }

  private broadcast(status: string): void {
    if (status !== 'paused') {
      this.lastStatus = status;
    }
    this.subscriptions.forEach((_sub: GestureSubscription, id: string) => this.events.status(id, status));
  }
}
