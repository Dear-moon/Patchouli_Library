import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/glass_dock.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/performance_preferences.dart';

import 'support/visual_review.dart';

const _tabs = [
  GlassDockItem(CupertinoIcons.house, '发现'),
  GlassDockItem(CupertinoIcons.book, '书架', symbol: ArchiveSymbol.shelf),
  GlassDockItem(CupertinoIcons.folder, '本地'),
  GlassDockItem(CupertinoIcons.person_crop_circle, '我的'),
];

dynamic _painter(WidgetTester tester, Finder icon) => tester
    .widget<CustomPaint>(
      find.descendant(
        of: icon,
        matching: find.byType(CustomPaint, skipOffstage: false),
        skipOffstage: false,
      ),
    )
    .painter;

Animation<double> _gesture(WidgetTester tester, Finder icon) =>
    _painter(tester, icon).gesture as Animation<double>;

Finder _dockIcon(int slot) => find.descendant(
  of: find.byKey(ValueKey('dock-tab-$slot')),
  matching: find.byType(ArchiveIcon),
);

Widget _host(Widget child, {bool still = false, bool low = false}) =>
    MaterialApp(
      theme: novelTheme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: PerformanceScope(
          preferences: PerformancePreferences(enabled: low),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

void main() {
  setUpAll(loadReviewFonts);

  testWidgets('navigation animates its destination, never the outgoing icon', (
    tester,
  ) async {
    var selected = 0;
    late StateSetter change;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, set) {
            change = set;
            return GlassDock(
              selectedIndex: selected,
              items: _tabs,
              onSelected: (value) => set(() => selected = value),
              onReselected: (_) {},
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Start the discovery gesture, then leave before it has finished.
    await tester.tapAt(tester.getCenter(_dockIcon(0)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(_gesture(tester, _dockIcon(0)).status, AnimationStatus.forward);

    final touch = await tester.startGesture(tester.getCenter(_dockIcon(3)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_painter(tester, _dockIcon(0)).contact.value, 0);
    final contact = tester.widget<ArchiveIconContact>(
      find
          .ancestor(of: _dockIcon(0), matching: find.byType(ArchiveIconContact))
          .first,
    );
    expect(contact.pressed, isFalse);
    await touch.up();
    await tester.pump();
    expect(selected, 3);
    expect(_gesture(tester, _dockIcon(0)).status, AnimationStatus.completed);
    expect(_painter(tester, _dockIcon(0)).change.value, 1);
    await tester.pump(const Duration(milliseconds: 180));
    expect(_gesture(tester, _dockIcon(0)).value, 1);
    expect(_gesture(tester, _dockIcon(3)).status, AnimationStatus.forward);

    // A further quick switch stops the just-departed icon too.
    change(() => selected = 1);
    await tester.pump();
    expect(_gesture(tester, _dockIcon(3)).value, 1);
    expect(_gesture(tester, _dockIcon(1)).value, 0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'reader action dock animates a non-selected previous/next action',
    (tester) async {
      var next = 0;
      await tester.pumpWidget(
        _host(
          GlassDock(
            selectedIndex: 1,
            animateInactiveIcons: true,
            items: const [
              GlassDockItem(CupertinoIcons.arrow_left, '上一章'),
              GlassDockItem(CupertinoIcons.book, '目录', selectableOnDrag: false),
              GlassDockItem(CupertinoIcons.arrow_right, '下一章'),
            ],
            onSelected: (value) => next = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(_dockIcon(2)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(next, 2);
      expect(_gesture(tester, _dockIcon(2)).status, AnimationStatus.forward);
      expect(_gesture(tester, _dockIcon(1)).value, 1);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'presentation icons move on entry and pause between finite pulses',
    (tester) async {
      await tester.pumpWidget(
        _host(
          const ContentNotice(icon: CupertinoIcons.search, title: '没有找到相关内容'),
        ),
      );
      final icon = find.byType(ArchiveIcon);
      expect(tester.widget<ArchiveIcon>(icon).ambient, isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_gesture(tester, icon).value, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(_gesture(tester, icon).value, 1);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(milliseconds: 2000));
      expect(_gesture(tester, icon).value, 1);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_gesture(tester, icon).value, inExclusiveRange(0, 1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'hidden tabs, reduced motion and low-performance stop idle pulses',
    (tester) async {
      Future<void> show({
        bool visible = true,
        bool still = false,
        bool low = false,
      }) => tester.pumpWidget(
        _host(
          TickerMode(
            enabled: visible,
            child: const ArchiveIcon.symbol(ArchiveSymbol.shelf, ambient: true),
          ),
          still: still,
          low: low,
        ),
      );
      final icon = find.byType(ArchiveIcon);
      await show();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_gesture(tester, icon).value, lessThan(1));
      for (final mode in ['hidden', 'reduced', 'low']) {
        await show(
          visible: mode != 'hidden',
          still: mode == 'reduced',
          low: mode == 'low',
        );
        expect(_gesture(tester, icon).value, 1);
        await tester.pump(const Duration(seconds: 4));
        expect(tester.binding.transientCallbackCount, 0);
        await show();
        await tester.pump(const Duration(milliseconds: 160));
        expect(_gesture(tester, icon).value, inExclusiveRange(0, 1));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'covering a route and backgrounding the app stop ambient motion',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(
            body: ContentNotice(
              icon: CupertinoIcons.wifi_exclamationmark,
              title: '连接未完成',
            ),
          ),
        ),
      );
      final icon = find.byType(ArchiveIcon, skipOffstage: false);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_gesture(tester, icon).value, lessThan(1));
      navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('另一页'))),
      );
      await tester.pumpAndSettle();
      expect(_gesture(tester, icon).value, 1);
      await tester.pump(const Duration(seconds: 4));
      expect(tester.binding.transientCallbackCount, 0);
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_gesture(tester, icon).value, lessThan(1));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(_gesture(tester, icon).value, 1);
      await tester.pump(const Duration(seconds: 4));
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_gesture(tester, icon).value, lessThan(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('the actual empty bookshelf uses the animated shelf artwork', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'shelfLayout': 'list'});
    final state = await LibraryState.load();
    addTearDown(state.dispose);
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          theme: novelTheme(Brightness.light),
          home: HomeShell(
            state: state,
            repository: const DemoNovelRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(_dockIcon(1)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    final icon = find.byKey(const ValueKey('empty-shelf-icon'));
    final widget = tester.widget<ArchiveIcon>(icon);
    expect(widget.symbol, ArchiveSymbol.shelf);
    expect(widget.ambient, isTrue);
    expect(find.text('书架还空着'), findsOneWidget);
    expect(_gesture(tester, icon).value, inExclusiveRange(0, 1));
    await captureReview(tester, capture, 'empty-shelf-motion');
    await tester.pumpAndSettle();
    await captureReview(tester, capture, 'empty-shelf-rest');
    await tester.tapAt(tester.getCenter(_dockIcon(3)));
    await tester.pumpAndSettle();
    final hidden = find.byKey(
      const ValueKey('empty-shelf-icon'),
      skipOffstage: false,
    );
    expect(_gesture(tester, hidden).value, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(_gesture(tester, hidden).value, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
