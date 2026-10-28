import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:woff2/woff2.dart';
import 'package:path_provider/path_provider.dart';

Uint8List _decodeSourceFont(Uint8List bytes) {
  final (result, decoded) = decodeFontIfWoff(bytes);
  return switch (result) {
    WoffDecodeResult.notWoff => bytes,
    WoffDecodeResult.ok => decoded!,
    _ => throw const FormatException('章节配套字体解码失败，请刷新本章'),
  };
}

class ReaderSourceFonts {
  static final _loads = <String, Future<String>>{};

  static Future<String> load(String encoded) {
    final bytes = base64Decode(encoded);
    final digest = sha256.convert(bytes).toString();
    final family = 'SourceChapter_$digest';
    return _loads.putIfAbsent(family, () async {
      try {
        final directory = Directory(
          '${(await getTemporaryDirectory()).path}/chapter-fonts-v1',
        );
        final file = File('${directory.path}/$digest.ttf');
        final Uint8List decoded;
        if (await file.exists()) {
          decoded = await file.readAsBytes();
        } else {
          decoded = await compute(_decodeSourceFont, bytes);
          await directory.create(recursive: true);
          final pending = File('${file.path}.part');
          await pending.writeAsBytes(decoded);
          await pending.rename(file.path);
        }
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(decoded)));
        await loader.load();
        return family;
      } catch (_) {
        _loads.remove(family);
        rethrow;
      }
    });
  }
}
