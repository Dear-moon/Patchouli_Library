import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import fileShare from '@ohos.fileshare';
import fileUri from '@ohos.file.fileuri';
import preferences from '@ohos.data.preferences';
import hash from '@ohos.file.hash';
import util from '@ohos.util';
import { bookByteLimit, bookTextEncoding, decodeBookBlock, HarmonyDocumentFailure, linkedChanged, linkedUnavailable } from './HarmonyDocumentPolicy';

interface LinkedBookGrant {
  reference: string;
  uri: string;
  name: string;
  internal: boolean;
}

export interface LinkedBookSelection {
  name: string;
  reference: string;
}

export interface LinkedBookRequest {
  reference: string;
  size?: number;
  modified?: number;
  encoding?: string;
  offset?: number;
  purpose?: string;
}

interface LinkedBookLease {
  file: fs.File;
  grant: LinkedBookGrant;
  size: number;
  modified: number;
}

/** One owner for durable read grants and live descriptors; never deletes originals. */
export default class HarmonyLinkedDocuments {
  private context: common.UIAbilityContext;
  private store: preferences.Preferences | null = null;
  private grants: LinkedBookGrant[] = [];
  private leases = new Map<string, LinkedBookLease>();
  private pendingRevocation = new Set<string>();

  constructor(context: common.UIAbilityContext) { this.context = context; }

  private async ready(): Promise<void> {
    if (this.store !== null) { return; }
    const store = await preferences.getPreferences(this.context, { name: 'linked-book-documents' });
    const raw = await store.get('grants-v1', '[]');
    if (typeof raw !== 'string') { throw linkedUnavailable(); }
    const grants = JSON.parse(raw) as LinkedBookGrant[];
    if (!Array.isArray(grants) || grants.some((grant: LinkedBookGrant) =>
      typeof grant.reference !== 'string' || !/^[a-fA-F0-9-]{32,36}$/.test(grant.reference) ||
      typeof grant.uri !== 'string' || typeof grant.name !== 'string' ||
      typeof grant.internal !== 'boolean')) { throw linkedUnavailable(); }
    this.grants = grants;
    this.store = store;
  }

  private async save(next: LinkedBookGrant[]): Promise<void> {
    const store = this.store;
    if (store === null) { throw linkedUnavailable(); }
    const before = JSON.stringify(this.grants);
    try {
      await store.put('grants-v1', JSON.stringify(next));
      await store.flush();
    } catch (error) {
      // Preferences caches writes before flush: restore that cache on failure.
      await store.put('grants-v1', before);
      throw error as Error;
    }
    this.grants = next;
  }

  private policy(uri: string): fileShare.PolicyInfo[] {
    return [{ uri: uri, operationMode: fileShare.OperationMode.READ_MODE }];
  }

  async retain(uri: string, internal: boolean = false, name?: string): Promise<LinkedBookSelection> {
    await this.ready();
    const label = name ?? new fileUri.FileUri(uri).name;
    let probe: fs.File;
    try { probe = await fs.open(uri, fs.OpenMode.READ_ONLY); } catch (_) { throw linkedUnavailable(); }
    try { this.metadata(await fs.stat(probe.fd), label); }
    finally { await fs.close(probe); }
    const existing = this.grants.some((grant: LinkedBookGrant) => grant.uri === uri);
    const alreadyPersisted = !internal && existing &&
      (await fileShare.checkPersistentPermission(this.policy(uri)))[0] === true;
    if (!internal && !alreadyPersisted) {
      try { await fileShare.persistPermission(this.policy(uri)); } catch (_) { throw linkedUnavailable(); }
    }
    const grant: LinkedBookGrant = {
      reference: util.generateRandomUUID(true), uri: uri, name: label, internal: internal
    };
    const retained = this.pendingRevocation.has(uri)
      ? this.grants.filter((value: LinkedBookGrant) => value.uri !== uri) : this.grants;
    try { await this.save([...retained, grant]); }
    catch (error) {
      if (!internal && !alreadyPersisted && !existing) { await fileShare.revokePermission(this.policy(uri)); }
      throw error as Error;
    }
    this.pendingRevocation.delete(uri);
    return { name: label, reference: grant.reference };
  }

