import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as easy;
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/glass_dock.dart';
import 'package:wenku8_flutter/feature_pages.dart';
import 'package:wenku8_flutter/review_content.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  final calls = <String>[];
  setUp(() {
    calls.clear();
    AppHaptics.resetForTesting();
    messenger.setMockMethodCallHandler(AppHaptics.channel, (call) async {
      expect(call.method, 'play');
      calls.add(call.arguments as String);
      return true;
    });
  });
  tearDown(() {
    AppHaptics.resetForTesting();
    messenger.setMockMethodCallHandler(AppHaptics.channel, null);
  });

  test(
    'gate prevents double knocks without silencing the next unrelated interaction',
    () {
      final gate = HapticGate();
      expect(gate.accept(HapticCue.detent, Duration.zero), isTrue);
      expect(
        gate.accept(HapticCue.detent, const Duration(milliseconds: 20)),
        isFalse,
      );
      expect(
        gate.accept(HapticCue.detent, const Duration(milliseconds: 70)),
        isTrue,
      );
      expect(
        gate.accept(HapticCue.action, const Duration(milliseconds: 101)),
        isFalse,
      );
      expect(
        gate.accept(HapticCue.success, const Duration(milliseconds: 102)),
        isFalse,
      );
      expect(
        gate.accept(HapticCue.selection, const Duration(milliseconds: 165)),
        isTrue,
      );
      expect(
        gate.accept(HapticCue.success, const Duration(milliseconds: 240)),
        isTrue,
      );
      expect(
        gate.accept(HapticCue.pageTurn, const Duration(milliseconds: 320)),
        isTrue,
      );
      expect(
        gate.accept(HapticCue.success, const Duration(milliseconds: 400)),
        isFalse,
      );
      expect(
        gate.accept(HapticCue.error, const Duration(milliseconds: 410)),
        isTrue,
      );
      expect(
        gate.accept(HapticCue.error, const Duration(milliseconds: 600)),
        isFalse,
      );
      expect(
        gate.accept(HapticCue.shelfStep, const Duration(milliseconds: 700)),
        isTrue,
      );
    },
  );

  test('normal progress detents retain their 70 ms cadence', () {
    final gate = HapticGate();
    for (var step = 0; step < 30; step++) {
      expect(
        gate.accept(HapticCue.detent, Duration(milliseconds: step * 70)),
        isTrue,
      );
    }
    expect(
      HapticGate.interval(HapticCue.shelfStep),
      const Duration(milliseconds: 65),
    );
  });

  testWidgets(
    'every interactive content surface clicks and copying confirms its result',
    (tester) async {
      var clock = Duration.zero;
      AppHaptics.resetForTesting(now: () => clock);
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ContentPanel(onTap: () {}, child: const Text('内容卡片')),
                JellyTapSurface(onTap: () {}, child: const Text('普通入口')),
                LiquidGlass(onTap: () {}, child: const Text('阅读面板')),
                const ReviewContent(content: '可复制的评论', byline: '作者'),
              ],
            ),
          ),
        ),
      );
      for (final label in ['内容卡片', '普通入口', '阅读面板']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        clock += const Duration(seconds: 1);
      }
      expect(calls, ['action', 'action', 'action']);
      await tester.tap(find.byKey(const ValueKey('review-copy-text')));
      await tester.pump();
      expect(calls, ['action', 'action', 'action', 'success']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Dock selects, buttons act, selected choices tick, confirmation warns',
    (tester) async {
      var clock = Duration.zero;
      AppHaptics.resetForTesting(now: () => clock);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  GlassDock(selectedIndex: 0, onSelected: (_) {}),
                  GlassTextButton(onPressed: () {}, child: const Text('操作')),
                  GlassTextButton(
                    selected: false,
                    onPressed: () {},
                    child: const Text('选项'),
                  ),
                  GlassTextButton(
                    onPressed: () => confirmNovelAction(
                      context,
                      title: '移除书籍？',
                      message: '保留原文件',
                      confirmLabel: '确认移除',
                      reduceMotion: true,
                    ),
                    child: const Text('删除'),
                  ),
                  const GlassTextButton(onPressed: null, child: Text('禁用')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('dock-tab-1'))),
      );
      await tester.pumpAndSettle();
      clock += const Duration(seconds: 1);
      await tester.tap(find.text('操作'));
      await tester.pumpAndSettle();
      clock += const Duration(seconds: 1);
      await tester.tap(find.text('选项'));
      await tester.pumpAndSettle();
      clock += const Duration(seconds: 1);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      clock += const Duration(seconds: 1);
      await tester.tap(find.text('确认移除'));
      await tester.pumpAndSettle();
      expect(calls, ['selection', 'action', 'selection', 'action', 'warning']);
      clock += const Duration(seconds: 1);
      await tester.tap(find.text('禁用'));
      await tester.pumpAndSettle();
      expect(calls.length, 5);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cancelled scroll, covered route and app background stay silent',
    (tester) async {
      late BuildContext source;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                source = context;
                return GestureDetector(
                  onHorizontalDragUpdate: (_) {},
                  child: GlassIconButton(
                    icon: Icons.image_outlined,
                    label: '图',
                    onPressed: () {},
                  ),
                );
              },
            ),
          ),
        ),
      );
      final finger = await tester.startGesture(
        tester.getCenter(find.byType(GlassIconButton)),
      );
      await finger.moveBy(const Offset(100, 0));
      await finger.up();
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('其他页面')),
        ),
      );
      await tester.pumpAndSettle();
      AppHaptics.play(source, HapticCue.success);
      await tester.pump();
      expect(calls, isEmpty);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      AppHaptics.play(source, HapticCue.error);
      await tester.pump();
      expect(calls, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      AppHaptics.play(source, HapticCue.success);
      await tester.pump();
      expect(calls, ['success']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'glass controls share one short feedback owner, not package impact plus app tick',
    (tester) async {
      var clock = Duration.zero;
      AppHaptics.resetForTesting(now: () => clock);
      final raw = <MethodCall>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') raw.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      var toggled = false;
      var slider = .5;
      var segment = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: StatefulBuilder(
                  builder: (context, update) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppControls.toggle(
                        context,
                        value: toggled,
                        onChanged: (value) => update(() => toggled = value),
                      ),
                      AppControls.slider(
                        context,
                        value: slider,
                        onChanged: (value) => update(() => slider = value),
                      ),
                      AppControls.segments<int>(
                        context,
                        groupValue: segment,
                        children: const {0: Text('第一项'), 1: Text('第二项')},
                        onValueChanged: (value) =>
                            update(() => segment = value!),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(easy.LiquidGlassSwitch));
      await tester.pumpAndSettle();
      expect(toggled, isTrue);
      expect(calls, ['selection']);
      clock += const Duration(seconds: 1);
      final finger = await tester.startGesture(
        tester.getCenter(find.byType(easy.LiquidGlassSlider)),
      );
      await finger.moveBy(const Offset(300, 0));
      await tester.pump(const Duration(milliseconds: 120));
      await finger.up();
      await tester.pumpAndSettle();
      expect(slider, 1);
      expect(calls, [
        'selection',
        'boundary',
      ], reason: 'Drag endpoint and release do not double-knock.');
      clock += const Duration(seconds: 1);
      await tester.tap(find.text('第二项'));
      await tester.pumpAndSettle();
      expect(segment, 1);
      expect(calls, ['selection', 'boundary', 'selection']);
      clock += const Duration(seconds: 1);
      await tester.tap(find.text('第二项'));
      await tester.pumpAndSettle();
      expect(
        calls,
        hasLength(3),
        reason: 'Selecting the existing value stays quiet.',
      );
      expect(
        raw,
        isEmpty,
        reason: 'No vendor light/medium impact escapes the shared gate.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('native refusal never falls through to a forced fallback', (
    tester,
  ) async {
    final fallback = <MethodCall>[];
    messenger.setMockMethodCallHandler(AppHaptics.channel, (_) async => false);
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      fallback.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AppHaptics.play(context, HapticCue.error),
              child: const Text('触发'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('触发'));
    await tester.pump();
    expect(
      fallback.where((call) => call.method == 'HapticFeedback.vibrate'),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
