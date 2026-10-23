import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/performance_preferences.dart';

import 'support/visual_review.dart';

dynamic _painter(WidgetTester tester, String key) => tester
    .widget<CustomPaint>(
      find.descendant(
        of: find.byKey(ValueKey(key), skipOffstage: false),
        matching: find.byType(CustomPaint, skipOffstage: false),
        skipOffstage: false,
      ),
    )
    .painter;

Animation<double> _gesture(WidgetTester tester, String key) =>
    _painter(tester, key).gesture as Animation<double>;

double _framePhase(WidgetTester tester, String key) {
  final painter = _painter(tester, key);
  return (((painter.gesture.value as double) -
              (painter.gestureStart as double)) /
          (painter.gestureSpan as double))
      .clamp(0, 1);
}

Widget _icon(String key, {bool animate = true}) => ArchiveIcon.symbol(
  ArchiveSymbol.shelf,
  key: ValueKey(key),
  size: 32,
  animate: animate,
);

Widget _host(Widget child, {bool reduced = false, bool low = false}) =>
    MaterialApp(
      theme: novelTheme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 600),
          disableAnimations: reduced,
        ),
        child: PerformanceScope(
          preferences: PerformancePreferences(enabled: low),
          child: Scaffold(body: child),
        ),
      ),
    );

