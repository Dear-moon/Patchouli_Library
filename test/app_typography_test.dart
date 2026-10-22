import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'support/serif_fixture.dart';
import 'support/font_store_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_typography.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_backup.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/listening/models.dart';
import 'package:wenku8_flutter/listening/store.dart';
import 'package:wenku8_flutter/main.dart';
import 'package:wenku8_flutter/reader_tools.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/pages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareSerifFixture);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'typeface persists, validates in backups and identifies reading layout',
    () async {
      final state = LibraryState(
        await SharedPreferences.getInstance(),
        fonts: InstalledSerifFixture(),
      );
      addTearDown(state.dispose);
      expect(state.appTypeface, AppTypeface.system);
      await state.setAppTypeface(AppTypeface.sourceHanSerif);
      final reloaded = LibraryState(
        await SharedPreferences.getInstance(),
        fonts: InstalledSerifFixture(),
      );
      addTearDown(reloaded.dispose);
      expect(reloaded.appTypeface, AppTypeface.sourceHanSerif);
      await state.savePosition(
        novel: demoNovels.first,
        chapter: 0,
        offset: 100,
        maximum: 500,
        width: 390,
      );
      final position = state.positionFor(demoNovels.first.id)!;
      expect(position.typeface, 'sourceHanSerif');
      expect(
        ReadingPosition.fromJson(position.toJson()).typeface,
        'sourceHanSerif',
      );
      final legacy = position.toJson()..remove('typeface');
      expect(ReadingPosition.fromJson(legacy).typeface, 'system');
      final records = <String, Object>{
        'appTypeface': 'sourceHanSerif',
        'reading_position_1': jsonEncode(position.toJson()),
      };
      final backup = await LibraryBackup.fromRecords(records);
      expect(
        (await LibraryBackup.parse(await backup.encode())).records,
        records,
      );
      await expectLater(
        LibraryBackup.fromRecords({'appTypeface': 'unknown'}),
        throwsFormatException,
      );
      await expectLater(
        LibraryBackup.fromRecords({
          'reading_position_1': jsonEncode({
            ...position.toJson(),
            'typeface': 'unknown',
          }),
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'installed system voice selections persist without synthesizing',
    () async {
      final voice = SpeechVoice(
        id: 'local',
        label: 'local',
        source: ListeningSource.system,
        engine: 'org.example.tts',
        offline: true,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('listening.voice.v1', jsonEncode(voice.toJson()));
      final store = ListeningStore(prefs);
      expect(store.voice.toJson(), voice.toJson());
      await store.saveVoice(voice);
      expect(ListeningStore(prefs).voice.toJson(), voice.toJson());
    },
  );
  test('font fixture is valid but only its license is bundled', () async {
    final bytes = await loadSerifFixture();
    expect(ascii.decode(bytes.buffer.asUint8List(0, 4)), 'OTTO');
    final tables = [
      for (var i = 0; i < bytes.getUint16(4); i++)
        ascii.decode(bytes.buffer.asUint8List(12 + i * 16, 4)),
    ];
    expect(tables, contains('fvar'));
    final assets = (await AssetManifest.loadFromAssetBundle(
      rootBundle,
    )).listAssets();
    expect(
      assets.where(
        (path) =>
            RegExp(r'\.(otf|ttf)$').hasMatch(path) &&
            path.startsWith('assets/fonts/'),
      ),
      isEmpty,
    );
    expect(
      await rootBundle.loadString('assets/fonts/OFL-SourceHanSerif.txt'),
      contains('SIL OPEN FONT LICENSE'),
    );
    expect(
      await rootBundle.loadString('assets/licenses/edge-tts.txt'),
      contains('LESSER GENERAL PUBLIC LICENSE'),
    );
  });
  testWidgets(
    'switching the global typeface preserves the measured reader paragraph',
    (tester) async {
      await (FontLoader(
        'SourceHanSerifCN',
      )..addFont(loadSerifFixture())).load();
      final state = LibraryState(
        await SharedPreferences.getInstance(),
        fonts: InstalledSerifFixture(),
      );
      final book = demoNovels.first.withChapters([
        NovelChapter(
          '字体测试',
          List.generate(
            100,
            (i) => '第 $i 段：${'阅读位置与字体变化一起保持。' * 6}',
          ).join('\n\n'),
        ),
      ]);
      await tester.pumpWidget(
        NovelApp(state: state, repository: const DemoNovelRepository()),
      );
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(HomeShell))).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderPage(
            novel: book,
            state: state,
            repository: const DemoNovelRepository(),
            initialChapter: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('reader-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scroll.position.jumpTo(2400);
      await tester.pumpAndSettle();
      ParagraphPosition anchor() => tester
          .widget<ReaderParagraph>(find.byType(ReaderParagraph).first)
          .registry
          .capture(scroll.position.pixels + FrostedHeader.toolbarHeight + 12)!;
      final before = anchor();
      await state.setAppTypeface(AppTypeface.sourceHanSerif);
      await tester.pumpAndSettle();
      expect(anchor().index, before.index);
      expect(anchor().fraction, closeTo(before.fraction, .02));
      expect(state.positionFor(book.id)!.typeface, 'sourceHanSerif');
      await state.setAppTypeface(AppTypeface.system);
      await tester.pumpAndSettle();
      expect(anchor().index, before.index);
      expect(anchor().fraction, closeTo(before.fraction, .02));
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
  testWidgets(
    'global font follows persisted switch and returns to the system',
    (tester) async {
      final state = LibraryState(
        await SharedPreferences.getInstance(),
        fonts: InstalledSerifFixture(),
      );
      await tester.pumpWidget(
        NovelApp(state: state, repository: const DemoNovelRepository()),
      );
      await tester.pumpAndSettle();
      final before = Theme.of(
        tester.element(find.text('发现').first),
      ).textTheme.bodyMedium!.fontFamily;
      await state.setAppTypeface(AppTypeface.sourceHanSerif);
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.text('发现').first),
        ).textTheme.bodyMedium!.fontFamily,
        'SourceHanSerifCN',
      );
      await state.setAppTypeface(AppTypeface.system);
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.text('发现').first),
        ).textTheme.bodyMedium!.fontFamily,
        before,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
  for (final cancel in [false, true]) {
    testWidgets(
      '${cancel ? 'cancelled' : 'quick'} typography drag commits the last preview exactly once',
      (tester) async {
        final committed = <double>[], previews = <double>[], phases = <bool>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReaderValueSlider(
                sliderKey: const ValueKey('slider'),
                label: '字号',
                value: 19,
                min: 15,
                max: 27,
                format: (v) => '$v',
                onCommitted: committed.add,
                onPreview: previews.add,
                onInteractionChanged: phases.add,
              ),
            ),
          ),
        );
        final rect = tester.getRect(find.byKey(const ValueKey('slider')));
        final gesture = await tester.startGesture(
          Offset(rect.left + rect.width / 3, rect.center.dy),
        );
        await gesture.moveBy(const Offset(25, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(80, 0));
        await tester.pump();
        expect(previews, isNotEmpty);
        expect(committed, isEmpty);
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pump();
        expect(committed, [previews.last]);
        expect(phases, [true, false]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
