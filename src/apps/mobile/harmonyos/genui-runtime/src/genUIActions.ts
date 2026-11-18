import { defineAction, type ActionEvent } from '@openuidev/react-lang';
import { z } from 'zod/v4';

/**
 * Open Intelligent UI's small host action surface. Actions are deliberately
 * separate from pure library functions: they run only after a user gesture
 * and are delivered through the owning host callback.
 */
export const copyToClipboardAction = defineAction({
  name: 'CopyToClipboard',
  description: 'Copy text to the clipboard, for example a list built with @Join',
  params: z.object({ text: z.string() }),
});

const calendarTime = z.union([z.string(), z.number()]);
const recurrence = z.object({
  frequency: z.enum(['daily', 'weekly', 'monthly', 'yearly']),
  interval: z.number().int().positive().optional(),
  count: z.number().int().positive().optional(),
  expire: calendarTime.optional(),
}).optional();
const calendarEvent = z.object({
  title: z.string().min(1),
  startTime: calendarTime,
  endTime: calendarTime,
  description: z.string().optional(),
  location: z.string().optional(),
  reminderMinutes: z.union([z.number().int().nonnegative(), z.array(z.number().int().nonnegative())]).optional(),
  recurrence,
});
const calendarEventPatch = z.object({
  id: z.number().int().positive(),
  title: z.string().min(1),
  startTime: calendarTime,
  endTime: calendarTime,
  description: z.string().optional(),
  location: z.string().optional(),
  reminderMinutes: z.union([z.number().int().nonnegative(), z.array(z.number().int().nonnegative())]).optional(),
  recurrence,
});

/** Calendar Kit actions are delivered to the native Local GenUI host. */
export const createCalendarEventAction = defineAction({
  name: 'CreateCalendarEvent',
  description: 'Create an event in the OpenBitFun calendar. startTime and endTime are ISO timestamps or epoch milliseconds.',
  params: z.object({ event: calendarEvent }),
});

export const updateCalendarEventAction = defineAction({
  name: 'UpdateCalendarEvent',
  description: 'Update an OpenBitFun calendar event by id.',
  params: z.object({ event: calendarEventPatch }),
});

export const deleteCalendarEventAction = defineAction({
  name: 'DeleteCalendarEvent',
  description: 'Delete an OpenBitFun calendar event by id.',
  params: z.object({ id: z.number().int().positive() }),
});

export const listCalendarEventsAction = defineAction({
  name: 'ListCalendarEvents',
  description: 'List OpenBitFun calendar events, optionally between two timestamps.',
  params: z.object({ filter: z.object({ startTime: calendarTime.optional(), endTime: calendarTime.optional() }) }),
});

export const genUIActions = [
  copyToClipboardAction,
  createCalendarEventAction,
  updateCalendarEventAction,
  deleteCalendarEventAction,
  listCalendarEventsAction,
];

async function copyText(text: string): Promise<boolean> {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    // Fall through to the compatibility path used by WebViews without the
    // Clipboard API or without a secure origin.
  }
  const textarea = document.createElement('textarea');
  try {
    textarea.value = text;
    textarea.setAttribute('readonly', '');
    textarea.style.cssText = 'position:fixed;opacity:0;pointer-events:none';
    document.body.append(textarea);
    textarea.select();
    return document.execCommand('copy');
  } catch {
    return false;
  } finally {
    textarea.remove();
  }
}

/** Runs a product action and returns null for actions owned by the caller. */
export function runGenUIAction(event: Pick<ActionEvent, 'type' | 'params'>): Promise<boolean> | null {
  if (event.type !== copyToClipboardAction.name) return null;
  const text = event.params?.text;
  return typeof text === 'string' ? copyText(text) : Promise.resolve(false);
}
