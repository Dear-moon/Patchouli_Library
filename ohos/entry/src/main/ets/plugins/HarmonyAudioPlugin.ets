import { FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCall, MethodResult, EventChannel, EventSink, Any } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import media from '@ohos.multimedia.media';
import audio from '@ohos.multimedia.audio';
import avSession from '@ohos.multimedia.avsession';
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';
import wantAgent, { WantAgent } from '@ohos.app.ability.wantAgent';
import fs from '@ohos.file.fs';
import deviceInfo from '@ohos.deviceInfo';
import { BusinessError } from '@ohos.base';

/** Hardware file playback only; Dart remains the one chapter/segment queue. */
export default class HarmonyAudioPlugin implements FlutterPlugin {
  private context: common.UIAbilityContext;
  private cacheDir = '';
  private methods?: MethodChannel;
  private events?: EventChannel;
  private sink: EventSink | null = null;
  private queue: Promise<void> = Promise.resolve();
  private player?: media.AVPlayer;
  private file?: fs.File;
  private session?: avSession.AVSession;
  private audioSession?: audio.AudioSessionManager;
  private focusActive = false;
  private launch?: WantAgent;
  private background = false;
  private loadId = 0;
  private speed = 1;
  private detached = false;
  private stateWait?: (state: string) => void;
  private errorWait?: (error: Error) => void;
  private seekWait?: () => void;
  private focusLost = (_event: audio.AudioSessionDeactivatedEvent): void => {
    if (!this.focusActive) return;
    this.focusActive = false;
    this.methods?.invokeMethod('interrupted', null);
  };

