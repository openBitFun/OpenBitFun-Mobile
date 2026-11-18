import { abilityAccessCtrl, Context, Permissions } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import { MobileDesignColors } from '../../generated/MobileDesignTokens';
import { RemoteLogger } from '../RemoteLogger';

const READ_CALENDAR: Permissions = 'ohos.permission.READ_CALENDAR';
const WRITE_CALENDAR: Permissions = 'ohos.permission.WRITE_CALENDAR';
const CALENDAR_NAME: string = 'OpenBitFun';
const MAX_TITLE_LENGTH: number = 256;
const MAX_TEXT_LENGTH: number = 4000;
const MAX_REMINDERS: number = 5;

export type HarmonyCalendarAction = 'CreateCalendarEvent' | 'UpdateCalendarEvent' | 'DeleteCalendarEvent' | 'ListCalendarEvents';

export interface HarmonyCalendarActionResult {
  ok: boolean;
  kind: 'created' | 'updated' | 'deleted' | 'listed' | 'failed';
  eventId?: number;
  count?: number;
  error?: string;
}

interface CalendarActionParams {
  id?: Object;
  title?: Object;
  startTime?: Object;
  endTime?: Object;
  description?: Object;
  location?: Object;
  reminderMinutes?: Object;
  recurrence?: Object;
}

interface RecurrenceParams {
  frequency?: Object;
  interval?: Object;
  count?: Object;
  expire?: Object;
}

/**
 * Calendar Kit adapter for Local GenUI.
 *
 * The adapter owns one application-specific local calendar. It does not use
 * the Huawei Clock alarm store and it never touches calendars created by other
 * applications. Permission is requested only after an explicit GenUI action.
 */
export class HarmonyCalendarService {
  private readonly contextProvider: () => Context;
  private permissionRequest?: Promise<boolean>;
  private manager?: calendarManager.CalendarManager;
  private calendar?: calendarManager.Calendar;

  constructor(contextProvider: () => Context) {
    this.contextProvider = contextProvider;
  }

  async execute(action: HarmonyCalendarAction, rawParams: Object): Promise<HarmonyCalendarActionResult> {
    try {
      const params = HarmonyCalendarService.params(rawParams);
      if (action === 'CreateCalendarEvent') {
        return await this.create(params);
      }
      if (action === 'UpdateCalendarEvent') {
        return await this.update(params);
      }
      if (action === 'DeleteCalendarEvent') {
        return await this.remove(params);
      }
      if (action === 'ListCalendarEvents') {
        return await this.list(params);
      }
      return this.failure('unsupported calendar action');
    } catch (err) {
      const reason = HarmonyCalendarService.errorText(err);
      RemoteLogger.warn(`local genui calendar action failed: ${reason}`);
      return this.failure(reason);
    }
  }

  private async create(params: CalendarActionParams): Promise<HarmonyCalendarActionResult> {
    const event = this.event(params);
    const id = await (await this.ensureCalendar()).addEvent(event);
    return { ok: true, kind: 'created', eventId: id };
  }

  private async update(params: CalendarActionParams): Promise<HarmonyCalendarActionResult> {
    const id = HarmonyCalendarService.number(params.id, 'id', true);
    const event = this.event(params);
    event.id = id;
    await (await this.ensureCalendar()).updateEvent(event);
    return { ok: true, kind: 'updated', eventId: id };
  }

  private async remove(params: CalendarActionParams): Promise<HarmonyCalendarActionResult> {
    const id = HarmonyCalendarService.number(params.id, 'id', true);
    await (await this.ensureCalendar()).deleteEvent(id);
    return { ok: true, kind: 'deleted', eventId: id };
  }

  private async list(params: CalendarActionParams): Promise<HarmonyCalendarActionResult> {
    const calendar = await this.ensureCalendar();
    const start = params.startTime === undefined ? undefined : HarmonyCalendarService.time(params.startTime, 'startTime');
    const end = params.endTime === undefined ? undefined : HarmonyCalendarService.time(params.endTime, 'endTime');
    if (start !== undefined && end !== undefined && end <= start) {
      return this.failure('endTime must be later than startTime');
    }
    const filter = start !== undefined && end !== undefined ? calendarManager.EventFilter.filterByTime(start, end) : undefined;
    const events = await calendar.getEvents(filter);
    return { ok: true, kind: 'listed', count: events.length };
  }

  private async ensureCalendar(): Promise<calendarManager.Calendar> {
    await this.ensurePermission();
    if (this.calendar) {
      return this.calendar;
    }
    if (!this.manager) {
      this.manager = calendarManager.getCalendarManager(this.contextProvider());
    }
    const account: calendarManager.CalendarAccount = {
      name: CALENDAR_NAME,
      type: calendarManager.CalendarType.LOCAL,
      displayName: CALENDAR_NAME
    };
    try {
      this.calendar = await this.manager.getCalendar(account);
    } catch (_err) {
      this.calendar = await this.manager.createCalendar(account);
      await this.calendar.setConfig({ enableReminder: true, color: MobileDesignColors.brandDot.light });
    }
    return this.calendar;
  }

  private async ensurePermission(): Promise<void> {
    if (!this.permissionRequest) {
      this.permissionRequest = this.requestPermission();
    }
    if (!(await this.permissionRequest)) {
      throw new Error('calendar permission denied');
    }
  }

