export interface LocalGenUICalendarReceiptPort {
  calendarReceipts(appId: string): Promise<string[]>;
  saveCalendarReceipt(appId: string, paramsJson: string): Promise<void>;
}

/** Successful creates belong to the app and event payload, not a button position. */
export class LocalGenUICalendarActions {
  private readonly pending: Map<string, Promise<string>> = new Map<string, Promise<string>>();
  private readonly completed: Set<string> = new Set<string>();
  private readonly receipts: LocalGenUICalendarReceiptPort;
  constructor(receipts: LocalGenUICalendarReceiptPort) {
    this.receipts = receipts;
  }

  create(appId: string, params: Object, execute: () => Promise<string>): Promise<string> {
    const payload = JSON.stringify(params);
    const key = JSON.stringify([appId, payload]);
    const existing = this.pending.get(key);
    if (existing) return existing;
    const request = this.run(appId, payload, key, execute);
    this.pending.set(key, request);
    void request.finally(() => { this.pending.delete(key); });
    return request;
  }

  private async run(appId: string, payload: string, key: string, execute: () => Promise<string>): Promise<string> {
    try {
      if (this.completed.has(key) || (await this.receipts.calendarReceipts(appId)).indexOf(payload) >= 0) return '';
      const error = await execute();
      if (error.length > 0) return error;
      // Keep the in-process receipt even if durable storage fails after the OS created the event.
      this.completed.add(key);
      await this.receipts.saveCalendarReceipt(appId, payload);
      return '';
    } catch (error) {
      return String(error);
    }
  }
}
