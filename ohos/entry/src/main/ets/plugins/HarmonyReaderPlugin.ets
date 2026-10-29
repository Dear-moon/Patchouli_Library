import { FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCall, MethodResult, EventChannel, EventSink, Any } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import batteryInfo from '@ohos.batteryInfo';
import commonEvent from '@ohos.commonEventManager';
import settings from '@ohos.settings';
import HarmonyLocalFiles from './HarmonyLocalFiles';
import { GallerySaveAuthorizations } from './HarmonyGalleryAccess';
import HarmonyGallerySaveButtonFactory from './HarmonyGallerySaveButton';
import bundleManager from '@ohos.bundle.bundleManager';
import display from '@ohos.display';
import inputConsumer from '@ohos.multimodalInput.inputConsumer';
import { KeyEvent } from '@ohos.multimodalInput.keyEvent';

/** Reader-owned window state; leaving the reader restores the previous window. */
export default class HarmonyReaderPlugin implements FlutterPlugin {
  private context: common.UIAbilityContext;
  private methods: MethodChannel[] = [];
  private status?: EventChannel;
  private sink: EventSink | null = null;
  private timer: number = -1;
  private subscriber?: commonEvent.CommonEventSubscriber;
  private generation = 0;
  private brightness: number | null = null;
  private awake: boolean | null = null;
  private queue: Promise<void> = Promise.resolve();
  private files: HarmonyLocalFiles;
  private galleryAuthorizations: GallerySaveAuthorizations = new GallerySaveAuthorizations();
  private rateChannel?: MethodChannel;
  private rateWatching = false;
  private attached = false;
  private foreground = true;
  private controls?: MethodChannel;
  private volumeKeys = false;
  private previousPage = (_event: KeyEvent): void => { if (this.foreground && this.volumeKeys) { this.controls?.invokeMethod('page', -1); } };
  private nextPage = (_event: KeyEvent): void => { if (this.foreground && this.volumeKeys) { this.controls?.invokeMethod('page', 1); } };
  private rateChanged = (): void => { if (this.attached) { this.rateChannel?.invokeMethod('changed', null); } };
  constructor(context: common.UIAbilityContext) { this.context = context; this.files = new HarmonyLocalFiles(context, this.galleryAuthorizations); }
  getUniqueClassName(): string { return 'HarmonyReaderPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.attached = true;
    binding.getPlatformViewRegistry().registerViewFactory('org.mewx.wenku8/gallery_save_button',
      new HarmonyGallerySaveButtonFactory(binding.getBinaryMessenger(), this.galleryAuthorizations));
    const controls = new MethodChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/reader_controls');
    this.controls = controls;
    controls.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      this.queue = this.queue.then(async (): Promise<void> => {
        try {
          if (!this.attached) { result.error('reader_detached', '阅读器已关闭', null); return; }
          if (call.method === 'installedApp') {
            const app = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
            result.success(new Map<string, Object>([['appVersion', app.versionName], ['appBuild', app.versionCode]])); return;
          }
          const main = await window.getLastWindow(this.context);
          if (!this.attached) { result.error('reader_detached', '阅读器已关闭', null); return; }
          if (call.method === 'brightness') {
            const value = main.getWindowProperties().brightness;
            if (value >= 0) { result.success(value); return; }
            const raw = (await settings.getValue(this.context, settings.display.SCREEN_BRIGHTNESS_STATUS)).trim();
            const system = raw === '' ? NaN : Number(raw);
            result.success(Number.isFinite(system) && system >= 0 && system <= 255 ? system / 255 : null); return;
          }
          if (call.method !== 'apply') { result.notImplemented(); return; }
          this.setVolumeKeys(this.foreground && call.argument('volumePaging') === true);
          const next = this.foreground ? call.argument('brightness') as number | null : null;
          if (typeof next === 'number' && Number.isFinite(next) && next >= 0 && next <= 1) {
            if (this.brightness === null) { this.brightness = main.getWindowProperties().brightness; }
            await main.setWindowBrightness(next);
          } else if (this.brightness !== null) {
            await main.setWindowBrightness(this.brightness); this.brightness = null;
          }
          // Status visibility/insets remain Flutter's SystemChrome contract;
          // this plugin never overlays a second black system-bar background.
          result.success(null);
        } catch (_) { result.error('reader_window', '阅读器窗口暂不可用，请返回后重试', null); }
      });
    } });
    const local = new MethodChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/local_tools');
    local.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (this.files.supports(call.method)) { this.files.handle(call, result); return; }
      if (call.method !== 'keepScreenOn') { result.notImplemented(); return; }
      this.queue = this.queue.then(async (): Promise<void> => {
        try {
          const main = await window.getLastWindow(this.context);
          if (!this.attached) { result.error('reader_detached', '阅读器已关闭', null); return; }
          if (this.foreground && call.args === true) {
            if (this.awake === null) { this.awake = main.getWindowProperties().isKeepScreenOn; }
            await main.setWindowKeepScreenOn(true);
          } else if (this.awake !== null) {
            await main.setWindowKeepScreenOn(this.awake); this.awake = null;
          }
          result.success(null);
        } catch (_) { result.error('reader_window', '当前无法设置屏幕常亮', null); }
      });
    } });
    this.methods = [controls, local];
    this.rateChannel = new MethodChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/frame_rate');
    this.rateChannel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (!['info', 'set'].includes(call.method)) { result.notImplemented(); return; }
      if (call.method === 'set' && ![-1, 0].includes(call.argument('target') as number)) {
        result.error('frame_rate_unavailable', '鸿蒙当前由系统调度刷新率，暂不支持手动锁定', null); return;
      }
      window.getLastWindow(this.context).then((main: window.Window): void => {
        if (!this.attached) { result.error('reader_detached', '阅读器已关闭', null); return; }
        const screen = display.getDisplayByIdSync(main.getWindowProperties().displayId);
        const rate = screen.refreshRate;
        const observed = Number.isFinite(rate) && rate > 0 ? rate : null;
        const info = new Map<string, Object | null>([['target', -1], ['current', observed], ['maximum', null], ['rates', []], ['canSelect', false], ['selectedRate', null], ['selectedModeId', null], ['requestStatusAvailable', false], ['surfaceRequestState', 'system_managed']]);
        if (!this.rateWatching) { display.on('change', this.rateChanged); this.rateWatching = true; }
        result.success(info);
      }).catch((_error: Error): void => result.error('frame_rate_display', '暂时无法读取当前屏幕，请返回后重试', null));
    } });
    this.status = new EventChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/reader_status');
    this.status.setStreamHandler({ onListen: (_args: Any, sink: EventSink): void => this.listen(sink), onCancel: (_args: Any): void => this.stop() });
  }
  private emit(): void {
    if (!this.foreground) { return; }
    this.sink?.success(new Map<string, Object>([['time', Date.now()], ['battery', batteryInfo.batterySOC],
      ['charging', batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.ENABLE || batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.FULL]]));
  }
  private listen(sink: EventSink): void {
    this.stop(); this.sink = sink; this.startStatus();
  }
  private startStatus(): void {
    if (!this.foreground || !this.sink) { return; }
    this.emit(); const generation = this.generation;
    const tick = (): void => {
      if (this.sink === null || generation !== this.generation) { return; }
      this.timer = setTimeout((): void => {
        if (this.sink === null || generation !== this.generation) { return; }
        this.emit(); tick();
      }, 60000 - Date.now() % 60000 + 20);
    };
    tick();
    commonEvent.createSubscriber({ events: ['usual.event.BATTERY_CHANGED', 'usual.event.TIME_CHANGED'] }).then((subscriber: commonEvent.CommonEventSubscriber): void => {
      if (generation !== this.generation || !this.sink) { return; }
      this.subscriber = subscriber;
      commonEvent.subscribe(subscriber, (): void => { if (generation === this.generation) { this.emit(); } });
    }).catch((_error: Error): void => {});
  }
  private pauseStatus(): void {
    this.generation++; if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    if (this.subscriber) { commonEvent.unsubscribe(this.subscriber, (): void => {}); this.subscriber = undefined; }
  }
  private stop(): void { this.sink = null; this.pauseStatus(); }
  private setVolumeKeys(enabled: boolean): void {
    if (enabled === this.volumeKeys) { return; }
    if (enabled) {
      try {
        inputConsumer.on('keyPressed', { key: 16, action: 1, isRepeat: false }, this.previousPage);
        inputConsumer.on('keyPressed', { key: 17, action: 1, isRepeat: false }, this.nextPage);
        this.volumeKeys = true;
      } catch (_) {
        // If the second subscription fails, release the first as well.
        try { inputConsumer.off('keyPressed', this.previousPage); } catch (_) {}
        try { inputConsumer.off('keyPressed', this.nextPage); } catch (_) {}
        this.volumeKeys = false;
      }
    } else {
      this.volumeKeys = false;
      try { inputConsumer.off('keyPressed', this.previousPage); } catch (_) {}
      try { inputConsumer.off('keyPressed', this.nextPage); } catch (_) {}
    }
  }
  setForeground(value: boolean): void {
    if (this.foreground === value) { return; }
    this.foreground = value;
    if (!value) { this.galleryAuthorizations.clear(); this.pauseStatus(); this.setVolumeKeys(false); this.restoreWindow(); }
    else { this.startStatus(); }
  }
  private restoreWindow(): void {
    this.queue = this.queue.then(async (): Promise<void> => {
      try {
        const main = await window.getLastWindow(this.context);
        if (this.brightness !== null) {
          try { await main.setWindowBrightness(this.brightness); this.brightness = null; } catch (_) {}
        }
        if (this.awake !== null) {
          try { await main.setWindowKeepScreenOn(this.awake); this.awake = null; } catch (_) {}
        }
      } catch (_) {}
    });
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.galleryAuthorizations.clear();
    this.attached = false; this.controls = undefined; this.setVolumeKeys(false);
    this.stop(); this.methods.forEach((channel: MethodChannel): void => channel.setMethodCallHandler(null)); this.methods = [];
    this.status?.setStreamHandler(null);
    this.rateChannel?.setMethodCallHandler(null);
    if (this.rateWatching) { display.off('change', this.rateChanged); this.rateWatching = false; }
    this.restoreWindow();
  }
}
