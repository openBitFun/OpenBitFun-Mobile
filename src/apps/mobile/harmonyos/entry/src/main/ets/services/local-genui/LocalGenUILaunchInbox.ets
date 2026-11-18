/**
 * App ids opened from a home-screen card. `EntryAbility` delivers them before
 * or after the page exists: a cold start parks the id until the page
 * subscribes, a warm start (`onNewWant`) hands it over right away.
 */
export class LocalGenUILaunchInbox {
  private static pending: string = '';
  private static listener?: (appId: string) => void;

  static deliver(appId: string): void {
    if (appId.length === 0) {
      return;
    }
    const listener = LocalGenUILaunchInbox.listener;
    if (listener) {
      listener(appId);
    } else {
      LocalGenUILaunchInbox.pending = appId;
    }
  }

  static subscribe(listener: (appId: string) => void): void {
    LocalGenUILaunchInbox.listener = listener;
    const pending = LocalGenUILaunchInbox.pending;
    LocalGenUILaunchInbox.pending = '';
    if (pending.length > 0) {
      listener(pending);
    }
  }

  static unsubscribe(): void {
    LocalGenUILaunchInbox.listener = undefined;
  }
}
