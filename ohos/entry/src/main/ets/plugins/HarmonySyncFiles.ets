import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import fileShare from '@ohos.fileshare';
import fileUri from '@ohos.file.fileuri';
import picker from '@ohos.file.picker';
import preferences from '@ohos.data.preferences';
import util from '@ohos.util';
import { MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { HarmonyDocumentFailure } from './HarmonyDocumentPolicy';

interface SyncSelection { id: string; uri: string; name: string; created: boolean; }
interface SyncTransaction { selection: string; before: string; output: string; }
interface SyncRecovery { before: string; next: string; }
const maximumSyncBytes = 256 * 1024 * 1024;

/** One editable, user-selected sync document. No book originals are owned here. */
export default class HarmonySyncFiles {
  private context: common.UIAbilityContext;
  private storage: common.Context;
  private store?: preferences.Preferences;
  private selection: SyncSelection | null = null;
  private loadFailure = false;
  private transaction?: SyncTransaction;
  private recovered?: string;
  private workspace: string;
  private recoveryRoot: string;
  private storeName: string;
  constructor(context: common.UIAbilityContext, storage?: common.Context, storeName: string = 'sync-document-v1') {
    if (!/^[a-zA-Z0-9-]{1,80}$/.test(storeName)) { throw new Error('Invalid sync storage name'); }
    this.context = context; this.storage = storage ?? context;
    this.storeName = storeName;
    const suffix = storeName === 'sync-document-v1' ? '' : '-' + storeName;
    this.workspace = this.storage.cacheDir + '/.sync-work' + suffix;
    this.recoveryRoot = this.storage.filesDir + '/sync-recovery' + suffix;
  }
  supports(method: string): boolean {
    return ['syncInfo', 'createSync', 'openSync', 'readSync', 'writeSync', 'disconnectSync', 'recoverSync'].includes(method);
  }
  async handle(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'syncInfo': result.success(await this.info()); return;
      case 'createSync': result.success(await this.select(true)); return;
      case 'openSync': result.success(await this.select(false)); return;
      case 'readSync': result.success(await this.read()); return;
      case 'writeSync': await this.write(call.argument('expectedPath') as string, call.argument('path') as string); result.success(null); return;
      case 'disconnectSync': await this.disconnect(); result.success(null); return;
      case 'recoverSync': result.success(await this.recover(call.argument('which') as string)); return;
      default: result.notImplemented();
    }
  }
  private failure(code: string, message: string): HarmonyDocumentFailure { return new HarmonyDocumentFailure(code, message); }
  private async ready(): Promise<void> {
    if (this.store) { return; }
    const store = await preferences.getPreferences(this.storage, { name: this.storeName });
    const raw = await store.get('selection', '');
    if (raw !== '') {
      try {
        if (typeof raw !== 'string') { throw new Error('Invalid selection'); }
        const value = JSON.parse(raw) as SyncSelection;
        if (typeof value.uri !== 'string' || !value.uri.startsWith('file://') || typeof value.name !== 'string' ||
          typeof value.created !== 'boolean' || typeof value.id !== 'string') { throw new Error('Invalid selection'); }
        this.selection = value;
      } catch (_) { this.loadFailure = true; }
    }
    if (!fs.accessSync(this.workspace)) { await fs.mkdir(this.workspace); }
    // The Documents plugin is the single owner; a fresh instance follows engine
    // detachment/relaunch. Remove only this module's abandoned scratch names.
    for (const name of await fs.listFile(this.workspace)) {
      if (!/^(before|next|frozen|recovery)-[a-fA-F0-9-]{32,36}\.wenku8sync$/.test(name)) { continue; }
      const path = this.workspace + '/' + name, info = await fs.lstat(path);
      if (info.isFile() && !info.isSymbolicLink()) { await fs.unlink(path); }
    }
    if (!fs.accessSync(this.recoveryRoot)) { await fs.mkdir(this.recoveryRoot); }
    this.store = store;
  }
  private policy(uri: string): fileShare.PolicyInfo[] {
    return [{ uri: uri, operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE }];
  }
  private async commit(selection: SyncSelection | null): Promise<void> {
    const store = this.store;
    if (!store) { throw this.failure('sync_settings', '同步文件连接无法读取'); }
    const before = await store.get('selection', '');
    try {
      await store.put('selection', selection === null ? '' : JSON.stringify(selection)); await store.flush();
    } catch (error) { await store.put('selection', before); throw error as Error; }
    this.selection = selection;
    this.loadFailure = false;
  }
  private async select(create: boolean): Promise<Map<string, Object> | null> {
    await this.ready();
    const view = new picker.DocumentViewPicker(this.context);
    let selected: string[];
    if (create) {
      const options = new picker.DocumentSaveOptions(); options.newFileNames = ['文库同步.wenku8sync'];
      selected = await view.save(options);
    } else {
      const options = new picker.DocumentSelectOptions(); options.maxSelectNumber = 1;
      selected = await view.select(options);
    }
    if (!selected.length) { return null; }
    const uri = selected[0], name = new fileUri.FileUri(uri).name;
    if (!name.toLowerCase().endsWith('.wenku8sync')) { throw this.failure('sync_format', '请选择文库生成的 .wenku8sync 同步文件'); }
    const file = await fs.open(uri, fs.OpenMode.READ_WRITE | (create ? fs.OpenMode.CREATE : 0));
    try { await this.size(file.fd); } finally { await fs.close(file); }
    const policies = this.policy(uri);
    const retained = (await fileShare.checkPersistentPermission(policies))[0] === true;
    if (!retained) { await fileShare.persistPermission(policies); }
    const previous = this.selection;
    try { await this.commit({ id: util.generateRandomUUID(true), uri: uri, name: name, created: create }); }
    catch (error) { if (!retained) { await fileShare.revokePermission(policies); } throw error as Error; }
    await this.clearTransaction();
    if (previous && previous.uri !== uri) { await fileShare.revokePermission(this.policy(previous.uri)); }
    return this.info();
  }
  private async selectedFile(write: boolean = false): Promise<fs.File> {
    if (this.loadFailure) { throw this.failure('sync_settings', '同步文件连接无法读取，请重新选择文件'); }
    const selection = this.selection;
    if (!selection) { throw this.failure('sync_missing', '请先选择或创建云同步文件'); }
    try {
      await fileShare.activatePermission(this.policy(selection.uri));
      const file = await fs.open(selection.uri, write ? fs.OpenMode.READ_WRITE : fs.OpenMode.READ_ONLY);
      try { await this.size(file.fd); return file; } catch (error) { await fs.close(file); throw error as Error; }
    } catch (_) {
      await fileShare.deactivatePermission(this.policy(selection.uri)).catch((): void => {});
      throw this.failure('sync_permission', '同步文件访问权限已失效，请重新选择文件；本地数据未删除');
    }
  }
  private async closeSelected(file: fs.File): Promise<void> {
    try { await fs.close(file); }
    finally { if (this.selection) { await fileShare.deactivatePermission(this.policy(this.selection.uri)); } }
  }
  private async info(): Promise<Map<string, Object> | null> {
    await this.ready();
    if (this.loadFailure) { throw this.failure('sync_settings', '同步文件连接无法读取，请重新选择文件'); }
    if (!this.selection) { return null; }
    const file = await this.selectedFile();
    try { return new Map<string, Object>([['name', this.selection.name], ['created', this.selection.created], ['authority', ''], ['provider', '系统文档']]); }
    finally { await this.closeSelected(file); }
  }
  private temporary(kind: string): string { return this.workspace + '/' + kind + '-' + util.generateRandomUUID(true) + '.wenku8sync'; }
  private async size(fd: number): Promise<number> {
    const stat = await fs.stat(fd);
    if (!stat.isFile() || stat.size < 0 || stat.size > maximumSyncBytes) { throw this.failure('sync_size', '同步文件无效或超过 256 MiB'); }
    return stat.size;
  }
  private async local(path: string): Promise<fs.File> {
    const stat = await fs.lstat(path);
    if (!stat.isFile() || stat.isSymbolicLink()) { throw this.failure('sync_transaction', '同步暂存文件已变化，请重新同步'); }
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try { await this.size(file.fd); return file; } catch (error) { await fs.close(file); throw error as Error; }
  }
  private async copyFd(input: number, path: string): Promise<void> {
    const expected = await this.size(input);
    const output = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      await this.transfer(input, output.fd, expected); await fs.fsync(output.fd);
    } finally { await fs.close(output); }
  }
  private async transfer(input: number, output: number, expected: number): Promise<void> {
    fs.lseek(input, 0, fs.WhenceType.SEEK_SET); fs.lseek(output, 0, fs.WhenceType.SEEK_SET);
    let total = 0;
    while (true) {
      const buffer = new ArrayBuffer(65536);
      const count = await fs.read(input, buffer);
      if (count === 0) { break; }
      if (count < 0) { throw this.failure('sync_read', '同步文件未读取完整，请重新同步'); }
      if (total + count > maximumSyncBytes) { throw this.failure('sync_size', '同步文件超过 256 MiB'); }
      let written = 0;
      while (written < count) {
        const amount = await fs.write(output, buffer.slice(written, count));
        if (amount <= 0) { throw this.failure('sync_write', '同步文件未写入完整，恢复副本已保留'); }
        written += amount;
      }
      total += count;
    }
    // Some cloud document providers report zero before materializing content.
    // EOF, not a guessed zero length, determines whether the sync file is empty.
    if (expected > 0 && total !== expected || await this.size(input) !== expected) { throw this.failure('sync_conflict', '同步文件已变化，请重新同步'); }
  }
  private async equal(left: number, right: number): Promise<boolean> {
    const leftSize = await this.size(left), rightSize = await this.size(right);
    if (leftSize > 0 && rightSize > 0 && leftSize !== rightSize) { return false; }
    fs.lseek(left, 0, fs.WhenceType.SEEK_SET); fs.lseek(right, 0, fs.WhenceType.SEEK_SET);
    let offset = 0;
    while (true) {
      const first = await this.readBlock(left), second = await this.readBlock(right);
      if (first.length !== second.length) { return false; }
      if (!first.length) { break; }
      if (offset + first.length > maximumSyncBytes) { throw this.failure('sync_size', '同步文件超过 256 MiB'); }
      for (let index = 0; index < first.length; index++) { if (first[index] !== second[index]) { return false; } }
      offset += first.length;
    }
    return (leftSize === 0 || offset === leftSize) && (rightSize === 0 || offset === rightSize) &&
      leftSize === await this.size(left) && rightSize === await this.size(right);
  }
  private async readBlock(fd: number): Promise<Uint8Array> {
    const output = new Uint8Array(65536);
    let offset = 0;
    while (offset < output.length) {
      const buffer = new ArrayBuffer(output.length - offset), count = await fs.read(fd, buffer);
      if (count === 0) { break; }
      if (count < 0) { throw this.failure('sync_read', '同步文件未读取完整，请重新同步'); }
      output.set(new Uint8Array(buffer, 0, count), offset); offset += count;
    }
    return output.subarray(0, offset);
  }
  private async read(): Promise<Map<string, Object>> {
    await this.ready(); await this.clearTransaction();
    const selected = await this.selectedFile(), before = this.temporary('before'), output = this.temporary('next');
    try {
      await this.copyFd(selected.fd, before);
      const next = await fs.open(output, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY); await fs.close(next);
      this.transaction = { selection: this.selection!.id, before: before, output: output };
      return new Map<string, Object>([['path', before], ['size', (await fs.stat(before)).size], ['outputPath', output]]);
    } catch (error) { await this.remove(before); await this.remove(output); throw error as Error; }
    finally { await this.closeSelected(selected); }
  }
  private async copyLocal(source: string, destination: string): Promise<void> {
    const file = await this.local(source); try { await this.copyFd(file.fd, destination); } finally { await fs.close(file); }
  }
  private async saveRecovery(before: string, next: string): Promise<void> {
    const store = this.store!;
    const old = await store.get('recovery', '');
    const id = util.generateRandomUUID(true), record: SyncRecovery = {
      before: this.recoveryRoot + '/before-' + id + '.wenku8sync', next: this.recoveryRoot + '/next-' + id + '.wenku8sync'
    };
    try {
      await this.copyLocal(before, record.before); await this.copyLocal(next, record.next);
      await store.put('recovery', JSON.stringify(record)); await store.flush();
    } catch (error) {
      await store.put('recovery', old); await this.remove(record.before); await this.remove(record.next); throw error as Error;
    }
    if (typeof old === 'string' && old) {
      const previous = JSON.parse(old) as SyncRecovery;
      if (this.recoveryPath(previous.before) && this.recoveryPath(previous.next)) { await this.remove(previous.before); await this.remove(previous.next); }
    }
  }
  private async write(expectedPath: string, path: string): Promise<void> {
    await this.ready();
    const transaction = this.transaction;
    if (!transaction || transaction.selection !== this.selection?.id || expectedPath !== transaction.before || path !== transaction.output) {
      throw this.failure('sync_transaction', '同步文件连接或暂存已变化，请重新同步');
    }
    const frozen = this.temporary('frozen'); await this.copyLocal(path, frozen);
    const next = await this.local(frozen);
    try {
      const size = await this.size(next.fd);
      if (size <= 0) { throw this.failure('sync_empty', '同步内容为空，未更改云端文件'); }
      const before = await this.local(transaction.before);
      try {
        const target = await this.selectedFile(true);
        try {
          if (!await this.equal(before.fd, target.fd)) { throw this.failure('sync_conflict', '云端文件已发生变化，请重新同步；本地书籍与阅读记录已保留'); }
          await this.saveRecovery(transaction.before, frozen);
          try {
          // Providers expose descriptors, not atomic rename. Keep both durable
          // recovery versions before the first provider mutation.
          await fs.truncate(target.fd, 0); await this.transfer(next.fd, target.fd, size); await fs.fsync(target.fd);
          if (!await this.equal(next.fd, target.fd)) { throw this.failure('sync_write_unconfirmed', '同步文件写入未完整确认，恢复副本已保留，请勿重复覆盖'); }
          const selected = this.selection!;
          await this.commit({ id: selected.id, uri: selected.uri, name: selected.name, created: false });
          } catch (error) {
            if (error instanceof HarmonyDocumentFailure && error.code === 'sync_write_unconfirmed') { throw error; }
            throw this.failure('sync_write', '同步文件未能完成写入或确认，恢复副本已保留；请检查文件提供器或重新选择文件');
          }
        } finally { await this.closeSelected(target); }
      } finally { await fs.close(before); }
      await this.clearTransaction();
    } finally { await fs.close(next); await this.remove(frozen); }
  }
  private recoveryPath(path: string): boolean {
    return typeof path === 'string' && path.startsWith(this.recoveryRoot + '/') && !path.substring(this.recoveryRoot.length + 1).includes('/');
  }
  private async recover(which: string): Promise<string | null> {
    if (which !== 'before' && which !== 'next') { throw this.failure('sync_recovery', '恢复副本类型无效'); }
    await this.ready(); const raw = await this.store!.get('recovery', '');
    if (raw === '') { return null; }
    const record = JSON.parse(raw as string) as SyncRecovery, source = which === 'before' ? record.before : record.next;
    if (!this.recoveryPath(source)) { throw this.failure('sync_recovery', '恢复副本无法读取'); }
    const output = this.temporary('recovery'); await this.copyLocal(source, output);
    if (this.recovered) { await this.remove(this.recovered); }
    this.recovered = output; return output;
  }
  private async disconnect(): Promise<void> {
    await this.ready();
    if (this.selection) { await fileShare.revokePermission(this.policy(this.selection.uri)); }
    await this.commit(null); await this.dispose();
  }
  private async remove(path: string): Promise<void> { if (fs.accessSync(path)) { await fs.unlink(path); } }
  private async clearTransaction(): Promise<void> {
    const transaction = this.transaction; this.transaction = undefined;
    if (transaction) { await this.remove(transaction.before); await this.remove(transaction.output); }
  }
  async dispose(): Promise<void> {
    await this.clearTransaction(); if (this.recovered) { await this.remove(this.recovered); this.recovered = undefined; }
  }
}
