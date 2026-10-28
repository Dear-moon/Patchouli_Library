import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../catalog.dart';
import '../offline_repository.dart';
import '../reader_content.dart';
import '../reader_languages.dart';
import 'cache.dart';
import 'languages.dart';
import 'models.dart';
import 'store.dart';
import 'custom_tts.dart';

abstract interface class ListeningAudioOutput {
  Stream<Duration> get positions;
  Stream<void> get completions;
  Future<Duration?> load(File file, Duration position);
  Future<void> play();
  Future<void> suspend();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}

class ListeningProgress {
  const ListeningProgress({
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });
  final Duration position, duration;
}

/// Chapter content progress is independent of clip duration/decoder resets.
/// Unknown future audio lengths are not presented as a made-up total time.
class ListeningChapterProgress {
  const ListeningChapterProgress({
    this.fraction = 0,
    this.position = Duration.zero,
  });
  final double fraction;
  final Duration position;
  @override
  bool operator ==(Object other) =>
      other is ListeningChapterProgress &&
      fraction == other.fraction &&
      position == other.position;
  @override
  int get hashCode => Object.hash(fraction, position);
}

class ListeningSnapshot {
  const ListeningSnapshot({
    this.novel,
    this.chapter = 0,
    this.segment = 0,
    this.segments = const [],
    this.phase = ListeningPhase.stopped,
    this.voice = defaultEdgeVoice,
    this.currentVoice,
    this.voiceOverrides = const {},
    this.spokenLanguage,
    this.languages = const {},
    this.missingLanguages = const {},
    this.skippedLanguageSegments = 0,
    this.speed = 1,
    this.follow = true,
    this.playRequested = false,
    this.sleepUntil,
    this.sleepAfterChapter = false,
    this.skippedSegments = 0,
    this.error,
  });
  final Novel? novel;
  final int chapter, segment;
  final int skippedSegments;
  final List<SpeechSegment> segments;
  final ListeningPhase phase;
  final SpeechVoice voice;
  final SpeechVoice? currentVoice;
  final Map<String, SpeechVoice> voiceOverrides;
  SpeechVoice get outputVoice => currentVoice ?? voice;
  final String? spokenLanguage;
  final Set<String> languages, missingLanguages;
  final int skippedLanguageSegments;
  final double speed;
  final bool follow, sleepAfterChapter, playRequested;
  final DateTime? sleepUntil;
  final String? error;
  SpeechSegment? get current =>
      segment >= 0 && segment < segments.length ? segments[segment] : null;
  bool get playing => phase == ListeningPhase.playing;
  bool get requestingPlayback =>
      playRequested && (playing || phase == ListeningPhase.preparing);
  bool get active =>
      phase != ListeningPhase.stopped && phase != ListeningPhase.completed;
  String get chapterTitle =>
      novel != null && chapter >= 0 && chapter < novel!.chapters.length
      ? novel!.chapters[chapter].title
      : '';
}

class ListeningVoiceCatalog {
  const ListeningVoiceCatalog({
    this.online = const [defaultEdgeVoice, alternateEdgeVoice],
    this.offline = const [],
    this.loading = false,
    this.checked = false,
    this.message,
    this.messageSource,
  });
  final List<SpeechVoice> online, offline;
  final bool loading, checked;
  final String? message;
  final ListeningSource? messageSource;
}

/// One listening session for the app. Audio positions never notify the app,
/// reader layout, bookshelf, glass compositor or LibraryState.
class ListeningController {
  ListeningController({
    required this.repository,
    required this.audio,
    required this.store,
    required this.outputFactory,
    this.customSpeech,
    this.preparationTimeout = const Duration(seconds: 35),
    this.decoderTimeout = const Duration(seconds: 10),
  }) {
    _voiceOverrides = store.languageVoices(store.voice);
    snapshot.value = ListeningSnapshot(
      voice: store.voice,
      voiceOverrides: _voiceOverrides,
      speed: store.speed,
      follow: store.follow,
    );
  }
  final NovelRepository repository;
  final SpeechAudioSource audio;
  final ListeningStore store;
  final CustomSpeechSettings? customSpeech;
  final Duration preparationTimeout, decoderTimeout;
  final Future<ListeningAudioOutput> Function(ListeningController controller)
  outputFactory;
  final snapshot = ValueNotifier(const ListeningSnapshot());
  final progress = ValueNotifier(const ListeningProgress());
  final chapterProgress = ValueNotifier(const ListeningChapterProgress());
  final voices = ValueNotifier(const ListeningVoiceCatalog());
  ListeningAudioOutput? _output;
  Future<ListeningAudioOutput>? _opening;
  Future<void> _commands = Future.value();
  SpeechCancellation _cancel = SpeechCancellation();
  StreamSubscription<Duration>? _positions;
  StreamSubscription<void>? _completions;
  Timer? _sleep;
  Future<void>? _voiceRefresh;
  Future<void>? _disposing;
  File? _currentFile;
  final _preparedAhead =
      <(SpeechSegment, ListeningSource, String?, String, String), File>{};
  Object? _prefetchRun;
  static const _lookAhead = 3;
  ReaderContent _chapterContent = const ReaderContent([]);
  List<SpeechSegment> _rawSegments = const [];
  Map<String, SpeechVoice> _languageVoices = const {};
  Map<String, SpeechVoice> _voiceOverrides = const {};
  (ListeningSource, String?, String, String)? _inventoryKey;
  Future<List<SpeechVoice>>? _inventory;
  final _loadingFiles = <String, int>{};
  int _generation = 0;
  int _consecutiveFailures = 0;
  int _playEpoch = 0;
  bool _desiredPlaying = false, _loading = false, _disposed = false;
  bool _atSegmentEnd = false;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  List<SpeechSegment> _timelineSegments = const [];
  final _clipDurations = <SpeechSegment, Duration>{};
  List<int> _textOffsets = const [0];
  List<Duration> _timeOffsets = const [Duration.zero];
  Object? _timelineKey;
  (SpeechSegment, ListeningSource, String?, String, String) _audioIdentity(
    SpeechSegment segment,
    SpeechVoice voice,
  ) => (segment, voice.source, voice.engine, voice.id, voice.locale);

