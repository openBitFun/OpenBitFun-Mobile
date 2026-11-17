import { NetworkErrorPolicy } from '../../services/NetworkErrorPolicy';

/** Present structured failures without exposing SDK messages or response bodies. */
export class AccountLoginErrorPolicy {
  static messageKey(error: Object): string {
    return NetworkErrorPolicy.messageKey(error) || 'remote.settings.accountLoginFailed';
  }
}
