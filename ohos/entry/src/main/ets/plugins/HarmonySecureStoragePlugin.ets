import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import asset from '@ohos.security.asset';
import crypto from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import { BusinessError } from '@ohos.base';

interface SecureEnvelope { version: number; iv: string; data: string; }

/** Device-bound keys never enter preferences, backups, logs or other devices. */
export class HarmonySecureRecord {
  private context: common.Context;
  private name: string;
  private maximum: number;
  private nullable: boolean;
  private keyPromise?: Promise<crypto.SymKey>;
  private codec = new util.Base64Helper();
  constructor(context: common.Context, name: string, maximum: number, nullable: boolean = true) {
    this.context = context; this.name = name; this.maximum = maximum; this.nullable = nullable;
  }
  private async key(create: boolean): Promise<crypto.SymKey> {
    if (!this.keyPromise) { this.keyPromise = this.loadKey(create); }
    try { return await this.keyPromise; } catch (error) { this.keyPromise = undefined; throw error as Error; }
  }
  private async loadKey(create: boolean): Promise<crypto.SymKey> {
    const alias = new util.TextEncoder().encodeInto('wenku8.' + this.name + '.v1');
    const query = new Map<asset.Tag, asset.Value>([[asset.Tag.ALIAS, alias], [asset.Tag.RETURN_TYPE, asset.ReturnType.ALL]]);
    let bytes: Uint8Array;
    try {
      const records = await asset.query(query);
      if (records.length !== 1) { throw new Error('Secure key unavailable'); }
      bytes = records[0].get(asset.Tag.SECRET) as Uint8Array;
    } catch (error) {
      if (!create || (error as BusinessError).code !== 24000002) { throw error as Error; }
      bytes = (await crypto.createRandom().generateRandom(32)).data;
      await asset.add(new Map<asset.Tag, asset.Value>([
        [asset.Tag.ALIAS, alias], [asset.Tag.SECRET, bytes],
        [asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED],
        [asset.Tag.SYNC_TYPE, asset.SyncType.NEVER]
      ]));
    }
    if (!(bytes instanceof Uint8Array) || bytes.length !== 32) { throw new Error('Secure key unavailable'); }
    return crypto.createSymKeyGenerator('AES256').convertKey({ data: bytes });
  }
  async read(): Promise<string | null> {
    const prefs = await preferences.getPreferences(this.context, { name: this.name + '-secure' });
    const raw = await prefs.get('config', '');
    if (raw === '') { return null; }
    if (typeof raw !== 'string' || raw.length > this.maximum * 8 + 256) { throw new Error('Invalid secure record'); }
    const envelope = JSON.parse(raw) as SecureEnvelope;
    if (envelope.version !== 1 || typeof envelope.iv !== 'string' || typeof envelope.data !== 'string') { throw new Error('Invalid secure record'); }
    const iv = this.codec.decodeSync(envelope.iv), sealed = this.codec.decodeSync(envelope.data);
    if (iv.length !== 12 || sealed.length < 16 || sealed.length > this.maximum * 4 + 16) { throw new Error('Invalid secure record'); }
    const cipher = crypto.createCipher('AES256|GCM|NoPadding');
    const params: crypto.GcmParamsSpec = { algName: 'GcmParamsSpec', iv: { data: iv },
      aad: { data: new util.TextEncoder().encodeInto(this.name) }, authTag: { data: sealed.slice(sealed.length - 16) } };
    await cipher.init(crypto.CryptoMode.DECRYPT_MODE, await this.key(false), params);
    const clear = await cipher.doFinal({ data: sealed.subarray(0, sealed.length - 16) });
    const text = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(clear.data);
    if (text.length > this.maximum) { throw new Error('Invalid secure record'); }
    return text;
  }
  async write(text: string | null): Promise<void> {
    if (text !== null && (typeof text !== 'string' || text.length > this.maximum) || text === null && !this.nullable) {
      throw new Error('Invalid secure record');
    }
    const prefs = await preferences.getPreferences(this.context, { name: this.name + '-secure' });
    const before = await prefs.get('config', '');
    try {
      if (text === null) { await prefs.delete('config'); }
      else {
        const iv = (await crypto.createRandom().generateRandom(12)).data;
        const cipher = crypto.createCipher('AES256|GCM|NoPadding');
        const params: crypto.GcmParamsSpec = { algName: 'GcmParamsSpec', iv: { data: iv },
          aad: { data: new util.TextEncoder().encodeInto(this.name) }, authTag: { data: new Uint8Array(16) } };
        await cipher.init(crypto.CryptoMode.ENCRYPT_MODE, await this.key(true), params);
        const sealed = await cipher.doFinal({ data: new util.TextEncoder().encodeInto(text) });
        const value: SecureEnvelope = { version: 1, iv: this.codec.encodeToStringSync(iv), data: this.codec.encodeToStringSync(sealed.data) };
        await prefs.put('config', JSON.stringify(value));
      }
      await prefs.flush();
    } catch (error) {
      // A failed flush must not make a cache-only update appear durable.
      if (before === '') { await prefs.delete('config'); } else { await prefs.put('config', before); }
      throw error as Error;
    }
  }
}

class SecureChannel implements MethodCallHandler {
  private record: HarmonySecureRecord;
  private code: string;
  private message: string;
  private queue: Promise<void> = Promise.resolve();
  constructor(record: HarmonySecureRecord, code: string, message: string) { this.record = record; this.code = code; this.message = message; }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'read' && call.method !== 'write') { result.notImplemented(); return; }
    this.queue = this.queue.then(async (): Promise<void> => {
      try {
        if (call.method === 'read') { result.success(await this.record.read()); }
        else { await this.record.write(call.args as string | null); result.success(null); }
      } catch (_) { result.error(this.code, this.message, null); }
    });
  }
}

export default class HarmonySecureStoragePlugin implements FlutterPlugin {
  private channels: MethodChannel[] = [];
  getUniqueClassName(): string { return 'HarmonySecureStoragePlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    const context = binding.getApplicationContext();
    const cloud = new MethodChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/cloud_sources');
    cloud.setMethodCallHandler(new SecureChannel(new HarmonySecureRecord(context, 'cloud-sources', 65536), 'secure_storage', '无法读取或保存本机网盘连接，请解锁设备后重试'));
    const speech = new MethodChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/custom_speech');
    speech.setMethodCallHandler(new SecureChannel(new HarmonySecureRecord(context, 'custom-speech', 16384), 'secure_storage', '语音接口配置未保存或无法读取，请解锁设备后重试'));
    const lan = new MethodChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/lan_reading_config');
    lan.setMethodCallHandler(new SecureChannel(new HarmonySecureRecord(context, 'lan-reading', 20000, false), 'pairing_storage', '本机配对信息暂时无法读取或保存，请解锁设备后重试'));
    this.channels = [cloud, speech, lan];
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    for (const channel of this.channels) { channel.setMethodCallHandler(null); }
    this.channels = [];
  }
}
