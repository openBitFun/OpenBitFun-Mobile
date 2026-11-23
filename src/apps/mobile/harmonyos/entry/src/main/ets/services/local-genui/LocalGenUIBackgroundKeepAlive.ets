/** Platform-neutral lease used to keep a local provider request alive in background. */
export interface LocalGenUIBackgroundKeepAlive {
  keepAlive(onExpired: () => void): boolean;
  releaseKeepAlive(): void;
}
