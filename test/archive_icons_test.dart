import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/glass_dock.dart';
import 'package:wenku8_flutter/performance_preferences.dart';
import 'package:xml/xml.dart';

import '../tools/export_icon_studio.dart';
import '../tools/icon_studio.dart';
import 'support/visual_review.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReviewFonts);

  test('every symbol exports finite artwork inside its optical canvas', () {
    final spills = <String, Rect>{};
    for (final symbol in ArchiveSymbol.values) {
      for (final motion in [
        ArchiveIconGesture.rest,
        const ArchiveIconGesture(1.2, 1.2, 1.2),
        const ArchiveIconGesture(-.3, -.3, -.3),
        for (var i = 0; i <= 32; i++) ArchiveIconMotion.frame(i / 32),
      ]) {
        final paths = ArchiveIconArt.paths(
          symbol,
          gesture: motion,
          active: true,
        );
        expect(paths, isNotEmpty, reason: symbol.name);
        for (final path in paths) {
          expect(path.getBounds().isFinite, isTrue, reason: symbol.name);
          // Bounds include Bézier control points; check actual curve ink.
          for (final metric in path.computeMetrics()) {
            for (var step = 0; step <= 32; step++) {
              final point = metric
                  .getTangentForOffset(metric.length * step / 32)!
                  .position;
              if (point.dx < .85 ||
                  point.dx > 23.15 ||
                  point.dy < .85 ||
                  point.dy > 23.15) {
                final pixel = Rect.fromLTWH(point.dx, point.dy, 0, 0);
                spills[symbol.name] =
                    spills[symbol.name]?.expandToInclude(pixel) ?? pixel;
              }
            }
          }
        }
        final svg = ArchiveIconArt.svg(symbol, gesture: motion);
        expect(XmlDocument.parse(svg).rootElement.name.local, 'svg');
        expect(svg, isNot(contains('NaN')));
        expect(svg, isNot(contains('Infinity')));
      }
    }
    expect(spills, isEmpty, reason: spills.toString());
  });

  test('paper gesture anticipates, overshoots and settles in three parts', () {
    expect(ArchiveIconMotion.frame(0).lead, 0);
    expect(ArchiveIconMotion.frame(.10).lead, lessThan(0));
    final peak = ArchiveIconMotion.frame(.36);
    expect(peak.lead, closeTo(1, .001));
    expect(peak.follow, lessThan(peak.lead));
    expect(peak.trail, lessThan(peak.follow));
    expect(ArchiveIconMotion.frame(.64).lead, lessThan(0));
    final settled = ArchiveIconMotion.frame(1);
    expect([settled.lead, settled.follow, settled.trail], everyElement(0));
  });

  testWidgets(
    'a short accepted tap plays a full visible gesture after release',
    (tester) async {
      final key = GlobalKey();
      var calls = 0;
      await tester.pumpWidget(
        _host(
          GlassIconButton.custom(
            label: '调整',
            onPressed: () => calls++,
            child: RepaintBoundary(
              key: key,
              child: const Center(
                child: ArchiveIcon.symbol(ArchiveSymbol.sliders, size: 24),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = await _pixels(tester, key);
      await tester.tap(find.byType(GlassIconButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      final during = await _pixels(tester, key);
      var changed = 0;
      for (var i = 0; i < before.length; i += 4) {
        if (before[i] != during[i] ||
            before[i + 1] != during[i + 1] ||
            before[i + 2] != during[i + 2] ||
            before[i + 3] != during[i + 3]) {
          changed++;
        }
      }
      expect(calls, 1);
      expect(changed, greaterThan(40));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpAndSettle();
      expect(await _pixels(tester, key), orderedEquals(before));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  test('every existing app IconData has a vector and no raw Icon remains', () {
    final symbols = File('lib/archive_icons.dart').readAsStringSync();
    final definitions = RegExp(
      r'(?:CupertinoIcons|Icons)\s*\.\s*(\w+)\s*:',
    ).allMatches(symbols).map((m) => m[1]).toSet();
    const aliases = {'checkmark': 'check_mark', 'arrow_clockwise': 'refresh'};
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('archive_icons.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      expect(RegExp(r'\bIcon\(').hasMatch(source), isFalse, reason: file.path);
      for (final m in RegExp(
        r'(?:CupertinoIcons|Icons)\s*\.\s*(\w+)',
      ).allMatches(source)) {
        expect(
          definitions,
          contains(aliases[m[1]] ?? m[1]),
          reason: '${file.path}: ${m[0]}',
        );
      }
    }
    for (final entry in ArchiveIconSymbols.legacy.entries) {
      expect(ArchiveIconSymbols.resolve(entry.key), entry.value);
    }
    expect(
      ArchiveIconSymbols.resolve(CupertinoIcons.checkmark),
      ArchiveSymbol.check,
    );
    expect(
      ArchiveIconSymbols.resolve(CupertinoIcons.arrow_clockwise),
      ArchiveSymbol.refresh,
    );
  });

  testWidgets('a cancelled drag never plays the accepted-click gesture', (
    tester,
  ) async {
    final key = GlobalKey();
    var calls = 0;
    await tester.pumpWidget(
      _host(
        GestureDetector(
          onHorizontalDragUpdate: (_) {},
          child: GlassIconButton.custom(
            label: '本地书库',
            onPressed: () => calls++,
            child: RepaintBoundary(
              key: key,
              child: const ArchiveIcon.symbol(ArchiveSymbol.folder, size: 24),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = await _pixels(tester, key);
    final finger = await tester.startGesture(
      tester.getCenter(find.byType(GlassIconButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await finger.moveBy(const Offset(90, 0));
    await tester.pump();
    await finger.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, 0);
    expect(await _pixels(tester, key), orderedEquals(before));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('rapid replay keeps the current pose and still mode stops it', (
    tester,
  ) async {
    final key = GlobalKey();
    Future<void> show(int trigger, {bool still = false}) => tester.pumpWidget(
      _host(
        _boundary(
          key,
          ArchiveIcon.symbol(ArchiveSymbol.shelf, size: 40, trigger: trigger),
        ),
        still: still,
      ),
    );
    await show(0);
    await tester.pumpAndSettle();
    final rest = await _pixels(tester, key);
    await show(1);
    await tester.pump(const Duration(milliseconds: 240));
    final moving = await _pixels(tester, key);
    expect(moving, isNot(orderedEquals(rest)));
    await show(2);
    expect(await _pixels(tester, key), orderedEquals(moving));
    await tester.pump(const Duration(milliseconds: 80));
    await show(3, still: true);
    expect(await _pixels(tester, key), orderedEquals(rest));
    expect(tester.binding.transientCallbackCount, 0);
    await show(4, still: true);
    expect(await _pixels(tester, key), orderedEquals(rest));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'contact changes ink, not layout; release returns exactly to rest',
    (tester) async {
      final capture = GlobalKey();
      await tester.pumpWidget(
        _host(
          _boundary(
            capture,
            GlassIconButton(
              icon: CupertinoIcons.slider_horizontal_3,
              label: '阅读设置',
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final finder = find.byIcon(CupertinoIcons.slider_horizontal_3);
      final size = tester.getSize(finder);
      final before = await _pixels(tester, capture);
      final finger = await tester.startGesture(tester.getCenter(finder));
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump(const Duration(milliseconds: 140));
      expect(await _pixels(tester, capture), isNot(orderedEquals(before)));
      expect(tester.getSize(finder), size);
      await finger.up();
      await tester.pumpAndSettle();
      expect(await _pixels(tester, capture), orderedEquals(before));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  for (final pair in [
    (CupertinoIcons.play_fill, CupertinoIcons.pause_fill),
    (CupertinoIcons.chevron_right, CupertinoIcons.chevron_down),
    (CupertinoIcons.circle, CupertinoIcons.checkmark_circle_fill),
    (CupertinoIcons.bookmark, CupertinoIcons.bookmark_fill),
    (CupertinoIcons.eye, CupertinoIcons.eye_slash),
  ]) {
    testWidgets(
      'state morph ${pair.$1.codePoint} is continuous and reversible',
      (tester) async {
        final key = GlobalKey();
        Future<void> show(IconData data) => tester.pumpWidget(
          _host(
            _boundary(key, ArchiveIcon(data, size: 40, semanticLabel: '状态')),
          ),
        );
        await show(pair.$1);
        final start = await _pixels(tester, key);
        await show(pair.$2);
        expect(await _pixels(tester, key), orderedEquals(start));
        await tester.pump(const Duration(milliseconds: 90));
        expect(await _pixels(tester, key), isNot(orderedEquals(start)));
        // Interrupt an unfinished transition, as repeated real taps do.
        await show(pair.$1);
        await tester.pumpAndSettle();
        expect(await _pixels(tester, key), orderedEquals(start));
        expect(tester.binding.transientCallbackCount, 0);
        await show(pair.$2);
        await tester.pumpAndSettle();
        final end = await _pixels(tester, key);
        await tester.pumpWidget(const SizedBox.shrink());
        await show(pair.$2);
        expect(await _pixels(tester, key), orderedEquals(end));
      },
    );
  }

  testWidgets('reduced motion and low-performance settle state immediately', (
    tester,
  ) async {
    for (final low in [false, true]) {
      Future<void> show(IconData data) => tester.pumpWidget(
        _host(ArchiveIcon(data, size: 24), still: !low, low: low),
      );
      await show(CupertinoIcons.play_fill);
      await show(CupertinoIcons.pause_fill);
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);
    }
  });

  testWidgets('Material control keeps its full target, tooltip and semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var calls = 0;
    await tester.pumpWidget(
      _host(
        ArchiveIconButton(
          tooltip: '复制评论',
          icon: const ArchiveIcon(CupertinoIcons.doc_on_doc),
          onPressed: () => calls++,
        ),
      ),
    );
    expect(find.byTooltip('复制评论'), findsOneWidget);
    final target = find.byType(ArchiveIconButton);
    expect(tester.getSize(target).shortestSide, greaterThanOrEqualTo(40));
    await tester.tapAt(tester.getTopLeft(target) + const Offset(3, 3));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.pumpWidget(
      _host(
        const ArchiveIconButton(
          tooltip: '复制评论',
          icon: ArchiveIcon(CupertinoIcons.doc_on_doc),
          onPressed: null,
        ),
      ),
    );
    await tester.tap(find.byType(ArchiveIconButton));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'semantic labels do not expose paths; theme opacity and RTL work',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final key = GlobalKey();
      Future<void> show(TextDirection direction, {double opacity = 1}) =>
          tester.pumpWidget(
            _host(
              Directionality(
                textDirection: direction,
                child: IconTheme(
                  data: IconThemeData(
                    color: Colors.white,
                    size: 30,
                    opacity: opacity,
                  ),
                  child: _boundary(
                    key,
                    const ArchiveIcon.symbol(
                      ArchiveSymbol.back,
                      semanticLabel: '返回',
                    ),
                  ),
                ),
              ),
              dark: true,
            ),
          );
      await show(TextDirection.ltr);
      await tester.pumpAndSettle();
      final ltr = await _pixels(tester, key);
      expect(find.bySemanticsLabel('返回'), findsOneWidget);
      expect(tester.getSize(find.byType(ArchiveIcon)), const Size(30, 30));
      await show(TextDirection.rtl);
      expect(await _pixels(tester, key), isNot(orderedEquals(ltr)));
      await show(TextDirection.ltr, opacity: .4);
      expect(await _pixels(tester, key), isNot(orderedEquals(ltr)));
      expect(tester.binding.transientCallbackCount, 0);
      semantics.dispose();
    },
  );

  testWidgets('studio remains usable at 320 logical pixels', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const IconStudioApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('dock-tab-3'))),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<GlassDock>(find.byType(GlassDock)).selectedIndex, 3);
    await tester.ensureVisible(find.byKey(const ValueKey('studio-play')));
    await tester.tap(find.byKey(const ValueKey('studio-play')));
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('production controls and full family render in light and dark', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1080, 2040);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final dark in [false, true]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(dark),
          theme: novelTheme(dark ? Brightness.dark : Brightness.light),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(body: Atmosphere(child: const IconStudioSheet())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('故障排查'), findsOneWidget);
      await captureReview(tester, key, dark ? 'icons-dark' : 'icons-light');
      await tester.tap(find.byKey(const ValueKey('studio-play')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await captureReview(
        tester,
        key,
        dark ? 'icons-dark-motion' : 'icons-light-motion',
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    }
    if (const bool.fromEnvironment('EXPORT_ARCHIVE_ICONS')) {
      exportIconStudio(Directory('build/icon-studio'));
    }
  });

  testWidgets('record the real Flutter motion at 48 and 24 logical pixels', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('EXPORT_ARCHIVE_ICONS')) return;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 230);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Directory('build/icon-studio/motion').createSync(recursive: true);
    final key = GlobalKey();
    late StateSetter change;
    var epoch = 0;
    var active = false;
    const symbols = [
      ArchiveSymbol.discover,
      ArchiveSymbol.shelf,
      ArchiveSymbol.book,
      ArchiveSymbol.folder,
      ArchiveSymbol.profile,
      ArchiveSymbol.bookmark,
      ArchiveSymbol.play,
      ArchiveSymbol.sliders,
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: novelTheme(Brightness.light),
        home: StatefulBuilder(
          builder: (context, set) {
            change = set;
            return RepaintBoundary(
              key: key,
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '折页墨线',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const ArchiveCode(
                        'WENKU8 / 48px + 24px / NATIVE FLUTTER MOTION',
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          for (final base in symbols)
                            Expanded(
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      for (final size in [48.0, 24.0]) ...[
                                        ArchiveIcon.symbol(
                                          active
                                              ? switch (base) {
                                                  ArchiveSymbol.play =>
                                                    ArchiveSymbol.pause,
                                                  ArchiveSymbol.bookmark =>
                                                    ArchiveSymbol.bookmarked,
                                                  _ => base,
                                                }
                                              : base,
                                          size: size,
                                          active: active,
                                          trigger: epoch,
                                        ),
                                        if (size == 48)
                                          const SizedBox(width: 10),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    base.label,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await captureReview(tester, key, 'motion/000');
    for (var turn = 0; turn < 2; turn++) {
      change(() {
        epoch++;
        active = !active;
      });
      await tester.pump();
      await tester.pump();
      for (var frame = 1; frame <= 32; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await captureReview(
          tester,
          key,
          'motion/${(turn * 32 + frame).toString().padLeft(3, '0')}',
        );
      }
    }
    expect(tester.takeException(), isNull);
    // AnimationController retires its ticker on the first frame strictly after
    // the duration; the captured 640 ms endpoint is already the resting pose.
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.binding.transientCallbackCount, 0);
  });
}

Widget _host(
  Widget child, {
  bool still = false,
  bool low = false,
  bool dark = false,
}) => MaterialApp(
  themeAnimationDuration: Duration.zero,
  theme: novelTheme(dark ? Brightness.dark : Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: PerformanceScope(
      preferences: PerformancePreferences(enabled: low),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

Widget _boundary(GlobalKey key, Widget child) => RepaintBoundary(
  key: key,
  child: SizedBox(width: 64, height: 64, child: Center(child: child)),
);

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key) async {
  final render =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  if (render.debugNeedsPaint) tester.binding.rootPipelineOwner.flushPaint();
  final image = render.toImageSync();
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final copy = Uint8List.fromList(bytes.buffer.asUint8List());
  image.dispose();
  return copy;
}
