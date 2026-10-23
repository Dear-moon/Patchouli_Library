import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_search_field.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/archive_wave.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/illustration_layout_page.dart';
import 'package:wenku8_flutter/reader_illustrations.dart';
import 'package:wenku8_flutter/local_platform.dart';
import 'package:wenku8_flutter/palette_image.dart';
import 'package:wenku8_flutter/palette_settings_page.dart';
import 'package:wenku8_flutter/performance_preferences.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/review_content.dart';

import 'app_palette_test.dart' show twoColorImage;
import 'support/cover_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  var clock = Duration.zero;
  setUp(() {
    clock = Duration.zero;
    calls.clear();
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
  void advance() => clock += const Duration(milliseconds: 500);
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets(
    'search touch, submit and clear respond; restored input stays quiet',
    (tester) async {
      final text = TextEditingController(text: '初始搜索');
      final focus = FocusNode();
      addTearDown(text.dispose);
      addTearDown(focus.dispose);
      final submitted = <String>[];
      await tester.pumpWidget(
        app(
          AppSearchField(
            inputKey: const ValueKey('haptic-search'),
            controller: text,
            focusNode: focus,
            hint: '搜索',
            onSubmitted: submitted.add,
          ),
        ),
      );
      text.text = '恢复查询';
      focus.requestFocus();
      await tester.pump();
      expect(calls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('haptic-search')));
      await tester.pump();
      expect(calls, ['selection']);
      advance();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(submitted, ['恢复查询']);
      expect(calls, ['selection', 'action']);
      advance();
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pump();
      expect(text.text, isEmpty);
      expect(calls, ['selection', 'action', 'action']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  List<Novel> books() => [
    for (var i = 0; i < 3; i++)
      Novel(
        id: 960000 + i,
        title: '书架触感 $i',
        author: '作者',
        genre: '轻小说',
        summary: '',
        colors: const [Colors.black, Colors.grey],
      ),
  ];

  testWidgets('3D shelf cover and caption each open with one committed pulse', (
    tester,
  ) async {
    phone(tester);
    var opens = 0;
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: ArchiveFileCarousel(
            books: books(),
            reduceMotion: true,
            onOpen: (_, _) => opens++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('archive-shelf-open')),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(calls, ['action']);
    advance();
    final scene = tester.renderObject<ArchiveShelfSceneRender>(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ShelfRow'),
    );
    final cover = find.descendant(
      of: find.byKey(ValueKey('archive-cover-${scene.debugCentreSlot}')),
      matching: find.byType(NovelCover),
    );
    await tester.tapAt(tester.getCenter(cover));
    await tester.pumpAndSettle();
    expect(opens, 2);
    expect(calls, ['action', 'action']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'flat shelf has a swipe detent and tap feedback, not setup feedback',
    (tester) async {
      phone(tester);
      var opens = 0;
      await tester.pumpWidget(
        app(
          PerformanceScope(
            preferences: const PerformancePreferences(enabled: true),
            child: ArchiveFileCarousel(
              books: books(),
              onOpen: (_, _) => opens++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.drag(find.byType(PageView), const Offset(-240, 0));
      await tester.pumpAndSettle();
      expect(calls, ['shelfStep']);
      expect(opens, 0);
      advance();
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(calls, ['shelfStep', 'action']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'inline and extracted comment links use the visible route for feedback',
    (tester) async {
      phone(tester);
      final opened = <Uri>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        app(
          ReviewContent(
            content: '<a href="https://example.com/book">打开链接</a>',
            byline: '作者',
            reduceMotion: true,
            onOpenLink: (uri) async => opened.add(uri),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The text's link recognizer is the same committed tap callback used by
      // SelectableText, independent of the selection overlay's platform layout.
      final span = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!;
      final link = span.children!.whereType<TextSpan>().single;
      (link.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pump();
      expect(opened.length, 1);
      expect(calls, ['action']);
      advance();
      await tester.tap(find.byKey(const ValueKey('review-extract-links')));
      await tester.pumpAndSettle();
      expect(calls, ['action', 'action']);
      advance();
      await tester.tap(find.byKey(const ValueKey('review-open-link-0')));
      await tester.pumpAndSettle();
      expect(opened.length, 2);
      expect(calls, ['action', 'action', 'action']);
      advance();
      await tester.tap(find.byKey(const ValueKey('review-copy-link-0')));
      await tester.pump();
      expect(calls, ['action', 'action', 'action', 'success']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'image sampling confirms selection and drag cells, never a cancelled down',
    (tester) async {
      phone(tester);
      final image = (await tester.runAsync(
        () async => PaletteImage.decode(await twoColorImage()),
      ))!;
      await tester.pumpWidget(
        MaterialApp(home: PaletteImagePickerPage(image: image)),
      );
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('palette-image-sampling'));
      final rect = tester.getRect(picker);
      final valid = Offset(rect.left + rect.width * .25, rect.center.dy);
      final cancelled = await tester.startGesture(valid);
      await tester.pump();
      expect(calls, isEmpty);
      await cancelled.cancel();
      await tester.pump();
      expect(calls, isEmpty);
      await tester.tapAt(valid);
      await tester.pump();
      expect(calls, ['selection']);
      advance();
      final drag = await tester.startGesture(valid);
      await drag.moveBy(const Offset(45, 0));
      await tester.pump();
      expect(calls, ['selection', 'detent']);
      advance();
      await drag.moveBy(const Offset(1, 0));
      await tester.pump();
      expect(calls, ['selection', 'detent']);
      await drag.moveBy(const Offset(45, 0));
      await tester.pump();
      expect(calls, ['selection', 'detent', 'detent']);
      advance();
      await drag.up();
      await tester.pumpAndSettle();
      expect(calls, ['selection', 'detent', 'detent']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'edge brightness emits changed steps and boundary once; settings load stays quiet',
    (tester) async {
      phone(tester);
      SharedPreferences.setMockInitialValues({});
      final library = await LibraryState.load();
      addTearDown(library.dispose);
      await library.setReaderPreferences(
        const ReaderPreferences(edgeBrightness: true, brightness: .5),
        persist: false,
      );
      final changes = <ReaderPreferences>[];
      await tester.pumpWidget(
        app(
          SizedBox.expand(
            child: ReaderBrightnessGesture(
              state: library,
              onChanged: (value, _) => changes.add(value),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(calls, isEmpty);
      final rail = find.byKey(const ValueKey('reader-edge-brightness'));
      final gesture = await tester.startGesture(tester.getCenter(rail));
      await gesture.moveBy(const Offset(0, -25));
      await tester.pump();
      expect(calls, ['detent']);
      advance();
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      expect(calls, ['detent', 'detent']);
      expect(changes.last.brightness, greaterThan(.5));
      advance();
      await gesture.moveBy(const Offset(0, -800));
      await tester.pump();
      expect(calls, ['detent', 'detent', 'boundary']);
      advance();
      await gesture.moveBy(const Offset(0, -50));
      await gesture.up();
      await tester.pump();
      expect(calls, ['detent', 'detent', 'boundary']);
      advance();
      calls.clear();
      final fine = await tester.startGesture(tester.getCenter(rail));
      await fine.moveBy(const Offset(0, -20));
      await tester.pump();
      expect(calls, isEmpty);
      await fine.up();
      await tester.pump();
      expect(calls, ['selection']);
      advance();
      calls.clear();
      final cancelled = await tester.startGesture(tester.getCenter(rail));
      await cancelled.moveBy(const Offset(0, -20));
      await tester.pump();
      await cancelled.cancel();
      await tester.pump();
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'illustration placement selection confirms without leaking into save',
    (tester) async {
      phone(tester);
      SharedPreferences.setMockInitialValues({'reduceMotion': true});
      final library = await LibraryState.load();
      addTearDown(library.dispose);
      final bytes = (await tester.runAsync(coverFixtureBytes))!;
      ReaderIllustrationCache.shared.offlineReader = (_) async => bytes;
      addTearDown(() {
        ReaderIllustrationCache.shared.offlineReader = null;
        ReaderIllustrationCache.shared.clearMemory();
      });
      const book = Novel(
        id: 960003,
        title: '插图选择',
        author: '作者',
        genre: '',
        summary: '',
        colors: [Colors.grey, Colors.white],
        chapters: [
          NovelChapter('正文', '原有段落', id: 1, volumeId: 1, volumeTitle: '第一卷'),
          NovelChapter(
            '插图',
            '<!--image-->https://images.example.invalid/pictures/1/haptic.jpg<!--image-->',
            id: 2,
            volumeId: 1,
            volumeTitle: '第一卷',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: IllustrationLayoutPage(
            novel: book,
            chapter: 0,
            state: library,
            repository: const DemoNovelRepository(),
            paragraph: 0,
            source: await ReaderContent.parse('原有段落'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      final choice = find.byKey(const ValueKey('illustration-choice-0'));
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: choice, matching: find.byType(InkWell)),
      );
      await tester.pump();
      expect(calls, ['selection']);
      expect(library.illustrationsFor(book.id), isEmpty);
      expect(
        tester
            .widget<GlassTextButton>(
              find.byKey(const ValueKey('illustration-confirm-placement')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