  void _releaseFile(File? file) {
    if (file != null &&
        file.path != _currentFile?.path &&
        !_preparedAhead.values.any((ready) => ready.path == file.path) &&
        !_loadingFiles.containsKey(file.path)) {
      audio.unprotect(file);
    }
  }

  void _retainLoad(File file) {
    _loadingFiles.update(file.path, (count) => count + 1, ifAbsent: () => 1);
    audio.protect(file);
  }

  void _releaseLoad(File? file) {
    if (file == null) return;
    final count = _loadingFiles[file.path] ?? 0;
    if (count <= 1) {
      _loadingFiles.remove(file.path);
    } else {
      _loadingFiles[file.path] = count - 1;
    }
    _releaseFile(file);
  }

  void _dropPrefetch() {
    _prefetchRun = null;
    final previous = _preparedAhead.values.toList();
    _preparedAhead.clear();
    for (final file in previous) {
      _releaseFile(file);
    }
  }

  void _prunePrefetch() {
    final state = snapshot.value;
    final wanted =
        <(SpeechSegment, ListeningSource, String?, String, String)>{};
    for (
      var i = state.segment + 1;
      i < state.segments.length && i <= state.segment + _lookAhead;
      i++
    ) {
      final segment = state.segments[i];
      final voice = _languageVoices[segment.language];
      if (voice != null) wanted.add(_audioIdentity(segment, voice));
    }
    for (final key
        in _preparedAhead.keys.where((key) => !wanted.contains(key)).toList()) {
      final file = _preparedAhead.remove(key);
      _releaseFile(file);
    }
  }

  void _updateTimeline() {
    final state = snapshot.value;
    final key = (
      state.novel?.id,
      state.chapter,
      state.voice.engine,
      state.voice.id,
      state.spokenLanguage,
      state.voiceOverrides,
    );
    if (_timelineKey != key) {
      _timelineKey = key;
      _clipDurations.clear();
      _timelineSegments = const [];
    }
    if (!identical(_timelineSegments, state.segments)) {
      _timelineSegments = state.segments;
      _textOffsets = [0];
      for (final part in state.segments) {
        _textOffsets.add(
          _textOffsets.last + part.text.length.clamp(1, 1000000),
        );
      }
      _updateTimeOffsets();
    }
    final index = state.segment;
    if (index < 0 || index >= state.segments.length) {
      chapterProgress.value = const ListeningChapterProgress();
      return;
    }
    final clip = progress.value;
    final fraction = _loading || clip.duration <= Duration.zero
        ? 0.0
        : (clip.position.inMicroseconds / clip.duration.inMicroseconds).clamp(
            0.0,
            1.0,
          );
    final weight = _textOffsets[index + 1] - _textOffsets[index];
    chapterProgress.value = ListeningChapterProgress(
      fraction: state.phase == ListeningPhase.completed
          ? 1
          : ((_textOffsets[index] + weight * fraction) / _textOffsets.last)
                .clamp(0.0, 1.0),
      position:
          _timeOffsets[index] + (_loading ? Duration.zero : clip.position),
    );
  }

  void _updateTimeOffsets() {
    _timeOffsets = [Duration.zero];
    for (final segment in _timelineSegments) {
      _timeOffsets.add(
        _timeOffsets.last + (_clipDurations[segment] ?? Duration.zero),
      );
    }
  }

  void _emit({
    Novel? novel,
    int? chapter,
    int? segment,
    List<SpeechSegment>? segments,
    ListeningPhase? phase,
    SpeechVoice? voice,
    SpeechVoice? currentVoice,
    bool clearCurrentVoice = false,
    Set<String>? languages,
    Set<String>? missingLanguages,
    int? skippedLanguageSegments,
    double? speed,
    bool? follow,
    String? error,
    bool clearSleep = false,
    DateTime? sleepUntil,
    bool? sleepAfterChapter,
    int? skippedSegments,
  }) {
    if (_disposed) return;
    final old = snapshot.value;
    snapshot.value = ListeningSnapshot(
      novel: novel ?? old.novel,
      chapter: chapter ?? old.chapter,
      segment: segment ?? old.segment,
      segments: segments ?? old.segments,
      phase: phase ?? old.phase,
      voice: voice ?? old.voice,
      currentVoice:
          currentVoice ?? (clearCurrentVoice ? null : old.currentVoice),
      voiceOverrides: _voiceOverrides,
      spokenLanguage: store.spokenLanguage((novel ?? old.novel)?.id ?? 0),
      languages: languages ?? old.languages,
      missingLanguages: missingLanguages ?? old.missingLanguages,
      skippedLanguageSegments:
          skippedLanguageSegments ?? old.skippedLanguageSegments,
      speed: speed ?? old.speed,
      follow: follow ?? old.follow,
      playRequested: _desiredPlaying,
      skippedSegments: skippedSegments ?? old.skippedSegments,
      error: error,
      sleepUntil: sleepUntil ?? (clearSleep ? null : old.sleepUntil),
      sleepAfterChapter:
          sleepAfterChapter ?? (clearSleep ? false : old.sleepAfterChapter),
    );
    _updateTimeline();
  }

