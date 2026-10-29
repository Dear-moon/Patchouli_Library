import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'catalog.dart';
import 'local_document_input.dart';
import 'local_import_options.dart';
import 'local_text_import.dart';
import 'local_text_reference.dart';

/// Legacy encodings keep the system decoder. These Unicode encodings have
/// strict, independently seekable boundaries shared by Dart and all hosts.
bool supportsLinkedTextInput(String encoding) => const {
  'UTF-8',
  'UTF8',
  'UTF-16LE',
  'UTF-16BE',
}.contains(encoding.toUpperCase());

/// One leased original enters the worker. No source text is retained or staged.
class LocalLinkedTextIndexJob {
  const LocalLinkedTextIndexJob({
    required this.input,
    required this.source,
    required this.name,
    required this.options,
  });

  final LocalDocumentInput input;
  final LocalTextSource source;
  final String name;
  final LocalImportOptions options;
}

typedef LocalLinkedTextIndexResult = ({
  List<NovelChapter> chapters,
  List<List<int>> checkpoints,
  List<List<int>> ranges,
});

/// Builds the unchanged sparse index off the UI isolate and verifies the exact
/// inspected identity while consuming every raw byte once in this operation.
Future<LocalLinkedTextIndexResult> indexLinkedTextInput(
  LocalLinkedTextIndexJob job,
) async {
  if (!supportsLinkedTextInput(job.source.encoding)) {
    throw const FormatException('此编码需要使用系统文本读取');
  }
  if (job.input.length != job.source.size) {
    throw const FormatException('原文件已变化，请重新选择');
  }
  final buffer = job.input.openReadBuffer();
  final checkpoints = <List<int>>[];
  final digest = _LinkedDigest();
  final hash = sha256.startChunkedConversion(digest);
  var hashClosed = false;
  try {
    Stream<String> chunks() async* {
      var offset = 0, chars = 0;
      while (offset < job.source.size) {
        final raw = buffer.read(
          offset,
          (job.source.size - offset).clamp(
            0,
            LocalDocumentReadBuffer.maxReadBytes,
          ),
        );
        final last = offset + raw.length == job.source.size;
        if (raw.isEmpty || offset + raw.length > job.source.size) {
          throw const FormatException('原文件已变化，请重新选择');
        }
        final block = job.source.encoding.toUpperCase().startsWith('UTF-16')
            ? _utf16Block(
                raw,
                littleEndian: job.source.encoding.toUpperCase() == 'UTF-16LE',
                last: last,
              )
            : _utf8Block(raw, last: last);
        checkpoints.add([chars, offset]);
        hash.add(Uint8List.sublistView(raw, 0, block.bytes));
        chars += block.text.length;
        offset += block.bytes;
        // The final code point can straddle this read. Its bytes and characters
        // belong to the next checkpoint, never to both blocks.
        yield block.text;
      }
    }

    final parsed = await indexTextChapters(
      chunks(),
      job.name,
      options: job.options,
    );
    hash.close();
    hashClosed = true;
    if (digest.value?.toString() != job.source.digest) {
      throw const FormatException('原文件已变化，请重新选择');
    }
    return (
      chapters: parsed.chapters,
      checkpoints: checkpoints,
      ranges: parsed.ranges,
    );
  } finally {
    if (!hashClosed) hash.close();
    buffer.close();
  }
}

({String text, int bytes}) _utf8Block(Uint8List raw, {required bool last}) {
  for (var trim = 0; trim <= (last ? 0 : 3); trim++) {
    final count = raw.length - trim;
    try {
      var text = utf8.decode(Uint8List.sublistView(raw, 0, count));
      // Native Charset/iconv blocks retain a block-leading BOM. Dart strips it;
      // keep the original UTF-16 character coordinates used by saved anchors.
      if (count >= 3 && raw[0] == 0xef && raw[1] == 0xbb && raw[2] == 0xbf) {
        text = '\uFEFF$text';
      }
      return (text: text, bytes: count);
    } on FormatException {
      if (trim == (last ? 0 : 3)) rethrow;
    }
  }
  throw const FormatException('原文件或文字编码已变化，请重新选择');
}

({String text, int bytes}) _utf16Block(
  Uint8List raw, {
  required bool littleEndian,
  required bool last,
}) {
  if (raw.length.isOdd) {
    throw const FormatException('UTF-16 原文件不完整，请重新选择');
  }
  final data = ByteData.sublistView(raw);
  final endian = littleEndian ? Endian.little : Endian.big;
  var count = raw.length;
  bool high(int unit) => unit >= 0xd800 && unit <= 0xdbff;
  bool low(int unit) => unit >= 0xdc00 && unit <= 0xdfff;
  if (!last && high(data.getUint16(count - 2, endian))) count -= 2;
  final units = Uint16List(count ~/ 2);
  for (var at = 0; at < units.length; at++) {
    final unit = data.getUint16(at * 2, endian);
    units[at] = unit;
    if (high(unit)) {
      if (++at == units.length || !low(data.getUint16(at * 2, endian))) {
        throw const FormatException('UTF-16 原文件不完整，请重新选择');
      }
      units[at] = data.getUint16(at * 2, endian);
    } else if (low(unit)) {
      throw const FormatException('UTF-16 原文件不完整，请重新选择');
    }
  }
  return (text: String.fromCharCodes(units), bytes: count);
}

class _LinkedDigest implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
