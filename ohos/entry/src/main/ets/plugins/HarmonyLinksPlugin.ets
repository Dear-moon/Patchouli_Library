import { FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import bundleManager from '@ohos.bundle.bundleManager';
import url from '@ohos.url';

/** Adapter for url_launcher's existing platform-interface channel. No new UI. */
export default class HarmonyLinksPlugin implements FlutterPlugin {
  private context: common.UIAbilityContext;
  private channel?: MethodChannel;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  getUniqueClassName(): string { return 'HarmonyLinksPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'plugins.flutter.io/url_launcher');
    this.channel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (call.method === 'closeWebView') { result.success(null); return; }
      if (!['canLaunch', 'launch'].includes(call.method)) { result.notImplemented(); return; }
      const raw = call.argument('url') as string;
      try {
        if (typeof raw !== 'string' || raw.length > 8192 || /[\x00-\x20\x7f\\]/.test(raw)) { result.success(false); return; }
        const value = new url.URL(raw);
        if (!['https:', 'http:'].includes(value.protocol) || value.username || value.password || !value.hostname) { result.success(false); return; }
        if (call.method === 'canLaunch') { result.success(bundleManager.canOpenLink(raw)); return; }
        this.context.openLink(raw).then((): void => result.success(true)).catch((_error: Error): void => result.success(false));
      } catch (_) { result.success(false); }
    } });
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void { this.channel?.setMethodCallHandler(null); }
}
