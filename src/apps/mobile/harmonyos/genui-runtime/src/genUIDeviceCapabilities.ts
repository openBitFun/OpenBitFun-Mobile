import { createContext, useContext } from 'react';

/**
 * Device capabilities a GenUI component may request from its host.
 *
 * Components never touch sensors, cameras or vibration directly: a host that
 * owns those capabilities provides this port (Harmony Local GenUI does), and
 * every other host leaves it absent so components render an explicit
 * "unavailable" state instead of pretending to work.
 */
export type GenUIGesture = 'raise_left_hand' | 'raise_right_hand' | 'raise_both_hands';
export type GenUIHaptic = 'none' | 'light' | 'medium' | 'heavy';
export type GenUICollaborationKind = 'photo' | 'scan' | 'gallery';
export interface GenUICollaborationResult {
  status: 'pending' | 'completed' | 'cancelled' | 'failed' | 'unavailable';
  asset?: string;
  reason?: string;
}
export interface GenUICollaborationPort {
  available: boolean;
  reason: string;
  start(kind: GenUICollaborationKind, onResult: (result: GenUICollaborationResult) => void): () => void;
}

/**
 * Lifecycle of a gesture subscription as reported by the host.
 *
 * `unavailable` means the device cannot serve this capability at all, while
 * `failed` is a transient runtime failure the host retries on its own.
 */
export type GenUIGestureStatus = 'starting' | 'active' | 'paused' | 'denied' | 'unavailable' | 'failed';

export interface GenUIGestureSubscription {
  gesture: GenUIGesture;
  label: string;
  onGesture: () => void;
  onStatus: (status: GenUIGestureStatus) => void;
}

export interface GenUIDeviceCapabilityPort {
  /** Native user-mediated cross-device image input; absent on unsupported hosts. */
  collaboration?: GenUICollaborationPort;
  /** Returns an unsubscribe function; the host stops the camera when none remain. */
  subscribeGesture(subscription: GenUIGestureSubscription): () => void;
  haptic(kind: GenUIHaptic): void;
  /** Optional window preference; absent on hosts that do not control orientation. */
  setOrientation?(orientation: 'auto' | 'portrait' | 'landscape'): void;
}

export const GenUIDeviceCapabilitiesContext = createContext<GenUIDeviceCapabilityPort | undefined>(undefined);

export function useGenUIDeviceCapabilities(): GenUIDeviceCapabilityPort | undefined {
  return useContext(GenUIDeviceCapabilitiesContext);
}
