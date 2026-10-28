import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import fileUri from '@ohos.file.fileuri';
import image from '@ohos.multimedia.image';
import util from '@ohos.util';
import { systemShare } from '@kit.ShareKit';
import { MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { BusinessError } from '@ohos.base';
import { GallerySaveAuthorizations, GallerySaveFailure, saveGalleryImage } from './HarmonyGalleryAccess';

export interface LocalExportImage { name: string; bytes: Uint8Array; }
export function exportFileName(name: string, fallback: string): string {
  const value = name.replace(/[\\/\x00-\x1f\x7f:*?"<>|]/g, '_').trim();
  return value && value !== '.' && value !== '..' ? value.substring(0, 160) : fallback;
}
export function exportBackupBytes(text: string): Uint8Array {
  if (!text.length) { throw new Error('备份内容为空，请重新导出文库备份'); }
  const bytes = new util.TextEncoder().encodeInto(text);
  if (bytes.length > 4 * 1024 * 1024) { throw new Error('备份超过 4 MiB，请减少本地记录后重试'); }
  return bytes;
}
export async function exportImageBytes(bytes: Uint8Array, name: string, original: boolean): Promise<LocalExportImage> {
  if (!(bytes instanceof Uint8Array) || bytes.length < 16 || bytes.length > (original ? 8 : 12) * 1024 * 1024) { throw new Error('图片格式或大小无效'); }
  const source = image.createImageSource(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  try {
    const info = await source.getImageInfo(); const size = info.size;
    if (size.width <= 0 || size.height <= 0 || size.width > (original ? 80000000 : 12000000) / size.height ||
      !original && (size.width > 4096 || size.height > 8192)) { throw new Error('图片尺寸过大，无法导出'); }
    let suffix: string;
    if (bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71) { suffix = 'png'; }
    else if (original && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) { suffix = 'jpg'; }
    else if (original && bytes[0] === 71 && bytes[1] === 73 && bytes[2] === 70) { suffix = 'gif'; }
    else if (original && bytes[0] === 82 && bytes[1] === 73 && bytes[8] === 87 && bytes[9] === 69) { suffix = 'webp'; }
    else { throw new Error('不支持此图片格式'); }
    const stem = exportFileName(name.replace(/\.[^/.]+$/, ''), original ? '文库插图' : '文库摘录');
    return { name: stem + '.' + suffix, bytes: bytes };
  } finally { await source.release(); }
}

/** Image saves use the gallery; backup pickers and sharing retain their contracts. */
export default class HarmonyLocalFiles {
  private context: common.UIAbilityContext;
  private busy = false;
  private galleryAuthorizations: GallerySaveAuthorizations;
  constructor(context: common.UIAbilityContext, galleryAuthorizations: GallerySaveAuthorizations) {
    this.context = context; this.galleryAuthorizations = galleryAuthorizations;
  }
  supports(method: string): boolean { return ['exportBackup', 'importBackup', 'shareText', 'shareImage', 'exportImage', 'saveBookImage', 'saveImageToGallery'].includes(method); }
  async handle(call: MethodCall, result: MethodResult): Promise<void> {
    if (this.busy) { result.error('document_busy', '请先完成当前文件或分享操作', null); return; }
    this.busy = true;
    try {
      if (call.method === 'importBackup') { result.success(await this.importBackup()); return; }
      if (call.method === 'shareText') {
        const text = call.argument('text') as string;
        if (typeof text !== 'string' || !text.trim() || text.length > 100000) { throw new Error('缺少要分享的文字，或文字过长'); }
        await this.share(new systemShare.SharedData({ utd: 'general.plain-text', content: text })); result.success(null); return;
      }
      let bytes: Uint8Array; let name: string;
      if (call.method === 'exportBackup') {
        const text = call.argument('text') as string;
        if (typeof text !== 'string') { throw new Error('缺少备份内容'); }
        bytes = exportBackupBytes(text); name = exportFileName(call.argument('name') as string || '', '文库备份.json');
      } else {
        const data = await exportImageBytes(call.argument('bytes') as Uint8Array, call.argument('name') as string || '', call.method === 'saveBookImage');
        bytes = data.bytes; name = data.name;
      }
      if (call.method === 'saveImageToGallery' || call.method === 'exportImage' || call.method === 'saveBookImage') {
        await saveGalleryImage(this.context, bytes, name, this.galleryAuthorizations,
          call.argument('authorizationToken') as string | null | undefined);
        result.success(true); return;
      }
      if (call.method === 'shareImage') {
        // Share Kit may hand a file to the recipient after its panel disappears.
        // Retain the small cache copy until a later cache sweep, not the book.
        const folder = this.context.cacheDir + '/.share-work';
        if (!fs.accessSync(folder)) { await fs.mkdir(folder); }
        await this.clearOldShares(folder);
        const path = folder + '/' + util.generateRandomUUID(true) + '-' + name;
        await this.write(path, bytes, true);
        await this.share(new systemShare.SharedData({ utd: 'general.png', uri: fileUri.getUriFromPath(path) })); result.success(null); return;
      }
      const options = new picker.DocumentSaveOptions(); options.newFileNames = [name];
      const destinations = await new picker.DocumentViewPicker(this.context).save(options);
      if (!destinations.length) { result.success(false); return; }
      await this.write(destinations[0], bytes, false); result.success(true);
    } catch (error) {
      const code = (error as BusinessError).code;
      result.error(error instanceof GallerySaveFailure ? error.code : 'local_document', (error as Error).message || '文件操作未完成，请重试',
        new Map<string, string>([['stage', 'ohos_local_tools'], ['operation', call.method], ['code', String(code ?? '')]]));
    } finally { this.busy = false; }
  }
  private async importBackup(): Promise<string | null> {
    const options = new picker.DocumentSelectOptions(); options.maxSelectNumber = 1;
    const selected = await new picker.DocumentViewPicker(this.context).select(options);
    if (!selected.length) { return null; }
    const file = await fs.open(selected[0], fs.OpenMode.READ_ONLY);
    try {
      const stat = await fs.stat(file.fd);
      if (!stat.isFile() || stat.size <= 0 || stat.size > 4 * 1024 * 1024) { throw new Error('备份为空或超过 4 MiB，请重新选择文库备份'); }
      const bytes = new Uint8Array(stat.size); let offset = 0;
      while (offset < bytes.length) {
        const block = new ArrayBuffer(Math.min(65536, bytes.length - offset)); const count = await fs.read(file.fd, block);
        if (count <= 0) { throw new Error('备份未读取完整，请重新选择'); }
        bytes.set(new Uint8Array(block, 0, count), offset); offset += count;
      }
      return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes);
    } finally { await fs.close(file); }
  }
  private async write(path: string, bytes: Uint8Array, create: boolean): Promise<void> {
    const file = await fs.open(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC | (create ? fs.OpenMode.CREATE : 0));
    try {
      let offset = 0;
      while (offset < bytes.length) {
        const count = await fs.write(file.fd, bytes.slice(offset, offset + 65536).buffer as ArrayBuffer);
        if (count <= 0) { throw new Error('文件未写入完整，请重新导出'); } offset += count;
      }
      await fs.fsync(file.fd);
    } finally { await fs.close(file); }
  }
  private async share(data: systemShare.SharedData): Promise<void> {
    const controller = new systemShare.ShareController(data);
    await new Promise<void>((resolve, reject): void => {
      const dismissed = (): void => { controller.off('dismiss', dismissed); resolve(); };
      controller.on('dismiss', dismissed);
      controller.show(this.context, {}).catch((error: Error): void => { controller.off('dismiss', dismissed); reject(error); });
    });
  }
  private async clearOldShares(folder: string): Promise<void> {
    const names = await fs.listFile(folder);
    for (const name of names) {
      const path = folder + '/' + name; const info = await fs.lstat(path);
      if (info.isFile() && !info.isSymbolicLink() && info.mtime * 1000 < Date.now() - 86400000) { await fs.unlink(path); }
    }
  }
}
