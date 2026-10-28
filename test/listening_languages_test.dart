import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/listening/cache.dart';
import 'package:wenku8_flutter/listening/controller.dart';
import 'package:wenku8_flutter/listening/edge_tts.dart';
import 'package:wenku8_flutter/listening/languages.dart';
import 'package:wenku8_flutter/listening/models.dart';
import 'package:wenku8_flutter/listening/store.dart';
import 'package:wenku8_flutter/listening/widgets.dart';
import 'package:wenku8_flutter/local_books.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_rich_content.dart';

import 'support/epub_bilingual_fixture.dart';
import 'support/listening_fixture.dart';
import 'support/visual_review.dart';

const japaneseVoice = SpeechVoice(
  id: 'ja-JP-NanamiNeural',
  label: '七海 · 日文女声',
  source: ListeningSource.edge,
  locale: 'ja-JP',
);
const japaneseMale = SpeechVoice(
  id: 'ja-JP-KeitaNeural',
  label: '圭太 · 日文男声',
  source: ListeningSource.edge,
  locale: 'ja-JP',
);
const systemChinese = SpeechVoice(
  id: 'zh-installed',
  label: '中文离线',
  source: ListeningSource.system,
  engine: 'org.example.tts',
  offline: true,
);
const systemJapanese = SpeechVoice(
  id: 'ja-installed',
  label: '日文离线',
  source: ListeningSource.system,
  engine: 'org.example.tts',
  locale: 'ja-JP',
  offline: true,
);

class _InventoryAudio extends FakeSpeechAudio
    implements SpeechLanguageVoiceSource {
  List<SpeechVoice> inventory = [defaultEdgeVoice, japaneseVoice];
  int queries = 0;
  Completer<void>? inventoryGate;
  @override
  Future<List<SpeechVoice>> languageVoices(SpeechVoice preferred) async {
    queries++;
    await inventoryGate?.future;
    return List.of(inventory);
  }
}

