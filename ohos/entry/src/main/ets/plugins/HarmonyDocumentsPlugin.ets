import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fileUri from '@ohos.file.fileuri';
import util from '@ohos.util';
import hilog from '@ohos.hilog';
import taskpool from '@ohos.taskpool';
import { BusinessError } from '@ohos.base';
import bookEngine from 'libwenku_book_engine.so';
import HarmonyLinkedDocuments, { LinkedBookRequest } from './HarmonyLinkedDocuments';
import { bookByteLimit, bookTextEncoding, HarmonyDocumentFailure, linkedUnavailable } from './HarmonyDocumentPolicy';
import HarmonyFolderScanner from './HarmonyFolderScanner';
import HarmonyBookOpenInbox from './HarmonyBookOpenInbox';
import { extractHarmonyPdf } from './HarmonyPdfTask';
import HarmonySyncFiles from './HarmonySyncFiles';

interface SelectedBook {
  name: string;
  path?: string;
  token?: string;
  reference?: string;
  error?: string;
}

/** Same deferred import contract as the other hosts, without Android/JNI. */
export default class HarmonyDocumentsPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private pending = new Map<string, string>();
  private owned = new Set<string>();
  private queue: Promise<void> = Promise.resolve();
  private context: common.UIAbilityContext;
  private storage: common.Context;
  private workspace: string;
  private linked: HarmonyLinkedDocuments;
  private scanner: HarmonyFolderScanner;
  private sync: HarmonySyncFiles;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.storage = context;
    this.workspace = context.filesDir + '/.import-work';
    this.linked = new HarmonyLinkedDocuments(context);
    this.scanner = new HarmonyFolderScanner(context, this.linked, (uri: string): Promise<SelectedBook> => this.stage(uri, 'pickBook'));
    this.sync = new HarmonySyncFiles(context);
  }

  getUniqueClassName(): string { return 'HarmonyDocumentsPlugin'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    // path_provider uses the application context, whose files/cache roots differ
    // from the UIAbility module roots. Pickers still need the UIAbility context.
    this.storage = binding.getApplicationContext();
    this.workspace = this.storage.cacheDir + '/.import-work';
    this.sync = new HarmonySyncFiles(this.context, this.storage);
    this.scanner = new HarmonyFolderScanner(this.context, this.linked,
      (uri: string): Promise<SelectedBook> => this.stage(uri, 'pickBook'), undefined, 'book-folder-scan-v1', this.storage);
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'org.mewx.wenku8/book_documents');
    this.channel.setMethodCallHandler(this);
    HarmonyBookOpenInbox.onAvailable = (): void => { this.channel?.invokeMethod('bookOpenAvailable', null); };
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    HarmonyBookOpenInbox.onAvailable = null;
    this.queue = this.queue.then(async (): Promise<void> => {
      try { await this.linked.closeAll(); } finally { await this.sync.dispose(); }
    }).catch((error: Error) => {
      hilog.error(0, 'BookDocuments', '释放原文件句柄失败：%{public}s', error.name);
    });
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    // A whole selection never becomes a whole-library memory allocation.
    this.queue = this.queue.then(async () => {
      try { await this.handle(call, result); }
      catch (error) {
        const failure = error as BusinessError;
        result.error(error instanceof HarmonyDocumentFailure ? error.code : 'document_io',
          failure.message || '无法读取文件，请重新选择',
          new Map<string, string>([['stage', 'ohos_document'], ['operation', call.method],
            ['code', String(failure.code ?? '')]]));
      }
    });
  }

  private async handle(call: MethodCall, result: MethodResult): Promise<void> {
    if (this.sync.supports(call.method)) { await this.sync.handle(call, result); return; }
    switch (call.method) {
      case 'pendingBookOpen': result.success(HarmonyBookOpenInbox.pending()); return;
      case 'resolveBookOpen': {
        const request = HarmonyBookOpenInbox.source(call.argument('id') as string);
        result.success(call.argument('copy') === true ? await this.stage(request.uri, 'pickBook', request.name) :
          await this.linked.retain(request.uri, false, request.name)); return;
      }
      case 'pickBookOpenReference': {
        HarmonyBookOpenInbox.source(call.argument('id') as string);
        const options = new picker.DocumentSelectOptions(); options.maxSelectNumber = 1;
        const uris = await new picker.DocumentViewPicker(this.context).select(options);
        result.success(uris.length ? await this.linked.retain(uris[0]) : null); return;
      }
      case 'finishBookOpen': HarmonyBookOpenInbox.finish(call.argument('id') as string); result.success(null); return;
      case 'deleteBookOpenSource': {
        HarmonyBookOpenInbox.source(call.argument('id') as string);
        throw new HarmonyDocumentFailure('move_unavailable', '文件来源仅提供读取权限，已保留书库副本和原文件');
      }
      case 'scanFolderInfo': result.success(await this.scanner.info()); return;
      case 'selectScanFolder': result.success(await this.scanner.selectFolder()); return;
      case 'selectAllScan': result.success(await this.scanner.applicationDocuments()); return;
      case 'setScanAutomatic': await this.scanner.automatic(call.argument('value') === true); result.success(null); return;
      case 'disconnectScanFolder': await this.scanner.disconnect(); result.success(null); return;
      case 'scanFormats': result.success(await this.scanner.scanFormats()); return;
      case 'setScanFormats': await this.scanner.setFormats(call.argument('extensions') as string[]); result.success(null); return;
      case 'scanBooks': result.success(await this.scanner.scan()); return;
      case 'stageScanBook': result.success(await this.scanner.stageBook(call.argument('token') as string)); return;
      case 'linkScanBook': result.success(await this.scanner.linkBook(call.argument('token') as string)); return;
      case 'markScanBook': await this.scanner.mark(call.argument('token') as string); result.success(null); return;
      case 'finishBookScan': this.scanner.finish(); result.success(null); return;
      case 'pickImage': {
        const options = new photoAccessHelper.PhotoSelectOptions();
        options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE; options.maxSelectNumber = 1;
        const selected = await new photoAccessHelper.PhotoViewPicker().select(options);
        result.success(selected.photoUris.length ? await this.stage(selected.photoUris[0], 'pickImage') : null); return;
      }
      case 'pickBooks':
      case 'pickDictionaryFiles':
      case 'pickBook':
      case 'pickTextReference':
      case 'pickOriginalReference':
      case 'pickFont': {
        const view = new picker.DocumentViewPicker(this.context);
        const options = new picker.DocumentSelectOptions();
        options.maxSelectNumber = call.method === 'pickDictionaryFiles' ? 64 : call.method === 'pickBooks' ? 500 : 1;
        if (call.method === 'pickFont') { options.fileSuffixFilters = ['字体|.ttf,.otf,.ttc']; }
        if (call.method === 'pickDictionaryFiles') {
          options.fileSuffixFilters = ['词典|.mdx,.mdd,.mobi,.ifo,.idx,.gz,.dict,.dz,.syn,.zip'];
        }
        const uris = await view.select(options);
        if (call.method === 'pickDictionaryFiles' && uris.length > 64) {
          throw new Error('一次最多选择 64 个词典文件');
        }
        const values: SelectedBook[] = [];
        for (const uri of uris) {
          const name = new fileUri.FileUri(uri).name;
          if ((call.method !== 'pickDictionaryFiles' && call.argument('linkOriginals') === true) || call.method === 'pickTextReference' ||
            call.method === 'pickOriginalReference') {
            try { values.push(await this.linked.retain(uri)); }
            catch (error) {
              if (call.method !== 'pickBooks') { throw error as Error; }
              values.push({ name: name, error: (error as Error).message });
            }
          } else if (call.argument('deferred') === true && call.method === 'pickBooks') {
            const token = util.generateRandomUUID(true);
            this.pending.set(token, uri);
            values.push({ name: name, token: token });
          } else {
            try { values.push(await this.stage(uri, call.method)); }
            catch (error) {
              if (call.method !== 'pickBooks' && call.method !== 'pickDictionaryFiles') { throw error as Error; }
              values.push({ name: name, error: (error as Error).message });
            }
          }
        }
        result.success(call.method === 'pickBooks' || call.method === 'pickDictionaryFiles' ? values : (values.length > 0 ? values[0] : null));
        return;
      }
      case 'openLinkedDocument': result.success(await this.linked.open(this.linkedRequest(call))); return;
      case 'closeLinkedDocument': await this.linked.close(call.argument('lease') as string); result.success(null); return;
      case 'releaseLinkedText': await this.linked.release(call.argument('reference') as string); result.success(null); return;
      case 'inspectLinkedText': result.success(await this.linked.inspectText(this.linkedRequest(call))); return;
      case 'readLinkedText': result.success(await this.linked.readText(this.linkedRequest(call))); return;
      case 'readLinkedBytes': result.success(await this.linked.readBytes(this.linkedRequest(call))); return;
      case 'stageLinkedDocument': {
        const staged: SelectedBook[] = [];
        try {
          const value = await this.linked.withDocument(call.argument('reference') as string,
            async (uri: string, name: string): Promise<SelectedBook> => {
              const copy = await this.stage(uri, 'pickBook');
              staged.push(copy);
              return copy;
            });
          result.success(value);
        } catch (error) {
          for (const copy of staged) {
            if (copy.path !== undefined) { await this.release(copy.path); }
          }
          throw error as Error;
        }
        return;
      }
      case 'stagedTextReference': {
        const path = call.argument('path') as string;
        if (!this.owned.has(path) && !await this.portableInput(path)) { throw linkedUnavailable(); }
        result.success((await this.linked.retain(path, true, '原书.txt')).reference); return;
      }
      case 'stageImportBook': {
        const token = call.argument('token') as string;
        const uri = this.pending.get(token);
        if (!uri) { throw new Error('文件的访问授权已失效，请重新选择'); }
        result.success(await this.stage(uri, 'pickBook'));
        return;
      }
      case 'releaseBooks': {
        const paths = call.argument('paths') as string[] | null;
        for (const path of paths ?? []) { await this.release(path); }
        const tokens = call.argument('tokens') as string[] | null;
        for (const token of tokens ?? []) { this.pending.delete(token); }
        result.success(null);
        return;
      }
      case 'decodeText': {
        const path = await this.decode(call.argument('path') as string, call.argument('encoding') as string,
          40 * 1024 * 1024, 120 * 1024 * 1024);
        let text: string;
        try { text = await fs.readText(path); } finally { await this.release(path); }
        result.success(text);
        return;
      }
      case 'decodeTextFile': {
        result.success(await this.decode(call.argument('path') as string, call.argument('encoding') as string,
          (call.argument('maximumInputBytes') as number | null) ?? 128 * 1024 * 1024,
          (call.argument('maximumOutputBytes') as number | null) ?? 384 * 1024 * 1024));
        return;
      }
      case 'decodeBookNames': {
        const names = call.argument('names') as Uint8Array[];
        if (names.length > 64 || names.some((bytes: Uint8Array) => bytes.length === 0 || bytes.length > 4096)) {
          throw new Error('ZIP 文件名数据无效');
        }
        const decoded: string[] = [];
        for (const bytes of names) {
          let value: string | null = null;
          for (const encoding of ['utf-8', 'gb18030', 'ibm437']) {
            try { value = util.TextDecoder.create(encoding, { fatal: true }).decodeToString(bytes); break; }
            catch (_) { /* Try the next declared legacy encoding, never replace characters. */ }
          }
          if (value === null) { throw new Error('无法识别 ZIP 文件名编码，请使用 UTF-8 文件名重新压缩'); }
          decoded.push(value);
        }
        result.success(decoded);
        return;
      }
      case 'extractKindle': {
        const path = call.argument('path') as string;
        const output = call.argument('output') as string;
        if (!this.owned.has(path) && !await this.portableInput(path)) {
          throw new Error('导入文件的访问授权已失效，请重新选择');
        }
        const source = await fs.lstat(path);
        if (!source.isFile() || source.isSymbolicLink() || source.size <= 0 || source.size > 256 * 1024 * 1024) {
          throw new Error('Kindle 原书为空或超过 256 MiB');
        }
        await this.nativeOutput(output, 'kindle');
        result.success(await bookEngine.extractKindle(path, output));
        return;
      }
      case 'extractPdf': {
        const path = call.argument('path') as string;
        const output = call.argument('output') as string;
        if (!this.owned.has(path) && !await this.portableInput(path)) {
          throw new Error('导入文件的访问授权已失效，请重新选择');
        }
        const source = await fs.lstat(path);
        if (!source.isFile() || source.isSymbolicLink() || source.size <= 0 || source.size > 512 * 1024 * 1024) {
          throw new Error('PDF 原书为空或超过 512 MiB');
        }
        await this.nativeOutput(output, 'pdf');
        // The 512 MiB / 10000-page contract can exceed an ordinary TaskPool task
        // timeout. This worker is released only after extraction has settled.
        const task = new taskpool.LongTask(extractHarmonyPdf, call.argument('name') as string, path, output);
        try { await taskpool.execute(task); } finally { taskpool.terminateTask(task); }
        result.success(null); return;
      }
      case 'prepareLinkedDocument':
      case 'prepareBook':
        result.error('format_unavailable', /\.doc$/i.test(call.argument('name') as string)
          ? '暂不支持旧版二进制 DOC，请先另存为 DOCX 或 RTF 后导入'
          : '无法识别此文档格式，请选择完整的原文件', null);
        return;
      default: result.notImplemented();
    }
  }

  private async allocate(kind: string): Promise<string> {
    try { await fs.mkdir(this.workspace); }
    catch (error) { if (!fs.accessSync(this.workspace)) { throw error as Error; } }
    const path = this.workspace + '/' + kind + '-' + util.generateRandomUUID(true);
    const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    await fs.close(file);
    this.owned.add(path);
    return path;
  }

  private async release(path: string): Promise<void> {
    // Only exact internally allocated names are eligible; external URIs and
    // original provider documents can never be deleted by this method.
    if (!this.owned.has(path)) { return; }
    if (fs.accessSync(path)) { await fs.unlink(path); }
    this.owned.delete(path);
  }

  private linkedRequest(call: MethodCall): LinkedBookRequest {
    const reference = call.argument('reference') as string;
    if (typeof reference !== 'string') { throw linkedUnavailable(); }
    return { reference: reference, size: (call.argument('size') as number | null) ?? undefined,
      modified: (call.argument('modified') as number | null) ?? undefined,
      encoding: (call.argument('encoding') as string | null) ?? undefined,
      offset: (call.argument('offset') as number | null) ?? undefined,
      purpose: (call.argument('purpose') as string | null) ?? undefined };
  }

  private async stage(uri: string, kind: string, suppliedName?: string): Promise<SelectedBook> {
    const name = suppliedName ?? new fileUri.FileUri(uri).name;
    if (kind === 'pickDictionaryFiles' && !/\.(mdx|mdd|mobi|ifo|idx(?:\.gz)?|dict(?:\.dz)?|syn|zip)$/i.test(name)) {
      throw new Error('请选择 MDX、MDD、MOBI 词典、StarDict 文件或 ZIP 词典包');
    }
    const maximum = kind === 'pickDictionaryFiles' ? 512 * 1024 * 1024 : kind === 'pickImage' ? 20 * 1024 * 1024 : kind === 'pickFont' ? 32 * 1024 * 1024 : bookByteLimit(name);
    const input = await fs.open(uri, fs.OpenMode.READ_ONLY);
    let output: string | null = null;
    try {
      const before = await fs.stat(input.fd);
      if (before.size > maximum) { throw new Error('文件超过此格式的导入大小限制'); }
      output = await this.allocate('import');
      const sink = await fs.open(output, fs.OpenMode.WRITE_ONLY);
      let total = 0;
      try {
        const buffer = new ArrayBuffer(256 * 1024);
        let count = await fs.read(input.fd, buffer);
        while (count > 0) {
          total += count;
          if (total > maximum) { throw new Error('文件超过此格式的导入大小限制'); }
          await this.write(sink.fd, buffer.slice(0, count));
          count = await fs.read(input.fd, buffer);
        }
      } finally { await fs.close(sink); }
      if (total <= 0) { throw new Error('文件为空，请检查原文件'); }
      // Virtual/cloud providers can expose a bounded stream without a known
      // regular-file size. Keep their explicit copy-import path usable.
      if (before.isFile() && before.size > 0) {
        const after = await fs.stat(input.fd);
        if (total !== before.size || after.size !== before.size || after.mtimeNs !== before.mtimeNs || after.mtime !== before.mtime) {
          throw new Error('文件在读取时已变化，请重新选择');
        }
      }
      return { name: name, path: output };
    } catch (error) {
      if (output !== null) { await this.release(output); }
      throw error as Error;
    } finally { await fs.close(input); }
  }

  private async write(fd: number, buffer: ArrayBuffer): Promise<void> {
    let offset = 0;
    while (offset < buffer.byteLength) {
      const count = await fs.write(fd, buffer.slice(offset));
      if (count <= 0) { throw new Error('无法写入导入文件，请检查可用空间'); }
      offset += count;
    }
  }

  private async decode(path: string, encoding: string, maximum: number = 128 * 1024 * 1024,
    maximumOutput: number = 384 * 1024 * 1024): Promise<string> {
    if (!Number.isSafeInteger(maximum) || !Number.isSafeInteger(maximumOutput) || maximum <= 0 ||
      maximumOutput <= 0 || maximum > 1024 * 1024 * 1024 || maximumOutput > 1024 * 1024 * 1024) {
      throw new Error('文档转换大小限制无效');
    }
    if (!this.owned.has(path) && !await this.portableInput(path)) { throw new Error('导入文件的访问授权已失效，请重新选择'); }
    const input = await fs.open(path, fs.OpenMode.READ_ONLY);
    let output: string | null = null;
    try {
      const buffer = new ArrayBuffer(64 * 1024);
      let count = await fs.read(input.fd, buffer);
      const selected = bookTextEncoding(encoding || 'auto', new Uint8Array(buffer, 0, count),
        count < (await fs.stat(input.fd)).size);
      const decoder = util.TextDecoder.create(selected, { fatal: true });
      const encoder = new util.TextEncoder();
      output = await this.allocate('decoded');
      const sink = await fs.open(output, fs.OpenMode.WRITE_ONLY);
      try {
        let total = 0;
        let produced = 0;
        while (count > 0) {
          total += count;
          if (total > maximum) { throw new Error('文本超过转换大小限制，请拆分后导入'); }
          const text = decoder.decodeToString(new Uint8Array(buffer, 0, count), { stream: true });
          const bytes = text ? encoder.encodeInto(text) : new Uint8Array(0);
          produced += bytes.byteLength;
          if (produced > maximumOutput) { throw new Error('解码后的文档超过大小限制，请拆分后导入'); }
          await this.write(sink.fd, bytes.buffer as ArrayBuffer);
          count = await fs.read(input.fd, buffer);
        }
        const remaining = decoder.decodeToString(new Uint8Array(0), { stream: false });
        const tail = remaining ? encoder.encodeInto(remaining) : new Uint8Array(0);
        if (produced + tail.byteLength > maximumOutput) { throw new Error('解码后的文档超过大小限制，请拆分后导入'); }
        await this.write(sink.fd, tail.buffer as ArrayBuffer);
      } finally { await fs.close(sink); }
      return output;
    } catch (error) {
      if (output !== null) { await this.release(output); }
      throw error as Error;
    } finally { await fs.close(input); }
  }

  /** Read-only Dart conversion/download quarantines, never deletion grants. */
  private async portableInput(path: string): Promise<boolean> {
    const roots = ['portable-book-import', 'cloud-book-import'].map((name: string): string => this.storage.cacheDir + '/' + name);
    const base = roots.find((root: string): boolean => path.startsWith(root + '/'));
    if (base === undefined) { return false; }
    const parts = path.substring(base.length + 1).split('/');
    if (parts.some((part: string) => part === '' || part === '.' || part === '..' || part.includes('\\'))) { return false; }
    let current = base;
    try {
      if ((await fs.lstat(current)).isSymbolicLink()) { return false; }
      for (const part of parts) {
        current += '/' + part;
        if ((await fs.lstat(current)).isSymbolicLink()) { return false; }
      }
      return (await fs.stat(path)).isFile();
    } catch (_) { return false; }
  }

  /** Export is only permitted into this job's new, empty resource directory. */
  private async nativeOutput(path: string, kind: string): Promise<void> {
    const base = this.storage.cacheDir + '/portable-book-import';
    if (!path.startsWith(base + '/')) { throw new Error('转换暂存目录无效'); }
    const parts = path.substring(base.length + 1).split('/');
    if (parts.length !== 3 || !parts[0].startsWith('job-') || !parts[1].startsWith(kind + '-') || parts[2] !== 'OEBPS' ||
      parts.some((part: string) => part.includes('\\') || part === '.' || part === '..')) {
      throw new Error('转换只能写入本次导入的暂存目录');
    }
    let current = base;
    for (const part of ['', ...parts]) {
      if (part !== '') { current += '/' + part; }
      const stat = await fs.lstat(current);
      if (stat.isSymbolicLink() || !stat.isDirectory()) { throw new Error('转换暂存目录已变化'); }
    }
    if ((await fs.listFile(path)).length !== 0) { throw new Error('转换暂存目录不是空目录'); }
  }
}
