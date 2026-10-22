import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'local_book_archive.dart';
import 'local_document_input.dart';

/// Runs off the UI isolate. The index points only into this book's retained
/// original, never to external paths or remote resources.
Uint8List readLocalEpubImage(({String directory, String name}) request) {
  return readLocalEpubImageFromFile((
    directory: request.directory,
    name: request.name,
    original: '${request.directory}/original',
  ));
}

Uint8List readLocalEpubImageFromFile(
  ({String directory, String name, String original}) request,
) => readLocalEpubImageFromInput((
  directory: request.directory,
  name: request.name,
  original: LocalDocumentInput.file(request.original),
));

Uint8List readLocalEpubImageFromInput(
  ({String directory, String name, LocalDocumentInput original}) request,
) {
  final index = File('${request.directory}/media.json');
  if (index.lengthSync() > 1024 * 1024) {
    throw const FormatException('本地插图索引过大');
  }
  final value = jsonDecode(index.readAsStringSync());
  if (value is! Map || value['version'] != 1 || value['entries'] is! Map) {
    throw const FormatException('本地插图索引无效');
  }
  final path = (value['entries'] as Map)[request.name];
  if (path is! String) throw const FormatException('原书中没有这张插图');
  final buffer = request.original.open();
  try {
    final archive = readLocalBookArchive(
      buffer.stream,
      maxSize: 1024 * 1024 * 1024,
    );
    final image = archive.findFile(path);
    if (image == null || !image.isFile || image.size > 8 * 1024 * 1024) {
      throw const FormatException('原书插图无效或超过 8 MiB');
    }
    // Stored ZIP entries can be views into the leased mapping. Return owned
    // pixels before its descriptor and mapping are released.
    return Uint8List.fromList(image.readBytes()!);
  } on ArchiveException {
    throw const FormatException('原书插图无法读取，请重新导入完整原书');
  } finally {
    buffer.close();
  }
}
