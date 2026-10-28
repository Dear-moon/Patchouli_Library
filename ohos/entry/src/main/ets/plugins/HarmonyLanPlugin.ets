import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import mdns from '@ohos.net.mdns';
import deviceInfo from '@ohos.deviceInfo';
import util from '@ohos.util';
import { BusinessError } from '@ohos.base';

export function privateLanHost(host: string): boolean {
  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) { return false; }
  const octets = host.split('.').map((value: string): number => Number(value));
  if (octets.some((value: number): boolean => value < 0 || value > 255)) { return false; }
  return octets[0] === 10 || octets[0] === 127 || octets[0] === 192 && octets[1] === 168 ||
    octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31 || octets[0] === 169 && octets[1] === 254;
}

export interface NearbyDevice { id: string; name: string; host: string; port: number; }
export type LanEventObserver = (method: string, value: Object | null) => void;

/** DNS-SD carries only identity and endpoint. Dart owns pairing and encrypted transfers. */
export default class HarmonyLanPlugin implements FlutterPlugin, MethodCallHandler {
  private context: common.UIAbilityContext;
  private channel: MethodChannel | null = null;
  private discovery?: mdns.DiscoveryService;
  private advertised?: mdns.LocalServiceInfo;
  private epoch = 0;
  private ownId = '';
  private found = new Map<string, NearbyDevice>();
  private present = new Set<string>();
  private resolving = new Set<string>();
  private queue: Promise<void> = Promise.resolve();
  private observer?: LanEventObserver;
  constructor(context: common.UIAbilityContext, observer?: LanEventObserver) { this.context = context; this.observer = observer; }
  getUniqueClassName(): string { return 'HarmonyLanPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/lan_discovery');
    this.channel.setMethodCallHandler(this);
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'start' && call.method !== 'stop') { result.notImplemented(); return; }
    this.queue = this.queue.then(async (): Promise<void> => {
      let stage = 'arguments';
      try {
        if (call.method === 'stop') { await this.stop(); result.success(null); return; }
        const id = call.argument('id') as string, port = call.argument('port') as number;
        if (typeof id !== 'string' || !/^[a-f0-9]{32}$/.test(id) || !Number.isInteger(port) || port < 1024 || port > 65535) { throw new Error('Invalid advertisement'); }
        await this.stop(); this.ownId = id;
        const generation = this.epoch;
        const name = (deviceInfo.marketName || deviceInfo.productModel || '鸿蒙设备').trim().substring(0, 60);
        const encoder = new util.TextEncoder();
        const service: mdns.LocalServiceInfo = { serviceType: '_wenkuread._tcp', serviceName: 'wenku-' + id.substring(0, 12), port: port,
          serviceAttribute: [
            { key: 'id', value: Array.from(encoder.encodeInto(id)) },
            { key: 'name', value: Array.from(encoder.encodeInto(name)) },
            { key: 'v', value: [49] }
          ] };
        stage = 'advertise'; this.advertised = await mdns.addLocalService(this.context, service);
        if (generation !== this.epoch) { await this.stop(); result.success(name); return; }
        stage = 'create_discovery'; const discovery = mdns.createDiscoveryService(this.context, '_wenkuread._tcp');
        this.discovery = discovery;
        discovery.on('discoveryStart', (event: mdns.DiscoveryEventInfo): void => {
          if (generation !== this.epoch) { return; }
          if (event.errorCode !== undefined) { this.failed(generation, 'discovery_start', event.errorCode); }
          else { this.emit('ready', null); }
        });
        discovery.on('serviceFound', (info: mdns.LocalServiceInfo): void => {
          if (generation !== this.epoch || info.serviceType.replace(/\.$/, '') !== '_wenkuread._tcp' ||
            !info.serviceName.startsWith('wenku-') || this.present.size >= 64) { return; }
          this.present.add(info.serviceName);
          this.resolve(info, generation);
        });
        discovery.on('serviceLost', (info: mdns.LocalServiceInfo): void => {
          if (generation !== this.epoch) { return; }
          this.present.delete(info.serviceName); this.found.delete(info.serviceName); this.publish();
        });
        discovery.on('discoveryStop', (event: mdns.DiscoveryEventInfo): void => {
          if (generation === this.epoch) { this.failed(generation, 'discovery_stop', event.errorCode); }
        });
        stage = 'start_discovery'; discovery.startSearchingMDNS(); result.success(name);
      } catch (error) {
        await this.stop(); result.error('LAN_DISCOVERY', '自动发现暂不可用，请检查本地网络权限',
          new Map<string, string>([['stage', stage], ['code', String((error as BusinessError).code ?? '')]]));
      }
    });
  }
  private resolve(info: mdns.LocalServiceInfo, generation: number): void {
    if (this.resolving.has(info.serviceName)) { return; }
    this.resolving.add(info.serviceName);
    mdns.resolveLocalService(this.context, info).then((value: mdns.LocalServiceInfo): void => {
      if (generation !== this.epoch || !this.present.has(info.serviceName)) { return; }
      const attributes = new Map<string, string>();
      try {
        for (const attribute of value.serviceAttribute ?? []) {
          if (attribute.value.length > 256) { return; }
          attributes.set(attribute.key, util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(attribute.value)));
        }
      } catch (_) { return; }
      const id = attributes.get('id') ?? '', name = attributes.get('name') ?? '';
      const host = value.host?.address ?? '', port = value.port ?? 0;
      if (id === this.ownId || !/^[a-f0-9]{32}$/.test(id) || !name.trim() || name.length > 64 || attributes.get('v') !== '1' ||
        !privateLanHost(host) || !Number.isInteger(port) || port < 1024 || port > 65535) { return; }
      this.found.set(info.serviceName, { id: id, name: name, host: host, port: port }); this.publish();
    }).catch((): void => { /* One unresolvable announcement must not stop other nearby devices. */ })
      .finally((): void => { if (generation === this.epoch) { this.resolving.delete(info.serviceName); } });
  }
  private emit(method: string, value: Object | null): void {
    this.channel?.invokeMethod(method, value); this.observer?.(method, value);
  }
  private publish(): void { this.emit('devices', Array.from(this.found.values())); }
  private failed(generation: number, stage: string, code?: number): void {
    if (generation !== this.epoch) { return; }
    this.queue = this.queue.then(async (): Promise<void> => {
      if (generation !== this.epoch) { return; }
      await this.stop(); this.emit('failure', new Map<string, string>([['stage', stage], ['code', String(code ?? '')]]));
    });
  }
  private async stop(): Promise<void> {
    this.epoch++;
    const discovery = this.discovery; this.discovery = undefined;
    if (discovery) {
      try { discovery.off('discoveryStart'); discovery.off('discoveryStop'); discovery.off('serviceFound'); discovery.off('serviceLost'); }
      catch (_) { /* Stale callbacks are already excluded by the epoch. */ }
      try { discovery.stopSearchingMDNS(); } catch (_) { /* Already stopped. */ }
    }
    const advertised = this.advertised; this.advertised = undefined;
    if (advertised) { try { await mdns.removeLocalService(this.context, advertised); } catch (_) { /* Service may already be removed on network loss. */ } }
    this.present.clear(); this.resolving.clear(); this.found.clear(); this.publish();
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null); this.channel = null;
    this.queue = this.queue.then((): Promise<void> => this.stop());
  }
}
