import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as easy;
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/updates/release_highlights.dart';
import 'package:wenku8_flutter/updates/release_markdown.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  var clock = Duration.zero;
  setUp(() {
    calls.clear();
    clock = Duration.zero;
    AppHaptics.resetForTesting(now: () => clock);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AppHaptics.channel,
      (call) async {
        calls.add(call.arguments as String);
        return true;
      },
    );
  });
  tearDown(() {
    AppHaptics.resetForTesting();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AppHaptics.channel,
      null,
    );
  });

  testWidgets('ordinary touch and scrolling stay quiet until an edge', (
    tester,
  ) async {
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const NovelScrollBehavior(),
        home: Scaffold(
          body: ListView.builder(
            controller: scroll,
            itemExtent: 80,
            itemCount: 60,
            itemBuilder: (_, i) => Text('条目 $i'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(calls, isEmpty);
    final finger = await tester.startGesture(const Offset(200, 300));
    await finger.moveBy(const Offset(0, -80));
    await tester.pump();
    clock += const Duration(milliseconds: 200);
    await finger.moveBy(const Offset(0, -80));
    await tester.pump();
    await finger.up();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(calls, isEmpty, reason: 'programmatic scrolling is silent');
    clock += const Duration(seconds: 1);
    final edge = await tester.startGesture(const Offset(200, 300));
    await edge.moveBy(const Offset(0, -60));
    await tester.pump();
    clock += const Duration(milliseconds: 200);
    await edge.moveBy(const Offset(0, -60));
    await tester.pump();
    await edge.up();
    await tester.pumpAndSettle();
    expect(calls, ['boundary']);
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
  });

  testWidgets('continuous slider has interior and fine-step feedback once', (
    tester,
  ) async {
    var value = .5;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: StatefulBuilder(
                builder: (context, update) => AppControls.slider(
                  context,
                  value: value,
                  onChanged: (next) => update(() => value = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    easy.LiquidGlassSlider slider() =>
        tester.widget(find.byType(easy.LiquidGlassSlider));
    slider().onChangeStart?.call(.5);
    slider().onChanged(.501);
    await tester.pump();
    expect(value, .501);
    expect(calls, ['detent'], reason: 'even a fine adjustment is acknowledged');
    clock += const Duration(milliseconds: 70);
    slider().onChanged(.55);
    await tester.pump();
    clock += const Duration(milliseconds: 70);
    slider().onChanged(.6);
    await tester.pump();
    expect(calls, ['detent', 'detent', 'detent']);
    clock += const Duration(milliseconds: 200);
    slider().onChangeEnd?.call(.6);
    await tester.pump();
    expect(calls, hasLength(3), reason: 'release does not add a second owner');
    clock += const Duration(milliseconds: 200);
    slider().onChangeStart?.call(.6);
    slider().onChanged(1);
    slider().onChangeEnd?.call(1);
    await tester.pump();
    expect(calls.last, 'boundary');
    expect(calls, hasLength(4));
  });

  testWidgets(
    'sheet barrier and drag dismissal acknowledge the closing action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => GlassTextButton(
                onPressed: () => showJellySheet<void>(
                  context: context,
                  builder: (_) =>
                      const SizedBox(height: 180, child: Text('弹层内容')),
                ),
                child: const Text('打开弹层'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开弹层'));
      await tester.pumpAndSettle();
      expect(calls, ['action']);
      clock += const Duration(seconds: 1);
      await tester.tapAt(const Offset(10, 30));
      await tester.pumpAndSettle();
      expect(find.text('弹层内容'), findsNothing);
      expect(calls, ['action', 'action']);
      clock += const Duration(seconds: 1);
      await tester.tap(find.text('打开弹层'));
      await tester.pumpAndSettle();
      clock += const Duration(seconds: 1);
      await tester.drag(find.text('弹层内容'), const Offset(0, 140));
      await tester.pumpAndSettle();
      expect(find.text('弹层内容'), findsNothing);
      expect(calls, ['action', 'action', 'action', 'action']);
    },
  );

  testWidgets(
    'release links and manual page changes click, entrance stays silent',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ReleaseNotes(
                  '[项目主页](https://example.com)',
                  onOpenLink: (_) async => opened++,
                ),
                Builder(
                  builder: (context) => GlassTextButton(
                    onPressed: () => showInstalledReleaseNotes(context),
                    child: const Text('查看更新'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('项目主页'));
      await tester.pump();
      expect(opened, 1);
      expect(calls, ['action']);
      clock += const Duration(seconds: 1);
      await tester.tap(find.text('查看更新'));
      await tester.pumpAndSettle();
      expect(calls, ['action', 'action']);
      clock += const Duration(seconds: 1);
      await tester.drag(
        find.byKey(const ValueKey('release-details-pages')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      expect(calls, ['action', 'action', 'pageTurn']);
      clock += const Duration(seconds: 1);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('installed-release-details')),
        findsNothing,
      );
      expect(calls.last, 'action');
    },
  );
}
