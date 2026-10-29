import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'book_import_limits.dart';

/// Plain files from existing libraries remain readable. A plain file wins while
/// compaction is in flight; its verified gzip replacement commits on deletion.
Future<String> readLocalText(File plain) async {
  var size = 0;
  final bytes = localTextBytes(plain).map((chunk) {
    size += chunk.length;
    if (size > maxLocalEpubBytes) throw const FormatException('本地正文解压后过大');
    return chunk;
  });
  return bytes.transform(utf8.decoder).join();
}

Future<bool> localTextExists(File plain) async =>
    await plain.exists() || await File('${plain.path}.gz').exists();

Stream<List<int>> localTextBytes(File plain) async* {
  RandomAccessFile? input;
  try {
    input = await plain.open();
  } on FileSystemException {
    if (await plain.exists()) rethrow;
  }
  if (input == null) {
    yield* File('${plain.path}.gz').openRead().transform(gzip.decoder);
  } else {
    // An opened handle stays readable if compaction unlinks the plain file.
    try {
      while (true) {
        final chunk = await input.read(64 * 1024);
        if (chunk.isEmpty) break;
        yield chunk;
      }
    } finally {
      await input.close();
    }
  }
}

Future<int> localTextByteLength(File plain) async {
  try {
    return await plain.length();
  } on FileSystemException {
    if (await plain.exists()) rethrow;
  }
  return localTextBytes(
    plain,
  ).fold<int>(0, (size, chunk) => size + chunk.length);
}

void writeCompressedLocalText(File plain, String text) =>
    File('${plain.path}.gz').writeAsBytesSync(gzip.encode(utf8.encode(text)));

/// Stream comparison is needed before deleting a readable copy. Chunk sizes may
/// differ after decompression; no second whole-book buffer or digest is needed.
Future<bool> sameLocalTextBytes(
  Stream<List<int>> a,
  Stream<List<int>> b,
) async {
  final left = StreamIterator(a), right = StreamIterator(b);
  Future<List<int>> nextChunk(StreamIterator<List<int>> iterator) async {
    while (await iterator.moveNext()) {
      if (iterator.current.isNotEmpty) return iterator.current;
    }
    return const [];
  }

  var l = <int>[], r = <int>[], li = 0, ri = 0;
  try {
    while (true) {
      if (li == l.length) {
        l = await nextChunk(left);
        li = 0;
      }
      if (ri == r.length) {
        r = await nextChunk(right);
        ri = 0;
      }
      if (l.isEmpty || r.isEmpty) return l.isEmpty && r.isEmpty;
      final count = (l.length - li) < (r.length - ri)
          ? l.length - li
          : r.length - ri;
      for (var i = 0; i < count; i++) {
        if (l[li + i] != r[ri + i]) return false;
      }
      li += count;
      ri += count;
    }
  } finally {
    await left.cancel();
    await right.cancel();
  }
}

/// Each original remains untouched. Interrupted work leaves either the readable
/// plain file or the completed, byte-for-byte verified compressed replacement.
Future<int> compactLocalText(File plain) async {
  if (!await plain.exists()) return 0;
  final size = await plain.length();
  final compressed = File('${plain.path}.gz');
  final next = File('${plain.path}.storage-next');
  try {
    await plain.openRead().transform(gzip.encoder).pipe(next.openWrite());
    final after = await next.length();
    if (after >= size) return 0;
    if (!await sameLocalTextBytes(
      plain.openRead(),
      next.openRead().transform(gzip.decoder),
    )) {
      throw const FormatException('本地正文压缩校验失败，原正文已保留');
    }
    await next.rename(compressed.path);
    await plain.delete();
    return size - after;
  } finally {
    if (await next.exists()) await next.delete();
  }
}
