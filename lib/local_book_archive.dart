import 'dart:typed_data';

import 'package:archive/archive.dart';

class LocalBookArchiveCorruption extends FormatException {
  LocalBookArchiveCorruption(this.path, this.reason)
    : super(path == null ? '压缩文件损坏，请重新下载完整原书' : '压缩文件内容损坏：$path，请重新下载完整原书');
  final String? path;
  final String reason;
}

LocalBookArchiveCorruption _damagedArchive([
  String? path,
  String reason = 'ZIP 文件记录损坏',
]) => LocalBookArchiveCorruption(path, reason);

/// Check a requested entry, without expanding unrelated text or images.
/// [ArchiveFile.readBytes] alone does not verify ZIP CRCs or short output.
Uint8List readLocalBookArchiveEntry(ArchiveFile file) {
  try {
    final output = OutputMemoryStream();
    file.writeContent(output);
    final bytes = output.getBytes();
    if (bytes.length != file.size) {
      throw _damagedArchive(file.name, '展开后的大小与 ZIP 目录不一致');
    }
    if (file.crc32 != null && getCrc32(bytes) != file.crc32) {
      throw _damagedArchive(file.name, '内容 CRC 校验不一致');
    }
    return bytes;
  } on LocalBookArchiveCorruption {
    rethrow;
  } on ArchiveException {
    throw _damagedArchive(file.name, '压缩内容无法解码');
  } on FormatException {
    throw _damagedArchive(file.name, '压缩内容无法解码');
  } on RangeError {
    throw _damagedArchive(file.name, '压缩内容不完整');
  }
}

/// Inspect directory limits and local-record structure before decoding entries.
/// File streams keep compressed images on disk until an image is requested.
Archive readLocalBookArchive(
  InputStream input, {
  required int maxSize,
  int maxEntrySize = 40 * 1024 * 1024,
}) {
  if (input.totalLength < 22) {
    throw const FormatException('压缩文件不完整，请重新下载原书');
  }
  final ZipDirectory headers;
  try {
    headers = ZipDirectory()..read(input);
    _checkArchiveStructure(input, headers);
  } on ArchiveException {
    throw _damagedArchive();
  } on RangeError {
    throw _damagedArchive();
  }
  if (headers.fileHeaders.isEmpty) {
    throw const FormatException('压缩包中没有可读取的文件');
  }
  if (headers.fileHeaders.length > 12000) {
    throw const FormatException('压缩包包含过多文件');
  }
  var declared = 0;
  for (final header in headers.fileHeaders) {
    declared += header.uncompressedSize;
    _checkEntryLimits(header, declared, maxSize, maxEntrySize);
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
        _unsupportedPath(entry.name)) {
      throw const FormatException('压缩包大小或路径不受支持');
    }
  }
  return archive;
}

class LocalBookArchiveRecovery {
  const LocalBookArchiveRecovery(this.archive, this.damagedEntries);
  final Archive archive;
  final Map<String, String> damagedEntries;
}

/// Only the explicitly selected recovery import uses this entry point. The
/// central directory must be readable; unsafe paths and size limits still fail.
/// Damaged local records stay in [damagedEntries], never as invented content.
LocalBookArchiveRecovery readLocalBookArchiveForRecovery(
  InputStream input, {
  required int maxSize,
  int maxEntrySize = 40 * 1024 * 1024,
}) {
  final directory = _readRecoveryDirectory(input);
  if (directory.fileHeaders.isEmpty) {
    throw const FormatException('压缩包中没有可读取的文件');
  }
  if (directory.fileHeaders.length > 12000) {
    throw const FormatException('压缩包包含过多文件');
  }
  var declared = 0;
  final names = <String>{};
  for (final header in directory.fileHeaders) {
    declared += header.uncompressedSize;
    _checkEntryLimits(header, declared, maxSize, maxEntrySize);
    if (header.diskNumberStart != 0 || header.generalPurposeBitFlag & 1 != 0) {
      throw const FormatException('不支持分卷或加密 ZIP，请选择未加密的完整原书');
    }
    if (!const {0, 8, 12, 93}.contains(header.compressionMethod)) {
      throw const FormatException('EPUB 使用暂不支持的压缩方式');
    }
    if (!names.add(header.filename)) {
      throw const FormatException('压缩目录包含重复资源，无法安全恢复');
    }
  }
  final archive = Archive();
  final damaged = <String, String>{};
  final sorted = directory.fileHeaders.toList()
    ..sort((a, b) => a.localHeaderOffset.compareTo(b.localHeaderOffset));
  for (var index = 0; index < sorted.length; index++) {
    final header = sorted[index];
    final next = index + 1 < sorted.length
        ? sorted[index + 1].localHeaderOffset
        : directory.centralDirectoryOffset;
    final limit = next.clamp(0, directory.centralDirectoryOffset);
    try {
      _checkArchiveEntryStructure(
        input,
        header,
        limit,
        directory.centralDirectoryOffset,
      );
      final content = ZipFile(header)
        ..read(
          input.subset(
            position: header.localHeaderOffset,
            length: limit - header.localHeaderOffset,
          ),
        );
      final entry = header.filename.endsWith('/')
          ? ArchiveFile.directory(header.filename)
          : ArchiveFile.file(header.filename, header.uncompressedSize, content);
      entry
        ..compression = content.compressionMethod
        ..crc32 = header.crc32
        ..mode = header.externalFileAttributes >> 16
        ..lastModTime =
            header.lastModifiedFileDate << 16 | header.lastModifiedFileTime;
      archive.add(entry);
    } on LocalBookArchiveCorruption catch (error) {
      damaged[header.filename] = error.reason;
    } on ArchiveException {
      damaged[header.filename] = 'ZIP 本地文件记录无法读取';
    } on RangeError {
      damaged[header.filename] = 'ZIP 本地文件记录不完整';
    }
  }
  return LocalBookArchiveRecovery(archive, damaged);
}

