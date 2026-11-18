import { vibrator } from '@kit.SensorServiceKit';

/** Short vibration feedback for Local GenUI apps; failures are silent by design. */
export class LocalGenUIHaptics {
  static play(kind: string): void {
    const duration = kind === 'heavy' ? 60 : kind === 'medium' ? 35 : kind === 'light' ? 18 : 0;
    if (duration <= 0) {
      return;
    }
    try {
      vibrator.startVibration({ type: 'time', duration }, { id: 0, usage: 'touch' }).catch(() => {});
    } catch (_err) {
      // A device without a vibrator simply gives no feedback.
    }
  }
}
