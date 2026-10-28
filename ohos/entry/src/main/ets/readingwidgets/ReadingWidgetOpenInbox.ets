export interface ReadingWidgetOpenRequest {
  ticket: number;
  destination: string;
}

/** Widget navigation is independent of external book-import requests. */
export default class ReadingWidgetOpenInbox {
  private static nextTicket: number = 0;
  private static request: ReadingWidgetOpenRequest | null = null;
  static onAvailable: (() => void) | null = null;

  static offer(destination: string): boolean {
    if (destination !== 'statistics' && destination !== 'moments' && destination !== 'continue' && destination !== 'excerpts' && !/^configure:[0-9]{1,32}$/.test(destination)) { return false; }
    ReadingWidgetOpenInbox.nextTicket++;
    ReadingWidgetOpenInbox.request = { ticket: ReadingWidgetOpenInbox.nextTicket, destination: destination };
    ReadingWidgetOpenInbox.onAvailable?.();
    return true;
  }

  static peek(): ReadingWidgetOpenRequest | null {
    const request: ReadingWidgetOpenRequest | null = ReadingWidgetOpenInbox.request;
    return request === null ? null : { ticket: request.ticket, destination: request.destination };
  }

  static ack(ticket: number): boolean {
    if (ReadingWidgetOpenInbox.request?.ticket !== ticket) { return false; }
    ReadingWidgetOpenInbox.request = null;
    return true;
  }

  /** Atomically transfer ownership before invoking Dart, not after its reply. */
  static claim(): ReadingWidgetOpenRequest | null {
    const request = ReadingWidgetOpenInbox.peek();
    if (request !== null) { ReadingWidgetOpenInbox.request = null; }
    return request;
  }

  /** Failed deliveries can return only the latest tap; never revive an older route. */
  static restore(request: ReadingWidgetOpenRequest): boolean {
    if (request.ticket !== ReadingWidgetOpenInbox.nextTicket || ReadingWidgetOpenInbox.request !== null ||
      (request.destination !== 'statistics' && request.destination !== 'moments' && request.destination !== 'continue' && request.destination !== 'excerpts' && !/^configure:[0-9]{1,32}$/.test(request.destination))) { return false; }
    ReadingWidgetOpenInbox.request = { ticket: request.ticket, destination: request.destination };
    // No automatic retry here: failure waits for the next Dart-ready handshake.
    return true;
  }

  static consume(): string | null {
    const request: ReadingWidgetOpenRequest | null = ReadingWidgetOpenInbox.claim();
    if (request === null) { return null; }
    return request.destination;
  }
}
