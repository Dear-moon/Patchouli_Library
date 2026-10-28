import fileUri from '@ohos.file.fileuri';
import util from '@ohos.util';
import { HarmonyDocumentFailure } from './HarmonyDocumentPolicy';

interface BookOpenRequest { id: string; uri: string; name: string; }

/** Cold/warm system opens keep the original URI until the shared importer finishes. */
export default class HarmonyBookOpenInbox {
  private static requests: BookOpenRequest[] = [];
  static onAvailable: (() => void) | null = null;

  static offer(uri: string, suppliedName?: string): boolean {
    if (typeof uri !== 'string' || !uri.startsWith('file://') || uri.includes('\0')) { return false; }
    let name: string;
    try { name = suppliedName || new fileUri.FileUri(uri).name; } catch (_) { return false; }
    if (!/\.(txt|epub|mobi|azw|azw3|prc|zip|html?|xhtml|md|markdown|fb2|docx?|rtf|pdf)$/i.test(name)) { return false; }
    if (!HarmonyBookOpenInbox.requests.some((request: BookOpenRequest): boolean => request.uri === uri)) {
      HarmonyBookOpenInbox.requests.push({ id: util.generateRandomUUID(true), uri: uri, name: name });
    }
    HarmonyBookOpenInbox.onAvailable?.();
    return true;
  }

  static pending(): Map<string, Object> | null {
    const request = HarmonyBookOpenInbox.requests[0];
    return request ? new Map<string, Object>([['id', request.id], ['name', request.name], ['canLink', true],
      ['canLocate', false], ['canMove', false]]) : null;
  }

  static source(id: string): BookOpenRequest {
    const request = HarmonyBookOpenInbox.requests.find((value: BookOpenRequest): boolean => value.id === id);
    if (!request) { throw new HarmonyDocumentFailure('import_reference', '文件打开请求已结束，请从文件管理重新打开'); }
    return request;
  }

  static finish(id: string): void {
    HarmonyBookOpenInbox.requests = HarmonyBookOpenInbox.requests.filter((request: BookOpenRequest): boolean => request.id !== id);
  }
}
