import { createContext, useContext } from "react";
import { messages, type Locale, type MessageKey } from "./messages";

export const LocaleContext = createContext<Locale>("en-US");

export function useI18n() {
  const locale = useContext(LocaleContext);
  return { t: (key: MessageKey) => messages[locale][key] };
}
