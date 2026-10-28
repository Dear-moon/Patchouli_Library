import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as markdown;
import 'package:xml/xml.dart' as xml;
import 'package:xml/xml_events.dart' as events;

import 'book_import_limits.dart';
import 'epub_image_styles.dart';
import 'epub_rich_text.dart';
import 'local_markup_decode.dart';

part 'portable_markup_prepare.dart';
part 'portable_structured_prepare.dart';
part 'portable_rtf_prepare.dart';
part 'portable_kindle_prepare.dart';

typedef PreparedBookDocument = ({String name, String? path, String? error});
typedef PrepareBookDocument =
    Future<List<PreparedBookDocument>> Function(String name, String path);
typedef DecodeBookNames = Future<List<String>> Function(List<Uint8List> names);
typedef ExtractKindle = Future<int> Function(String source, String directory);
typedef ExtractPdf =
    Future<void> Function(String name, String source, String directory);

/// Only owns outputs it creates. Source files and native working copies retain
/// their existing owner. Heavy ZIP work runs in an isolate with bounded buffers.
class PortableBookPreparer {
  PortableBookPreparer({
    required this.directory,
    required this.decodeNames,
    required this.convert,
    this.textCodecToken,
    this.extractKindle,
    this.extractPdf,
  });
  final Directory directory;
  final DecodeBookNames decodeNames;
  final PrepareBookDocument convert;
  final ExtractKindle? extractKindle;
  final ExtractPdf? extractPdf;
  // Production supplies the root token so request/response decoding remains
  // native and strictly bounded without moving HTML parsing onto the UI thread.
  final RootIsolateToken? textCodecToken;
  final _outputs = <String, _PreparationJob>{};
  Future<void> _releaseQueue = Future.value();

  /// Called once for this app-private cache, before the shared preparer exists.
  /// A killed import leaves only disposable job-* directories here. Links are
  /// removed as links, and unrelated names or sibling caches are left alone.
  static Future<void> clearPreviousRuns(Directory directory) async {
    await directory.create(recursive: true);
    await for (final entry in directory.list(followLinks: false)) {
      if (!entry.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last
          .startsWith('job-')) {
        continue;
      }
      if (entry is Directory) await entry.delete(recursive: true);
      if (entry is Link) await entry.delete();
    }
  }

  Future<List<PreparedBookDocument>> prepare(String name, String path) async {
    await directory.create(recursive: true);
    final work = await Directory(
      await directory.resolveSymbolicLinks(),
    ).createTemp('job-');
    final job = _PreparationJob(work);
    try {
      final results = <PreparedBookDocument>[];
      if (_isPortableDocument(name)) {
        results.add(await _markup(name, path, work.path));
      } else if (_isKindle(name)) {
        results.addAll(
          extractKindle != null
              ? [await _kindle(name, path, work)]
              : await convert(name, path),
        );
      } else if (name.toLowerCase().endsWith('.pdf')) {
        results.addAll(
          extractPdf != null
              ? [await _pdf(name, path, work)]
              : await convert(name, path),
        );
      } else {
        final unpacked = await compute(_unpackBooks, (
          source: path,
          directory: work.path,
        ), debugLabel: 'local-zip-prepare');
        final names = <String>[];
        for (var start = 0; start < unpacked.names.length; start += 64) {
          final chunk = unpacked.names.sublist(
            start,
            math.min(start + 64, unpacked.names.length),
          );
          final decoded = await decodeNames(chunk);
          if (decoded.length != chunk.length) {
            throw const FormatException('ZIP 文件名解析不完整，请重新选择原文件');
          }
          names.addAll(decoded);
        }
        await compute(
          _validateArchiveNames,
          names,
          debugLabel: 'local-zip-names',
        );
        final companions = <String>{};
        final memberForResult = <int, String>{};
        for (final item in unpacked.books) {
          final firstResult = results.length;
          final decodedName = names[item.index].split('/').last;
          if (item.error != null) {
            results.add((name: decodedName, path: null, error: item.error));
          } else if (RegExp(
            r'\.(txt|epub)$',
            caseSensitive: false,
          ).hasMatch(decodedName)) {
            results.add((name: decodedName, path: item.path, error: null));
          } else {
            try {
              final converted = _isPortableDocument(decodedName)
                  ? [
                      await _markup(
                        decodedName,
                        item.path!,
                        work.path,
                        archive: path,
                        member: names[item.index],
                        names: names,
                        companions: companions,
                      ),
                    ]
                  : _isKindle(decodedName) && extractKindle != null
                  ? [await _kindle(decodedName, item.path!, work)]
                  : decodedName.toLowerCase().endsWith('.pdf') &&
                        extractPdf != null
                  ? [await _pdf(decodedName, item.path!, work)]
                  : await convert(decodedName, item.path!);
              if (converted.isEmpty) throw const FormatException('文件中没有可导入的书籍');
              results.addAll(converted);
            } catch (error) {
              results.add((
                name: decodedName,
                path: null,
                error: _prepareFailure(error),
              ));
            }
          }
          for (var index = firstResult; index < results.length; index++) {
            memberForResult[index] = names[item.index];
          }
        }
        // A referenced file containing only footnotes is a book resource, not
        // an extra empty book or a spurious import failure. Unreferenced books
        // and note documents with ordinary prose keep their own batch entries.
        for (var index = results.length - 1; index >= 0; index--) {
          if (!companions.contains(memberForResult[index])) continue;
          final output = results.removeAt(index).path;
          if (output != null && File(output).parent.path == work.path) {
            await File(output).delete();
          }
        }
      }
      for (final result in results) {
        final output = result.path;
        if (output != null && File(output).parent.path == work.path) {
          job.paths.add(output);
          _outputs[output] = job;
        }
      }
      if (job.paths.isEmpty) await work.delete(recursive: true);
      return results;
    } catch (_) {
      for (final output in job.paths) {
        _outputs.remove(output);
      }
      if (await work.exists()) await work.delete(recursive: true);
      rethrow;
    }
  }

