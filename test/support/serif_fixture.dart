import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:wenku8_flutter/font_download.dart';

/// The regression face is not an application asset. Host tests use the local
/// fixture; explicit Android render/benchmark tests fetch the same public face
/// into that disposable test application's private cache.
ByteData? _hostBytes;
Future<ByteData> loadSerifFixture() async {
  if (!Platform.isAndroid) {
    // Host widget tests use a fake async zone. Read this test-only fixture once
    // without leaving an unpumpable filesystem future inside a widget action.
    return _hostBytes ??= ByteData.sublistView(
      File('test/fixtures/fonts/SourceHanSerifCN-VF.otf').readAsBytesSync(),
    );
  }
  File file;
  file = File('${(await getTemporaryDirectory()).path}/$sourceHanFontFile');
  if (!await file.exists() || await file.length() != sourceHanFontBytes) {
    await FontDownloadClient().download(
      file,
      cancellation: FontDownloadCancellation(),
      onProgress: (_) {},
    );
  }
  return ByteData.sublistView(await file.readAsBytes());
}
