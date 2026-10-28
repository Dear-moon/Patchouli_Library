import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'reading_widget_reference.dart';
import 'reading_widget_skin.dart';
import 'reading_widget_snapshot.dart';

List<ImageProvider> readingDesktopImages(ReadingWidgetSnapshot data) {
  final names = switch (data.skin) {
    ReadingWidgetSkin.seasons => [
      'char_season_${['spring', 'summer', 'autumn', 'winter'][seasonIndex(data.localDay)]}',
    ],
    ReadingWidgetSkin.night => ['char_night_desk', 'char_night_roof'],
    ReadingWidgetSkin.film => ['char_pv_train', 'char_pv_open'],
    ReadingWidgetSkin.paper => ['char_papercut'],
    _ => ['char_cover'],
  };
  return [
    ResizeImage(const AssetImage('assets/branding/app-icon.png'), width: 48),
    for (final name in names)
      ResizeImage(AssetImage('assets/report/$name.webp'), width: 1080),
  ];
}

Future<void> warmReadingDesktopImages(ReadingWidgetSnapshot data) async {
  await Future.wait(
    readingDesktopImages(data).map((provider) async {
      final done = Completer<void>();
      final stream = provider.resolve(
        const ImageConfiguration(devicePixelRatio: 1),
      );
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (image, synchronous) {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object error, StackTrace? stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        },
      );
      stream.addListener(listener);
      try {
        await done.future;
      } finally {
        stream.removeListener(listener);
      }
    }),
  );
}

/// Uses the same isolated Flutter render pipeline as report/keepsake export.
/// The desktop hosts keep the resulting local images and their real deep links.
Future<Map<String, Uint8List>> renderReadingDesktopCards(
  ReadingWidgetSnapshot data, {
  String? fontFamily,
}) async {
  await warmReadingDesktopImages(data);
  final result = <String, Uint8List>{};
  for (final size in ReadingDesktopSize.values) {
    result[size.name] = await renderReadingDesktopCard(
      data,
      size,
      fontFamily: fontFamily,
    );
  }
  return result;
}

Future<Uint8List> renderReadingDesktopCard(
  ReadingWidgetSnapshot data,
  ReadingDesktopSize size, {
  String? fontFamily,
  Brightness? brightness,
  bool paintQuote = true,
}) async {
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: WidgetsBinding.instance.platformDispatcher.views.first,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size.size),
      physicalConstraints: BoxConstraints.tight(size.size),
      devicePixelRatio: 1,
    ),
    child: boundary,
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  final focus = FocusManager();
  final owner = BuildOwner(focusManager: focus);
  renderView.prepareInitialFrame();
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: MediaQueryData(
        size: size.size,
        devicePixelRatio: 1,
        disableAnimations: true,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: false,
          child: DefaultTextStyle(
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: 12,
              color: Colors.black,
            ),
            child: ReadingDesktopCard(
              data: data,
              size: size,
              brightness: brightness,
              paintQuote: paintQuote,
            ),
          ),
        ),
      ),
    ),
  ).attachToRenderTree(owner);
  void flush() {
    owner.buildScope(root);
    pipeline.flushLayout();
    pipeline.flushCompositingBits();
    pipeline.flushPaint();
  }

  try {
    flush();
    await Future<void>.delayed(Duration.zero);
    flush();
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('小组件图片未能生成');
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    owner.buildScope(
      root,
      () => root.update(
        RenderObjectToWidgetAdapter<RenderBox>(container: boundary),
      ),
    );
    owner.finalizeTree();
    pipeline.rootNode = null;
    renderView.child = null;
    boundary.dispose();
    renderView.dispose();
    pipeline.dispose();
    focus.dispose();
  }
}
