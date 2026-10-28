import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Resolve through Flutter's asset image cache and own one decoded image handle.
/// A missing illustration is a failed preview, never a text-only export fallback.
Future<ui.Image> loadReadingReportArt(BuildContext context, String asset) {
  final result = Completer<ui.Image>();
  final stream = AssetImage(
    asset,
  ).resolve(createLocalImageConfiguration(context));
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      final image = info.image.clone();
      info.dispose();
      stream.removeListener(listener);
      result.complete(image);
    },
    onError: (Object error, StackTrace? stack) {
      stream.removeListener(listener);
      result.completeError(const FormatException('主题插画未能载入，请重新打开预览'), stack);
    },
  );
  stream.addListener(listener);
  return result.future;
}
