import { FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import textToSpeech from '@hms.ai.textToSpeech';
import fs from '@ohos.file.fs';
import deviceInfo from '@ohos.deviceInfo';
import { BusinessError } from '@ohos.base';

const ENGINE_ID = 'com.huawei.harmony.speech';

class PcmFrameLocation {
  offset: number;
  length: number;
  constructor(offset: number, length: number) { this.offset = offset; this.length = length; }
}

class SynthesisJob {
  id: string;
  path: string;
  result: MethodResult;
  file?: fs.File;
  spool?: fs.File;
  assemblyPath: string;
  bytes = 0;
  frames: Map<number, PcmFrameLocation> = new Map();
  sampleRate = 0;
  sampleBit = 0;
  channels = 0;
  timer = -1;
  completing = false;
  ordered = false;
  work: Promise<void> = Promise.resolve();
  finishing?: Promise<void>;
  failureCode = '';
  failureMessage = '';
  constructor(id: string, path: string, result: MethodResult) {
    this.id = id; this.path = path; this.assemblyPath = path + '.pcm.part'; this.result = result;
  }
}

/** System TTS renders PCM into the shared WAV cache; it never speaks directly. */
export default class HarmonySpeechPlugin implements FlutterPlugin {
  private context: common.UIAbilityContext;
  private cacheDir = '';
  private channel?: MethodChannel;
  private engine?: textToSpeech.TextToSpeechEngine;
  private creating?: Promise<textToSpeech.TextToSpeechEngine>;
  private engineKey = '';
  private job?: SynthesisJob;
  private detached = false;
  private inventory: textToSpeech.VoiceInfo[] = [];

  constructor(context: common.UIAbilityContext) { this.context = context; }
  getUniqueClassName(): string { return 'HarmonySpeechPlugin'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.detached = false;
    this.cacheDir = binding.getApplicationContext().cacheDir;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/system_speech');
    this.channel.setMethodCallHandler({ onMethodCall: (call: MethodCall, result: MethodResult): void => {
      if (call.method === 'cancel') {
        const cancelled = this.job?.id === call.argument('requestId') ? this.cancel() : Promise.resolve();
        cancelled.then((): void => result.success(null)); return;
      }
      this.handle(call, result).catch((error: Error): void => {
        result.error('TTS_UNAVAILABLE', error.message || '鸿蒙系统语音暂不可用', null);
      });
    } });
  }

  private async handle(call: MethodCall, result: MethodResult): Promise<void> {
    if (!canIUse('SystemCapability.AI.TextToSpeech')) {
      if (call.method === 'engines') { result.success([]); return; }
      result.error('TTS_UNAVAILABLE', '此设备未提供系统语音服务，请选择在线音色或自定义接口', null); return;
    }
    switch (call.method) {
      case 'engines': result.success([new Map<string, Object>([['id', ENGINE_ID], ['name', '鸿蒙系统语音']])]); return;
      case 'voices': {
        this.validateEngine(call);
        const voices = await this.voices();
        result.success(voices.map((voice: textToSpeech.VoiceInfo): Map<string, Object> =>
          new Map<string, Object>([
            ['id', this.voiceId(voice)], ['name', voice.description || `${voice.language} · ${voice.gender || '系统音色'}`],
            ['locale', voice.language], ['networkRequired', false], ['quality', 0],
            ['features', voice.status && voice.status !== 'INSTALLED' ? ['notInstalled'] : []]
          ])));
        return;
      }
      case 'synthesize': this.validateEngine(call); await this.synthesize(call, result); return;
      case 'settings': result.error('TTS_SETTINGS', '请在系统设置中搜索「文字转语音」或「朗读」管理音色', null); return;
      default: result.notImplemented();
    }
  }

  private validateEngine(call: MethodCall): void {
    const engine = call.argument('engine') as string;
    if (engine !== ENGINE_ID && engine !== '@default') throw new Error('所选系统引擎不属于此设备，请重新选择鸿蒙系统语音');
  }

  private voiceId(voice: textToSpeech.VoiceInfo): string {
    return `${voice.language}|${voice.person}|${voice.style}`;
  }

  private async voices(): Promise<textToSpeech.VoiceInfo[]> {
    const query: textToSpeech.VoiceQuery = { requestId: `voices-${Date.now()}`, online: 1 };
    if (deviceInfo.sdkApiVersion >= 19) {
      this.inventory = await textToSpeech.listVoices(query);
    } else {
      // Listing voices while a later paragraph is being synthesized must not
      // shut down its engine just to switch to the default voice.
      if (this.creating) await this.creating;
      const engine = this.engine || await this.getEngine('zh-CN', 0, '');
      this.inventory = await engine.listVoices(query);
    }
    return this.inventory;
  }

  private async getEngine(language: string, person: number, style: string): Promise<textToSpeech.TextToSpeechEngine> {
    if (this.creating) await this.creating;
    const key = `${language}|${person}|${style}`;
    if (this.engine && key === this.engineKey) return this.engine;
    const creating = this.openEngine(language, person, style);
    this.creating = creating;
    try { return await creating; }
    finally { if (this.creating === creating) this.creating = undefined; }
  }

  private async openEngine(language: string, person: number, style: string): Promise<textToSpeech.TextToSpeechEngine> {
    const key = `${language}|${person}|${style}`;
    this.engine?.shutdown();
    this.engine = undefined;
    this.engineKey = '';
    const params: textToSpeech.CreateEngineParams = { language: language, person: person, online: 1 };
    if (style.length > 0) params.extraParams = { style: style };
    const engine = await textToSpeech.createEngine(params);
    if (this.detached) { engine.shutdown(); throw new Error('系统语音已关闭'); }
    engine.setListener({
      onStart: (id: string, response: textToSpeech.StartResponse): void => {
        const job = this.job;
        if (!job || job.id !== id || job.completing || job.finishing) return;
        if (response.audioType.toLowerCase() !== 'pcm' || response.sampleRate <= 0 ||
          ![8, 16, 24, 32].includes(response.sampleBit)) {
          this.fail('TTS_CONTENT', '系统语音返回了不支持的音频格式'); return;
        }
        job.sampleRate = response.sampleRate;
        job.sampleBit = response.sampleBit;
        // Huawei's PcmPlayer decodes this PCM as CHANNEL_1. Do not copy the
        // response's audioChannel (3 for the default stream) into the WAV count.
        job.channels = 1;
      },
      onData: (id: string, data: ArrayBuffer, response: textToSpeech.SynthesisResponse): void => {
        const job = this.job;
        if (!job || job.id !== id || job.completing || job.finishing) return;
        if (response.audioType.toLowerCase() !== 'pcm' || !Number.isInteger(response.sequence) ||
          response.sequence < 0 || job.frames.has(response.sequence)) {
          console.error('Wenku8 HarmonySpeech unexpected PCM frame: ' + JSON.stringify(response));
          this.fail('TTS_CONTENT', '系统语音音频片段不完整，请重试'); return;
        }
        // The service may reuse its callback buffer. Consume it before returning,
        // rather than copying and retaining every PCM frame until completion.
        // Arrival order lives on disk; only sequence/offset/length stay in memory.
        try {
          if (!job.spool || fs.writeSync(job.spool.fd, data) !== data.byteLength) throw new Error('PCM spool write was incomplete');
          job.frames.set(response.sequence, new PcmFrameLocation(44 + job.bytes, data.byteLength));
          job.bytes += data.byteLength;
        } catch (error) {
          console.error('Wenku8 HarmonySpeech PCM spool: ' + (error as Error).message);
          this.fail('TTS_CONTENT', '系统语音缓存写入失败');
        }
      },
      onComplete: (id: string, response: textToSpeech.CompleteResponse): void => {
        if (this.job?.id === id && response.type === 0) this.complete();
      },
      onStop: (id: string, _response: textToSpeech.StopResponse): void => {
        const job = this.job;
        if (job?.id === id && !job.completing && !job.finishing) this.fail('TTS_CANCELLED', '语音准备已取消');
      },
      onError: (id: string, code: number, message: string): void => {
        const job = this.job;
        if (!job || job.id !== id || job.completing || job.finishing) return;
        this.fail(code === 1002300002 ? 'TTS_LANGUAGE_UNAVAILABLE' : code === 1002300001 ? 'TTS_CONTENT' : 'TTS_UNAVAILABLE', message);
      }
    });
    this.engine = engine;
    this.engineKey = key;
    return engine;
  }

  private async synthesize(call: MethodCall, result: MethodResult): Promise<void> {
    const path = call.argument('path') as string;
    const text = call.argument('text') as string;
    const id = call.argument('requestId') as string;
    if (!path.startsWith(this.cacheDir + '/listening-audio-v1/') || path.includes('/../') || !path.endsWith('.wav.part')) {
      result.error('TTS_CONTENT', '语音缓存路径无效', null); return;
    }
    if (this.job) { result.error('TTS_UNAVAILABLE', '系统正在准备另一段语音，请重试', null); return; }
    const job = new SynthesisJob(id, path, result);
    this.job = job;
    job.timer = setTimeout((): void => { if (this.job === job) this.fail('TTS_TIMEOUT', '系统语音准备超时'); }, 30000);
    try {
      const voiceId = call.argument('voice') as string;
      let locale = (call.argument('locale') as string) || 'zh-CN';
      let person = 0;
      let style = '';
      if (voiceId !== '@default') {
        const voices = this.inventory.length > 0 ? this.inventory : await this.voices();
        const voice = voices.find((value: textToSpeech.VoiceInfo): boolean => this.voiceId(value) === voiceId);
        if (!voice || (voice.status && voice.status !== 'INSTALLED')) throw new Error('此音色尚未安装，请在系统中下载或选择其他音色');
        locale = voice.language; person = voice.person; style = voice.style;
      }
      if (this.job !== job || job.failureCode || job.finishing) return;
      const engine = await this.getEngine(locale, person, style);
      if (this.job !== job || job.failureCode || job.finishing) return;
      job.spool = fs.openSync(job.path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      fs.lseek(job.spool.fd, 44, fs.WhenceType.SEEK_SET); // Reserve the WAV header without copying PCM.
      engine.speak(text, { requestId: id, extraParams: { playType: 0, audioType: 'pcm', speed: 1, volume: 1, pitch: 1, languageContext: locale, queueMode: 0 } });
    } catch (error) {
      if (this.job === job) {
        const code = (error as BusinessError).code;
        this.fail(code === 1002300002 ? 'TTS_LANGUAGE_UNAVAILABLE' : code === 1002300001 ? 'TTS_CONTENT' : 'TTS_UNAVAILABLE',
          (error as Error).message || '系统语音准备失败');
      }
    }
  }

  private complete(): void {
    const job = this.job;
    if (!job || job.completing || job.finishing) return;
    if (!job.spool || job.bytes <= 56 || job.sampleRate <= 0 || job.sampleBit <= 0 || job.channels <= 0) {
      this.fail('TTS_CONTENT', '系统语音没有返回完整音频'); return;
    }
    job.completing = true;
    job.work = this.writeWave(job);
    job.work.then((): void => { this.finish(job); }).catch((error: Error): void => {
      console.error('Wenku8 HarmonySpeech PCM cache: ' + error.message);
      this.finish(job, 'TTS_CONTENT', '系统语音缓存写入失败');
    });
  }

  private async writeWave(job: SynthesisJob): Promise<void> {
    const order = Array.from(job.frames.keys()).sort((a: number, b: number): number => a - b);
    // Do not guess a sequence base from the first callback: frame 1 may arrive
    // before frame 0. Validate both supported bases only after all frames arrive.
    if (order.length === 0 || (order[0] !== 0 && order[0] !== 1)) throw new Error('PCM sequence has no first frame');
    for (let index = 1; index < order.length; index++) {
      if (order[index] !== order[index - 1] + 1) throw new Error('PCM sequence has a missing frame');
    }
    const header = new ArrayBuffer(44);
    const bytes = new Uint8Array(header);
    const view = new DataView(header);
    const text = (offset: number, value: string): void => {
      for (let index = 0; index < value.length; index++) bytes[offset + index] = value.charCodeAt(index);
    };
    text(0, 'RIFF'); view.setUint32(4, 36 + job.bytes, true); text(8, 'WAVE'); text(12, 'fmt ');
    view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, job.channels, true);
    const block = job.channels * job.sampleBit / 8;
    view.setUint32(24, job.sampleRate, true); view.setUint32(28, job.sampleRate * block, true);
    view.setUint16(32, block, true); view.setUint16(34, job.sampleBit, true); text(36, 'data'); view.setUint32(40, job.bytes, true);
    let offset = 44;
    job.ordered = true;
    for (const sequence of order) {
      const frame = job.frames.get(sequence)!;
      if (frame.offset !== offset) job.ordered = false;
      offset += frame.length;
    }
    if (job.ordered) {
      // Normal service order is already a WAV body. Patch its reserved header,
      // avoiding a second PCM write/read pass and any assembly buffer.
      fs.lseek(job.spool!.fd, 0, fs.WhenceType.SEEK_SET);
      if (await fs.write(job.spool!.fd, header) !== header.byteLength) throw new Error('WAV header write was incomplete');
      if (!job.failureCode) await fs.fsync(job.spool!.fd);
      return;
    }
    job.file = await fs.open(job.assemblyPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    if (job.failureCode) return;
    if (await fs.write(job.file.fd, header) !== header.byteLength) throw new Error('WAV header write was incomplete');
    // One reusable window bounds assembly memory regardless of utterance length
    // or callback order. Disk reads, writes and final flush yield to the UI loop.
    const buffer = new ArrayBuffer(65536);
    for (const sequence of order) {
      if (job.failureCode) return;
      const frame = job.frames.get(sequence)!;
      fs.lseek(job.spool!.fd, frame.offset, fs.WhenceType.SEEK_SET);
      let remaining = frame.length;
      while (remaining > 0) {
        if (job.failureCode) return;
        const count = await fs.read(job.spool!.fd, buffer, { length: Math.min(buffer.byteLength, remaining) });
        if (job.failureCode) return;
        if (count <= 0 || count > remaining) throw new Error('PCM spool read was incomplete');
        if (await fs.write(job.file.fd, buffer, { length: count }) !== count) throw new Error('PCM frame write was incomplete');
        remaining -= count;
      }
    }
    if (!job.failureCode) await fs.fsync(job.file.fd);
  }

  private finish(job: SynthesisJob, code: string = '', message: string = ''): Promise<void> {
    if (code && !job.failureCode) {
      job.failureCode = code; job.failureMessage = message;
      try { this.engine?.stop(); } catch (_error) {}
    }
    if (job.finishing) return job.finishing;
    clearTimeout(job.timer);
    job.finishing = this.closeJob(job);
    return job.finishing;
  }

  private async closeJob(job: SynthesisJob): Promise<void> {
    // Cancellation marks the job first, then waits for an in-flight read/write.
    // Never close its descriptor while FileIO is still using it.
    try { await job.work; } catch (_error) {}
    try {
      if (job.file) await fs.close(job.file);
    } catch (_error) {
      if (!job.failureCode) { job.failureCode = 'TTS_CONTENT'; job.failureMessage = '系统语音缓存关闭失败'; }
    }
    job.file = undefined;
    try { if (job.spool) await fs.close(job.spool); } catch (_error) {}
    job.spool = undefined;
    if (!job.failureCode && !job.ordered) {
      try {
        // Both paths are this job's private .part files in the same cache.
        // Remove the arrival-order body only after the reordered WAV is closed.
        await fs.unlink(job.path);
        await fs.rename(job.assemblyPath, job.path);
      } catch (_error) { job.failureCode = 'TTS_CONTENT'; job.failureMessage = '系统语音缓存无法保存'; }
    }
    try { await fs.unlink(job.assemblyPath); } catch (_error) {}
    if (job.failureCode) { try { await fs.unlink(job.path); } catch (_error) {} }
    job.frames.clear();
    if (this.job === job) this.job = undefined;
    if (job.failureCode) job.result.error(job.failureCode, job.failureMessage, null);
    else job.result.success(job.path);
  }

  private fail(code: string, message: string): void {
    const job = this.job;
    if (!job) return;
    console.error('Wenku8 HarmonySpeech ' + code + ': ' + message);
    this.finish(job, code, message);
  }

  private cancel(): Promise<void> {
    return this.job ? this.finish(this.job, 'TTS_CANCELLED', '语音准备已取消') : Promise.resolve();
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.detached = true;
    this.cancel();
    this.channel?.setMethodCallHandler(null);
    this.engine?.shutdown(); this.engine = undefined; this.engineKey = '';
  }
}
