import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'local_epub_media.dart';

/// Portable, narrowly scoped references; imported books never access arbitrary
/// file:// paths or send their illustration paths to the remote API.
class LocalBookMedia {
  static Directory? root;
  static Future<Uint8List>? Function(int id, String name)? externalImage;
  static final _pending = <String, Future<Uint8List>>{};
  static final _covers = <String, Uint8List>{};
  static final _coverFutures = <String, Future<Uint8List>>{};
  static Uint8List? peek(String? url) => _covers[url];
  static void evict(int bookId) {
    _covers.removeWhere((url, _) => Uri.tryParse(url)?.host == '$bookId');
    _coverFutures.removeWhere((url, _) => Uri.tryParse(url)?.host == '$bookId');
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

  static Future<Uint8List> load(String source) async {
    if (_covers[source] case final bytes?) return bytes;
    return _pending
        .putIfAbsent(source, () => _read(source))
        .whenComplete(() => _pending.remove(source));
  }

  /// Older EPUBs can use img-N.jpg as their cover. Cache by role, not filename;
  /// otherwise every reader return rereads/redecodes it and restarts arrival.
  static Future<Uint8List> loadCover(String source) =>
      _coverFutures.putIfAbsent(source, () async {
        try {
          final bytes = await load(source);
          _rememberCover(source, bytes);
          return bytes;
        } catch (_) {
          _coverFutures.remove(source);
          rethrow;
        }
      });
  static void _rememberCover(String source, Uint8List bytes) {
    _covers.remove(source);
    var size = _covers.values.fold<int>(
      bytes.length,
      (sum, data) => sum + data.length,
    );
    while (size > 8 * 1024 * 1024 && _covers.isNotEmpty) {
      final key = _covers.keys.first;
      size -= _covers.remove(key)!.length;
      _coverFutures.remove(key);
    }
    _covers[source] = bytes;
  }

  static Future<Uint8List> _read(String source) async {
    final uri = Uri.parse(source);
    if (root == null || !valid(uri)) throw const FormatException('本地插图地址无效');
    final directory = '${root!.path}/${uri.host}';
    final file = File('$directory${uri.path}');
    final Uint8List bytes;
    if (await file.exists()) {
      if (await file.length() > 8 * 1024 * 1024) {
        throw const FormatException('本地插图过大');
      }
      bytes = await file.readAsBytes();
    } else {
      bytes =
          await (externalImage?.call(
                int.parse(uri.host),
                uri.path.substring(1),
              ) ??
              compute(readLocalEpubImage, (
                directory: directory,
                name: uri.path.substring(1),
              )));
    }
    if (uri.path.startsWith('/cover.')) {
      _rememberCover(source, bytes);
    }
    return bytes;
  }
}