  Future<PreparedBookDocument> _markup(
    String name,
    String path,
    String work, {
    String? archive,
    String? member,
    List<String> names = const [],
    Set<String>? companions,
  }) async {
    final output = await compute(
      _isMarkup(name) ? _prepareMarkup : _prepareStructured,
      (
        name: name,
        source: path,
        directory: work,
        archive: archive,
        member: member,
        names: names,
        token: textCodecToken,
      ),
      debugLabel: 'local-markup-prepare',
    );
    companions?.addAll(output.companions);
    return (
      name: name.replaceFirst(RegExp(r'\.[^.]+$'), '.epub'),
      path: output.path,
      error: null,
    );
  }

  /// Serial cleanup also makes overlapping retry calls idempotent. The final
  /// output releases that job's unreturned failed/intermediate files as well.
  Future<void> releasePaths(Iterable<String> paths) {
    final selected = paths.toSet();
    final operation = _releaseQueue.then((_) async {
      for (final path in selected) {
        final job = _outputs[path];
        if (job == null) continue;
        if (await FileSystemEntity.type(
                  job.directory.path,
                  followLinks: false,
                ) !=
                FileSystemEntityType.directory ||
            await job.directory.resolveSymbolicLinks() != job.directory.path) {
          throw const FileSystemException('导入暂存目录已变化，未删除任何原文件');
        }
        final file = File(path);
        if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          await file.delete();
        }
        if (job.paths.length == 1 && await job.directory.exists()) {
          await job.directory.delete(recursive: true);
        }
        job.paths.remove(path);
        _outputs.remove(path);
      }
    });
    _releaseQueue = operation.catchError((Object _) {});
    return operation;
  }
}

class _PreparationJob {
  _PreparationJob(this.directory);
  final Directory directory;
  final paths = <String>{};
}

/// Keep one resource open at a time. Eagerly opening all stream entries holds
/// thousands of descriptors and buffers before ZIP encoding even begins.
class _PortableEpubOutput {
  _PortableEpubOutput(this.file) : output = OutputFileStream(file.path) {
    encoder.startEncode(output, modified: modified);
  }
  static final modified = DateTime.utc(2000);
  final File file;
  final OutputFileStream output;
  final encoder = ZipEncoder();

  void add(ArchiveFile entry) {
    entry.creationTime = modified.millisecondsSinceEpoch ~/ 1000;
    entry.lastModTime = entry.creationTime;
    encoder.add(entry);
  }

  void text(String name, String text) => add(ArchiveFile.string(name, text));

  void resource(String name, File source) {
    final input = InputFileStream(source.path);
    try {
      add(ArchiveFile.stream(name, input));
    } finally {
      input.closeSync();
    }
  }

  void finish() {
    encoder.endEncode();
    close();
    if (file.lengthSync() > maxLocalEpubBytes) {
      throw const FormatException('转换后的 EPUB 超过 512 MiB，请拆分后导入');
    }
  }

  void close() => output.closeSync();
}

typedef _UnpackedBook = ({int index, String? path, String? error});
typedef _UnpackedBooks = ({List<Uint8List> names, List<_UnpackedBook> books});
const _maxExpanded = 1024 * 1024 * 1024;