void main() {
  setUpAll(loadReviewFonts);

  testWidgets('visible icons greet once and rebuilds never replay or vibrate', (
    tester,
  ) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AppHaptics.channel,
      (call) async {
        haptics.add(call.method);
        return true;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AppHaptics.channel,
        null,
      ),
    );
    Future<void> show() =>
        tester.pumpWidget(_host(Center(child: _icon('book'))));
    await show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_gesture(tester, 'book').value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(_gesture(tester, 'book').value, 1);
    await show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_gesture(tester, 'book').value, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(tester.binding.transientCallbackCount, 0);
    expect(haptics, isEmpty);
  });

  testWidgets('entry staggers by visible position without moving layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [_icon('top'), _icon('bottom')],
        ),
      ),
    );
    final top = tester.getRect(find.byKey(const ValueKey('top')));
    final bottom = tester.getRect(find.byKey(const ValueKey('bottom')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(
      _painter(tester, 'top').gestureStart,
      lessThan(_painter(tester, 'bottom').gestureStart as double),
    );
    expect(tester.getRect(find.byKey(const ValueKey('top'))), top);
    expect(tester.getRect(find.byKey(const ValueKey('bottom'))), bottom);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('cached offscreen and offstage icons stay still on entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Stack(
          children: [
            SizedBox(
              height: 160,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _icon('visible'),
                    const SizedBox(height: 600),
                    _icon('below-viewport'),
                  ],
                ),
              ),
            ),
            Offstage(child: _icon('offstage')),
            TickerMode(enabled: false, child: _icon('hidden-tab')),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(_gesture(tester, 'visible').value, inExclusiveRange(0, 1));
    for (final key in ['below-viewport', 'offstage', 'hidden-tab']) {
      expect(_gesture(tester, key).value, 1, reason: key);
    }
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('visible rows cascade top middle bottom with equal-row timing', (
    tester,
  ) async {
    final capture = GlobalKey();
    Widget row(String name, String label) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label)),
          ArchiveIcon.symbol(
            ArchiveSymbol.shelf,
            key: ValueKey('$name-a'),
            size: 48,
          ),
          const SizedBox(width: 36),
          ArchiveIcon.symbol(
            ArchiveSymbol.shelf,
            key: ValueKey('$name-b'),
            size: 48,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      _host(
        RepaintBoundary(
          key: capture,
          child: ColoredBox(
            color: const Color(0xfffaf7ef),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  row('top', '顶部'),
                  row('middle', '中部'),
                  row('bottom', '底部'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (final name in ['top', 'middle', 'bottom']) {
      expect(
        _painter(tester, '$name-a').gestureStart,
        _painter(tester, '$name-b').gestureStart,
      );
    }
    final spread = (_painter(tester, 'bottom-a').gestureStart as double) * 880;
    expect(spread, 360);
    await tester.pump(const Duration(milliseconds: 190));
    expect(_framePhase(tester, 'top-a'), inExclusiveRange(.3, .4));
    expect(_framePhase(tester, 'middle-a'), lessThan(.05));
    expect(_framePhase(tester, 'bottom-a'), 0);
    await captureReview(tester, capture, 'page-icons-cascade-190ms-top');
    await tester.pump(const Duration(milliseconds: 180));
    expect(_framePhase(tester, 'middle-a'), inExclusiveRange(.3, .4));
    expect(_framePhase(tester, 'bottom-a'), lessThan(.05));
    await captureReview(tester, capture, 'page-icons-cascade-370ms-middle');
    await tester.pump(const Duration(milliseconds: 180));
    expect(_framePhase(tester, 'top-a'), 1);
    expect(_framePhase(tester, 'bottom-a'), inExclusiveRange(.3, .4));
    await captureReview(tester, capture, 'page-icons-cascade-550ms-bottom');
    await tester.pumpAndSettle();
    await captureReview(tester, capture, 'page-icons-cascade-settled');
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('lazy rows do not greet on scroll-in or scroll-back to the top', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(
        ListView.builder(
          controller: scroll,
          cacheExtent: 0,
          itemExtent: 80,
          itemCount: 40,
          itemBuilder: (_, index) => Center(child: _icon('row-$index')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(_gesture(tester, 'row-16').value, 1);
    scroll.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(_gesture(tester, 'row-0').value, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('late first-screen results get one entrance, not on rebuild', (
    tester,
  ) async {
    var ready = false;
    late StateSetter update;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (_, set) {
            update = set;
            return SingleChildScrollView(
              child: ready ? _icon('loaded') : const Text('loading'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    update(() => ready = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(_gesture(tester, 'loaded').value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    update(() {});
    await tester.pump();
    expect(_gesture(tester, 'loaded').value, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('returning to a retained tab replays only its current icons', (
    tester,
  ) async {
    Future<void> show(bool first) => tester.pumpWidget(
      _host(
        Stack(
          children: [
            TickerMode(enabled: first, child: _icon('first')),
            TickerMode(enabled: !first, child: _icon('second')),
          ],
        ),
      ),
    );
    await show(true);
    await tester.pumpAndSettle();
    await show(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(_gesture(tester, 'first').value, 1);
    expect(_gesture(tester, 'second').value, inExclusiveRange(0, 1));
    await show(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(_gesture(tester, 'first').value, inExclusiveRange(0, 1));
    expect(_gesture(tester, 'second').value, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('a reused header follows new page entry, not animation frames', (
    tester,
  ) async {
    final clock = AnimationController(
      vsync: tester,
      value: 1,
      duration: const Duration(milliseconds: 280),
    );
    addTearDown(clock.dispose);
    await tester.pumpWidget(
      _host(
        ArchiveMotionScope(
          animation: clock,
          child: Center(child: _icon('header')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    clock.forward(from: 0);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(_gesture(tester, 'header').value, inExclusiveRange(0, 1));
    final progress = _gesture(tester, 'header').value;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_gesture(tester, 'header').value, greaterThan(progress));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('covering a route stops action icons and returning greets once', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(body: Center(child: _icon('route'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(_gesture(tester, 'route').value, lessThan(1));
    navigator.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('next'))),
    );
    await tester.pumpAndSettle();
    expect(_gesture(tester, 'route').value, 1);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(_gesture(tester, 'route').value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
  });

  testWidgets('background and reduced motion stop every entrance', (
    tester,
  ) async {
    Future<void> show({bool reduced = false, bool low = false}) =>
        tester.pumpWidget(
          _host(
            Center(child: _icon('icon')),
            reduced: reduced,
            low: low,
          ),
        );
    await show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(_gesture(tester, 'icon').value, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(_gesture(tester, 'icon').value, inExclusiveRange(0, 1));
    await show(reduced: true);
    expect(_gesture(tester, 'icon').value, 1);
    await show(low: true);
    expect(_gesture(tester, 'icon').value, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('captures shared toolbar and decorative entrance at real size', (
    tester,
  ) async {
    final capture = GlobalKey();
    await tester.pumpWidget(
      _host(
        RepaintBoundary(
          key: capture,
          child: ColoredBox(
            color: const Color(0xfffaf7ef),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in [
                        (CupertinoIcons.search, '搜索'),
                        (CupertinoIcons.line_horizontal_3_decrease, '筛选'),
                        (CupertinoIcons.cloud_download, '缓存'),
                        (CupertinoIcons.settings, '设置'),
                      ])
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: GlassIconButton(
                            icon: item.$1,
                            label: item.$2,
                            onPressed: () {},
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 48),
                  const ArchiveIcon.symbol(ArchiveSymbol.shelf, size: 48),
                  const SizedBox(height: 16),
                  const Text('书架还空着'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await captureReview(tester, capture, 'page-icons-entry-240ms');
    await tester.pumpAndSettle();
    await captureReview(tester, capture, 'page-icons-entry-settled');
    expect(tester.binding.transientCallbackCount, 0);
  });
}
