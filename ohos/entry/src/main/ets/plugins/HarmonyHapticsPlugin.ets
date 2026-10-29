import { FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import deviceInfo from '@ohos.deviceInfo';
import settings from '@ohos.settings';
import vibrator from '@ohos.vibrator';

/** Public preset effects, with the OS touch policy left in control. */
export default class HarmonyHapticsPlugin implements FlutterPlugin {
  private channel?: MethodChannel;
  private context: common.UIAbilityContext;
  private effects = new Map<string, boolean>();
  constructor(context: common.UIAbilityContext) { this.context = context; }
  getUniqueClassName(): string { return 'HarmonyHapticsPlugin'; }

  private systemEnabled(): boolean | null {
    try {
      const value = settings.getValueSync(this.context, settings.sound.HAPTIC_FEEDBACK_STATUS, '');
      if (value === '1' || value === 'true') { return true; }
      if (value === '0' || value === 'false') { return false; }
    } catch (_) {}
    return null;
  }
  private supports(effect: string): boolean {
    const cached = this.effects.get(effect);
    if (cached !== undefined) { return cached; }
    try {
      const supported = vibrator.isSupportEffectSync(effect);
      this.effects.set(effect, supported); return supported;
    } catch (_) { return false; }
  }
  private hasVibrator(): boolean | null {
    if (deviceInfo.sdkApiVersion >= 19) {
      try { return vibrator.getVibratorInfoSync().some((info: vibrator.VibratorInfo): boolean => info.isLocalVibrator); }
      catch (_) {}
    }
    if (this.supports('haptic.effect.soft') || this.supports('haptic.clock.timer')) { return true; }
    return null;
  }
  private capabilities(): Map<string, Object | null> {
    // The preset API accepts intensity, but exposes no per-device confirmation
    // that the motor applies it. Unknown must not masquerade as fixed strength.
    return new Map<string, Object | null>([
      ['hasVibrator', this.hasVibrator()], ['hasAmplitudeControl', null],
      ['supportsIntensityRequest', true], ['sdk', deviceInfo.sdkApiVersion],
      ['hapticFeedbackEnabled', this.systemEnabled()]
    ]);
  }
  private effect(cue: string): string | null {
    let preferred: string;
    switch (cue) {
      case 'longPress': case 'action': preferred = 'haptic.effect.hard'; break;
      case 'boundary': preferred = 'haptic.effect.sharp'; break;
      case 'success': preferred = 'haptic.notice.success'; break;
      case 'warning': preferred = 'haptic.notice.warning'; break;
      case 'error': preferred = 'haptic.notice.fail'; break;
      case 'selection': case 'shelfStep': case 'detent': case 'pageTurn': preferred = 'haptic.effect.soft'; break;
      default: return null;
    }
    if (this.supports(preferred)) { return preferred; }
    return this.supports('haptic.clock.timer') ? 'haptic.clock.timer' : '';
  }
  private async play(call: MethodCall): Promise<boolean> {
    const cue = typeof call.args === 'string' ? call.args : call.argument('cue') as string;
    const strength = typeof call.args === 'string' ? 'standard' : call.argument('strength') as string;
    if (!['light', 'standard', 'strong'].includes(strength)) { return false; }
    if (this.systemEnabled() === false || this.hasVibrator() === false) { return false; }
    const effect = this.effect(cue);
    if (effect === null) { return false; }
    try {
      if (effect !== '') {
        await vibrator.startVibration({ type: 'preset', effectId: effect,
          intensity: strength === 'light' ? 35 : strength === 'strong' ? 100 : 65 }, { usage: 'touch' });
      } else {
        // Basic motors may have no preset library. Time mode has fixed strength.
        await vibrator.startVibration({ type: 'time', duration: cue === 'longPress' ? 30 : 18 }, { usage: 'touch' });
      }
      return true;
    } catch (_) { return false; }
  }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8_flutter/haptics');
    this.channel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (call.method === 'capabilities') { result.success(this.capabilities()); return; }
      if (call.method !== 'play') { result.notImplemented(); return; }
      this.play(call).then((accepted: boolean): void => result.success(accepted))
        .catch((_error: Error): void => result.success(false));
    } });
  }
  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null); this.channel = undefined; this.effects.clear();
  }
}
