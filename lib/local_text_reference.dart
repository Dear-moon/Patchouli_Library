import 'dart:convert';
import 'package:flutter/services.dart';
import 'book_import_limits.dart';
import 'local_text_import.dart';

class LocalTextReferenceFailure extends FormatException {
  const LocalTextReferenceFailure(this.bookId, super.message);
  final int bookId;
}

class LocalTextSource {
  const LocalTextSource({
    required this.reference,
    required this.encoding,
    required this.size,
    required this.modified,
    required this.digest,
  });
  final String reference, encoding, digest;
  final int size, modified;
  Map<String, Object> toJson() => {
    'reference': reference,
    'encoding': encoding,
    'size': size,
    'modified': modified,
    'digest': digest,
  };
  factory LocalTextSource.fromJson(Map value) {
    if (value['reference'] is! String ||
        (value['reference'] as String).isEmpty ||
        value['encoding'] is! String ||
        value['digest'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['digest']) ||
        value['size'] is! int ||
        value['size'] <= 0 ||
        value['size'] > maxLocalTextBytes ||
        value['modified'] is! int) {
      throw const FormatException('关联原文件记录有误，请重新定位原文件');
    }
    return LocalTextSource(
      reference: value['reference'],
      encoding: value['encoding'],
      size: value['size'],
      modified: value['modified'],
      digest: value['digest'],
    );
  }
}

typedef LocalTextBlock = ({String text, int next});

/// The platform keeps only a durable read grant. Blocks end on decoder boundaries
/// and contain at most 32K UTF-16 units, including for GB18030/Big5/UTF-16 TXT.
abstract class LocalTextAccess {
  Future<LocalTextSource> inspect(String reference, {String encoding = 'auto'});
  Future<LocalTextBlock> block(LocalTextSource source, int offset);
  Stream<List<int>> bytes(LocalTextSource source);
  Future<void> release(String reference);
}

class PlatformLocalTextAccess implements LocalTextAccess {
  static const _channel = MethodChannel('org.mewx.wenku8/book_documents');
  @override
  Future<LocalTextSource> inspect(
    String reference, {
    String encoding = 'auto',
  }) async => LocalTextSource.fromJson(
    (await _channel.invokeMapMethod<String, dynamic>('inspectLinkedText', {
      'reference': reference,
      'encoding': encoding,
    }))!,
  );
  @override
  Future<LocalTextBlock> block(LocalTextSource source, int offset) async {
    final value = (await _channel.invokeMapMethod<String, dynamic>(
      'readLinkedText',
      {...source.toJson(), 'offset': offset},
    ))!;
    final bytes = value['textBytes'] as Uint8List;
    var text = utf8.decode(bytes);
    if (bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf) {
      text = '\uFEFF$text';
    }
    return (text: text, next: value['next'] as int);
  }

  @override
  Stream<List<int>> bytes(LocalTextSource source) async* {
    var at = 0;
    while (at < source.size) {
      final value = (await _channel.invokeMethod<Uint8List>('readLinkedBytes', {
        ...source.toJson(),
        'offset': at,
      }))!;
      if (value.isEmpty || at + value.length > source.size) {
        throw const FormatException('原文件已变化，请重新定位原文件');
      }
      at += value.length;
      yield value;
    }
  }

  @override
  Future<void> release(String reference) => _channel.invokeMethod<void>(
    'releaseLinkedText',
    {'reference': reference},
  );
}

/// Sparse decoder checkpoints plus one character range per chapter. No prose,
/// normalized full text or original bytes are written into the local library.
class LocalTextIndex {
  const LocalTextIndex(this.source, this.checkpoints, this.ranges);
  final LocalTextSource source;
  final List<List<int>> checkpoints, ranges;
  Map<String, Object> toJson() => {
    'version': 1,
    ...source.toJson(),
    'checkpoints': checkpoints,
    'ranges': ranges,
  };
  factory LocalTextIndex.fromJson(Object? value) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['checkpoints'] is! List ||
        value['ranges'] is! List) {
      throw const FormatException('TXT 位置索引有误，请重新定位原文件');
    }
    final source = LocalTextSource.fromJson(value);
    List<List<int>> pairs(Object raw, int limit, bool checkpoint) {
      if (raw is! List || raw.isEmpty || raw.length > limit) {
        throw const FormatException('TXT 位置索引有误');
      }
      final result = <List<int>>[];
      for (final pair in raw) {
        if (pair is! List ||
            pair.length != 2 ||
            pair.any((n) => n is! int || n < 0)) {
          throw const FormatException('TXT 位置索引有误');
        }
        final p = pair.cast<int>();
        if (checkpoint
            ? p[1] >= source.size ||
                  result.isNotEmpty &&
                      (p[0] <= result.last[0] || p[1] <= result.last[1])
            : p[0] >= p[1] || result.isNotEmpty && p[0] < result.last[1]) {
          throw const FormatException('TXT 位置索引有误');
        }
        result.add(p);
      }
      return result;
    }

    final checkpoints = pairs(value['checkpoints'], 20000, true);
    if (checkpoints.first[0] != 0 || checkpoints.first[1] != 0) {
      throw const FormatException('TXT 位置索引有误');
    }
    return LocalTextIndex(
      source,
      checkpoints,
      pairs(value['ranges'], 10000, false),
    );
  }

  Stream<String> text(
    LocalTextAccess access, {
    int start = 0,
    int? end,
  }) async* {
    final point = checkpoints.lastWhere((p) => p[0] <= start);
    var chars = point[0], at = point[1];
    while (at < source.size && (end == null || chars < end)) {
      final block = await access.block(source, at);
      if (block.next <= at || block.next > source.size || block.text.isEmpty) {
        throw const FormatException('原文件已变化，请重新定位原文件');
      }
      final from = (start - chars).clamp(0, block.text.length);
      final to = end == null
          ? block.text.length
          : (end - chars).clamp(0, block.text.length);
      if (to > from) yield block.text.substring(from, to);
      chars += block.text.length;
      at = block.next;
    }
    if (end != null && chars < end) {
      throw const FormatException('原文件已变化，请重新定位原文件');
    }
  }

  Future<String> body(LocalTextAccess access, int chapterIndex) async {
    final range = ranges[chapterIndex];
    final paragraphs = <String>[];
    await for (final line in localTextLines(
      text(access, start: range[0], end: range[1]),
      offset: range[0],
      removeBom: false,
    )) {
      final value = line.text.trim();
      if (value.isNotEmpty) paragraphs.add(value);
    }
    return paragraphs.join('\n\n');
  }

  Stream<List<int>> decodedBytes(LocalTextAccess access) async* {
    var first = true;
    await for (var chunk in text(access)) {
      if (first) {
        chunk = chunk.replaceFirst(RegExp('^\uFEFF'), '');
        first = false;
      }
      yield utf8.encode(chunk);
    }
  }
}
