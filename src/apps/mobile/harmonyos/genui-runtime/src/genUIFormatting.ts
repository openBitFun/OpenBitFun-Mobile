import { i18nService } from './local-runtime/i18n';
export function formatGenUINumber(value: number, decimals = 2): string {
  return i18nService.formatNumber(value, { minimumFractionDigits: decimals, maximumFractionDigits: decimals, useGrouping: false });
}
