/**
 * Turns skeleton keypoints into discrete body gestures. Pure: the camera and
 * detector feed it frames, tests feed it fixtures.
 *
 * Orientation-free: "raised" is measured along the body's own up direction
 * (hips -> shoulders, or shoulders -> nose when hips are out of frame), so a
 * rotated camera surface does not change the meaning of a gesture.
 */
export interface LocalGestureKeypoint {
  /** skeletonDetection.SkeletonPointType value. */
  type: number;
  x: number;
  y: number;
  score: number;
}

export enum LocalGestureName {
  RaiseLeft = 'raise_left_hand',
  RaiseRight = 'raise_right_hand',
  RaiseBoth = 'raise_both_hands'
}

const NOSE = 0;
const LEFT_SHOULDER = 5;
const RIGHT_SHOULDER = 6;
const LEFT_WRIST = 9;
const RIGHT_WRIST = 10;
const LEFT_HIP = 11;
const RIGHT_HIP = 12;

const MIN_SCORE = 0.3;
/** Wrist must be this many shoulder widths above its shoulder. */
const RAISE_THRESHOLD = 0.35;
/** Below this it counts as lowered again (hysteresis). */
const LOWER_THRESHOLD = 0.1;
/** Consecutive frames needed to accept a pose change. */
const STABLE_FRAMES = 2;

interface Vec {
  x: number;
  y: number;
}

export interface LocalGestureFrame {
  /** Wrist height above its shoulder, in shoulder widths, along the body's up axis. */
  leftLift: number;
  rightLift: number;
  /** False when the shoulders are not both visible. */
  tracked: boolean;
}

const UNTRACKED: LocalGestureFrame = { leftLift: -1, rightLift: -1, tracked: false };

export class LocalGestureClassifier {
  /**
   * `mirrored` swaps the person's sides when the camera surface is a mirror
   * image (front camera on some devices); calibrated per host.
   */
  private readonly mirrored: boolean;
  private pendingLeft: boolean = false;
  private pendingRight: boolean = false;
  private pendingCount: number = 0;
  /** A gesture fires once per raise; lowering both hands re-arms. */
  private armed: boolean = true;

  constructor(mirrored: boolean) {
    this.mirrored = mirrored;
  }

  /** Per-frame measurement; exported for tests and diagnostics. */
  static measure(points: LocalGestureKeypoint[]): LocalGestureFrame {
    const at = (type: number): Vec | undefined => {
      const p = points.find((item: LocalGestureKeypoint) => item.type === type && item.score >= MIN_SCORE);
      return p ? { x: p.x, y: p.y } : undefined;
    };
    const ls = at(LEFT_SHOULDER);
    const rs = at(RIGHT_SHOULDER);
    if (!ls || !rs) {
      return UNTRACKED;
    }
    const width = Math.hypot(ls.x - rs.x, ls.y - rs.y);
    if (width <= 0) {
      return UNTRACKED;
    }
    const shoulders: Vec = { x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2 };
    const lh = at(LEFT_HIP);
    const rh = at(RIGHT_HIP);
    const nose = at(NOSE);
    let up: Vec;
    if (lh && rh) {
      up = { x: shoulders.x - (lh.x + rh.x) / 2, y: shoulders.y - (lh.y + rh.y) / 2 };
    } else if (nose) {
      up = { x: nose.x - shoulders.x, y: nose.y - shoulders.y };
    } else {
      return UNTRACKED;
    }
    const length = Math.hypot(up.x, up.y);
    if (length <= 0) {
      return UNTRACKED;
    }
    const unit: Vec = { x: up.x / length, y: up.y / length };
    const lift = (wrist: Vec | undefined, shoulder: Vec): number =>
      wrist ? ((wrist.x - shoulder.x) * unit.x + (wrist.y - shoulder.y) * unit.y) / width : -1;
    return { leftLift: lift(at(LEFT_WRIST), ls), rightLift: lift(at(RIGHT_WRIST), rs), tracked: true };
  }

  /** Feed one frame; returns a gesture when one is completed. */
  accept(points: LocalGestureKeypoint[]): LocalGestureName | undefined {
    const frame = LocalGestureClassifier.measure(points);
    let leftLift = frame.leftLift;
    let rightLift = frame.rightLift;
    if (this.mirrored) {
      const swap = leftLift;
      leftLift = rightLift;
      rightLift = swap;
    }
    if (!frame.tracked || (leftLift < LOWER_THRESHOLD && rightLift < LOWER_THRESHOLD)) {
      this.armed = true;
    }
    const left = leftLift > RAISE_THRESHOLD;
    const right = rightLift > RAISE_THRESHOLD;
    if (left === this.pendingLeft && right === this.pendingRight) {
      this.pendingCount += 1;
    } else {
      this.pendingLeft = left;
      this.pendingRight = right;
      this.pendingCount = 1;
    }
    if (this.pendingCount < STABLE_FRAMES || (!left && !right) || !this.armed) {
      return undefined;
    }
    this.armed = false;
    if (left && right) {
      return LocalGestureName.RaiseBoth;
    }
    return left ? LocalGestureName.RaiseLeft : LocalGestureName.RaiseRight;
  }

  reset(): void {
    this.pendingLeft = false;
    this.pendingRight = false;
    this.pendingCount = 0;
    this.armed = true;
  }
}
