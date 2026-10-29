import util from '@ohos.util';

export class HarmonyDocumentFailure extends Error {
  code: string;
  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

export interface DecodedBookBlock {
  text: string;
  consumed: number;
}

export function bookByteLimit(name: string): number {
  const suffix = name.split('.').pop()?.toLowerCase() ?? '';
  switch (suffix) {
    case 'epub': case 'pdf': case 'docx': case 'zip': return 512 * 1024 * 1024;
    case 'mobi': case 'azw': case 'azw3': case 'prc': return 256 * 1024 * 1024;
    case 'html': case 'htm': case 'xhtml': case 'md': case 'markdown': return 32 * 1024 * 1024;
    default: return 128 * 1024 * 1024;
  }
}

export function linkedUnavailable(): HarmonyDocumentFailure {
  return new HarmonyDocumentFailure('linked_permission',
    '无法访问原文件，请重新定位原文件，或选择「复制到应用」');
}

export function linkedChanged(): HarmonyDocumentFailure {
  return new HarmonyDocumentFailure('linked_changed',
    '原文件已变化，请重新定位；原有阅读进度与书签仍保留');
}

/** A block ends before an incomplete character, never with replacement text. */
export function decodeBookBlock(bytes: Uint8Array, encoding: string, hasMore: boolean): DecodedBookBlock {
  for (let tail = 0; tail <= (hasMore ? 3 : 0); tail++) {
    const consumed = bytes.length - tail;
    if (consumed <= 0) { break; }
    try {
      const label = encoding.toUpperCase() === 'CP932' ? 'windows-31j' : encoding;
      // Harmony's flag means "omit the BOM", unlike WHATWG TextDecoder. Keep
      // the marker so source byte offsets remain aligned with decoded text.
      const text = util.TextDecoder.create(label, { fatal: true, ignoreBOM: false })
        .decodeToString(bytes.subarray(0, consumed));
      if (text.length > 0) { return { text: text, consumed: consumed }; }
    } catch (_) { /* Retry only the at-most-three trailing bytes of a split character. */ }
  }
  throw new HarmonyDocumentFailure('text_encoding',
    '无法按所选编码读取原文件，请在导入设置中选择正确编码');
}

export function bookTextEncoding(value: string, sample: Uint8Array, hasMore: boolean): string {
  const names = ['UTF-8', 'GB18030', 'Big5', 'Big5-HKSCS', 'UTF-16LE', 'UTF-16BE',
    'SHIFT_JIS', 'CP932', 'EUC-JP', 'KOI8-R', 'ISO-8859-1',
    'WINDOWS-1250', 'WINDOWS-1251', 'WINDOWS-1252', 'WINDOWS-1253', 'WINDOWS-1254',
    'WINDOWS-1255', 'WINDOWS-1256', 'WINDOWS-1257', 'WINDOWS-1258'];
  if (value.toLowerCase() !== 'auto') {
    const selected = names.find((name: string) => name.toLowerCase() === value.toLowerCase());
    if (selected === undefined) {
      throw new HarmonyDocumentFailure('text_encoding', '不支持此文字编码');
    }
    return selected;
  }
  if (sample[0] === 0xff && sample[1] === 0xfe) { return 'UTF-16LE'; }
  if (sample[0] === 0xfe && sample[1] === 0xff) { return 'UTF-16BE'; }
  try {
    decodeBookBlock(sample, 'UTF-8', hasMore);
    return 'UTF-8';
  } catch (_) {
    // GB18030 and Big5 overlap: do not silently accept the wrong prose.
    throw new HarmonyDocumentFailure('text_encoding',
      '无法自动确认文字编码，请在导入设置中选择 GB18030／GBK、Big5 或其他原书编码');
  }
}