  private metadata(stat: fs.Stat, name: string): number[] {
    if (!stat.isFile() || stat.size <= 0 || stat.size > bookByteLimit(name)) { throw linkedUnavailable(); }
    const modified = stat.mtimeNs === undefined ? stat.mtime * 1000 : Number(stat.mtimeNs / 1000000n);
    return [stat.size, modified];
  }

  private async acquire(args: LinkedBookRequest): Promise<LinkedBookLease> {
    await this.ready();
    const grant = this.grants.find((value: LinkedBookGrant) => value.reference === args.reference);
    if (grant === undefined) { throw linkedUnavailable(); }
    try {
      if (!grant.internal) { await fileShare.activatePermission(this.policy(grant.uri)); }
      const file = await fs.open(grant.uri, fs.OpenMode.READ_ONLY);
      try {
        const data = this.metadata(await fs.stat(file.fd), grant.name);
        if (args.size !== undefined && args.size !== data[0] ||
          args.modified !== undefined && args.modified !== data[1]) { throw linkedChanged(); }
        return { file: file, grant: grant, size: data[0], modified: data[1] };
      } catch (error) { await fs.close(file); throw error as Error; }
    } catch (error) {
      if (!grant.internal && !this.active(grant.uri)) {
        await this.deactivate(grant.uri);
      }
      throw error instanceof HarmonyDocumentFailure ? error : linkedUnavailable();
    }
  }

  private active(uri: string): boolean {
    for (const lease of this.leases.values()) {
      if (lease.grant.uri === uri) { return true; }
    }
    return false;
  }

  private async deactivate(uri: string): Promise<void> {
    if (this.pendingRevocation.has(uri)) {
      const persisted = await fileShare.checkPersistentPermission(this.policy(uri));
      if (persisted[0] === true) {
        await fileShare.deactivatePermission(this.policy(uri));
        await fileShare.revokePermission(this.policy(uri));
      }
      // Keep the record retryable until revocation succeeds; never orphan a grant.
      await this.save(this.grants.filter((grant: LinkedBookGrant) => grant.uri !== uri));
      this.pendingRevocation.delete(uri);
    } else {
      await fileShare.deactivatePermission(this.policy(uri));
    }
  }

  async open(args: LinkedBookRequest): Promise<Map<string, Object>> {
    if (args.purpose !== undefined && args.purpose !== 'text-index') {
      throw new HarmonyDocumentFailure('linked_input', '原文件读取用途无效');
    }
    const lease = await this.acquire(args);
    const token = util.generateRandomUUID(true);
    this.leases.set(token, lease);
    const result = new Map<string, Object>([
      ['lease', token], ['descriptor', lease.file.fd], ['size', lease.size], ['modified', lease.modified]
    ]);
    if (args.purpose === 'text-index') { result.set('offset', 0); }
    return result;
  }

  async close(token: string): Promise<void> {
    const lease = this.leases.get(token);
    if (lease === undefined) { return; }
    this.leases.delete(token);
    try { await fs.close(lease.file); }
    finally {
      if (!lease.grant.internal && !this.active(lease.grant.uri)) { await this.deactivate(lease.grant.uri); }
    }
  }

  async closeAll(): Promise<void> {
    let failure: Error | null = null;
    for (const token of Array.from(this.leases.keys())) {
      try { await this.close(token); } catch (error) { failure = error as Error; }
    }
    if (failure !== null) { throw failure; }
  }