Novel bilingualBook() {
  final parsed = parseLocalBook(
    LocalBookInput('双语.epub', bilingualEpubFixture()),
  );
  return demoNovels.first.withChapters([
    NovelChapter('双语正文', parsed.bodies.single),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReviewFonts);
  late ListeningController controller;
  late FakeListeningOutput output;
  late _InventoryAudio audio;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    output = FakeListeningOutput();
    audio = _InventoryAudio();
    controller = ListeningController(
      repository: const DemoNovelRepository(),
      audio: audio,
      store: ListeningStore(await SharedPreferences.getInstance()),
      outputFactory: (_) async => output,
    );
  });
  tearDown(() async => controller.dispose());

  void expectMatchedPreparations() {
    for (var i = 0; i < audio.prepared.length; i++) {
      expect(
        speechLanguageCode(audio.preparedVoices[i].locale),
        audio.prepared[i].language,
      );
    }
  }

  test(
    'automatic matching uses publication tags, source coordinates and actual voice for prefetch/cursor',
    () async {
      final book = bilingualBook();
      final content = await ReaderContent.parse(book.chapters.single.content);
      await controller.start(book, chapter: 0);
      await listeningMicrotasks();
      var state = controller.snapshot.value;
      expect(state.languages, {'zh', 'ja', 'en'});
      expect(state.segments.map((s) => s.paragraph), [0, 1, 2, 3, 4]);
      expect(state.missingLanguages, {'en'});
      expect(state.skippedLanguageSegments, 1);
      expect(audio.queries, 1);
      expect(state.outputVoice.id, defaultEdgeVoice.id);
      expect(audio.preparedVoices.map((v) => v.id), contains(japaneseVoice.id));
      output.complete();
      await listeningMicrotasks();
      state = controller.snapshot.value;
      expect(state.current!.paragraph, 1);
      expect(state.outputVoice.id, japaneseVoice.id);
      expect(
        state.voice.id,
        defaultEdgeVoice.id,
      ); // preferred voice is not overwritten
      expect(state.current!.text, content.paragraphs[1]);
      await controller.seek(const Duration(seconds: 7));
      final saved = controller.savedCursor(book.id)!;
      expect(saved.segmentHash, state.current!.key(japaneseVoice));
      await controller.stop();
      await controller.start(book, chapter: 0, resume: true, autoplay: false);
      expect(controller.snapshot.value.current!.paragraph, 1);
      expect(output.initialPosition.inSeconds, 7);
      expect(controller.snapshot.value.phase, ListeningPhase.paused);
      expectMatchedPreparations();
    },
  );

  test(
    'only one spoken language is per book and independent of displayed text',
    () async {
      final book = bilingualBook();
      final content = await ReaderContent.parse(book.chapters.single.content);
      await controller.setSpokenLanguage(book.id, 'zh-CN');
      await controller.start(book, chapter: 0);
      expect(controller.snapshot.value.segments.map((s) => s.paragraph), [
        0,
        2,
      ]);
      expect(controller.snapshot.value.spokenLanguage, 'zh');
      expect(controller.snapshot.value.missingLanguages, isEmpty);
      expect(audio.prepared.every((s) => s.language == 'zh'), isTrue);
      await controller.pause();
      await controller.setSpokenLanguage(book.id, 'ja');
      expect(controller.snapshot.value.segments.map((s) => s.paragraph), [
        1,
        3,
        4,
      ]);
      expect(controller.snapshot.value.current!.paragraph, 1);
      expect(controller.snapshot.value.phase, ListeningPhase.paused);
      expect(output.playing, isFalse);
      expect(content.order.toList(), [0, 1, 2, 3, 4, 5]);
      expect(controller.spokenLanguage(book.id + 1), isNull);
      final reloaded = ListeningStore(await SharedPreferences.getInstance());
      expect(reloaded.spokenLanguage(book.id), 'ja');
      await controller.setSpokenLanguage(book.id, null);
      expect(controller.snapshot.value.segments.map((s) => s.paragraph), [
        0,
        1,
        2,
        3,
        4,
      ]);
      expect(controller.snapshot.value.phase, ListeningPhase.paused);
      expectMatchedPreparations();
    },
  );

  test(
    'missing models skip every affected language without using the Chinese voice',
    () async {
      audio.inventory = [defaultEdgeVoice];
      await controller.start(bilingualBook(), chapter: 0);
      expect(controller.snapshot.value.segments.map((s) => s.paragraph), [
        0,
        2,
      ]);
      expect(controller.snapshot.value.missingLanguages, {'ja', 'en'});
      expect(controller.snapshot.value.skippedLanguageSegments, 4);
      output.complete();
      await listeningMicrotasks();
      expect(controller.snapshot.value.current!.paragraph, 2);
      expect(audio.prepared.every((s) => s.language == 'zh'), isTrue);
      expect(controller.snapshot.value.skippedSegments, 0);
      expectMatchedPreparations();
    },
  );

  test(
    'each language uses its own saved voice, including prefetch and paused changes',
    () async {
      audio.inventory = [
        defaultEdgeVoice,
        alternateEdgeVoice,
        japaneseVoice,
        japaneseMale,
      ];
      await controller.setLanguageVoice('zh', alternateEdgeVoice);
      await controller.setLanguageVoice('ja', japaneseMale);
      final book = bilingualBook();
      await controller.start(book, chapter: 0);
      await listeningMicrotasks();
      expect(controller.snapshot.value.outputVoice.id, alternateEdgeVoice.id);
      output.complete();
      await listeningMicrotasks();
      expect(controller.snapshot.value.current!.language, 'ja');
      expect(controller.snapshot.value.outputVoice.id, japaneseMale.id);
      await controller.pause();
      await controller.setLanguageVoice('ja', japaneseVoice);
      expect(controller.snapshot.value.outputVoice.id, japaneseVoice.id);
      expect(controller.snapshot.value.phase, ListeningPhase.paused);
      expect(output.playing, isFalse);
      final saved = ListeningStore(
        await SharedPreferences.getInstance(),
      ).languageVoices(defaultEdgeVoice);
      expect(saved['zh']!.id, alternateEdgeVoice.id);
      expect(saved['ja']!.id, japaneseVoice.id);
      await controller.setVoice(systemChinese);
      expect(controller.snapshot.value.voiceOverrides, isEmpty);
      await controller.setVoice(defaultEdgeVoice);
      expect(
        controller.snapshot.value.voiceOverrides['ja']!.id,
        japaneseVoice.id,
      );
      expect(
        controller.snapshot.value.voiceOverrides['zh']!.id,
        alternateEdgeVoice.id,
      );
      expectMatchedPreparations();
    },
  );

  test(
    'an unavailable explicitly selected voice skips the language rather than silently substituting one',
    () async {
      audio.inventory = [defaultEdgeVoice, japaneseVoice];
      await controller.setLanguageVoice('ja', japaneseMale);
      await controller.start(bilingualBook(), chapter: 0);
      expect(controller.snapshot.value.segments.map((part) => part.paragraph), [
        0,
        2,
      ]);
      expect(controller.snapshot.value.missingLanguages, {'ja', 'en'});
      expect(
        audio.preparedVoices.every((voice) => voice.id != japaneseVoice.id),
        isTrue,
      );
      await controller.pause();
      await controller.setLanguageVoice('ja', null);
      expect(
        controller.snapshot.value.segments.any((part) => part.language == 'ja'),
        isTrue,
      );
      expect(
        controller.snapshot.value.voiceOverrides.containsKey('ja'),
        isFalse,
      );
      expect(controller.snapshot.value.phase, ListeningPhase.paused);
    },
  );

  test(
    'per-language voice choices reject another language or provider and do not autoplay',
    () async {
      await expectLater(
        controller.setLanguageVoice('ja', defaultEdgeVoice),
        throwsA(isA<SpeechFailure>()),
      );
      await expectLater(
        controller.setLanguageVoice('ja', systemJapanese),
        throwsA(isA<SpeechFailure>()),
      );
      expect(controller.snapshot.value.voiceOverrides, isEmpty);
      expect(output.plays, 0);
      expect(
        (await controller.voicesForLanguage('ja')).map((voice) => voice.id),
        [japaneseVoice.id],
      );
      expect(audio.prepared, isEmpty);
    },
  );

  test(
    'custom/default voice cache identities include the requested locale',
    () {
      const phrase = SpeechSegment(0, 0, 3, '研究所');
      for (final source in [ListeningSource.system, ListeningSource.custom]) {
        SpeechVoice voice(String locale) => SpeechVoice(
          id: source == ListeningSource.system ? '@default' : 'same-id',
          label: 'fixture',
          source: source,
          engine: 'org.example.tts',
          locale: locale,
        );
        expect(phrase.key(voice('ja-JP')), isNot(phrase.key(voice('zh-CN'))));
      }
    },
  );

  test(
    'no selected language model stops explicitly without synthesizing or scanning later chapters',
    () async {
      audio.inventory = [defaultEdgeVoice];
      final first = bilingualBook();
      final book = first.withChapters([
        ...first.chapters,
        const NovelChapter('不应请求的下一章', '正文。'),
      ]);
      await controller.setSpokenLanguage(book.id, 'ja');
      await controller.start(book, chapter: 0);
      expect(controller.snapshot.value.phase, ListeningPhase.failed);
      expect(controller.snapshot.value.error, contains('日文语音模型'));
      expect(controller.snapshot.value.error, contains('已停止朗读'));
      expect(controller.snapshot.value.chapter, 0);
      expect(controller.snapshot.value.current, isNull);
      expect(controller.snapshot.value.playRequested, isFalse);
      expect(audio.prepared, isEmpty);
      expect(output.plays, 0);
      expect(output.loaded, isEmpty);
    },
  );

  test(
    'system inventory cannot borrow a model from a different engine/provider',
    () async {
      audio.inventory = [
        systemChinese,
        japaneseVoice,
        const SpeechVoice(
          id: 'ja-other',
          label: '其他引擎',
          source: ListeningSource.system,
          engine: 'org.other.tts',
          locale: 'ja-JP',
        ),
      ];
      await controller.setVoice(systemChinese);
      await controller.start(bilingualBook(), chapter: 0);
      expect(controller.snapshot.value.segments.map((s) => s.paragraph), [
        0,
        2,
      ]);
      expect(controller.snapshot.value.missingLanguages, {'ja', 'en'});
      expect(
        audio.preparedVoices.every(
          (voice) => voice.engine == systemChinese.engine,
        ),
        isTrue,
      );
      expectMatchedPreparations();
      await controller.pause();
      audio.inventory = [systemChinese, systemJapanese];
      await controller.refreshVoices(online: false);
      await controller.setSpokenLanguage(bilingualBook().id, 'ja');
      expect(controller.snapshot.value.outputVoice.id, systemJapanese.id);
      expect(controller.snapshot.value.phase, ListeningPhase.paused);
      expectMatchedPreparations();
    },
  );

  test(
    'a runtime missing-data result skips this language, not the three-error recovery path',
    () async {
      audio.errorFor = (part) => part.language == 'ja'
          ? const SpeechFailure(
              '语音数据未安装',
              kind: SpeechFailureKind.missingLanguage,
            )
          : null;
      await controller.start(bilingualBook(), chapter: 0);
      output.complete();
      await listeningMicrotasks();
      expect(controller.snapshot.value.current!.paragraph, 2);
      expect(controller.snapshot.value.phase, ListeningPhase.playing);
      expect(controller.snapshot.value.missingLanguages, {'ja', 'en'});
      expect(controller.snapshot.value.skippedLanguageSegments, 4);
      expect(controller.snapshot.value.skippedSegments, 0);
      final rejected = audio.prepared
          .where((part) => part.language == 'ja')
          .map((part) => part.key(japaneseVoice))
          .toSet();
      expect(
        output.loaded.every((file) => !rejected.any(file.path.contains)),
        isTrue,
      );
      expectMatchedPreparations();
    },
  );

  test(
    'shorter Japanese recovery segments retain language, offsets and resumable effective voice',
    () async {
      final text = '${'これは長い文章です。' * 24}終わりです。';
      final body = ReaderRichBody(
        [text, '这段是中文。'],
        formats: const {
          0: ReaderRichParagraph(language: 'ja', opacity: .4),
          1: ReaderRichParagraph(language: 'zh'),
        },
      ).encode();
      final book = demoNovels.first.withChapters([NovelChapter('长段落', body)]);
      audio.errorFor = (part) => part.text.length > 100
          ? const SpeechFailure('长文本被拒绝', kind: SpeechFailureKind.content)
          : null;
      await controller.start(book, chapter: 0);
      final part = controller.snapshot.value.current!;
      expect(part.language, 'ja');
      expect(part.text.length, lessThanOrEqualTo(84));
      expect(text.substring(part.start, part.end), part.text);
      await controller.seek(const Duration(seconds: 5));
      await controller.stop();
      await controller.start(book, chapter: 0, resume: true, autoplay: false);
      expect(controller.snapshot.value.current!.start, part.start);
      expect(controller.snapshot.value.current!.language, 'ja');
      expect(output.initialPosition.inSeconds, 5);
      expectMatchedPreparations();
    },
  );

  test(
    'switching language while inventory is pending cancels the old plan',
    () async {
      final gate = Completer<void>();
      audio.inventoryGate = gate;
      final book = bilingualBook();
      final starting = controller.start(book, chapter: 0);
      await listeningMicrotasks();
      expect(controller.snapshot.value.phase, ListeningPhase.preparing);
      await controller.setSpokenLanguage(book.id, 'zh');
      await starting;
      gate.complete();
      await listeningMicrotasks();
      expect(controller.snapshot.value.phase, ListeningPhase.playing);
      expect(controller.snapshot.value.segments.map((s) => s.paragraph), [
        0,
        2,
      ]);
      expect(audio.prepared.every((s) => s.language == 'zh'), isTrue);
      expectMatchedPreparations();
    },
  );

  test(
    'metadata beats script inference; unmarked Han preserves the selected language',
    () {
      expect(speechParagraphLanguage('zh-CN', 'カタカナ', 'ja-JP'), 'zh');
      expect(speechParagraphLanguage('', 'これは日本語です。', 'zh-CN'), 'ja');
      expect(speechParagraphLanguage('', '한국어입니다', 'zh-CN'), 'ko');
      expect(speechParagraphLanguage('', '研究所', 'ja-JP'), 'ja');
      expect(speechParagraphLanguage('', '研究所', 'zh-CN'), 'zh');
      expect(speechLanguageCode('jpn-JP'), 'ja');
      expect(speechLanguageCode('chi'), 'zh');
      expect(speechLanguageCode('<script>'), isEmpty);
    },
  );

  test(
    'Edge voice validation accepts supported locales without admitting mismatched IDs or SSML injection',
    () {
      expect(EdgeSpeechClient.validVoice(japaneseVoice.id, 'ja-JP'), isTrue);
      expect(EdgeSpeechClient.validVoice('en-US-AriaNeural', 'en-US'), isTrue);
      expect(EdgeSpeechClient.validVoice(defaultEdgeVoice.id, 'zh-CN'), isTrue);
      expect(EdgeSpeechClient.validVoice(japaneseVoice.id, 'zh-CN'), isFalse);
      expect(
        EdgeSpeechClient.validVoice('ja-JP-NanamiNeural"/>', 'ja-JP'),
        isFalse,
      );
    },
  );

  test(
    'native language inventory is selected-engine scoped and excludes missing models',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'speech-language-inventory-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final cache = SpeechAudioCache(dir, EdgeSpeechClient());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SpeechAudioCache.system, (call) async {
            expect(call.method, 'voices');
            expect((call.arguments as Map)['engine'], 'org.example.tts');
            return [
              {'id': 'zh', 'locale': 'zho-CN', 'networkRequired': false},
              {'id': 'ja', 'locale': 'ja-JP', 'networkRequired': false},
              {'id': 'en', 'locale': 'en-US', 'networkRequired': true},
              {
                'id': 'missing',
                'locale': 'ja-JP',
                'features': ['notInstalled'],
              },
            ];
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SpeechAudioCache.system, null),
      );
      final found = await cache.languageVoices(systemChinese);
      expect(found.map((v) => v.id), ['zh', 'ja', 'en']);
      expect(found.map((v) => speechLanguageCode(v.locale)), [
        'zh',
        'ja',
        'en',
      ]);
      expect(found.every((v) => v.engine == systemChinese.engine), isTrue);
    },
  );

  test(
    'custom providers only speak their configured language without probing another service',
    () async {
      const custom = SpeechVoice(
        id: 'my-japanese',
        label: '自定义日文',
        source: ListeningSource.custom,
        engine: 'configured-provider',
        locale: 'ja-JP',
      );
      await controller.setVoice(custom);
      await controller.start(bilingualBook(), chapter: 0);
      expect(controller.snapshot.value.segments.map((part) => part.paragraph), [
        1,
        3,
        4,
      ]);
      expect(controller.snapshot.value.missingLanguages, {'zh', 'en'});
      expect(audio.queries, 0);
      expect(
        audio.preparedVoices.every((voice) => voice.id == custom.id),
        isTrue,
      );
      expectMatchedPreparations();
    },
  );

  test(
    'cache blocks wrong-language synthesis even if a caller bypasses the listening plan',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'speech-language-guard-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final cache = SpeechAudioCache(dir, EdgeSpeechClient());
      await expectLater(
        cache.prepare(
          const SpeechSegment(0, 0, 5, '日本語です', language: 'ja'),
          defaultEdgeVoice,
          SpeechCancellation(),
        ),
        throwsA(
          isA<SpeechFailure>().having(
            (e) => e.kind,
            'kind',
            SpeechFailureKind.missingLanguage,
          ),
        ),
      );
      expect(await dir.list().isEmpty, isTrue);
    },
  );

  test(
    'tagged native requests carry their locale and native missing data maps to the skip contract',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'speech-language-channel-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final cache = SpeechAudioCache(dir, EdgeSpeechClient());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SpeechAudioCache.system, (call) async {
            expect(call.method, 'synthesize');
            final args = call.arguments as Map;
            expect(args['voice'], systemJapanese.id);
            expect(args['locale'], 'ja-JP');
            throw PlatformException(
              code: 'TTS_LANGUAGE_UNAVAILABLE',
              message: '缺少模型',
            );
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SpeechAudioCache.system, null),
      );
      await expectLater(
        cache.prepare(
          const SpeechSegment(0, 0, 5, '日本語です', language: 'ja'),
          systemJapanese,
          SpeechCancellation(),
        ),
        throwsA(
          isA<SpeechFailure>().having(
            (e) => e.kind,
            'kind',
            SpeechFailureKind.missingLanguage,
          ),
        ),
      );
      expect(await dir.list().isEmpty, isTrue);
    },
  );

  testWidgets(
    'listening language choices render and persist before playback without changing visual language',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: novelTheme(Brightness.light),
            home: Scaffold(
              body: SafeArea(
                child: ListeningPanel(
                  controller: controller,
                  novel: bilingualBook(),
                  chapter: 0,
                  embedded: true,
                  languages: const {'zh', 'ja'},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chinese = find.byKey(const ValueKey('listening-language-only-zh'));
      await tester.ensureVisible(chinese);
      await tester.tap(chinese);
      await tester.runAsync(listeningMicrotasks);
      await tester.pumpAndSettle();
      expect(controller.spokenLanguage(bilingualBook().id), 'zh');
      expect(find.text('仅朗读日文'), findsOneWidget);
      expect(find.textContaining('没有对应语言的语音模型就跳过'), findsOneWidget);
      expect(controller.snapshot.value.novel, isNull);
      await tester.ensureVisible(find.text('本书朗读语言'));
      await tester.pumpAndSettle();
      await captureReview(tester, boundary, 'bilingual-listening-languages');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'each language opens a matching voice picker and restores automatic selection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      audio.inventory = [
        defaultEdgeVoice,
        alternateEdgeVoice,
        japaneseVoice,
        japaneseMale,
      ];
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: novelTheme(Brightness.light),
            home: Scaffold(
              body: SafeArea(
                child: ListeningPanel(
                  controller: controller,
                  novel: bilingualBook(),
                  chapter: 0,
                  embedded: true,
                  languages: const {'zh', 'ja'},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('listening-language-voice-ja'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('日文音色'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey('listening-language-option-${defaultEdgeVoice.id}'),
        ),
        findsNothing,
      );
      await captureReview(tester, boundary, 'bilingual-japanese-voice-picker');
      await tester.tap(
        find.byKey(ValueKey('listening-language-option-${japaneseMale.id}')),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(listeningMicrotasks);
      await tester.pumpAndSettle();
      expect(
        controller.snapshot.value.voiceOverrides['ja']!.id,
        japaneseMale.id,
      );
      expect(
        controller.snapshot.value.voiceOverrides.containsKey('zh'),
        isFalse,
      );
      expect(controller.snapshot.value.novel, isNull);
      await tester.ensureVisible(find.text('分语言音色'));
      await tester.pumpAndSettle();
      await captureReview(tester, boundary, 'bilingual-per-language-voices');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('listening-language-voice-default')),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(listeningMicrotasks);
      await tester.pumpAndSettle();
      expect(
        controller.snapshot.value.voiceOverrides.containsKey('ja'),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'provided bilingual EPUB keeps the reported Chinese/Japanese pair out of the wrong speech plan',
    () async {
      final path = const String.fromEnvironment('BILINGUAL_EPUB');
      final parsed = parseLocalBook(
        LocalBookInput('provided.epub', await File(path).readAsBytes()),
      );
      final source = parsed.bodies.firstWhere((body) => body.contains('肩膀上的伤'));
      final content = await ReaderContent.parse(source);
      final chinese = content.paragraphs.indexWhere(
        (text) => text.contains('肩膀上的伤'),
      );
      final japanese = content.paragraphs.indexWhere(
        (text) => text.contains('肩に負った傷'),
      );
      expect(chinese, greaterThanOrEqualTo(0));
      expect(japanese, greaterThanOrEqualTo(0));
      expect(content.formats[chinese]!.language, 'zh');
      expect(content.formats[japanese]!.language, 'ja');
      final book = demoNovels.first.withChapters([
        NovelChapter('实际双语正文', source),
      ]);
      await controller.setSpokenLanguage(book.id, 'ja');
      await controller.start(book, chapter: 0);
      expect(
        controller.snapshot.value.segments.any(
          (part) => part.paragraph == chinese,
        ),
        isFalse,
      );
      expect(
        controller.snapshot.value.segments.any(
          (part) => part.paragraph == japanese,
        ),
        isTrue,
      );
      expect(
        controller.snapshot.value.segments.every(
          (part) => part.language == 'ja',
        ),
        isTrue,
      );
      expectMatchedPreparations();
    },
    skip: const String.fromEnvironment('BILINGUAL_EPUB').isEmpty,
  );
}