void _checkEntryLimits(
  ZipFileHeader header,
  int total,
  int maxSize,
  int maxEntrySize,
) {
  if (header.uncompressedSize < 0 ||
      header.uncompressedSize > maxEntrySize ||
      total > maxSize ||
      (header.externalFileAttributes >> 16) & 0xf000 == 0xa000) {
    throw const FormatException('压缩包包含不支持的文件或大小超出限制');
  }
  if (_unsupportedPath(header.filename)) {
    throw const FormatException('压缩包大小或路径不受支持');
  }
}

// ZipDirectory.read eagerly visits local records. Read only its central-header
// metadata here, so one broken local record cannot hide healthy later records.
ZipDirectory _readRecoveryDirectory(InputStream input) {
  try {
    final length = input.totalLength;
    if (length < 22) throw _damagedArchive();
    final tailStart = length > 65557 ? length - 65557 : 0;
    final tail = input.subset(position: tailStart).toUint8List();
    final bytes = ByteData.sublistView(tail);
    var eocd = -1;
    for (var at = tail.length - 22; at >= 0; at--) {
      if (bytes.getUint32(at, Endian.little) == ZipDirectory.eocdSignature &&
          at + 22 + bytes.getUint16(at + 20, Endian.little) == tail.length) {
        eocd = tailStart + at;
        break;
      }
    }
    if (eocd < 0) throw _damagedArchive();
    final end = input.subset(position: eocd, length: 22)..skip(4);
    final directory = ZipDirectory()
      ..filePosition = eocd
      ..numberOfThisDisk = end.readUint16()
      ..diskWithTheStartOfTheCentralDirectory = end.readUint16()
      ..totalCentralDirectoryEntriesOnThisDisk = end.readUint16()
      ..totalCentralDirectoryEntries = end.readUint16()
      ..centralDirectorySize = end.readUint32()
      ..centralDirectoryOffset = end.readUint32();
    if (eocd >= 20) {
      final locator = input.subset(position: eocd - 20, length: 20);
      if (locator.readUint32() == ZipDirectory.zip64EocdLocatorSignature) {
        if (locator.readUint32() != 0) throw _damagedArchive();
        final offset = locator.readUint64();
        if (locator.readUint32() != 1 ||
            offset < 0 ||
            offset + 56 > eocd - 20) {
          throw _damagedArchive();
        }
        final wide = input.subset(position: offset, length: eocd - 20 - offset);
        if (wide.readUint32() != ZipDirectory.zip64EocdSignature ||
            wide.readUint64() < 44) {
          throw _damagedArchive();
        }
        wide.skip(4);
        directory
          ..numberOfThisDisk = wide.readUint32()
          ..diskWithTheStartOfTheCentralDirectory = wide.readUint32()
          ..totalCentralDirectoryEntriesOnThisDisk = wide.readUint64()
          ..totalCentralDirectoryEntries = wide.readUint64()
          ..centralDirectorySize = wide.readUint64()
          ..centralDirectoryOffset = wide.readUint64();
      }
    }
    if (directory.numberOfThisDisk != 0 ||
        directory.diskWithTheStartOfTheCentralDirectory != 0 ||
        directory.totalCentralDirectoryEntriesOnThisDisk !=
            directory.totalCentralDirectoryEntries ||
        directory.totalCentralDirectoryEntries > 12000 ||
        directory.totalCentralDirectoryEntries < 0 ||
        directory.centralDirectoryOffset < 0 ||
        directory.centralDirectorySize < 0 ||
        directory.centralDirectoryOffset + directory.centralDirectorySize >
            eocd) {
      throw _damagedArchive();
    }
    final central = input.subset(
      position: directory.centralDirectoryOffset,
      length: directory.centralDirectorySize,
    );
    for (
      var index = 0;
      index < directory.totalCentralDirectoryEntries;
      index++
    ) {
      if (central.length < 46) throw _damagedArchive();
      final fixed = central.peekBytes(46);
      if (fixed.readUint32() != ZipFileHeader.signature) {
        throw _damagedArchive();
      }
      fixed.skip(24);
      final variable =
          fixed.readUint16() + fixed.readUint16() + fixed.readUint16();
      if (46 + variable > central.length) throw _damagedArchive();
      central.skip(4);
      directory.fileHeaders.add(ZipFileHeader()..read(central));
    }
    if (!central.isEOS) {
      if (central.length < 6 ||
          central.readUint32() != 0x05054b50 ||
          central.readUint16() != central.length) {
        throw _damagedArchive();
      }
    }
    return directory;
  } on ArchiveException {
    throw _damagedArchive();
  } on RangeError {
    throw _damagedArchive();
  }
}

