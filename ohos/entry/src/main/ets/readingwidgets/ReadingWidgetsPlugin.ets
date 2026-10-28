import { Any, FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import ReadingWidgetOpenInbox, { ReadingWidgetOpenRequest } from './ReadingWidgetOpenInbox';
import ReadingWidgetStore from './ReadingWidgetStore';

/** One shared channel: persisted snapshots and acknowledged widget navigation. */
export default class ReadingWidgetsPlugin implements FlutterPlugin {
  private channel?: MethodChannel;
  private store?: ReadingWidgetStore;
  private generation: number = 0;
  private ready: boolean = false;
  private inFlight: ReadingWidgetOpenRequest | null = null;
  private available: (() => void) | null = null;
  private publications: Promise<void> = Promise.resolve();

  getUniqueClassName(): string { return 'ReadingWidgetsPlugin'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.detach();
    this.store = new ReadingWidgetStore(binding.getApplicationContext());
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/reading_widgets');
    this.channel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      switch (call.method) {
        case 'cardsSupported': result.success(true); return;
        case 'completeConfiguration': result.success(null); return; // Form configuration returns through the shared page.
        case 'publishCards': {
          const store = this.store;
          if (store === undefined) { result.error('reading_widget_cards', '小组件尚未准备好', null); return; }
          const operation = this.publications.then((): Promise<void> => store.publishCards(JSON.stringify(call.argument('cards'))));
          this.publications = operation.catch((_error: Error): void => {});
          operation.then((): void => result.success(null)).catch((_error: Error): void => result.error('reading_widget_cards', '小组件暂未更新', null)); return;
        }
        case 'bindCard': {
          this.store?.bindCard(call.argument('widgetId') as string, call.argument('cardId') as string)
            .then((): void => result.success(null)).catch((_error: Error): void => result.error('reading_widget_bind', '小组件未能设置', null)); return;
        }
        case 'publishSnapshot': this.publish(call, result); return;
        case 'consumeOpenRequest':
          // The first Dart poll establishes that its method handler is installed.
          this.ready = true;
          // Warm delivery already owns navigation until its callback settles.
          // A simultaneous resume poll must not navigate to the same route twice.
          result.success(this.inFlight === null ? ReadingWidgetOpenInbox.consume() : null);
          this.deliver();
          return;
        default: result.notImplemented();
      }
    } });
    this.available = (): void => this.deliver();
    ReadingWidgetOpenInbox.onAvailable = this.available;
    // Cold requests stay queued until Dart explicitly performs its first poll.
  }

  private publish(call: MethodCall, result: MethodResult): void {
    const json: string = call.argument('json') as string;
    const store: ReadingWidgetStore | undefined = this.store;
    if (typeof json !== 'string' || store === undefined) {
      result.error('reading_widget_snapshot', '无法更新阅读小组件', null);
      return;
    }
    // Keep publication order even when an earlier validation or write fails.
    const operation: Promise<void> = this.publications.then((): Promise<void> => store.publish(json));
    this.publications = operation.catch((_error: Error): void => {});
    operation.then((): void => result.success(null))
      .catch((_error: Error): void => result.error('reading_widget_snapshot', '无法更新阅读小组件', null));
  }

  private deliver(): void {
    const channel: MethodChannel | undefined = this.channel;
    if (!this.ready || channel === undefined || this.inFlight !== null ||
      ReadingWidgetOpenInbox.onAvailable !== this.available) { return; }
    const request = ReadingWidgetOpenInbox.claim();
    if (request === null) { return; }
    const generation: number = this.generation;
    const ticket: number = request.ticket;
    this.inFlight = request;
    const complete = (accepted: boolean): void => {
      if (generation !== this.generation || this.inFlight?.ticket !== ticket) { return; }
      this.inFlight = null;
      if (!accepted) { ReadingWidgetOpenInbox.restore(request); }
      const next = ReadingWidgetOpenInbox.peek();
      // A failed call remains recoverable by consumeOpenRequest/new activity,
      // but is not recursively retried while Dart has no usable route handler.
      if (next !== null && next.ticket !== ticket) { ReadingWidgetOpenInbox.onAvailable?.(); }
    };
    try {
      channel.invokeMethod('openReadingSurface', request.destination, {
        success: (_value: Any): void => complete(true),
        error: (_code: string, _message: string, _details: Any): void => complete(false),
        notImplemented: (): void => complete(false)
      });
    } catch (_) { complete(false); }
  }

  private detach(): void {
    const released = this.inFlight !== null ? ReadingWidgetOpenInbox.restore(this.inFlight) : false;
    this.generation++;
    this.ready = false;
    this.inFlight = null;
    if (ReadingWidgetOpenInbox.onAvailable === this.available) { ReadingWidgetOpenInbox.onAvailable = null; }
    this.available = null;
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
    this.store = undefined;
    // Pending cold/warm requests belong to the process, not this engine.
    // If a replacement engine is already ready, hand its listener the released tap.
    if (released) { ReadingWidgetOpenInbox.onAvailable?.(); }
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void { this.detach(); }
}
