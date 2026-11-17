interface NetworkFailure {
  code?: number;
  statusCode?: number;
  message?: string;
}

/** Presentation keys only: never change transport errors or retry a mutation here. */
export class NetworkErrorPolicy {
  static messageKey(error: Object): string {
    const failure = error as NetworkFailure;
    const text = (failure.message || JSON.stringify(error) || '').toLowerCase();
    // A lost acknowledgement does not mean the operation failed on the host.
    if (text.includes('delivery outcome is unknown')) return 'errors.deliveryUnknown';
    // Legacy wrappers sometimes retain only the SDK code in their message.
    const embedded = text.match(/(?:code["\s]*[:=]\s*)(230\d{4})\b/);
    const code = failure.code !== undefined ? failure.code : embedded ? Number(embedded[1]) : undefined;
    if (code === 2300028) return 'account.errorTimeout';
    if (code === 2300035 || code === 2300060 || code === 2300058 || code === 2300059) {
      return 'account.errorSecureConnection';
    }
    if ((code !== undefined && code >= 2300000 && code < 2301000) || text.includes('account transport failed')) return 'account.errorNetwork';
    if (failure.statusCode === 401 || /\bhttp 401\b/.test(text)) return 'remote.settings.accountExpired';
    if (failure.statusCode === 429 || /\bhttp 429\b/.test(text)) return 'account.errorRateLimited';
    if ((failure.statusCode !== undefined && failure.statusCode >= 500 && failure.statusCode < 600) ||
      /\bhttp 5\d\d\b/.test(text)) return 'errors.serviceUnavailable';
    if (/(connection|request|network|rpc|health probe).*(timed out|timeout)|\betimedout\b/.test(text)) {
      return 'account.errorTimeout';
    }
    if (/(ssl|tls|certificate).*(failed|error|invalid|expired)/.test(text)) return 'account.errorSecureConnection';
    if (/(could not|couldn't|cannot|unable to) resolve|\bdns\b|\benotfound\b|\beconn(refused|reset)\b|network (is )?(unreachable|unavailable|error)|no network|failed to fetch/.test(text) ||
      /relay.*(closed|disconnected|connection (lost|changed))|remote transport is not connected|websocket.*(failed|error|closed)/.test(text)) {
      return 'account.errorNetwork';
    }
    return '';
  }
}