_UnpackedBooks _unpackBooks(({String source, String directory}) job) {
  final source = File(job.source);
  final length = source.lengthSync();
  if (length == 0 || length > maxLocalArchiveBytes) {
    throw const FormatException('ZIP 为空或超过 512 MiB，请检查原文件');
  }
  final input = InputFileStream(job.source);
  try {
    _preflightDirectory(input);
    final directory = ZipDirectory()..read(input);
    if (directory.fileHeaders.isEmpty || directory.fileHeaders.length > 12000) {
      throw const FormatException('ZIP 目录为空、损坏或文件过多');
    }
    final names = _rawDirectoryNames(input, directory);
    var declared = 0;
    final candidates = <int>[];
    for (final (index, header) in directory.fileHeaders.indexed) {
      final size = header.uncompressedSize;
      if (size < 0 ||
          size > _maxExpanded - declared ||
          (header.externalFileAttributes >> 16) & 0xf000 == 0xa000) {
        throw const FormatException('ZIP 含符号链接或展开后超过 1 GiB');
      }
      declared += size;
      // Suffixes and separators are ASCII in both UTF-8 and GB18030. Names
      // become filesystem-independent labels after native charset decoding.
      final label = latin1.decode(names[index]);
      if (!label.endsWith('/') &&
          !label
              .split('/')
              .any((part) => part.startsWith('.') || part == '__MACOSX') &&
          supportsBookImport(label) &&
          !label.toLowerCase().endsWith('.zip')) {
        candidates.add(index);
      }
    }
    if (candidates.isEmpty) throw const FormatException('ZIP 内没有支持的书籍或文档');
    if (candidates.length > 200) {
      throw const FormatException('一个 ZIP 最多导入 200 本书');
    }
    var expanded = 0;
    final books = <_UnpackedBook>[];
    for (final index in candidates) {
      final header = directory.fileHeaders[index];
      final target = File('${job.directory}/item-$index.source');
      try {
        final label = latin1.decode(names[index]);
        final limit = localBookByteLimit(label);
        if (header.uncompressedSize < 1 || header.uncompressedSize > limit) {
          throw const FormatException('书籍为空或超过此格式的大小限制');
        }
        _writeZipEntry(
          header,
          target,
          math.min(limit, _maxExpanded - expanded),
        );
        expanded += header.uncompressedSize;
        books.add((index: index, path: target.path, error: null));
      } catch (error) {
        if (target.existsSync()) target.deleteSync();
        books.add((index: index, path: null, error: _prepareFailure(error)));
      }
    }
    return (names: names, books: books);
  } finally {
    input.closeSync();
  }
}

// The same bounded native inflater is used for book members and explicitly
// referenced images/styles. No archive path is ever used as an output path.
void _writeZipEntry(ZipFileHeader header, File target, int limit) {
  final file = header.file;
  if (file == null || (header.generalPurposeBitFlag | file.flags) & 1 != 0) {
    throw const FormatException('ZIP 中的书籍已加密，无法导入');
  }
  if (header.uncompressedSize > limit || header.uncompressedSize < 0) {
    throw const FormatException('ZIP 中的文件展开后超过大小限制');
  }
  if (header.compressionMethod != 0 && header.compressionMethod != 8) {
    throw const FormatException('ZIP 使用了不支持的压缩方式，请改用标准 ZIP');
  }
  final raw = file.getStream(decompress: false);
  if (raw.length != header.compressedSize) {
    throw const FormatException('ZIP 中的书籍数据不完整');
  }
  final output = _BoundedBookSink(
    target,
    math.min(limit, header.uncompressedSize),
  );
  try {
    if (header.compressionMethod == 8) {
      final decoder = ZLibCodec(
        raw: true,
      ).decoder.startChunkedConversion(output);
      while (!raw.isEOS) {
        decoder.add(raw.readBytes(math.min(16384, raw.length)).toUint8List());
      }
      decoder.close();
    } else {
      while (!raw.isEOS) {
        output.add(raw.readBytes(math.min(65536, raw.length)).toUint8List());
      }
    }
    if (output.count != header.uncompressedSize || output.crc != header.crc32) {
      throw const FormatException('ZIP 中的书籍校验失败，请重新下载原文件');
    }
  } finally {
    output.close();
  }
}

