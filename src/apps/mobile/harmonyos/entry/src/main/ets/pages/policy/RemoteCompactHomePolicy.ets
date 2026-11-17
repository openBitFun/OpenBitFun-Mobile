/** Cached sessions remain stored, but remote entry points require a live host. */
export class RemoteCompactHomePolicy {
  static shouldShowInitialLoading(connectionState: string, sessionCount: number, loadingHome: boolean): boolean {
    // Recovery keeps the existing surface, including an already empty home.
    if (sessionCount > 0 || connectionState === 'reconnecting') return false;
    return loadingHome || connectionState === 'parsing' || connectionState === 'pairing';
  }

  static shouldShowRecentSessions(connected: boolean): boolean {
    return connected;
  }

  static shouldShowWelcomeHome(controlTargetType: string, connectionState: string, signedIn: boolean = false): boolean {
    return !signedIn && controlTargetType === 'none' && connectionState !== 'connected';
  }

  static shouldShowConnectHome(connectionState: string): boolean {
    return connectionState !== 'connected';
  }

  static headerSubtitle(connectionState: string, desktopName: string): string {
    // Recovery retains the selected device context; health belongs in the sidebar.
    if (connectionState !== 'connected' && connectionState !== 'reconnecting') {
      return '';
    }
    return desktopName;
  }
}
