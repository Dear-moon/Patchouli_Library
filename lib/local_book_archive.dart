import 'package:archive/archive.dart';

/// Inspect central-directory limits before decoding any entry. File streams
/// keep compressed images on disk until an individual image is requested.
Archive readLocalBookArchive(
  InputStream input, {
  required int maxSize,
  int maxEntrySize = 40 * 1024 * 1024,
}) {
  if (input.length < 22) {
    throw const FormatException('压缩文件不完整，请重新下载原书');
  }
  final headers = ZipDirectory()..read(input);
  if (headers.fileHeaders.isEmpty) {
    throw const FormatException('压缩包中没有可读取的文件');
  }
  if (headers.fileHeaders.length > 12000) {
    throw const FormatException('压缩包包含过多文件');
  }
  var declared = 0;
  for (final header in headers.fileHeaders) {
    declared += header.uncompressedSize;
    if (header.uncompressedSize > maxEntrySize ||
        declared > maxSize ||
        (header.externalFileAttributes >> 16) & 0xf000 == 0xa000) {
      throw const FormatException('压缩包包含不支持的文件或大小超出限制');
    }
  }
  input.setPosition(0);
  final archive = ZipDecoder().decodeStream(input);
  if (archive.length > 12000) throw const FormatException('压缩包包含过多文件');
  var total = 0;
  for (final entry in archive) {
    total += entry.size;
    if (entry.isSymbolicLink ||
        entry.size > maxEntrySize ||
        total > maxSize ||
        entry.name.startsWith('/') ||
        entry.name.contains('\\') ||
        entry.name.split('/').contains('..')) {
      throw const FormatException('压缩包大小或路径不受支持');
    }
  }
  return archive;
}
