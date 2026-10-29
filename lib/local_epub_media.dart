import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'local_book_archive.dart';
import 'local_document_input.dart';

/// A damaged/missing image does not discard the other images read under the
/// same original-file lease. Failures remain retryable by the caller.
class LocalBookImageResult {
  const LocalBookImageResult.success(this.bytes) : error = null;
  const LocalBookImageResult.failure(this.error) : bytes = null;

  final Uint8List? bytes;
  final String? error;
}

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
  final result = readLocalEpubImagesFromInput((
    directory: request.directory,
    names: [request.name],
    original: request.original,
  ))[request.name]!;
  if (result.bytes case final bytes?) return bytes;
  throw FormatException(result.error ?? '原书插图无法读取');
}

/// Reads at most four cold images with one index read and archive open. Owned
/// encoded bytes leave the worker before the input mapping/lease is released.
Map<String, LocalBookImageResult> readLocalEpubImagesFromInput(
  ({String directory, List<String> names, LocalDocumentInput original}) request,
) {
  if (request.names.isEmpty) return {};
  if (request.names.length > 4) {
    throw const FormatException('本地插图批次过大');
  }
  final index = File('${request.directory}/media.json');
  if (index.lengthSync() > 1024 * 1024) {
    throw const FormatException('本地插图索引过大');
  }
  final value = jsonDecode(index.readAsStringSync());
  if (value is! Map || value['version'] != 1 || value['entries'] is! Map) {
    throw const FormatException('本地插图索引无效');
  }
  final entries = value['entries'] as Map;
  final results = <String, LocalBookImageResult>{};
  final paths = <String, String>{};
  for (final name in request.names) {
    final path = entries[name];
    if (path is String) {
      paths[name] = path;
    } else {
      results[name] = const LocalBookImageResult.failure('原书中没有这张插图');
    }
  }
  if (paths.isEmpty) return results;
  final buffer = request.original.open();
  try {
    final archive = value['recoverDamagedEpub'] == true
        ? readLocalBookArchiveForRecovery(
            buffer.stream,
            maxSize: 1024 * 1024 * 1024,
          ).archive
        : readLocalBookArchive(buffer.stream, maxSize: 1024 * 1024 * 1024);
    for (final entry in paths.entries) {
      final name = entry.key, path = entry.value;
      try {
        final image = archive.findFile(path);
        if (image == null || !image.isFile || image.size > 8 * 1024 * 1024) {
          results[name] = const LocalBookImageResult.failure('原书插图无效或超过 8 MiB');
          continue;
        }
        // Stored ZIP entries can be views into the leased mapping.
        final bytes = readLocalBookArchiveEntry(image);
        results[name] = LocalBookImageResult.success(Uint8List.fromList(bytes));
      } on ArchiveException {
        results[name] = const LocalBookImageResult.failure(
          '原书插图无法读取，请重新导入完整原书',
        );
      } on FormatException {
        results[name] = const LocalBookImageResult.failure(
          '原书插图无法读取，请重新导入完整原书',
        );
      }
    }
    return results;
  } on ArchiveException {
    throw const FormatException('原书插图无法读取，请重新导入完整原书');
  } finally {
    buffer.close();
  }
}