bool _unsupportedPath(String name) =>
    name.startsWith('/') ||
    name.contains('\\') ||
    name.split('/').contains('..');

void _checkArchiveStructure(InputStream input, ZipDirectory directory) {
  final start = directory.centralDirectoryOffset;
  final size = directory.centralDirectorySize;
  if (directory.filePosition < 0 ||
      directory.numberOfThisDisk != 0 ||
      directory.diskWithTheStartOfTheCentralDirectory != 0 ||
      directory.totalCentralDirectoryEntriesOnThisDisk !=
          directory.totalCentralDirectoryEntries ||
      directory.fileHeaders.length != directory.totalCentralDirectoryEntries ||
      start < 0 ||
      size < 0 ||
      start + size > directory.filePosition ||
      directory.filePosition + 22 > input.totalLength) {
    throw _damagedArchive();
  }
  final sorted = directory.fileHeaders.toList()
    ..sort((a, b) => a.localHeaderOffset.compareTo(b.localHeaderOffset));
  for (var index = 0; index < sorted.length; index++) {
    final header = sorted[index];
    final limit = index + 1 < sorted.length
        ? sorted[index + 1].localHeaderOffset
        : start;
    _checkArchiveEntryStructure(input, header, limit, start);
  }
}

void _checkArchiveEntryStructure(
  InputStream input,
  ZipFileHeader header,
  int limit,
  int start,
) {
  final offset = header.localHeaderOffset;
  if (header.diskNumberStart != 0 ||
      offset < 0 ||
      offset + 30 > limit ||
      limit > start ||
      header.compressedSize < 0 ||
      header.uncompressedSize < 0) {
    throw _damagedArchive(header.filename, 'ZIP 本地记录位置或长度无效');
  }
  final local = input.subset(position: offset, length: limit - offset);
  if (local.readUint32() != ZipFile.zipSignature) {
    throw _damagedArchive(header.filename, 'ZIP 本地文件头损坏');
  }
  local.skip(2); // version needed
  final flags = local.readUint16();
  final method = local.readUint16();
  local.skip(4); // modification time and date
  final crc = local.readUint32();
  final compressed = local.readUint32();
  final uncompressed = local.readUint32();
  final nameLength = local.readUint16();
  final extraLength = local.readUint16();
  final dataStart = offset + 30 + nameLength + extraLength;
  final dataEnd = dataStart + header.compressedSize;
  if (flags & 1 != 0) {
    throw const FormatException('不支持加密 ZIP，请选择未加密的完整原书');
  }
  if (dataStart > limit || dataEnd > limit) {
    throw _damagedArchive(header.filename);
  }
  final name = local.readString(size: nameLength);
  if (_unsupportedPath(name)) {
    throw const FormatException('压缩包大小或路径不受支持');
  }
  if (flags != header.generalPurposeBitFlag ||
      method != header.compressionMethod ||
      name != header.filename) {
    throw _damagedArchive(header.filename);
  }
  if (flags & 8 == 0) {
    // Zip64 places real sizes in the extra field, not these 32-bit fields.
    if (crc != header.crc32 ||
        compressed != 0xffffffff && compressed != header.compressedSize ||
        uncompressed != 0xffffffff && uncompressed != header.uncompressedSize) {
      throw _damagedArchive(header.filename);
    }
  } else {
    // Streaming writers put CRC/sizes after the compressed payload. The
    // decoder reads those too; do not let a truncated descriptor read into
    // the next local header or the central directory.
    var zip64 = false;
    final extra = local.readBytes(extraLength);
    while (extra.length >= 4) {
      final id = extra.readUint16();
      final length = extra.readUint16();
      if (length > extra.length) throw _damagedArchive(header.filename);
      if (id == 1) zip64 = true;
      extra.skip(length);
    }
    final descriptor = input.subset(position: dataEnd, length: limit - dataEnd);
    final minimum = zip64 ? 20 : 12;
    if (descriptor.length < minimum) throw _damagedArchive(header.filename);
    final signatureOrCrc = descriptor.readUint32();
    final hasSignature = signatureOrCrc == 0x08074b50;
    if (hasSignature && descriptor.length < minimum) {
      throw _damagedArchive(header.filename);
    }
    final descriptorCrc = hasSignature
        ? descriptor.readUint32()
        : signatureOrCrc;
    final descriptorCompressed = zip64
        ? descriptor.readUint64()
        : descriptor.readUint32();
    final descriptorUncompressed = zip64
        ? descriptor.readUint64()
        : descriptor.readUint32();
    if (descriptorCrc != header.crc32 ||
        descriptorCompressed != header.compressedSize ||
        descriptorUncompressed != header.uncompressedSize) {
      throw _damagedArchive(header.filename);
    }
  }
}