/// Bound the central directory before the archive library allocates its header
/// objects. ZIP64 is accepted within the same 12,000-entry/512 MiB contract.
void _preflightDirectory(InputFileStream input) {
  if (input.length < 22) throw const FormatException('ZIP 不完整，请重新下载原文件');
  final start = math.max(0, input.length - 65557);
  final tail = input.subset(position: start).toUint8List();
  final data = ByteData.sublistView(tail);
  var end = -1;
  for (var index = tail.length - 22; index >= 0; index--) {
    if (data.getUint32(index, Endian.little) == 0x06054b50 &&
        index + 22 + data.getUint16(index + 20, Endian.little) == tail.length) {
      end = start + index;
      break;
    }
  }
  if (end < 0) throw const FormatException('ZIP 目录缺失或文件不完整');
  final at = end - start;
  var count = data.getUint16(at + 10, Endian.little);
  var size = data.getUint32(at + 12, Endian.little);
  var offset = data.getUint32(at + 16, Endian.little);
  if (data.getUint16(at + 4, Endian.little) != 0 ||
      data.getUint16(at + 6, Endian.little) != 0) {
    throw const FormatException('请先合并 ZIP 分卷，再选择完整压缩包');
  }
  if (count == 0xffff || size == 0xffffffff || offset == 0xffffffff) {
    if (end < 20) throw const FormatException('ZIP64 目录不完整');
    final locator = ByteData.sublistView(
      input.subset(position: end - 20, length: 20).toUint8List(),
    );
    final position = locator.getUint64(8, Endian.little);
    if (locator.getUint32(0, Endian.little) != 0x07064b50 ||
        position < 0 ||
        position > input.length - 56) {
      throw const FormatException('ZIP64 目录不完整');
    }
    final record = ByteData.sublistView(
      input.subset(position: position, length: 56).toUint8List(),
    );
    if (record.getUint32(0, Endian.little) != 0x06064b50 ||
        record.getUint32(16, Endian.little) != 0 ||
        record.getUint32(20, Endian.little) != 0) {
      throw const FormatException('ZIP64 目录损坏或包含未合并分卷');
    }
    count = record.getUint64(32, Endian.little);
    size = record.getUint64(40, Endian.little);
    offset = record.getUint64(48, Endian.little);
  }
  if (count <= 0 ||
      count > 12000 ||
      size < 0 ||
      size > 64 * 1024 * 1024 ||
      offset < 0 ||
      offset + size > end) {
    throw const FormatException('ZIP 目录损坏或包含过多文件');
  }
  final central = input.subset(position: offset, length: size);
  var actual = 0;
  while (central.length >= 46) {
    final header = ByteData.sublistView(central.readBytes(46).toUint8List());
    if (header.getUint32(0, Endian.little) != 0x02014b50) break;
    actual++;
    final name = header.getUint16(28, Endian.little);
    final variable =
        name +
        header.getUint16(30, Endian.little) +
        header.getUint16(32, Endian.little);
    if (actual > 12000 ||
        name < 1 ||
        name > 4096 ||
        variable > central.length) {
      throw const FormatException('ZIP 文件名目录损坏或包含过多文件');
    }
    central.skip(variable);
  }
  if (actual != count) throw const FormatException('ZIP 文件目录数量不一致，请检查原文件');
  input.setPosition(0);
}

List<Uint8List> _rawDirectoryNames(
  InputFileStream input,
  ZipDirectory directory,
) {
  final central = input.subset(
    position: directory.centralDirectoryOffset,
    length: directory.centralDirectorySize,
  );
  final result = <Uint8List>[];
  for (var index = 0; index < directory.fileHeaders.length; index++) {
    if (central.length < 46) throw const FormatException('ZIP 文件名目录不完整');
    final fixed = ByteData.sublistView(central.readBytes(46).toUint8List());
    final name = fixed.getUint16(28, Endian.little),
        extra = fixed.getUint16(30, Endian.little),
        comment = fixed.getUint16(32, Endian.little);
    if (fixed.getUint32(0, Endian.little) != 0x02014b50 ||
        name == 0 ||
        name > 4096 ||
        name + extra + comment > central.length) {
      throw const FormatException('ZIP 文件名目录损坏');
    }
    result.add(central.readBytes(name).toUint8List());
    central.skip(extra + comment);
  }
  return result;
}

void _validateArchivePath(String name) {
  if (name.startsWith('/') ||
      name.contains('\\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(name) ||
      name.runes.any((rune) => rune < 32 || rune == 127) ||
      name.split('/').contains('..')) {
    throw const FormatException('ZIP 包含无效路径，请检查原文件');
  }
}

void _validateArchiveNames(List<String> names) {
  for (final name in names) {
    _validateArchivePath(name);
  }
}

String _prepareFailure(Object error) => switch (error) {
  FormatException(:final message) => message,
  PlatformException(:final message) => message ?? '此格式暂时无法转换',
  FileSystemException() => '无法展开书籍，请检查原文件和剩余空间',
  _ => 'ZIP 数据损坏或使用了不支持的压缩方式',
};

class _BoundedBookSink extends ByteConversionSink {
  _BoundedBookSink(File file, this.maximum)
    : output = file.openSync(mode: FileMode.write);
  final RandomAccessFile output;
  final int maximum;
  var count = 0, crc = 0;
  var closed = false;
  @override
  void add(List<int> bytes) {
    if (closed || bytes.length > maximum - count) {
      throw const FormatException('ZIP 中的书籍展开后超过大小限制');
    }
    output.writeFromSync(bytes);
    count += bytes.length;
    crc = getCrc32(bytes, crc);
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    output.closeSync();
  }
}
