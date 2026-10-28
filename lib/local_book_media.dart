import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'local_document_input.dart';
import 'local_epub_media.dart';
import 'local_book_import_issues.dart';

export 'local_epub_media.dart' show LocalBookImageResult;

/// Portable, narrowly scoped references; imported books never access arbitrary
/// file:// paths or send their illustration paths to the remote API.
class LocalBookMedia {
  static Directory? _root;
  static int _revisionClock = 0, _rootRevision = 0;
  static final _revisions = <int, int>{};

  static Directory? get root => _root;

  /// A library reload starts a new source generation. Bind its batch resolver
  /// after this assignment, so a previous store cannot read a new library.
  static set root(Directory? value) {
    _root = value;
    _rootRevision = ++_revisionClock;
    _revisions.clear();
    _covers.clear();
    _coverPending.clear();
    _pending.clear();
    _coverBytes = 0;
    externalImages = null;
    importWarnings = null;
  }

  /// Bound to the active store, like the existing operation-scoped media reader.
  static LocalBookImportWarningAccess? importWarnings;

  static Future<Uint8List>? Function(int id, String name)? externalImage;

  /// A store can read up to four names under one operation-scoped original
  /// lease. Null retains the managed-file and legacy single-reader paths.
  static Future<Map<String, LocalBookImageResult>>? Function(
    int id,
    List<String> names,
  )?
  externalImages;
  static final _pending = <String, Future<Uint8List>>{};
  static const _maxCoverBytes = 8 * 1024 * 1024;
  static const _maxCoverEntries = 256;
  static final _covers = <String, _LocalCoverEntry>{};
  static final _coverPending = <String, Future<Uint8List>>{};
  static int _coverBytes = 0;

  @visibleForTesting
  static int get cachedCoverBytes => _coverBytes;
  @visibleForTesting
  static int get cachedCoverEntries => _covers.length;

  static _LocalCoverEntry? _touch(String? url) {
    final entry = _covers.remove(url);
    if (entry != null) _covers[url!] = entry;
    return entry;
  }

  static Uint8List? peek(String? url) => _touch(url)?.bytes;

  /// Reader caches tag local bytes/headers with this generation. Late work from
  /// an evicted source must not populate a newly relinked book's cache.
  static int revisionOf(String url) =>
      _revisions[int.tryParse(Uri.tryParse(url)?.host ?? '')] ?? _rootRevision;

  static void evict(int bookId) {
    if (_revisions.length >= 2048 && !_revisions.containsKey(bookId)) {
      _rootRevision = ++_revisionClock;
      _revisions.clear();
    }
    _revisions[bookId] = ++_revisionClock;
    bool belongs(String url) => Uri.tryParse(url)?.host == '$bookId';
    for (final url in _covers.keys.where(belongs).toList()) {
      _coverBytes -= _covers.remove(url)!.bytes.length;
    }
    _coverPending.removeWhere((url, _) => belongs(url));
    _pending.removeWhere((url, _) => belongs(url));
  }

  static bool valid(Uri uri) =>
      uri.scheme == 'wenku-local' &&
      (int.tryParse(uri.host) ?? 0) >= 0x60000000 &&
      (int.tryParse(uri.host) ?? 0) <= 0x7fffffff &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      RegExp(
        r'^/(cover|cover-custom-[0-9]+|img-[0-9]+)\.(png|jpg|jpeg|webp|gif)$',
      ).hasMatch(uri.path);

  static Future<Uint8List> load(String source) {
    if (_touch(source) case final entry?) return entry.future;
    if (Uri.tryParse(source)?.path.startsWith('/cover.') == true) {
      return loadCover(source);
    }
    return _loadSource(source);
  }

  /// Coalesces single-image and batch readers. At most four same-book archive
  /// misses share one worker/lease; a broken image fails only its own future.
  static Map<String, Future<Uint8List>> loadBatch(Iterable<String> sources) {
    final result = <String, Future<Uint8List>>{};
    final groups = <int, Map<String, Completer<Uint8List>>>{};
    final directory = root;
    final batchReader = externalImages, singleReader = externalImage;
    for (final source in sources.toSet()) {
      if (_touch(source) case final cached?) {
        result[source] = cached.future;
        continue;
      }
      if (_pending[source] case final pending?) {
        result[source] = pending;
        continue;
      }
      final uri = Uri.tryParse(source);
      if (directory == null || uri == null || !valid(uri)) {
        result[source] = Future.error(const FormatException('本地插图地址无效'));
        continue;
      }
      if (uri.path.startsWith('/cover.')) {
        result[source] = loadCover(source);
        continue;
      }
      final completer = Completer<Uint8List>();
      late final Future<Uint8List> future;
      future = completer.future.whenComplete(() {
        if (identical(_pending[source], future)) _pending.remove(source);
      });
      _pending[source] = future;
      result[source] = future;
      (groups[int.parse(uri.host)] ??= {})[source] = completer;
    }
    for (final group in groups.entries) {
      unawaited(() async {
        final entries = group.value.entries.toList();
        for (var start = 0; start < entries.length; start += 4) {
          final chunk = entries.skip(start).take(4).toList();
          try {
            final values = await _readBatch(
              directory!,
              group.key,
              chunk.map((entry) => entry.key).toList(),
              batchReader,
              singleReader,
            );
            for (final entry in chunk) {
              final name = Uri.parse(entry.key).path.substring(1);
              final image = values.images[name];
              if (values.failures[name] case final failure?) {
                entry.value.completeError(failure.$1, failure.$2);
              } else if (image?.bytes case final bytes?) {
                entry.value.complete(bytes);
              } else {
                entry.value.completeError(
                  FormatException(image?.error ?? '原书中没有这张插图'),
                );
              }
            }
          } catch (error, stack) {
            for (final entry in chunk) {
              if (!entry.value.isCompleted) {
                entry.value.completeError(error, stack);
              }
            }
          }
        }
      }());
    }
    return result;
  }

