import { createContext, useContext } from 'react';
import type { ActionPlan } from '@openuidev/react-lang';

export type CalendarCreateStatus = 'pending' | 'added';
export interface GenUICalendarStatus {
  ready: boolean;
  statuses: ReadonlyMap<string, CalendarCreateStatus>;
}
export const GenUICalendarStatusContext = createContext<GenUICalendarStatus | undefined>(undefined);

/** Stable across object property order, including the action's nested event. */
export function calendarActionKey(params: Record<string, unknown>): string {
  return JSON.stringify(params, (_key, value: unknown) => value && typeof value === 'object' && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b))) : value);
}

/** Only pure calendar-create buttons get the calendar completion label. */
export function useCalendarButtonStatus(plan: unknown): CalendarCreateStatus | 'loading' | undefined {
  const context = useContext(GenUICalendarStatusContext);
  const steps = (plan as ActionPlan | undefined)?.steps;
  if (!context || !steps?.length || !steps.every(step => step.type === 'custom_action' && step.name === 'CreateCalendarEvent')) return undefined;
  if (!context.ready) return 'loading';
  const statuses = steps.map(step => step.type === 'custom_action' ? context.statuses.get(calendarActionKey(step.params)) : undefined);
  if (statuses.every(status => status === 'added')) return 'added';
  return statuses.some(status => status === 'pending') ? 'pending' : undefined;
}
