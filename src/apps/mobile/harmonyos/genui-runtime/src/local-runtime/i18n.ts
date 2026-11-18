import { useSyncExternalStore } from 'react';
import en from './en-US.json';
import zh from './zh-CN.json';

type Locale = 'en-US' | 'zh-CN';
type Catalog = { [key: string]: Catalog | string };
const catalogs: Record<Locale, Catalog> = { 'en-US': en, 'zh-CN': zh };
const listeners = new Set<() => void>();
let locale: Locale = 'zh-CN';

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

function translate(language: Locale, key: string, values?: Record<string, unknown>): string {
  let value: Catalog | string | undefined = catalogs[language];
  for (const segment of key.split('.')) {
    value = typeof value === 'object' ? value[segment] : undefined;
  }
  if (typeof value !== 'string') return key;
  return value.replace(/\{\{\s*(\w+)\s*\}\}/g, (match, name: string) =>
    values?.[name] == null ? match : String(values[name]));
}

export const i18nService = {
  setLocale(next: Locale) {
    if (next === locale) return;
    locale = next;
    document.documentElement.lang = locale;
    listeners.forEach(listener => listener());
  },
  formatNumber(value: number, options?: Intl.NumberFormatOptions) {
    return new Intl.NumberFormat(locale, options).format(value);
  },
  formatDate(value: Date, options?: Intl.DateTimeFormatOptions) {
    return new Intl.DateTimeFormat(locale, options).format(value);
  },
};

export function useI18n(_namespace: 'flow-chat') {
  const language = useSyncExternalStore(subscribe, () => locale);
  return { t: (key: string, values?: Record<string, unknown>) => translate(language, key, values) };
}