  bool _valid(int generation) =>
      !_disposed && generation == _generation && !_cancel.cancelled;
  Future<T> _command<T>(Future<T> Function() action) {
    final next = _commands.then((_) => action());
    _commands = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<ListeningAudioOutput> _ensureOutput() async {
    if (_output != null) return _output!;
    try {
      final output = await (_opening ??= outputFactory(this));
      if (_disposed) {
        await output.dispose();
        throw const SpeechCancelled();
      }
      if (_output == null) {
        _output = output;
        _positions = output.positions.listen(
          _position,
          onError: _playbackError,
        );
        _completions = output.completions.listen(
          (_) => _completed(),
          onError: _playbackError,
        );
      }
      return output;
    } finally {
      _opening = null;
    }
  }

  void _position(Duration position) {
    if (_disposed || _loading || snapshot.value.current == null) return;
    progress.value = ListeningProgress(
      position: position,
      duration: progress.value.duration,
    );
    _updateTimeline();
    if (snapshot.value.playing &&
        DateTime.now().difference(_lastSave) >= const Duration(seconds: 5)) {
      unawaited(saveCursor());
    }
  }

  void _playbackError(Object error, [StackTrace? stack]) {
    // Loading reports its own decoder errors. Old player stream errors emitted
    // while replacing the source must not fail the newly selected paragraph.
    if (!_disposed && !_loading && snapshot.value.playing) {
      _fail(error, _generation);
    }
  }

  void _fail(Object error, int generation) {
    if (!_valid(generation) || error is SpeechCancelled) return;
    _desiredPlaying = false;
    _loading = false;
    _emit(
      phase: ListeningPhase.failed,
      error: error is SpeechFailure ? error.message : '这一段暂未播放成功，请重试',
    );
    unawaited(
      _command(() async {
        if (_valid(generation) &&
            snapshot.value.phase == ListeningPhase.failed) {
          await _output?.pause();
        }
      }).catchError((Object _) {}),
    );
    unawaited(saveCursor());
  }

  ListeningCursor? savedCursor(int novelId) => store.cursor(novelId);
  Future<void> start(
    Novel novel, {
    required int chapter,
    int paragraph = 0,
    bool resume = false,
    bool autoplay = true,
  }) async {
    if (_disposed) return;
    final saving = saveCursor();
    _cancel.cancel();
    _cancel = SpeechCancellation();
    _dropPrefetch();
    final generation = ++_generation;
    _desiredPlaying = autoplay;
    _consecutiveFailures = 0;
    _loading = true;
    _chapterContent = const ReaderContent([]);
    _rawSegments = const [];
    _languageVoices = const {};
    _inventory = null;
    _inventoryKey = null;
    final cursor = resume ? savedCursor(novel.id) : null;
    _emit(
      novel: novel,
      chapter: chapter,
      segments: const [],
      segment: 0,
      phase: ListeningPhase.preparing,
      skippedSegments: 0,
      clearCurrentVoice: true,
      languages: const {},
      missingLanguages: const {},
      skippedLanguageSegments: 0,
    );
    progress.value = const ListeningProgress();
    try {
      await saving;
      if (!_valid(generation)) return;
      await _command(() async {
        await _output?.suspend();
      });
      if (!_valid(generation)) return;
      if (novel.chapters.isEmpty) {
        novel = novel.withChapters(await repository.chapters(novel.id));
        if (!_valid(generation)) return;
      }
      if (novel.chapters.isEmpty) throw const SpeechFailure('这本书还没有可朗读的章节');
      if (repository case final OfflineNovelRepository offline) {
        await offline.rememberDirectory(novel);
      }
      if (!_valid(generation)) return;
      if (cursor != null) {
        final stable = cursor.chapterId > 0
            ? novel.chapters.indexWhere((c) => c.id == cursor.chapterId)
            : -1;
        chapter = stable >= 0 ? stable : cursor.chapter;
        paragraph = cursor.paragraph;
      }
      _emit(novel: novel);
      await _loadChapter(
        chapter.clamp(0, novel.chapters.length - 1),
        generation,
        paragraph: paragraph,
        cursor: cursor,
      );
    } catch (error) {
      _fail(error, generation);
    }
  }

  Future<void> _loadChapter(
    int chapter,
    int generation, {
    int paragraph = 0,
    ListeningCursor? cursor,
  }) async {
    final novel = snapshot.value.novel!;
    // Image-only inserts are skipped iteratively, with a finite directory bound.
    for (var index = chapter; index < novel.chapters.length; index++) {
      if (!_valid(generation)) return;
      _loading = true;
      _rawSegments = const [];
      _chapterContent = const ReaderContent([]);
      _emit(
        chapter: index,
        segments: const [],
        segment: 0,
        phase: ListeningPhase.preparing,
        clearCurrentVoice: true,
        missingLanguages: const {},
        skippedLanguageSegments: 0,
      );
      final source = await repository.chapterContent(
        novel.id,
        novel.chapters[index],
      );
      if (!_valid(generation)) return;
      final content = source.trim().isEmpty
          ? const ReaderContent([])
          : await ReaderContent.parse(source);
      if (content.hasSourceFont) {
        throw const SpeechFailure(
          '本章使用原站配套字体，暂不支持朗读',
          kind: SpeechFailureKind.content,
        );
      }
      if (!_valid(generation)) return;
      final segments = source.length > 64 * 1024
          ? await compute(speechSegments, content.paragraphs)
          : speechSegments(content.paragraphs);
      if (!_valid(generation)) return;
      if (segments.isEmpty) {
        paragraph = 0;
        cursor = null;
        continue;
      }
      _chapterContent = content;
      _rawSegments = segments;
      if (!await _planChapter(generation)) {
        if (!_valid(generation)) return;
        paragraph = 0;
        cursor = null;
        continue;
      }
      await _loadPlannedSegment(
        generation,
        paragraph: paragraph,
        cursor: cursor,
      );
      return;
    }
    if (spokenLanguage(novel.id) case final language?) {
      throw SpeechFailure('没有找到可朗读的${readerLanguageLabel(language)}段落');
    }
    _finish();
  }

  String? spokenLanguage(int novelId) => store.spokenLanguage(novelId);

  Future<List<SpeechVoice>> _availableLanguageVoices(
    SpeechVoice preferred,
    Set<String> needed,
    int generation,
  ) async {
    if (preferred.source == ListeningSource.custom) return [preferred];
    // Keep ordinary single-language online playback independent of catalogue
    // availability. Cross-language matching only uses advertised voices.
    if (preferred.source == ListeningSource.edge &&
        needed.every(
          (code) =>
              code == speechLanguageCode(preferred.locale) &&
              (_voiceOverrides[code] == null ||
                  _voiceOverrides[code]!.id == preferred.id ||
                  [
                    defaultEdgeVoice.id,
                    alternateEdgeVoice.id,
                  ].contains(_voiceOverrides[code]!.id)),
        )) {
      return [preferred, defaultEdgeVoice, alternateEdgeVoice];
    }
    try {
      final found = await _cancel
          .wait(_voiceInventory(preferred))
          .timeout(preparationTimeout);
      if (!_valid(generation)) throw const SpeechCancelled();
      return found;
    } on SpeechCancelled {
      rethrow;
    } catch (_) {
      if (!_valid(generation)) throw const SpeechCancelled();
      _inventory = null;
      throw const SpeechFailure('暂时无法检测对应语言的语音模型，请重新检测音色后重试');
    }
  }

  Future<List<SpeechVoice>> _voiceInventory(SpeechVoice preferred) {
    final key = (
      preferred.source,
      preferred.engine,
      preferred.id,
      preferred.locale,
    );
    if (_inventoryKey != key || _inventory == null) {
      _inventoryKey = key;
      _inventory = switch (audio) {
        SpeechLanguageVoiceSource source => source.languageVoices(preferred),
        _ =>
          preferred.source == ListeningSource.edge
              ? audio.onlineVoices()
              : audio.offlineVoices(),
      };
    }
    return _inventory!;
  }

  Future<List<SpeechVoice>> voicesForLanguage(String language) async {
    final preferred = snapshot.value.voice;
    final code = speechLanguageCode(language);
    try {
      final found = preferred.source == ListeningSource.custom
          ? [preferred]
          : await _voiceInventory(preferred).timeout(preparationTimeout);
      return List.unmodifiable(
        found.where(
          (voice) =>
              voice.availableForListening &&
              voice.id != '@default' &&
              voice.source == preferred.source &&
              voice.engine == preferred.engine &&
              speechLanguageCode(voice.locale) == code,
        ),
      );
    } catch (_) {
      _inventory = null;
      if (preferred.source == ListeningSource.edge && code == 'zh') {
        return const [defaultEdgeVoice, alternateEdgeVoice];
      }
      throw const SpeechFailure('音色列表暂时不可用，请重试');
    }
  }

  Future<bool> _planChapter(int generation) async {
    final state = snapshot.value;
    final all = speechWithLanguages(_rawSegments, _chapterContent, state.voice);
    final selection = spokenLanguage(state.novel!.id);
    final candidates = all
        .where((part) => selection == null || part.language == selection)
        .toList();
    final languages = Set<String>.unmodifiable(
      all.map((part) => part.language),
    );
    if (candidates.isEmpty) {
      _emit(segments: const [], segment: 0, languages: languages);
      return false;
    }
    final needed = candidates.map((part) => part.language).toSet();
    final available = await _availableLanguageVoices(
      state.voice,
      needed,
      generation,
    );
    if (!_valid(generation)) return false;
    final matched = <String, SpeechVoice>{};
    for (final language in needed) {
      final voice = speechVoiceForLanguage(
        language,
        state.voice,
        available,
        selected: _voiceOverrides[language],
      );
      if (voice != null) matched[language] = voice;
    }
    _languageVoices = matched;
    final missing = Set<String>.unmodifiable(
      needed.difference(_languageVoices.keys.toSet()),
    );
    final segments = List<SpeechSegment>.unmodifiable(
      candidates.where((part) => _languageVoices.containsKey(part.language)),
    );
    _emit(
      segments: segments,
      segment: 0,
      languages: languages,
      missingLanguages: missing,
      skippedLanguageSegments: candidates.length - segments.length,
      clearCurrentVoice: true,
    );
    if (segments.isEmpty) throw SpeechFailure(_missingModelMessage(missing));
    return true;
  }

  String _missingModelMessage(Set<String> missing) {
    final configured = missing.where(_voiceOverrides.containsKey).toList();
    if (configured.isNotEmpty) {
      return '所选${configured.map(readerLanguageLabel).join('、')}音色不可用，已停止朗读';
    }
    return '未找到可用的${missing.map(readerLanguageLabel).join('、')}语音模型，已停止朗读';
  }

  Future<void> _loadPlannedSegment(
    int generation, {
    int paragraph = 0,
    ListeningCursor? cursor,
  }) async {
    var segments = snapshot.value.segments;
    var selected = segments.indexWhere(
      (s) =>
          s.paragraph >= paragraph &&
          (cursor == null ||
              s.paragraph != cursor.paragraph ||
              s.end > cursor.start),
    );
    if (selected < 0) selected = segments.length - 1;
    if (cursor != null &&
        segments[selected].key(_languageVoices[segments[selected].language]!) !=
            cursor.segmentHash) {
      final parts = speechRecoverySegments(segments[selected]);
      final recovered = parts.indexWhere(
        (part) =>
            part.start == cursor.start &&
            part.key(_languageVoices[part.language]!) == cursor.segmentHash,
      );
      if (parts.length > 1 && recovered >= 0) {
        segments = List.unmodifiable([
          ...segments.take(selected),
          ...parts,
          ...segments.skip(selected + 1),
        ]);
        selected += recovered;
      }
    }
    _emit(segments: segments, segment: selected);
    final restore =
        cursor != null &&
            segments[selected].key(
                  _languageVoices[segments[selected].language]!,
                ) ==
                cursor.segmentHash
        ? Duration(milliseconds: cursor.positionMs)
        : Duration.zero;
    await _loadSegment(selected, generation, restore: restore);
  }

  Future<void> _loadSegment(
    int index,
    int generation, {
    Duration restore = Duration.zero,
    double? seekFraction,
  }) async {
    final decoderRetried = <String>{};
    while (_valid(generation)) {
      final state = snapshot.value;
      if (index >= state.segments.length) {
        _loading = false;
        _atSegmentEnd = true;
        await _advance(generation);
        return;
      }
      final segment = state.segments[index];
      final voice = _languageVoices[segment.language];
      if (voice == null) {
        index++;
        restore = Duration.zero;
        seekFraction = null;
        continue;
      }
      final token = _cancel;
      _loading = true;
      _atSegmentEnd = false;
      _playEpoch++;
      _emit(
        segment: index,
        phase: ListeningPhase.preparing,
        currentVoice: voice,
      );
      progress.value = const ListeningProgress();
      final prefetched = _preparedAhead.remove(_audioIdentity(segment, voice));
      if (prefetched != null) {
        _retainLoad(prefetched);
      }
      File? protectedFile = prefetched;
      var decodeFailed = false;
      try {
        final file = prefetched ?? await _prepareAudio(segment, voice, token);
        if (!_valid(generation)) return;
        if (protectedFile == null) {
          _retainLoad(file);
          protectedFile = file;
        }
        final output = await _ensureOutput();
        if (!_valid(generation)) return;
        Duration? duration;
        await _command(() async {
          if (!_valid(generation)) return;
          await output.suspend();
          if (!_valid(generation)) return;
          try {
            duration = await output.load(file, restore).timeout(decoderTimeout);
            if (duration != null && duration! <= Duration.zero) {
              throw const SpeechFailure(
                '这一段音频没有有效时长',
                kind: SpeechFailureKind.content,
              );
            }
          } on SpeechCancelled {
            rethrow;
          } catch (_) {
            decodeFailed = true;
            throw const SpeechFailure(
              '这一段音频暂未解码成功',
              kind: SpeechFailureKind.content,
            );
          }
          if (!_valid(generation)) return;
          if (seekFraction != null && duration != null) {
            restore = Duration(
              microseconds:
                  (duration!.inMicroseconds * seekFraction.clamp(0.0, 1.0))
                      .round(),
            );
            await output.seek(restore);
          }
          if (duration != null &&
              seekFraction == null &&
              restore >= duration! &&
              duration! > Duration.zero) {
            restore = Duration.zero;
            await output.seek(restore);
          }
          await output.setSpeed(snapshot.value.speed);
        });
        if (!_valid(generation)) return;
        final previous = _currentFile;
        _currentFile = file;
        _releaseFile(previous);
        _prunePrefetch();
        _consecutiveFailures = 0;
        if (duration != null) {
          _clipDurations[segment] = duration!;
          _updateTimeOffsets();
        }
        progress.value = ListeningProgress(
          position: restore <= (duration ?? restore) ? restore : duration!,
          duration: duration ?? Duration.zero,
        );
        _loading = false;
        _atSegmentEnd = duration != null && restore >= duration!;
        _emit(
          phase: _desiredPlaying
              ? ListeningPhase.playing
              : ListeningPhase.paused,
        );
        if (_desiredPlaying) {
          if (_atSegmentEnd) {
            _completed();
          } else {
            _play(output, generation);
          }
        }
        unawaited(saveCursor());
        unawaited(_prefetch(generation, token));
        return;
      } catch (error) {
        if (!_valid(generation) || error is SpeechCancelled) return;
        if (error is SpeechFailure &&
            error.kind == SpeechFailureKind.missingLanguage) {
          _dropPrefetch();
          _languageVoices = Map.of(_languageVoices)..remove(segment.language);
          final remaining = List<SpeechSegment>.unmodifiable([
            ...state.segments.take(index),
            ...state.segments
                .skip(index)
                .where((part) => part.language != segment.language),
          ]);
          final missing = Set<String>.unmodifiable({
            ...state.missingLanguages,
            segment.language,
          });
          _emit(
            segments: remaining,
            missingLanguages: missing,
            skippedLanguageSegments:
                state.skippedLanguageSegments +
                state.segments.length -
                remaining.length,
            clearCurrentVoice: true,
          );
          if (remaining.isEmpty) {
            _fail(SpeechFailure(_missingModelMessage(missing)), generation);
            return;
          }
          restore = Duration.zero;
          seekFraction = null;
          continue;
        }
        if (decodeFailed && protectedFile != null) {
          final broken = protectedFile;
          _dropPrefetch();
          if (_currentFile?.path == broken.path) _currentFile = null;
          _releaseLoad(broken);
          protectedFile = null;
          await audio.invalidate(broken);
          if (!_valid(generation)) return;
          if (_desiredPlaying && decoderRetried.add(broken.path)) {
            restore = Duration.zero;
            continue;
          }
        }
        if (error is! SpeechFailure || !error.recoverable || !_desiredPlaying) {
          _fail(error, generation);
          return;
        }
        final parts = error.kind == SpeechFailureKind.content
            ? speechRecoverySegments(segment)
            : const <SpeechSegment>[];
        if (parts.length > 1) {
          _emit(
            segments: List.unmodifiable([
              ...state.segments.take(index),
              ...parts,
              ...state.segments.skip(index + 1),
            ]),
          );
        } else {
          if (++_consecutiveFailures >= 3) {
            _fail(
              const SpeechFailure('连续三段语音准备失败，已暂停；可以重试、跳过当前语段或切换音色'),
              generation,
            );
            return;
          }
          _emit(skippedSegments: snapshot.value.skippedSegments + 1);
          index++;
        }
        restore = Duration.zero;
        seekFraction = null;
      } finally {
        _releaseLoad(protectedFile);
      }
    }
  }

  Future<File> _prepareAudio(
    SpeechSegment segment,
    SpeechVoice voice,
    SpeechCancellation token,
  ) async {
    final attempt = SpeechCancellation();
    final detach = token.onCancel(attempt.cancel);
    try {
      attempt.check();
      return await attempt
          .wait(audio.prepare(segment, voice, attempt))
          .timeout(
            preparationTimeout,
            onTimeout: () {
              attempt.cancel();
              throw const SpeechFailure(
                '这一段语音准备超时',
                kind: SpeechFailureKind.timeout,
              );
            },
          );
    } finally {
      detach();
    }
  }

  void _play(ListeningAudioOutput output, int generation) {
    final epoch = ++_playEpoch;
    unawaited(
      output.play().catchError((Object error) {
        if (epoch == _playEpoch && _desiredPlaying) _fail(error, generation);
      }),
    );
  }

  Future<void> _prefetch(int generation, SpeechCancellation token) async {
    if (!_valid(generation) || !_desiredPlaying || _prefetchRun != null) return;
    final run = Object();
    _prefetchRun = run;
    bool current() => _valid(generation) && identical(_prefetchRun, run);
    try {
      while (current() && _desiredPlaying) {
        _prunePrefetch();
        final state = snapshot.value;
        SpeechSegment? segment;
        SpeechVoice? voice;
        for (
          var i = state.segment + 1;
          i < state.segments.length && i <= state.segment + _lookAhead;
          i++
        ) {
          final candidate = state.segments[i];
          final matched = _languageVoices[candidate.language];
          if (matched != null &&
              !_preparedAhead.containsKey(_audioIdentity(candidate, matched))) {
            segment = candidate;
            voice = matched;
            break;
          }
        }
        if (segment == null || voice == null) return;
        // One background synthesis at a time, without holding audible playback.
        final key = _audioIdentity(segment, voice);
        final file = await _prepareAudio(segment, voice, token);
        if (!current()) return;
        final live = snapshot.value;
        final index = live.segments.indexOf(segment);
        if (index <= live.segment || index > live.segment + _lookAhead) {
          continue;
        }
        _preparedAhead[key] = file;
        audio.protect(file);
        await audio.trimForPlayback();
      }
    } catch (_) {
      /* Playback reports a failure only if this segment is actually requested. */
    } finally {
      if (identical(_prefetchRun, run)) _prefetchRun = null;
    }
  }

  void _completed() {
    final state = snapshot.value;
    if (_disposed || _loading || !state.active || state.current == null) {
      return;
    }
    // Native completion can reach Dart just after a pause, especially for a
    // one-second phrase. Retain the end marker without auto-playing: otherwise
    // resume asks an already-completed decoder to play, with no new end event.
    _atSegmentEnd = true;
    final last = progress.value;
    if (last.duration > Duration.zero) {
      progress.value = ListeningProgress(
        position: last.duration,
        duration: last.duration,
      );
      _updateTimeline();
    }
    if (!_desiredPlaying || !state.playing) return;
    final generation = _generation;
    unawaited(
      _advance(
        generation,
      ).catchError((Object error) => _fail(error, generation)),
    );
  }

  Future<void> _advance(int generation) async {
    if (!_valid(generation)) return;
    final state = snapshot.value;
    if (state.segment + 1 < state.segments.length) {
      await _loadSegment(state.segment + 1, generation);
    } else if (state.sleepAfterChapter ||
        state.chapter + 1 >= state.novel!.chapters.length) {
      if (state.sleepAfterChapter) {
        await pause();
        _clearSleep();
      } else {
        _finish();
      }
    } else {
      await _loadChapter(state.chapter + 1, generation);
    }
  }

  void _finish() {
    _desiredPlaying = false;
    _loading = false;
    _emit(phase: ListeningPhase.completed);
    _clearSleep();
    unawaited(saveCursor());
    unawaited(
      _command(() async {
        await _output?.stop();
      }).catchError((Object _) {}),
    );
  }

  Future<void> pause() async {
    if (_disposed) return;
    _playEpoch++;
    _desiredPlaying = false;
    if (snapshot.value.active) _emit(phase: ListeningPhase.paused);
    await _command(() async {
      await _output?.pause();
    });
    await saveCursor();
  }

  Future<void> resume() async {
    final state = snapshot.value;
    if (_disposed || state.novel == null) return;
    _desiredPlaying = true;
    if (_loading) {
      _emit(phase: ListeningPhase.preparing);
      return;
    }
    if (_atSegmentEnd && state.phase == ListeningPhase.paused) {
      _emit(phase: ListeningPhase.playing);
      _completed();
      return;
    }
    if (state.phase == ListeningPhase.failed ||
        state.phase == ListeningPhase.stopped ||
        state.phase == ListeningPhase.completed ||
        _currentFile == null) {
      await start(state.novel!, chapter: state.chapter, resume: true);
    } else {
      _emit(phase: ListeningPhase.playing);
      final generation = _generation;
      final output = await _ensureOutput();
      await _command(() async {
        if (_valid(generation) && _desiredPlaying) _play(output, generation);
      });
      unawaited(_prefetch(generation, _cancel));
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    _playEpoch++;
    final saving = saveCursor();
    _desiredPlaying = false;
    _cancel.cancel();
    _generation++;
    _loading = false;
    _clearSleep();
    _emit(phase: ListeningPhase.stopped);
    await saving;
    await _command(() async {
      await _output?.stop();
    });
    final previous = _currentFile;
    _currentFile = null;
    _dropPrefetch();
    _releaseFile(previous);
  }

  Future<void> seek(Duration position) async {
    if (_loading || _output == null) return;
    final generation = _generation;
    final bounded = Duration(
      milliseconds: position.inMilliseconds.clamp(
        0,
        progress.value.duration.inMilliseconds,
      ),
    );
    _atSegmentEnd =
        progress.value.duration > Duration.zero &&
        bounded >= progress.value.duration;
    await _command(() async {
      if (_valid(generation)) await _output!.seek(bounded);
    });
    if (!_valid(generation) || _loading) return;
    progress.value = ListeningProgress(
      position: bounded,
      duration: progress.value.duration,
    );
    _updateTimeline();
    await saveCursor();
  }

  Future<void> seekChapterFraction(double fraction) async {
    final state = snapshot.value;
    if (!fraction.isFinite || state.current == null) return;
    final target = fraction.clamp(0.0, 1.0) * _textOffsets.last;
    var index = state.segments.length - 1;
    for (var i = 0; i < state.segments.length; i++) {
      if (target < _textOffsets[i + 1]) {
        index = i;
        break;
      }
    }
    final local =
        ((target - _textOffsets[index]) /
                (_textOffsets[index + 1] - _textOffsets[index]))
            .clamp(0.0, 1.0);
    if (index == state.segment &&
        !_loading &&
        progress.value.duration > Duration.zero) {
      await seek(
        Duration(
          microseconds: (progress.value.duration.inMicroseconds * local)
              .round(),
        ),
      );
    } else {
      await _jumpToSegment(index, autoplay: _desiredPlaying, fraction: local);
    }
  }

  Future<void> moveParagraph(int direction) async {
    final state = snapshot.value;
    if (state.current == null || state.novel == null) return;
    final paragraph = state.current!.paragraph;
    int? index;
    if (direction > 0) {
      for (var i = state.segment + 1; i < state.segments.length; i++) {
        if (state.segments[i].paragraph > paragraph) {
          index = i;
          break;
        }
      }
    } else {
      for (var i = 0; i < state.segment; i++) {
        if (state.segments[i].paragraph < paragraph) index = i;
      }
      if (index != null) {
        final target = state.segments[index].paragraph;
        index = state.segments.indexWhere((s) => s.paragraph == target);
      }
    }
    if (index == null) {
      final chapter = state.chapter + (direction > 0 ? 1 : -1);
      if (chapter >= 0 && chapter < state.novel!.chapters.length) {
        await start(state.novel!, chapter: chapter, autoplay: _desiredPlaying);
      }
      return;
    }
    await _jumpToSegment(index, autoplay: _desiredPlaying);
  }

  /// Gestures are only active for this book's existing listening session. A
  /// paused session counts, so the second double-tap resumes the exact clip.
  Future<void> paragraphDoubleTap({
    required int novelId,
    required int chapter,
    required int paragraph,
  }) async {
    final state = snapshot.value;
    if (_disposed ||
        !state.active ||
        state.novel?.id != novelId ||
        paragraph < 0 ||
        chapter < 0 ||
        chapter >= state.novel!.chapters.length) {
      return;
    }
    if (state.chapter == chapter && state.current?.paragraph == paragraph) {
      if (_desiredPlaying) {
        await pause();
      } else {
        await resume();
      }
    } else if (state.chapter == chapter) {
      final index = state.segments.indexWhere(
        (part) => part.paragraph == paragraph,
      );
      if (index >= 0) await _jumpToSegment(index, autoplay: true);
    } else {
      await start(state.novel!, chapter: chapter, paragraph: paragraph);
    }
  }

  Future<void> skipSegment() async {
    final state = snapshot.value;
    if (!state.active || state.current == null) return;
    final autoplay = _desiredPlaying || state.phase == ListeningPhase.failed;
    if (state.segment + 1 < state.segments.length) {
      await _jumpToSegment(state.segment + 1, autoplay: autoplay);
    } else if (state.chapter + 1 < state.novel!.chapters.length &&
        !state.sleepAfterChapter) {
      await start(state.novel!, chapter: state.chapter + 1, autoplay: autoplay);
    } else {
      await stop();
    }
  }

  Future<void> _jumpToSegment(
    int index, {
    required bool autoplay,
    double? fraction,
  }) async {
    if (_disposed) return;
    final saving = saveCursor();
    _cancel.cancel();
    _cancel = SpeechCancellation();
    _dropPrefetch();
    final generation = ++_generation;
    _desiredPlaying = autoplay;
    _consecutiveFailures = 0;
    _loading = true;
    _emit(segment: index, phase: ListeningPhase.preparing);
    await saving;
    if (!_valid(generation)) return;
    await _command(() async {
      if (_valid(generation)) await _output?.suspend();
    });
    if (!_valid(generation)) return;
    await _loadSegment(index, generation, seekFraction: fraction);
  }

  Future<void> moveChapter(int direction) async {
    final state = snapshot.value;
    if (state.novel == null) return;
    final chapter = state.chapter + direction;
    if (chapter >= 0 && chapter < state.novel!.chapters.length) {
      await start(state.novel!, chapter: chapter, autoplay: _desiredPlaying);
    }
  }

  Future<void> setVoice(SpeechVoice voice) async {
    if (!voice.availableForListening) {
      throw const SpeechFailure('请选择可用的朗读引擎');
    }
    await store.saveVoice(voice);
    if (_disposed) return;
    if (snapshot.value.voice.id == voice.id &&
        snapshot.value.voice.engine == voice.engine &&
        snapshot.value.voice.source == voice.source &&
        snapshot.value.voice.locale == voice.locale) {
      return;
    }
    await saveCursor();
    if (_disposed) return;
    final state = snapshot.value;
    // Directory/content loading has not selected an audio segment yet. Let it
    // finish under the new voice; cancelling its generation would strand it.
    _inventory = null;
    _inventoryKey = null;
    _voiceOverrides = store.languageVoices(voice);
    if (!state.active || _rawSegments.isEmpty) {
      _emit(voice: voice, clearCurrentVoice: true);
      return;
    }
    _emit(voice: voice, clearCurrentVoice: true);
    await _replanCurrent(state);
  }

  Future<void> setSpokenLanguage(int novelId, String? language) async {
    final previous = spokenLanguage(novelId);
    await saveCursor();
    await store.saveSpokenLanguage(novelId, language);
    if (_disposed) return;
    final state = snapshot.value;
    _emit();
    if (previous == spokenLanguage(novelId) ||
        state.novel?.id != novelId ||
        !state.active ||
        _rawSegments.isEmpty) {
      return;
    }
    await _replanCurrent(state);
  }

  Future<void> setLanguageVoice(String language, SpeechVoice? voice) async {
    final code = speechLanguageCode(language);
    final state = snapshot.value;
    if (code.isEmpty ||
        (voice != null &&
            (!voice.availableForListening ||
                voice.id == '@default' ||
                voice.source != state.voice.source ||
                voice.engine != state.voice.engine ||
                speechLanguageCode(voice.locale) != code))) {
      throw const SpeechFailure('请选择当前音源中对应语言的音色');
    }
    await saveCursor();
    await store.saveLanguageVoice(state.voice, code, voice);
    if (_disposed) return;
    final current = snapshot.value;
    _voiceOverrides = store.languageVoices(snapshot.value.voice);
    _emit();
    if (current.active && _rawSegments.isNotEmpty) {
      await _replanCurrent(current);
    }
  }

  Future<void> _replanCurrent(ListeningSnapshot previous) async {
    final cursor = previous.current == null
        ? null
        : ListeningCursor(
            novelId: previous.novel!.id,
            chapterId: previous.novel!.chapters[previous.chapter].id,
            chapter: previous.chapter,
            paragraph: previous.current!.paragraph,
            start: previous.current!.start,
            positionMs: progress.value.position.inMilliseconds,
            segmentHash: previous.current!.key(previous.outputVoice),
          );
    _cancel.cancel();
    _cancel = SpeechCancellation();
    _dropPrefetch();
    final generation = ++_generation;
    _playEpoch++;
    _loading = true;
    _consecutiveFailures = 0;
    _emit(phase: ListeningPhase.preparing, clearCurrentVoice: true);
    await _command(() async {
      if (_valid(generation)) await _output?.suspend();
    });
    if (!_valid(generation)) return;
    try {
      if (await _planChapter(generation)) {
        await _loadPlannedSegment(
          generation,
          paragraph: cursor?.paragraph ?? 0,
          cursor: cursor,
        );
      } else if (_valid(generation)) {
        await _loadChapter(previous.chapter + 1, generation);
      }
    } catch (error) {
      _fail(error, generation);
    }
  }

  Future<void> setSpeed(double speed) async {
    speed = speed.clamp(listeningMinimumSpeed, listeningMaximumSpeed);
    await store.saveSpeed(speed);
    _emit(speed: speed);
    await _command(() async {
      await _output?.setSpeed(speed);
    });
  }

  Future<void> setFollow(bool follow) async {
    await store.saveFollow(follow);
    _emit(follow: follow);
  }

  void setSleep({Duration? duration, bool afterChapter = false}) {
    _sleep?.cancel();
    final until = duration != null ? DateTime.now().add(duration) : null;
    _emit(clearSleep: true, sleepUntil: until, sleepAfterChapter: afterChapter);
    if (duration != null) {
      _sleep = Timer(duration, () {
        unawaited(pause());
        _clearSleep();
      });
    }
  }

  void _clearSleep() {
    _sleep?.cancel();
    _sleep = null;
    _emit(clearSleep: true);
  }

  Future<void> refreshVoices({bool online = true}) async {
    if (_disposed) return;
    if (_voiceRefresh case final pending?) return pending;
    final future = _fetchVoices(online: online);
    _voiceRefresh = future;
    try {
      await future;
    } finally {
      if (identical(_voiceRefresh, future)) _voiceRefresh = null;
    }
  }

  Future<void> _fetchVoices({required bool online}) async {
    final old = voices.value;
    voices.value = ListeningVoiceCatalog(
      online: old.online,
      offline: old.offline,
      checked: old.checked,
      loading: true,
    );
    try {
      final found = await (online
          ? audio.onlineVoices()
          : audio.offlineVoices());
      if (_disposed) return;
      _inventory = null;
      _inventoryKey = null;
      voices.value = ListeningVoiceCatalog(
        online: online && found.isNotEmpty ? found : old.online,
        offline: online ? old.offline : found,
        checked: true,
        message: found.isEmpty
            ? (online ? '暂未获取到更多在线音色，可继续使用已有音色' : '没有检测到可用音色，请在系统语音设置中检查引擎')
            : null,
        messageSource: online ? ListeningSource.edge : ListeningSource.system,
      );
    } catch (error) {
      if (!_disposed) {
        voices.value = ListeningVoiceCatalog(
          online: old.online,
          offline: old.offline,
          checked: old.checked,
          message: error is SpeechFailure ? error.message : '在线音色列表暂时不可用，请稍后重试',
          messageSource: online ? ListeningSource.edge : ListeningSource.system,
        );
      }
    }
  }

  Future<void> saveCursor() async {
    if (_disposed) return;
    final state = snapshot.value, current = snapshot.value.current;
    if (state.novel == null || current == null || _loading) return;
    _lastSave = DateTime.now();
    try {
      await store.saveCursor(
        ListeningCursor(
          novelId: state.novel!.id,
          chapterId: state.novel!.chapters[state.chapter].id,
          chapter: state.chapter,
          paragraph: current.paragraph,
          start: current.start,
          positionMs: progress.value.position.inMilliseconds,
          segmentHash: current.key(state.outputVoice),
        ),
      );
    } catch (_) {
      /* Playback remains usable; the panel can still explicitly restart here. */
    }
  }

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    await stop();
    _disposed = true;
    await _positions?.cancel();
    await _completions?.cancel();
    await _output?.dispose();
    snapshot.dispose();
    progress.dispose();
    chapterProgress.dispose();
    voices.dispose();
  }
}
