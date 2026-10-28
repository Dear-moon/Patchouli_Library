import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import fileShare from '@ohos.fileshare';
import preferences from '@ohos.data.preferences';
import picker from '@ohos.file.picker';
import util from '@ohos.util';
import hilog from '@ohos.hilog';
import HarmonyLinkedDocuments, { LinkedBookSelection } from './HarmonyLinkedDocuments';
import { bookByteLimit, HarmonyDocumentFailure } from './HarmonyDocumentPolicy';

interface ScanRoot { uri: string; name: string; internal: boolean; automatic: boolean; }
interface ScanFile { token: string; name: string; uri: string; size: number; modified: number; folder: string; }
interface ScanNode { path: string; relative: string; depth: number; }
interface ScanStamp { uri: string; size: number; modified: number; }
export interface StagedScanBook { name: string; path?: string; error?: string; }
export type ScanStage = (uri: string) => Promise<StagedScanBook>;
const formats: string[] = ['txt', 'epub', 'mobi', 'azw', 'azw3', 'prc', 'zip', 'html', 'htm', 'xhtml', 'md', 'markdown', 'fb2', 'docx', 'rtf', 'pdf'];

/** One serialized owner (the document plugin). Scanning never imports a book. */
export default class HarmonyFolderScanner {
  private context: common.UIAbilityContext;
  private linked: HarmonyLinkedDocuments;
  private stage: ScanStage;
  private documents: string;
  private namespace: string;
  private storage: common.Context;
  private root: ScanRoot | null = null;
  private stamps: ScanStamp[] = [];
  private pending = new Map<string, ScanFile>();
  private store: preferences.Preferences | null = null;
  private revocations: string[] = [];
  constructor(context: common.UIAbilityContext, linked: HarmonyLinkedDocuments, stage: ScanStage,
    documents?: string, namespace: string = 'book-folder-scan-v1', storage?: common.Context) {
    this.storage = storage ?? context;
    const root = documents ?? this.storage.filesDir + '/flutter';
    if (!root.startsWith(this.storage.filesDir + '/') && !root.startsWith(this.storage.cacheDir + '/')) { throw new Error('应用文档目录无效'); }
    this.context = context; this.linked = linked; this.stage = stage; this.documents = root; this.namespace = namespace;
  }
  private failure(): HarmonyDocumentFailure { return new HarmonyDocumentFailure('scan_permission', '扫描文件夹暂时无法读取，请重新选择；已导入的书籍保留'); }
  private policy(root: ScanRoot): fileShare.PolicyInfo[] { return [{ uri: root.uri, operationMode: fileShare.OperationMode.READ_MODE }]; }
  private async ready(): Promise<preferences.Preferences> {
    if (this.store) { return this.store; }
    const store = await preferences.getPreferences(this.context, { name: this.namespace });
    const text = await store.get('root', '') as string;
    if (text) {
      const root = JSON.parse(text) as ScanRoot;
      if (typeof root.uri !== 'string' || typeof root.name !== 'string' || typeof root.internal !== 'boolean' || typeof root.automatic !== 'boolean' ||
        root.internal && root.uri !== this.documents && root.uri !== this.context.filesDir + '/UserDocuments' &&
        root.uri !== this.context.filesDir + '/flutter') { throw this.failure(); }
      this.root = root;
    }
    const saved = JSON.parse(await store.get('completed', '[]') as string) as ScanStamp[];
    if (!Array.isArray(saved) || saved.length > 50000 || saved.some((stamp: ScanStamp): boolean => typeof stamp.uri !== 'string' ||
      !Number.isFinite(stamp.size) || stamp.size <= 0 || !Number.isFinite(stamp.modified))) { throw this.failure(); }
    const revocations = JSON.parse(await store.get('revocations', '[]') as string) as string[];
    if (!Array.isArray(revocations) || revocations.some((uri: string): boolean => typeof uri !== 'string')) { throw this.failure(); }
    this.stamps = saved; this.revocations = revocations; this.store = store;
    await this.revokePending(); return store;
  }
  private async revokePending(): Promise<void> {
    const store = this.store; if (!store) { return; }
    for (const uri of [...this.revocations]) {
      try {
        await fileShare.revokePermission([{ uri: uri, operationMode: fileShare.OperationMode.READ_MODE }]);
        const next = this.revocations.filter((value: string): boolean => value !== uri);
        await store.put('revocations', JSON.stringify(next)); await store.flush(); this.revocations = next;
      } catch (_) { hilog.error(0, 'BookFolderScan', '旧扫描目录授权暂未释放，已保留待重试记录'); }
    }
  }
  private async withRoot<T>(work: (root: ScanRoot, path: string) => Promise<T>): Promise<T> {
    await this.ready(); const root = this.root; if (!root) { throw this.failure(); }
    let file: fs.File | undefined;
    try {
      if (!root.internal) { await fileShare.activatePermission(this.policy(root)); }
      file = await fs.open(root.uri, fs.OpenMode.READ_ONLY);
      if (!(await fs.stat(file.fd)).isDirectory()) { throw this.failure(); }
      return await work(root, file.path);
    } finally {
      if (file) { await fs.close(file); }
      if (!root.internal) { await fileShare.deactivatePermission(this.policy(root)); }
    }
  }
  async info(): Promise<Map<string, Object> | null> {
    await this.ready(); if (!this.root) { return null; }
    let readable = true; try { await this.withRoot(async (_root: ScanRoot, _path: string): Promise<void> => {}); } catch (_) { readable = false; }
    return new Map<string, Object>([['name', this.root.name], ['automatic', this.root.automatic], ['readable', readable], ['all', this.root.internal]]);
  }
  async applicationDocuments(): Promise<Map<string, Object> | null> {
    if (!fs.accessSync(this.documents)) { await fs.mkdir(this.documents); }
    await this.select({ uri: this.documents, name: '应用文档', internal: true, automatic: false }); return this.info();
  }
  async selectFolder(): Promise<Map<string, Object> | null> {
    const options = new picker.DocumentSelectOptions(); options.maxSelectNumber = 1; options.selectMode = picker.DocumentSelectMode.FOLDER;
    const uris = await new picker.DocumentViewPicker(this.context).select(options);
    if (!uris.length) { return null; }
    const selected = uris[0]; const info = new fileUri.FileUri(selected);
    await this.select({ uri: selected, name: info.name || '指定文件夹', internal: false, automatic: false }); return this.info();
  }
  private async select(next: ScanRoot): Promise<void> {
    const store = await this.ready(); const before = this.root;
    const revocations = (before && !before.internal && before.uri !== next.uri
      ? Array.from(new Set(this.revocations.concat([before.uri]))) : this.revocations)
      .filter((uri: string): boolean => uri !== next.uri);
    if (!next.internal) { await fileShare.persistPermission(this.policy(next)); }
    try {
      const probe = await fs.open(next.uri, fs.OpenMode.READ_ONLY);
      try { if (!(await fs.stat(probe.fd)).isDirectory()) { throw this.failure(); } } finally { await fs.close(probe); }
      await store.put('root', JSON.stringify(next)); await store.put('completed', '[]');
      await store.put('revocations', JSON.stringify(revocations)); await store.flush();
    } catch (error) {
      await store.put('root', before ? JSON.stringify(before) : '');
      await store.put('completed', JSON.stringify(this.stamps)); await store.put('revocations', JSON.stringify(this.revocations));
      if (!next.internal && before?.uri !== next.uri) { await fileShare.revokePermission(this.policy(next)); }
      throw error as Error;
    }
    this.root = next; this.stamps = []; this.pending.clear(); this.revocations = revocations; await this.revokePending();
  }
  async automatic(value: boolean): Promise<void> {
    const store = await this.ready(); if (!this.root) { throw this.failure(); }
    const next: ScanRoot = { uri: this.root.uri, name: this.root.name, internal: this.root.internal, automatic: value };
    await store.put('root', JSON.stringify(next)); await store.flush(); this.root = next;
  }
  async disconnect(): Promise<void> {
    const store = await this.ready();
    const revocations = this.root && !this.root.internal ? Array.from(new Set(this.revocations.concat([this.root.uri]))) : this.revocations;
    await store.delete('root'); await store.delete('completed'); await store.put('revocations', JSON.stringify(revocations)); await store.flush();
    this.root = null; this.stamps = []; this.pending.clear(); this.revocations = revocations; await this.revokePending();
  }
  async scanFormats(): Promise<string[]> {
    const store = await this.ready(); const raw = await store.get('formats', formats.join(',')) as string;
    return raw.split(',').filter((value: string): boolean => formats.includes(value));
  }
  async setFormats(values: string[]): Promise<void> {
    if (!Array.isArray(values) || values.some((value: string): boolean => !formats.includes(value))) { throw new Error('扫描格式无效'); }
    const store = await this.ready(); await store.put('formats', Array.from(new Set(values)).join(',')); await store.flush();
  }
  async scan(): Promise<Map<string, Object>> {
    const extensions = await this.scanFormats(); this.pending.clear();
    const books: Map<string, Object>[] = []; const warnings: string[] = []; let total = 0; let unchanged = 0; let examined = 0;
    await this.withRoot(async (root: ScanRoot, base: string): Promise<void> => {
      const queue: ScanNode[] = [{ path: base, relative: '', depth: 0 }];
      const known = new Map<string, ScanStamp>(); this.stamps.forEach((stamp: ScanStamp): void => { known.set(stamp.uri, stamp); });
      while (queue.length && examined < 50000 && books.length < 10000) {
        const node = queue.shift(); if (!node) { break; }
        let names: string[];
        try { names = await fs.listFile(node.path, { recursion: false, listNum: 10001 }); }
        catch (_) { if (warnings.length < 32) { warnings.push((node.relative || root.name) + '：子目录无法读取，已跳过'); } continue; }
        if (names.length >= 10001 && warnings.length < 32) { warnings.push((node.relative || root.name) + '：文件过多，部分文件留待下次选择'); }
        names.sort();
        for (const name of names) {
          if (++examined > 50000 || books.length >= 10000) { break; }
          if (!name || name === '.' || name === '..' || name.includes('/') || name.includes('\\') || name.startsWith('.')) { continue; }
          const path = node.path + '/' + name; const relative = node.relative ? node.relative + '/' + name : name;
          try {
            const stat = await fs.lstat(path); if (stat.isSymbolicLink()) { continue; }
            if (stat.isDirectory()) { if (node.depth < 32) { queue.push({ path: path, relative: relative, depth: node.depth + 1 }); } continue; }
            const extension = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
            if (!stat.isFile() || stat.size <= 0 || !extensions.includes(extension)) { continue; }
            total++;
            if (stat.size > bookByteLimit(name)) { if (warnings.length < 32) { warnings.push(name + '：超过此格式的大小限制'); } continue; }
            const uri = root.internal ? path : root.uri.replace(/\/$/, '') + '/' + relative.split('/').map((part: string): string => encodeURIComponent(part)).join('/');
            const modified = stat.mtimeNs === undefined ? stat.mtime * 1000 : Number(stat.mtimeNs / 1000000n);
            const prior = known.get(uri); if (prior && prior.size === stat.size && prior.modified === modified) { unchanged++; continue; }
            const entry: ScanFile = { token: util.generateRandomUUID(true), name: name, uri: uri, size: stat.size, modified: modified, folder: node.relative };
            this.pending.set(entry.token, entry); books.push(new Map<string, Object>([['token', entry.token], ['name', name], ['size', entry.size], ['folder', entry.folder]]));
          } catch (_) { if (warnings.length < 32) { warnings.push(name + '：读取失败，已跳过'); } }
        }
      }
      if (queue.length || examined >= 50000 || books.length >= 10000) { warnings.push('本次扫描已达到数量上限，可选择更小的文件夹继续'); }
    });
    return new Map<string, Object>([['books', books], ['total', total], ['unchanged', unchanged], ['warnings', warnings]]);
  }
  private async checked(token: string): Promise<ScanFile> {
    const entry = this.pending.get(token); if (!entry) { throw this.failure(); }
    const file = await fs.open(entry.uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = await fs.stat(file.fd); const modified = stat.mtimeNs === undefined ? stat.mtime * 1000 : Number(stat.mtimeNs / 1000000n);
      if (!stat.isFile() || stat.size !== entry.size || modified !== entry.modified) { throw new Error('文件在扫描后已变化，请重新扫描'); }
    } finally { await fs.close(file); }
    return entry;
  }
  async stageBook(token: string): Promise<StagedScanBook> {
    return this.withRoot(async (_root: ScanRoot, _path: string): Promise<StagedScanBook> => this.stage((await this.checked(token)).uri));
  }
  async linkBook(token: string): Promise<LinkedBookSelection> {
    return this.withRoot(async (root: ScanRoot, _path: string): Promise<LinkedBookSelection> => {
      const entry = await this.checked(token); return this.linked.retain(entry.uri, root.internal, entry.name);
    });
  }
  async mark(token: string): Promise<void> {
    const store = await this.ready();
    await this.withRoot(async (_root: ScanRoot, _path: string): Promise<void> => {
      const entry = await this.checked(token);
      const next = this.stamps.filter((stamp: ScanStamp): boolean => stamp.uri !== entry.uri);
      next.push({ uri: entry.uri, size: entry.size, modified: entry.modified });
      if (next.length > 50000) { throw new Error('扫描记录已达到上限，请重新选择扫描文件夹'); }
      await store.put('completed', JSON.stringify(next)); await store.flush(); this.stamps = next;
    });
  }
  finish(): void { this.pending.clear(); }
}