  constructor(context: common.UIAbilityContext) { this.context = context; }
  getUniqueClassName(): string { return 'HarmonyAudioPlugin'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.detached = false;
    // Match path_provider_ohos: it uses the engine's application context, not
    // the UIAbility's module-scoped cache directory.
    this.cacheDir = binding.getApplicationContext().cacheDir;
    this.methods = new MethodChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/harmony_audio');
    this.methods.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      this.queue = this.queue.then(async (): Promise<void> => {
        try {
          if (this.detached) throw new Error('听书播放器已关闭');
          switch (call.method) {
            case 'initializeService': await this.initializeSession(); result.success(null); return;
            case 'initializePlayer': await this.initializePlayer(); result.success(null); return;
            case 'playbackRates': result.success(deviceInfo.sdkApiVersion >= 20 ? [] : [.5, .75, 1, 1.25, 1.5, 1.75, 2, 3]); return;
            case 'load': result.success(await this.load(call)); return;
            case 'play': await this.play(); result.success(null); return;
            case 'suspend': await this.pause(false); result.success(null); return;
            case 'pause': await this.pause(true); result.success(null); return;
            case 'stop': await this.stop(); result.success(null); return;
            case 'seek': await this.seek(call.argument('position') as number); result.success(null); return;
            case 'setSpeed': this.setSpeed(call.argument('speed') as number); result.success(null); return;
            case 'setMetadata': await this.metadata(call); result.success(null); return;
            case 'setPlaybackState': await this.playbackState(call); result.success(null); return;
            case 'disposePlayer': await this.disposePlayer(); result.success(null); return;
            default: result.notImplemented();
          }
        } catch (error) {
          console.error('Wenku8 HarmonyAudio ' + call.method + ': ' + (error as Error).message);
          result.error('harmony_audio', (error as Error).message || '音频播放失败，请重试', null);
        }
      });
    } });
    this.events = new EventChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/harmony_audio/events');
    this.events.setStreamHandler({
      onListen: (_args: Any, sink: EventSink): void => { this.sink = sink; },
      onCancel: (_args: Any): void => { this.sink = null; }
    });
  }

  private async initializeSession(): Promise<void> {
    if (this.session) return;
    const session = await avSession.createAVSession(this.context, '文库听书', 'audio');
    try {
      const launch = await wantAgent.getWantAgent({
        wants: [{ bundleName: this.context.abilityInfo.bundleName, abilityName: this.context.abilityInfo.name }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 195,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
      await session.setLaunchAbility(launch);
      session.on('play', (): void => { this.methods?.invokeMethod('play', null); });
      session.on('pause', (): void => { this.methods?.invokeMethod('pause', null); });
      session.on('stop', (): void => { this.methods?.invokeMethod('stop', null); });
      session.on('playNext', (): void => { this.methods?.invokeMethod('next', null); });
      session.on('playPrevious', (): void => { this.methods?.invokeMethod('previous', null); });
      session.on('fastForward', (): void => { this.methods?.invokeMethod('forward', null); });
      session.on('rewind', (): void => { this.methods?.invokeMethod('rewind', null); });
      this.launch = launch;
      this.session = session;
    } catch (error) {
      await session.destroy();
      throw error as Error;
    }
  }

  private async initializePlayer(): Promise<void> {
    if (this.player) return;
    if (!this.audioSession) {
      this.audioSession = audio.getAudioManager().getSessionManager();
      this.audioSession.on('audioSessionDeactivated', this.focusLost);
    }
    const player = await media.createAVPlayer();
    this.player = player;
    player.on('stateChange', (state: string): void => {
      if (this.player !== player) return;
      this.stateWait?.(state);
      if (state === 'completed') this.emit('completed');
    });
    player.on('timeUpdate', (position: number): void => {
      if (this.player !== player) return;
      this.sink?.success(new Map<string, Object>([['type', 'position'], ['loadId', this.loadId], ['position', position]]));
    });
    player.on('seekDone', (): void => { if (this.player === player) this.seekWait?.(); });
    player.on('error', (error: BusinessError): void => {
      if (this.player !== player) return;
      this.errorWait?.(new Error(error.message));
      this.sink?.success(new Map<string, Object>([['type', 'error'], ['loadId', this.loadId], ['code', String(error.code)], ['message', error.message]]));
    });
    player.on('audioInterrupt', (event: audio.InterruptEvent): void => {
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE || event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP || event.hintType === audio.InterruptHint.INTERRUPT_HINT_DUCK) {
        this.methods?.invokeMethod('interrupted', null);
      }
      // Calls, navigation and focus changes never auto-resume speech.
    });
    player.on('audioOutputDeviceChangeWithInfo', (event: audio.AudioStreamDeviceChangeInfo): void => {
      if (event.changeReason === audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE) {
        this.methods?.invokeMethod('interrupted', null);
      }
    });
  }

  private emit(type: string): void {
    this.sink?.success(new Map<string, Object>([['type', type], ['loadId', this.loadId]]));
  }

  private waitFor(state: string, action: () => void): Promise<void> {
    return new Promise<void>((resolve, reject): void => {
      let timer = -1;
      const finish = (error?: Error): void => {
        if (timer >= 0) clearTimeout(timer);
        this.stateWait = undefined;
        this.errorWait = undefined;
        if (error) reject(error); else resolve();
      };
      this.stateWait = (value: string): void => { if (value === state) finish(); };
      this.errorWait = (error: Error): void => finish(error);
      timer = setTimeout((): void => finish(new Error('音频准备超时，请重试')), 8000);
      try { action(); } catch (error) { finish(error as Error); }
    });
  }

  private async load(call: MethodCall): Promise<number> {
    const path = call.argument('path') as string;
    if (!path.startsWith(this.cacheDir + '/listening-audio-v1/') || path.includes('/../')) {
      throw new Error('听书音频不在应用缓存中');
    }
    await this.initializePlayer();
    const player = this.player!;
    if (player.state !== 'idle') await player.reset();
    if (this.file) { fs.closeSync(this.file); this.file = undefined; }
    this.loadId = call.argument('loadId') as number;
    this.file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    await this.waitFor('initialized', (): void => {
      player.fdSrc = { fd: this.file!.fd, offset: 0, length: fs.statSync(this.file!.fd).size };
    });
    player.audioRendererInfo = { content: audio.ContentType.CONTENT_TYPE_SPEECH, usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK, rendererFlags: 0 };
    player.audioInterruptMode = audio.InterruptMode.INDEPENDENT_MODE;
    await player.prepare();
    this.setSpeed(this.speed);
    const position = call.argument('position') as number;
    if (position > 0) await this.seek(position);
    return player.duration;
  }

  private async seek(position: number): Promise<void> {
    const player = this.player;
    if (!player || !Number.isFinite(position)) throw new Error('音频尚未准备好');
    const target = Math.max(0, Math.min(position, player.duration));
    await new Promise<void>((resolve, reject): void => {
      const timer = setTimeout((): void => { this.seekWait = undefined; reject(new Error('音频定位超时')); }, 4000);
      this.seekWait = (): void => { clearTimeout(timer); this.seekWait = undefined; resolve(); };
      try { player.seek(target, media.SeekMode.SEEK_CLOSEST); }
      catch (error) { clearTimeout(timer); this.seekWait = undefined; reject(error); }
    });
  }

  private setSpeed(speed: number): void {
    if (!Number.isFinite(speed) || speed < .5 || speed > 3) throw new Error('语速须在 0.5 到 3 倍之间');
    const player = this.player;
    if (deviceInfo.sdkApiVersion >= 20) {
      if (player && ['prepared', 'playing', 'paused', 'completed'].includes(player.state)) player.setPlaybackRate(speed);
    } else {
      const rates = [.75, 1, 1.25, 1.75, 2, .5, 1.5, 3];
      const rate = rates.indexOf(speed);
      if (rate < 0) throw new Error('当前鸿蒙系统不支持此语速，请选择可用档位');
      if (player && ['prepared', 'playing', 'paused', 'completed'].includes(player.state)) player.setSpeed(rate as media.PlaybackSpeed);
    }
    this.speed = speed;
  }

  private async play(): Promise<void> {
    const player = this.player;
    if (!player) throw new Error('音频尚未准备好');
    if (player.state === 'completed') { this.emit('completed'); return; }
    await this.initializeSession();
    await this.session!.activate();
    if (!this.focusActive) {
      await this.audioSession!.activateAudioSession({ concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_PAUSE_OTHERS });
      this.focusActive = true;
    }
    try {
      await player.play();
      // The continuous-task API checks an active, playing AVSession. The Dart
      // playing snapshot follows only after this method returns successfully.
      await this.session!.setAVPlaybackState({ state: avSession.PlaybackState.PLAYBACK_STATE_PLAY, speed: this.speed });
    } catch (error) {
      if (player.state === 'playing') await player.pause();
      await this.releaseFocus(); throw error as Error;
    }
    if (!this.background) {
      try {
        await backgroundTaskManager.startBackgroundRunning(this.context, backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, this.launch!);
        this.background = true;
      } catch (error) {
        await player.pause();
        await this.releaseFocus();
        console.error('Wenku8 HarmonyAudio background task rejected: ' + JSON.stringify(error));
        throw new Error('无法开启后台听书，请允许应用后台运行后重试');
      }
    }
  }

  private async pause(releaseBackground: boolean): Promise<void> {
    if (this.player?.state === 'playing') await this.player.pause();
    if (releaseBackground) { await this.endBackground(); await this.releaseFocus(); }
  }

  private async releaseFocus(): Promise<void> {
    if (!this.focusActive) return;
    this.focusActive = false;
    await this.audioSession?.deactivateAudioSession();
  }

  private async endBackground(): Promise<void> {
    if (!this.background) return;
    await backgroundTaskManager.stopBackgroundRunning(this.context);
    this.background = false;
  }

  private async stop(): Promise<void> {
    if (this.player && ['prepared', 'playing', 'paused', 'completed'].includes(this.player.state)) await this.player.stop();
    await this.endBackground();
    await this.releaseFocus();
    await this.session?.deactivate();
  }

  private async metadata(call: MethodCall): Promise<void> {
    await this.initializeSession();
    await this.session!.setAVMetadata({
      assetId: call.argument('id') as string,
      title: call.argument('title') as string,
      album: call.argument('album') as string,
      artist: call.argument('artist') as string,
    });
  }

  private async playbackState(call: MethodCall): Promise<void> {
    await this.initializeSession();
    const phase = call.argument('phase') as string;
    const playing = call.argument('playing') as boolean;
    let state = avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    if (phase === 'stopped' || phase === 'completed') state = avSession.PlaybackState.PLAYBACK_STATE_STOP;
    else if (phase === 'failed') state = avSession.PlaybackState.PLAYBACK_STATE_ERROR;
    else if (phase === 'preparing' && playing) state = avSession.PlaybackState.PLAYBACK_STATE_BUFFERING;
    else if (playing) state = avSession.PlaybackState.PLAYBACK_STATE_PLAY;
    await this.session!.setAVPlaybackState({ state: state, speed: call.argument('speed') as number,
      position: { elapsedTime: call.argument('position') as number, updateTime: Date.now() } });
    if (!playing) { await this.endBackground(); await this.releaseFocus(); }
    if (phase === 'stopped' || phase === 'completed' || phase === 'failed') await this.session!.deactivate();
  }

  private async disposePlayer(): Promise<void> {
    const player = this.player;
    this.player = undefined;
    await player?.release();
    if (this.file) { fs.closeSync(this.file); this.file = undefined; }
    await this.endBackground();
    await this.releaseFocus();
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.detached = true;
    this.methods?.setMethodCallHandler(null);
    this.events?.setStreamHandler(null);
    this.sink = null;
    this.queue = this.queue.then(async (): Promise<void> => {
      await this.disposePlayer();
      await this.session?.destroy();
      this.session = undefined;
      this.audioSession?.off('audioSessionDeactivated', this.focusLost);
      this.audioSession = undefined;
    }).catch((_error: Error): void => {});
  }
}