  private async requestPermission(): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(this.contextProvider(), [READ_CALENDAR, WRITE_CALENDAR]);
      return result.authResults.length === 2 &&
        result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED &&
        result.authResults[1] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (err) {
      RemoteLogger.warn(`local genui calendar permission request failed: ${HarmonyCalendarService.errorText(err)}`);
      return false;
    }
  }

  private event(params: CalendarActionParams): calendarManager.Event {
    const title = HarmonyCalendarService.text(params.title, 'title', MAX_TITLE_LENGTH, true);
    const start = HarmonyCalendarService.time(params.startTime, 'startTime', true) as number;
    const end = HarmonyCalendarService.time(params.endTime, 'endTime', true) as number;
    if (start !== undefined && end !== undefined && end <= start) {
      throw new Error('endTime must be later than startTime');
    }
    const event: calendarManager.Event = {
      title,
      startTime: start,
      endTime: end,
      type: calendarManager.EventType.NORMAL
    };
    const description = HarmonyCalendarService.text(params.description, 'description', MAX_TEXT_LENGTH, false);
    const location = HarmonyCalendarService.text(params.location, 'location', MAX_TEXT_LENGTH, false);
    if (description) event.description = description;
    if (location) {
      const place: calendarManager.Location = { location };
      event.location = place;
    }
    const reminders = HarmonyCalendarService.reminders(params.reminderMinutes);
    if (reminders.length > 0) event.reminderTime = reminders;
    const recurrence = HarmonyCalendarService.recurrence(params.recurrence);
    if (recurrence) event.recurrenceRule = recurrence;
    return event;
  }

  private static params(value: Object): CalendarActionParams {
    const raw = value as Record<string, Object>;
    if (raw['event'] && typeof raw['event'] === 'object') return raw['event'] as CalendarActionParams;
    if (raw['filter'] && typeof raw['filter'] === 'object') return raw['filter'] as CalendarActionParams;
    return value as CalendarActionParams;
  }

  private static text(value: Object | undefined, name: string, max: number, required: boolean = false): string {
    if (value === undefined || value === null) {
      if (required) throw new Error(`${name} is required`);
      return '';
    }
    if (typeof value !== 'string' || value.trim().length === 0) {
      if (required) throw new Error(`${name} must be a non-empty string`);
      return '';
    }
    const result = value.trim();
    if (result.length > max) throw new Error(`${name} is too long`);
    return result;
  }

  private static number(value: Object | undefined, name: string, required: boolean = false, minimum: number = 1): number {
    if (value === undefined || value === null || value === '') {
      if (required) throw new Error(`${name} is required`);
      return 0;
    }
    const result = typeof value === 'number' ? value : Number(value);
    if (!Number.isInteger(result) || result < minimum) {
      throw new Error(`${name} must be an integer greater than or equal to ${minimum}`);
    }
    return result;
  }

  private static time(value: Object | undefined, name: string, required: boolean = false): number | undefined {
    if (value === undefined || value === null || value === '') {
      if (required) throw new Error(`${name} is required`);
      return undefined;
    }
    const result = typeof value === 'number' ? value : Date.parse(String(value));
    if (!Number.isFinite(result) || result <= 0) throw new Error(`${name} must be an ISO date or epoch milliseconds`);
    return Math.trunc(result);
  }

  private static reminders(value: Object | undefined): number[] {
    if (value === undefined || value === null || value === '') return [];
    const raw: Object[] = typeof value === 'object' && value !== null
      ? (value as Object[])
      : [value as Object];
    if (raw.length > MAX_REMINDERS) throw new Error('too many reminders');
    const reminders: number[] = raw.map((item: Object): number =>
      HarmonyCalendarService.number(item, 'reminderMinutes', false, 0));
    if (reminders.some(item => item > 10080)) throw new Error('reminderMinutes is too large');
    return reminders;
  }

  private static recurrence(value: Object | undefined): calendarManager.RecurrenceRule | undefined {
    if (!value || typeof value !== 'object') return undefined;
    const input = value as RecurrenceParams;
    const frequency = String(input.frequency || '').toLowerCase();
    let mapped: calendarManager.RecurrenceFrequency;
    if (frequency === 'daily') mapped = calendarManager.RecurrenceFrequency.DAILY;
    else if (frequency === 'weekly') mapped = calendarManager.RecurrenceFrequency.WEEKLY;
    else if (frequency === 'monthly') mapped = calendarManager.RecurrenceFrequency.MONTHLY;
    else if (frequency === 'yearly') mapped = calendarManager.RecurrenceFrequency.YEARLY;
    else throw new Error('recurrence.frequency must be daily, weekly, monthly or yearly');
    const rule: calendarManager.RecurrenceRule = { recurrenceFrequency: mapped };
    if (input.interval !== undefined) rule.interval = HarmonyCalendarService.number(input.interval, 'recurrence.interval');
    if (input.count !== undefined) rule.count = HarmonyCalendarService.number(input.count, 'recurrence.count');
    if (input.expire !== undefined) rule.expire = HarmonyCalendarService.time(input.expire, 'recurrence.expire', true);
    return rule;
  }

  private failure(error: string): HarmonyCalendarActionResult {
    return { ok: false, kind: 'failed', error };
  }

  private static errorText(err: Object): string {
    if (err instanceof Error && err.message.length > 0) return err.message;
    try {
      const text = JSON.stringify(err);
      return text.length > 0 && text !== '{}' ? text : 'unknown error';
    } catch (_jsonErr) {
      return `${err}`;
    }
  }
}