  static Future<_LocalImageBatch> _readBatch(
    Directory root,
    int id,
    List<String> sources,
    Future<Map<String, LocalBookImageResult>>? Function(int, List<String>)?
    batchReader,
    Future<Uint8List>? Function(int, String)? singleReader,
  ) async {
    final directory = '${root.path}/$id';
    final result = <String, LocalBookImageResult>{};
    final failures = <String, (Object, StackTrace)>{};
    _LocalImageBatch resolved() => _LocalImageBatch(result, failures);
    final names = sources
        .map((source) => Uri.parse(source).path.substring(1))
        .toList();
    final missingNames = <String>{};
    await Future.wait(
      names.map((name) async {
        final file = File('$directory/$name');
        try {
          if (!await file.exists()) {
            missingNames.add(name);
            return;
          }
          if (await file.length() > 8 * 1024 * 1024) {
            result[name] = const LocalBookImageResult.failure('本地插图过大');
          } else {
            result[name] = LocalBookImageResult.success(
              await file.readAsBytes(),
            );
          }
        } on FileSystemException catch (error, stack) {
          failures[name] = (error, stack);
        }
      }),
    );
    final missing = names.where(missingNames.contains).toList();
    if (missing.isEmpty) return resolved();
    try {
      final batch = batchReader?.call(id, missing);
      if (batch != null) {
        result.addAll(await batch);
        return resolved();
      }
    } catch (error, stack) {
      for (final name in missing) {
        failures[name] = (error, stack);
      }
      return resolved();
    }
    final archived = <String>[];
    await Future.wait(
      missing.map((name) async {
        try {
          final image = singleReader?.call(id, name);
          if (image == null) {
            archived.add(name);
            return;
          }
          result[name] = LocalBookImageResult.success(await image);
        } catch (error, stack) {
          failures[name] = (error, stack);
        }
      }),
    );
    if (archived.isNotEmpty) {
      try {
        result.addAll(
          await compute(readLocalEpubImagesFromInput, (
            directory: directory,
            names: archived,
            original: LocalDocumentInput.file('$directory/original'),
          )),
        );
      } catch (error, stack) {
        for (final name in archived) {
          failures[name] = (error, stack);
        }
      }
    }
    return resolved();
  }

  static Future<Uint8List> _loadSource(String source) {
    if (_pending[source] case final future?) return future;
    late final Future<Uint8List> future;
    future = _read(source).whenComplete(() {
      if (identical(_pending[source], future)) _pending.remove(source);
    });
    _pending[source] = future;
    return future;
  }

  /// Older EPUBs can use img-N.jpg as their cover. Cache by role, not filename;
  /// otherwise every reader return rereads/redecodes it and restarts arrival.
  static Future<Uint8List> loadCover(String source) {
    if (_touch(source) case final entry?) return entry.future;
    if (_coverPending[source] case final future?) return future;
    late final Future<Uint8List> future;
    future = _loadSource(source)
        .then((bytes) {
          // An import/relink may evict the source while its old read completes.
          if (identical(_coverPending[source], future)) {
            _rememberCover(source, bytes, future);
          }
          return bytes;
        })
        .whenComplete(() {
          if (identical(_coverPending[source], future)) {
            _coverPending.remove(source);
          }
        });
    _coverPending[source] = future;
    return future;
  }

  static void _rememberCover(
    String source,
    Uint8List bytes,
    Future<Uint8List> future,
  ) {
    final previous = _covers.remove(source);
    if (previous != null) _coverBytes -= previous.bytes.length;
    // Large original images can still be opened, without retaining a completed
    // future that bypasses the encoded-cache budget.
    if (bytes.length > _maxCoverBytes) return;
    while (_covers.isNotEmpty &&
        (_coverBytes + bytes.length > _maxCoverBytes ||
            _covers.length >= _maxCoverEntries)) {
      final key = _covers.keys.first;
      _coverBytes -= _covers.remove(key)!.bytes.length;
    }
    _covers[source] = _LocalCoverEntry(bytes, future);
    _coverBytes += bytes.length;
  }

  static Future<Uint8List> _read(String source) async {
    final uri = Uri.parse(source);
    if (root == null || !valid(uri)) throw const FormatException('本地插图地址无效');
    final directory = '${root!.path}/${uri.host}';
    final reader = externalImage;
    final file = File('$directory${uri.path}');
    final Uint8List bytes;
    if (await file.exists()) {
      if (await file.length() > 8 * 1024 * 1024) {
        throw const FormatException('本地插图过大');
      }
      bytes = await file.readAsBytes();
    } else {
      bytes =
          await (reader?.call(int.parse(uri.host), uri.path.substring(1)) ??
              compute(readLocalEpubImage, (
                directory: directory,
                name: uri.path.substring(1),
              )));
    }
    return bytes;
  }
}

class _LocalImageBatch {
  const _LocalImageBatch(this.images, this.failures);
  final Map<String, LocalBookImageResult> images;
  final Map<String, (Object, StackTrace)> failures;
}

class _LocalCoverEntry {
  const _LocalCoverEntry(this.bytes, this.future);
  final Uint8List bytes;
  final Future<Uint8List> future;
}