  async release(reference: string): Promise<void> {
    await this.ready();
    const grant = this.grants.find((value: LinkedBookGrant) => value.reference === reference);
    if (grant === undefined) { return; }
    if (!grant.internal && !this.grants.some((value: LinkedBookGrant) =>
      value.uri === grant.uri && value.reference !== reference)) {
      this.pendingRevocation.add(grant.uri);
      if (!this.active(grant.uri)) { await this.deactivate(grant.uri); }
    } else {
      await this.save(this.grants.filter((value: LinkedBookGrant) => value.reference !== reference));
    }
  }

  private async verify(lease: LinkedBookLease): Promise<void> {
    const data = this.metadata(await fs.stat(lease.file.fd), lease.grant.name);
    if (data[0] !== lease.size || data[1] !== lease.modified) { throw linkedChanged(); }
  }

  private async bytes(lease: LinkedBookLease, offset: number, maximum: number): Promise<Uint8Array> {
    if (!Number.isSafeInteger(offset) || offset < 0 || offset >= lease.size) { throw linkedChanged(); }
    const buffer = new ArrayBuffer(Math.min(maximum, lease.size - offset));
    fs.lseek(lease.file.fd, offset, fs.WhenceType.SEEK_SET);
    let done = 0;
    while (done < buffer.byteLength) {
      const part = new ArrayBuffer(buffer.byteLength - done);
      const count = await fs.read(lease.file.fd, part);
      if (count <= 0) { throw linkedChanged(); }
      new Uint8Array(buffer).set(new Uint8Array(part, 0, count), done);
      done += count;
    }
    await this.verify(lease);
    return new Uint8Array(buffer);
  }

  async readBytes(args: LinkedBookRequest): Promise<Uint8Array> {
    const opened = await this.open(args);
    const token = opened.get('lease') as string;
    try { return await this.bytes(this.leases.get(token)!, args.offset ?? -1, 65536); }
    finally { await this.close(token); }
  }

  async inspectText(args: LinkedBookRequest): Promise<Map<string, Object>> {
    const opened = await this.open(args);
    const token = opened.get('lease') as string;
    try {
      const lease = this.leases.get(token)!;
      if (lease.size > 128 * 1024 * 1024) { throw linkedUnavailable(); }
      const first = await this.bytes(lease, 0, 65536);
      const encoding = bookTextEncoding(args.encoding ?? 'auto', first, first.length < lease.size);
      const digest = hash.createHash('sha256');
      digest.update(first.buffer as ArrayBuffer);
      let offset = first.length;
      while (offset < lease.size) {
        const chunk = await this.bytes(lease, offset, 65536);
        digest.update(chunk.buffer as ArrayBuffer);
        offset += chunk.length;
      }
      await this.verify(lease);
      return new Map<string, Object>([
        ['reference', args.reference], ['encoding', encoding], ['size', lease.size],
        ['modified', lease.modified], ['digest', digest.digest().toLowerCase()]
      ]);
    } finally { await this.close(token); }
  }

  async readText(args: LinkedBookRequest): Promise<Map<string, Object>> {
    const opened = await this.open(args);
    const token = opened.get('lease') as string;
    try {
      const lease = this.leases.get(token)!, offset = args.offset ?? -1;
      const input = await this.bytes(lease, offset, 32768);
      const encoding = bookTextEncoding(args.encoding ?? 'auto', input, offset + input.length < lease.size);
      const block = decodeBookBlock(input, encoding, offset + input.length < lease.size);
      return new Map<string, Object>([
        ['textBytes', new util.TextEncoder().encodeInto(block.text)], ['next', offset + block.consumed]
      ]);
    } finally { await this.close(token); }
  }

  async withDocument<T>(reference: string, read: (uri: string, name: string) => Promise<T>): Promise<T> {
    const opened = await this.open({ reference: reference });
    const token = opened.get('lease') as string;
    try {
      const lease = this.leases.get(token)!;
      const value = await read(lease.grant.uri, lease.grant.name);
      await this.verify(lease);
      return value;
    } finally { await this.close(token); }
  }
}
