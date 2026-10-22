import 'dart:io';
import 'package:wenku8_flutter/font_download.dart';

class FixtureFontDownload extends FontDownloadClient {
  int calls = 0;
  @override
  Future<void> download(
    File target, {
    required FontDownloadCancellation cancellation,
    required void Function(FontDownloadProgress) onProgress,
    int expectedBytes = sourceHanFontBytes,
    List<Uri>? from,
  }) async {
    calls++;
    cancellation.check();
    onProgress(const FontDownloadProgress(0, sourceHanFontBytes));
    await File('test/fixtures/fonts/SourceHanSerifCN-VF.otf').copy(target.path);
    cancellation.check();
    onProgress(
      const FontDownloadProgress(sourceHanFontBytes, sourceHanFontBytes),
    );
  }
}
