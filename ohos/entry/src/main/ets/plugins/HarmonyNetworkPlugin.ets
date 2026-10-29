import { FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCall, MethodResult, EventChannel, EventSink, Any } from '@ohos/flutter_ohos';
import connection from '@ohos.net.connection';
import { BusinessError } from '@ohos.base';

export function harmonyNetworkState(available: boolean, capabilities?: connection.NetCapabilities, blocked: boolean = false): string {
  if (!available || blocked) { return 'offline'; }
  const values = capabilities?.networkCap;
  if (!values) { return 'checking'; }
  if (!values.includes(connection.NetCap.NET_CAPABILITY_INTERNET)) { return 'offline'; }
  return values.includes(connection.NetCap.NET_CAPABILITY_VALIDATED) ? 'online' : 'checking';
}

/** Default-route events only: no timed connectivity requests or account probes. */
export default class HarmonyNetworkPlugin implements FlutterPlugin {
  private channel?: MethodChannel;
  private events?: EventChannel;
  private sink: EventSink | null = null;
  private net?: connection.NetConnection;
  private generation = 0;
  private lastState = '';
  private blocked = new Map<number, boolean>();
  getUniqueClassName(): string { return 'HarmonyNetworkPlugin'; }
  private current(): string {
    try {
      const net = connection.getDefaultNetSync();
      if (net.netId === 0) { return 'offline'; }
      return harmonyNetworkState(true, connection.getNetCapabilitiesSync(net), this.blocked.get(net.netId) === true);
    } catch (_) { return 'unknown'; }
  }
  private emit(generation: number, state: string = this.current()): void {
    if (generation !== this.generation || state === this.lastState) { return; }
    this.lastState = state; this.sink?.success(state);
  }
  private unregister(net: connection.NetConnection): void {
    try { net.unregister((_error: BusinessError): void => {}); } catch (_) {}
  }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/network_status');
    this.channel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (call.method !== 'current') { result.notImplemented(); return; }
      result.success(this.current());
    } });
    this.events = new EventChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/network_events');
    this.events.setStreamHandler({ onListen: (_args: Any, sink: EventSink): void => {
      this.stop(); this.sink = sink; const generation = this.generation;
      this.emit(generation);
      try {
        const net = connection.createNetConnection(); this.net = net;
        const emit = (): void => this.emit(generation);
        net.on('netAvailable', emit);
        net.on('netLost', (handle: connection.NetHandle): void => { if (generation !== this.generation) { return; } this.blocked.delete(handle.netId); emit(); });
        net.on('netUnavailable', emit);
        net.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo): void => {
          if (generation !== this.generation) { return; }
          try {
            if (connection.getDefaultNetSync().netId !== info.netHandle.netId) { return; }
            this.emit(generation, harmonyNetworkState(true, info.netCap, this.blocked.get(info.netHandle.netId) === true));
          } catch (_) { this.emit(generation, 'unknown'); }
        });
        net.on('netBlockStatusChange', (info: connection.NetBlockStatusInfo): void => {
          if (generation !== this.generation) { return; }
          this.blocked.set(info.netHandle.netId, info.blocked); emit();
        });
        net.register((error: BusinessError): void => {
          if (generation !== this.generation) { this.unregister(net); return; }
          this.emit(generation, error ? 'unknown' : this.current());
        });
      } catch (_) { this.emit(generation, 'unknown'); }
    }, onCancel: (_args: Any): void => this.stop() });
  }
  private stop(): void {
    this.generation++; this.sink = null; this.lastState = ''; this.blocked.clear();
    const net = this.net; this.net = undefined;
    if (net) { this.unregister(net); }
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.stop(); this.events?.setStreamHandler(null); this.channel?.setMethodCallHandler(null);
    this.events = undefined; this.channel = undefined;
  }
}
