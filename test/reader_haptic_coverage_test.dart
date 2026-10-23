import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/listening/controller.dart';
import 'package:wenku8_flutter/listening/models.dart';
import 'package:wenku8_flutter/listening/store.dart';
import 'package:wenku8_flutter/listening/widgets.dart';
import 'package:wenku8_flutter/reader_illustrations.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/reader_tools.dart';

import 'reader_modes_test.dart' as fixture;
import 'support/background_fixture.dart';
import 'support/cover_fixture.dart';
import 'support/listening_fixture.dart';
import 'support/visual_review.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  var clock = Duration.zero;
  setUpAll(loadReviewFonts);
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
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AppHaptics.channel,
      null,
    );
    AppHaptics.resetForTesting();
  });

  void nextInteraction() {
    clock += const Duration(seconds: 1);
    calls.clear();
  }

  testWidgets('reader chrome, accepted page and book boundary each respond', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'readerChromeVisible': true,
      'readerChromeHintSeen': true,
      'reduceMotion': true,
    });
    final library = LibraryState(
      await SharedPreferences.getInstance(),
      backgrounds: EmptyReaderBackgrounds(),
    );
    addTearDown(library.dispose);
    await library.setReaderPreferences(
      const ReaderPreferences(
        mode: ReaderMode.paged,
        tapPaging: true,
        reflowOnChrome: false,
      ),
    );
    await tester.pumpWidget(fixture.app(library));
    await fixture.settleReader(tester);
    expect(calls, isEmpty, reason: 'restoration is not a manual action');
    Future<void> tap(double x) async {
      nextInteraction();
      final rect = tester.getRect(fixture.content());
      await tester.tapAt(Offset(rect.left + rect.width * x, rect.center.dy));
      await fixture.settleReader(tester);
    }

    await tap(.5);
    expect(library.readerChromeVisible, isFalse);
    expect(calls, ['action']);
    await tap(.5);
    expect(library.readerChromeVisible, isTrue);
    expect(calls, ['action']);
    await tap(.1);
    expect(calls, ['boundary']);
    await tap(.9);
    expect(calls, ['pageTurn']);
    final pager = tester.widget<ReaderPagedView>(find.byType(ReaderPagedView));
    expect(pager.controller.page, greaterThan(0));
    nextInteraction();
    pager.controller.pageBy(1);
    await fixture.settleReader(tester);
    expect(calls, isEmpty, reason: 'automatic page movement stays quiet');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'reader slider owns pointer and semantic detents without release echo',
    (tester) async {
      var value = 2.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ReaderValueSlider(
                sliderKey: const ValueKey('haptic-reader-slider'),
                label: '字号',
                value: value,
                min: 0,
                max: 4,
                divisions: 4,
                format: (value) => '$value',
                onCommitted: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      );
      final slider = tester.widget<AppGlassSlider>(
        find.byKey(const ValueKey('haptic-reader-slider')),
      );
      expect(slider.haptics, isFalse);
      slider.onChangeStart?.call(2);
      slider.onChanged!(3);
      await tester.pump();
      expect(calls, ['detent']);
      nextInteraction();
      slider.onChangeEnd?.call(3);
      await tester.pump();
      expect(value, 3);
      expect(calls, isEmpty);
      final semantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('reader-slider-semantics-字号')),
      );
      semantics.properties.onIncrease!();
      await tester.pump();
      expect(value, 4);
      expect(calls, ['boundary']);
      nextInteraction();
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('reader-slider-semantics-字号')),
          )
          .properties
          .onDecrease!();
      await tester.pump();
      expect(value, 3);
      expect(calls, ['detent']);
    },
  );

  testWidgets('fine progress drag responds before crossing a haptic notch', (
    tester,
  ) async {
    final committed = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderValueSlider(
            sliderKey: const ValueKey('fine-progress'),
            label: '进度',
            value: 0,
            min: 0,
            max: 1,
            divisions: 500,
            hapticSteps: 100,
            format: (value) => '$value',
            onCommitted: committed.add,
          ),
        ),
      ),
    );
    final slider = tester.widget<AppGlassSlider>(
      find.byKey(const ValueKey('fine-progress')),
    );
    slider.onChangeStart!(0);
    slider.onChanged!(0);
    expect(calls, isEmpty);
    slider.onChanged!(.002);
    await tester.pump();
    expect(calls, ['detent']);
    clock += const Duration(milliseconds: 100);
    slider.onChanged!(.004);
    await tester.pump();
    expect(calls, [
      'detent',
    ], reason: 'subsequent values keep the existing cadence');
    slider.onChangeEnd!(.004);
    await tester.pump();
    expect(committed, [.004]);
    expect(calls, ['detent'], reason: 'release does not echo the drag');
    nextInteraction();
    slider.onChangeStart!(.004);
    slider.onChanged!(.002);
    await tester.pump();
    expect(calls, ['detent'], reason: 'each new effective gesture responds');
    slider.onChangeEnd!(.002);
    await tester.pump();
    expect(committed, [.004, .002]);
  });

  testWidgets(
    'paragraph double tap and accessibility share one manual feedback',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = ListeningController(
        repository: const DemoNovelRepository(),
        audio: FakeSpeechAudio(),
        store: ListeningStore(await SharedPreferences.getInstance()),
        outputFactory: (_) async => FakeListeningOutput(),
      );
      controller.snapshot.value = ListeningSnapshot(
        novel: demoNovels.first,
        chapter: 0,
        segments: const [SpeechSegment(0, 0, 4, '第一句。')],
        phase: ListeningPhase.paused,
      );
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListeningParagraphHighlight(
              controller: controller,
              novelId: demoNovels.first.id,
              chapter: 0,
              paragraph: 0,
              onDoubleTap: () async => activations++,
              child: const SizedBox(
                width: 200,
                height: 100,
                child: Text('第一句。'),
              ),
            ),
          ),
        ),
      );
      final target = find.byKey(
        const ValueKey('listening-paragraph-gesture-0'),
      );
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(target);
      await tester.pump();
      expect(activations, 1);
      expect(calls, ['action']);
      nextInteraction();
      final semantics = tester.widget<Semantics>(
        find.ancestor(of: target, matching: find.byType(Semantics)).first,
      );
      semantics.properties.onTap!();
      await tester.pump();
      expect(activations, 2);
      expect(calls, ['action']);
      await tester.pumpWidget(const SizedBox.shrink());
      final closing = controller.dispose();
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await closing;
    },
  );

  testWidgets(
    'cancelling an established gallery drag restores its page without feedback',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = (await tester.runAsync(coverFixtureBytes))!;
      final cache = ReaderIllustrationCache(request: (_) async => bytes);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderIllustrationGallery(
            urls: const [
              'https://images.example.invalid/a.png',
              'https://images.example.invalid/b.png',
            ],
            initialUrl: 'https://images.example.invalid/a.png',
            cache: cache,
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pumpAndSettle();
      }
      final viewer = find.byType(InteractiveViewer).first;
      final pages = tester
          .widget<PageView>(find.byKey(const ValueKey('book-image-canvas')))
          .controller!;
      final gesture = await tester.startGesture(tester.getCenter(viewer));
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 30));
      await gesture.moveBy(const Offset(-160, 0));
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        pages.page,
        greaterThan(.2),
        reason: 'the drag passed the turn threshold',
      );
      expect(calls, isEmpty);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(pages.page, 0);
      expect(find.text('IMAGE / 1 OF 2'), findsOneWidget);
      expect(calls, isEmpty);
      nextInteraction();
      await tester.drag(viewer, const Offset(-280, 0));
      await tester.pumpAndSettle();
      expect(pages.page, 1);
      expect(calls, ['pageTurn']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'illustration opening, zooming and accepted gallery swipe respond',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = (await tester.runAsync(coverFixtureBytes))!;
      final cache = ReaderIllustrationCache(request: (_) async => bytes);
      const urls = [
        'https://images.example.invalid/a.png',
        'https://images.example.invalid/b.png',
      ];
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderIllustration(
              url: urls.first,
              cache: cache,
              onOpen: () => opened++,
            ),
          ),
        ),
      );
      Future<void> imagesReady() async {
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pumpAndSettle();
        }
      }

      await imagesReady();
      expect(calls, isEmpty);
      await tester.tap(find.byType(Image));
      await tester.pump();
      expect(opened, 1);
      expect(calls, ['action']);
      nextInteraction();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderIllustrationGallery(
            urls: urls,
            initialUrl: urls.first,
            cache: cache,
          ),
        ),
      );
      await imagesReady();
      expect(calls, isEmpty);
      final viewer = find.byType(InteractiveViewer).first;
      await tester.drag(viewer, const Offset(-280, 0));
      await tester.pumpAndSettle();
      expect(find.text('IMAGE / 2 OF 2'), findsOneWidget);
      expect(calls, ['pageTurn']);
      nextInteraction();
      final image = find.byType(InteractiveViewer).last;
      await tester.tap(image);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(image);
      await tester.pumpAndSettle();
      expect(calls, ['action']);
      expect(
        tester
            .widget<InteractiveViewer>(image)
            .transformationController!
            .value
            .entry(0, 0),
        2,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
