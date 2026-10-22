import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_interactions.dart';
import '../app_ui.dart';
import '../catalog.dart';
import '../reader_tools.dart' show ReaderValueSlider;
import '../reader_speech_highlight.dart';
import '../reader_languages.dart';
import '../ui_notifiers.dart';
import 'controller.dart';
import 'models.dart';
import 'languages.dart';
import 'custom_tts_page.dart';
import 'system_tts_page.dart';

class ListeningScope extends InheritedWidget {
  const ListeningScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final ListeningController? controller;
  static ListeningController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ListeningScope>()?.controller;
  @override
  bool updateShouldNotify(ListeningScope oldWidget) =>
      controller != oldWidget.controller;
}

Future<void> showListeningPanel(
  BuildContext context, {
  required ListeningController controller,
  required Novel novel,
  required int chapter,
  int paragraph = 0,
  Set<String> languages = const {},
  bool reduceMotion = false,
  Widget Function(Widget)? surfaceWrapper,
}) => showJellySheet<void>(
  context: context,
  reduceMotion: reduceMotion,
  heightFactor: .86,
  surfaceWrapper: surfaceWrapper,
  builder: (_) => ListeningPanel(
    controller: controller,
    novel: novel,
    chapter: chapter,
    paragraph: paragraph,
    languages: languages,
  ),
);

class ListeningPanel extends StatefulWidget {
  const ListeningPanel({
    super.key,
    required this.controller,
    required this.novel,
    required this.chapter,
    this.paragraph = 0,
    this.embedded = false,
    this.languages = const {},
  });
  final ListeningController controller;
  final Novel novel;
  final int chapter, paragraph;
  final bool embedded;
  final Set<String> languages;
  @override
  State<ListeningPanel> createState() => _ListeningPanelState();
}

const listeningGestureHint = '双击其他段落可快速跳转朗读；双击当前段落可暂停，再次双击继续播放。';

class _ListeningPanelState extends State<ListeningPanel> {
  Future<void> _systemEngine() async {
    final voice = await showJellySheet<SpeechVoice>(
      context: context,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      builder: (_) => SystemSpeechEnginesPanel(
        selected: widget.controller.snapshot.value.voice,
      ),
    );
    if (voice != null && mounted) await _voice(voice);
  }

  Future<void> _configureCustom() async {
    final settings = widget.controller.customSpeech;
    if (settings == null) return;
    await pushNovelPage<void>(
      context,
      CustomSpeechPage(settings: settings, controller: widget.controller),
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
  }

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        showNovelFeedback(
          context,
          error is SpeechFailure ? error.message : '设置暂未保存，请重试',
        );
      }
    }
  }

  Future<void> _voice(SpeechVoice voice) async {
    await _act(() => widget.controller.setVoice(voice));
  }

  Future<void> _languageVoice(String language) async {
    final choice = await showJellySheet<({SpeechVoice? voice})>(
      context: context,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      builder: (_) => _LanguageVoicePicker(
        controller: widget.controller,
        language: language,
        selected: widget.controller.snapshot.value.voiceOverrides[language],
      ),
    );
    if (choice != null && mounted) {
      await _act(
        () => widget.controller.setLanguageVoice(language, choice.voice),
      );
    }
  }

  Future<void> _playUsingSource(Future<void> Function() action) => _act(action);

  Future<void> _playFromSettings(Future<void> Function() action) async {
    await _act(action);
    if (!mounted || !widget.embedded) return;
    final state = widget.controller.snapshot.value;
    if (state.novel?.id != widget.novel.id || !state.requestingPlayback) return;
    showNovelFeedback(
      context,
      listeningGestureHint,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('listening-panel-scroll'),
    primary: false,
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: ValueListenableBuilder<ListeningSnapshot>(
      valueListenable: widget.controller.snapshot,
      child: _preferences(),
      builder: (context, state, preferences) {
        final own = state.novel?.id == widget.novel.id;
        final cursor = widget.controller.savedCursor(widget.novel.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.embedded) ...[
              Row(
                children: [
                  const Expanded(
                    child: ArchiveSection(
                      title: '听书',
                      code: 'READER / AUDIO ARCHIVE',
                    ),
                  ),
                  GlassIconButton(
                    icon: CupertinoIcons.xmark,
                    label: '关闭听书面板',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            AppText(
              own && state.active ? state.novel!.title : widget.novel.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            AppText(
              '当前音源 · ${switch (state.voice.source) {
                ListeningSource.system => '系统引擎',
                ListeningSource.custom => '自定义接口',
                _ => '自然在线',
              }} · ${own ? state.outputVoice.label : state.voice.label}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            AppText(
              own && state.current != null
                  ? '第 ${state.chapter + 1} 章 · ${state.chapterTitle}'
                  : '从第 ${widget.chapter + 1} 章当前段落开始',
              style: const TextStyle(fontSize: 13),
            ),
            if (own && state.active)
              _ListeningTransportStatus(phase: state.phase),
            if (own && state.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AppText(state.error!),
              ),
            if (own && state.skippedSegments > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: AppText(
                  '已跳过 ${state.skippedSegments} 个未生成语音的语段',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (own && state.missingLanguages.isNotEmpty && state.error == null)
              Padding(
                key: const ValueKey('listening-missing-languages'),
                padding: const EdgeInsets.only(top: 10),
                child: AppText(
                  '${state.missingLanguages.map(readerLanguageLabel).join('、')}暂无可用的匹配音色'
                  '，已跳过 ${state.skippedLanguageSegments} 个语段',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (own && state.current != null)
              GlassTextButton(
                key: const ValueKey('listening-skip-segment'),
                onPressed: () => _act(widget.controller.skipSegment),
                child: const AppText('跳过当前语段'),
              ),
            if (own && state.current != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(13) * 1.6 * 2,
                child: AppText(
                  state.current!.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              AppText(
                '语段 ${state.segment + 1} / ${state.segments.length}',
                style: ArchiveDesign.codeStyle(context),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GlassIconButton(
                  icon: CupertinoIcons.backward_end,
                  label: '听上一段',
                  onPressed:
                      own &&
                          state.current != null &&
                          state.phase != ListeningPhase.preparing
                      ? () => _act(() => widget.controller.moveParagraph(-1))
                      : null,
                ),
                GlassIconButton(
                  key: const ValueKey('listening-play-pause'),
                  icon: own && (state.requestingPlayback)
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  label: own && (state.requestingPlayback) ? '暂停听书' : '开始听书',
                  onPressed: () => own && state.requestingPlayback
                      ? _act(widget.controller.pause)
                      : _playFromSettings(
                          () => own && state.active
                              ? widget.controller.resume()
                              : widget.controller.start(
                                  widget.novel,
                                  chapter: widget.chapter,
                                  paragraph: widget.paragraph,
                                  resume: cursor != null,
                                ),
                        ),
                ),
                GlassIconButton(
                  icon: CupertinoIcons.forward_end,
                  label: '听下一段',
                  onPressed:
                      own &&
                          state.current != null &&
                          state.phase != ListeningPhase.preparing
                      ? () => _act(() => widget.controller.moveParagraph(1))
                      : null,
                ),
                GlassIconButton(
                  key: const ValueKey('listening-stop'),
                  icon: CupertinoIcons.stop_fill,
                  label: '停止听书',
                  onPressed: state.active
                      ? () => _act(widget.controller.stop)
                      : null,
                ),
              ],
            ),
            if (own && state.current != null)
              ValueListenableBuilder<ListeningChapterProgress>(
                valueListenable: widget.controller.chapterProgress,
                builder: (context, progress, _) =>
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: progress.fraction),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                      builder: (context, fraction, _) => ReaderValueSlider(
                        key: ValueKey((state.novel?.id, state.chapter)),
                        sliderKey: const ValueKey('listening-position'),
                        label: '本章进度',
                        value: fraction,
                        min: 0,
                        max: 1,
                        format: (value) =>
                            '${(value * 100).toStringAsFixed(1)}%',
                        onCommitted: (value) => _act(
                          () => widget.controller.seekChapterFraction(value),
                        ),
                      ),
                    ),
              ),
            if (own && state.current != null)
              SelectedValueBuilder<
                ListeningProgress,
                ({int position, int duration})
              >(
                listenable: widget.controller.progress,
                select: (progress) => (
                  position: progress.position.inSeconds,
                  duration: progress.duration.inSeconds,
                ),
                builder: (context, progress, _) => AppText(
                  state.phase == ListeningPhase.preparing
                      ? '当前语段 · 准备中'
                      : '当前语段 · ${_time(progress.position)} / ${_time(progress.duration)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              children: [
                GlassTextButton(
                  key: const ValueKey('listening-from-here'),
                  onPressed: () => _playUsingSource(
                    () => widget.controller.start(
                      widget.novel,
                      chapter: widget.chapter,
                      paragraph: widget.paragraph,
                    ),
                  ),
                  child: const AppText('从阅读位置听起'),
                ),
                if (cursor != null)
                  GlassTextButton(
                    key: const ValueKey('listening-resume'),
                    onPressed: () => _playUsingSource(
                      () => widget.controller.start(
                        widget.novel,
                        chapter: cursor.chapter,
                        resume: true,
                      ),
                    ),
                    child: AppText('续听 · 第 ${cursor.chapter + 1} 章'),
                  ),
              ],
            ),
            if (state.novel != null && !own && state.active)
              AppText(
                '另一部作品正在听书，开始后将切换到本书',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            const Divider(height: 28),
            preferences!,
          ],
        );
      },
    ),
  );

  // The settings stay mounted while the transport changes clips. A paragraph
  // handoff must not rebuild sliders, switches or the entire voice catalogue.
  Widget _preferences() =>
      SelectedValueBuilder<
        ListeningSnapshot,
        ({
          SpeechVoice voice,
          double speed,
          bool follow,
          DateTime? sleepUntil,
          bool sleepAfterChapter,
          String? spokenLanguage,
          Set<String> languages,
          Map<String, SpeechVoice> voiceOverrides,
        })
      >(
        listenable: widget.controller.snapshot,
        select: (state) => (
          voice: state.voice,
          speed: state.speed,
          follow: state.follow,
          sleepUntil: state.sleepUntil,
          sleepAfterChapter: state.sleepAfterChapter,
          spokenLanguage: widget.controller.spokenLanguage(widget.novel.id),
          languages: state.novel?.id == widget.novel.id
              ? state.languages
              : const {},
          voiceOverrides: state.voiceOverrides,
        ),
        builder: (context, state, _) {
          final source = state.voice.source;
          final languages = <String>{
            ...widget.languages
                .map(speechLanguageCode)
                .where((code) => code.isNotEmpty),
            ...state.languages,
            speechLanguageCode(state.voice.locale),
            ...state.voiceOverrides.keys,
            if (state.spokenLanguage != null) state.spokenLanguage!,
          }.toList()..sort();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppText(
                '本书朗读语言',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  GlassTextButton(
                    key: const ValueKey('listening-language-auto'),
                    selected: state.spokenLanguage == null,
                    onPressed: () => _act(
                      () => widget.controller.setSpokenLanguage(
                        widget.novel.id,
                        null,
                      ),
                    ),
                    child: const AppText('自动匹配'),
                  ),
                  for (final language in languages)
                    GlassTextButton(
                      key: ValueKey('listening-language-only-$language'),
                      selected: state.spokenLanguage == language,
                      onPressed: () => _act(
                        () => widget.controller.setSpokenLanguage(
                          widget.novel.id,
                          language,
                        ),
                      ),
                      child: AppText('仅朗读${readerLanguageLabel(language)}'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              AppText(
                '按段落语言匹配音色，不改变正文显示。没有对应语言的语音模型就跳过，不使用其他语言代读。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              ReaderValueSlider(
                sliderKey: const ValueKey('listening-speed'),
                label: '语速',
                value: state.speed,
                min: listeningMinimumSpeed,
                max: listeningMaximumSpeed,
                divisions: 50,
                format: (value) => '${value.toStringAsFixed(2)}×',
                onCommitted: (value) =>
                    _act(() => widget.controller.setSpeed(value)),
              ),
              Row(
                children: [
                  const Expanded(child: AppText('跟随朗读段落')),
                  AppControls.toggle(
                    context,
                    key: const ValueKey('listening-follow'),
                    value: state.follow,
                    onChanged: (value) =>
                        _act(() => widget.controller.setFollow(value)),
                  ),
                ],
              ),
              AppText(
                '手动滑动会暂停自动跟随；双击其他段落仍会平滑定位，持续跟读可在这里重新开启',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              const AppText(
                '睡眠定时',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Wrap(
                spacing: 4,
                children: [
                  for (final minutes in [15, 30, 60])
                    GlassTextButton(
                      onPressed: () => widget.controller.setSleep(
                        duration: Duration(minutes: minutes),
                      ),
                      child: AppText('$minutes 分钟'),
                    ),
                  GlassTextButton(
                    onPressed: () =>
                        widget.controller.setSleep(afterChapter: true),
                    child: const AppText('本章结束'),
                  ),
                  GlassTextButton(
                    onPressed: () => widget.controller.setSleep(),
                    child: const AppText('关闭定时'),
                  ),
                ],
              ),
              AppText(
                state.sleepAfterChapter
                    ? '将在本章结束后暂停'
                    : state.sleepUntil != null
                    ? '${state.sleepUntil!.hour.toString().padLeft(2, '0')}:${state.sleepUntil!.minute.toString().padLeft(2, '0')} 暂停'
                    : '当前未设置定时',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Divider(height: 28),
              const AppText(
                '音源与音色',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              AppControls.segments<ListeningSource>(
                context,
                groupValue: source,
                children: {
                  ListeningSource.edge: const AppText(
                    '自然在线',
                    textAlign: TextAlign.center,
                  ),
                  if (widget.controller.customSpeech != null)
                    ListeningSource.custom: const AppText(
                      '自定义',
                      textAlign: TextAlign.center,
                    ),
                  ListeningSource.system: const AppText(
                    '系统引擎',
                    textAlign: TextAlign.center,
                  ),
                },
                onValueChanged: (source) async {
                  if (source == ListeningSource.edge) {
                    await _voice(defaultEdgeVoice);
                  }
                  if (source == ListeningSource.system) await _systemEngine();
                  if (source == ListeningSource.custom) {
                    final config = widget.controller.customSpeech?.config;
                    if (config == null) {
                      await _configureCustom();
                    } else {
                      await _voice(config.voice);
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
              AppText(
                source == ListeningSource.system
                    ? '使用手机安装的 TTS 引擎，语音数据与联网方式由引擎管理。'
                    : source == ListeningSource.custom
                    ? '使用你配置的 Microsoft SSML 兼容接口。'
                    : 'Edge 神经网络音色 · 免费，无需登录。未缓存语段需联网生成；已生成语音可直接复用。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              GlassTextButton(
                key: const ValueKey('listening-system-engines'),
                onPressed: _systemEngine,
                child: const AppText('选择系统朗读引擎'),
              ),
              if (widget.controller.customSpeech != null)
                GlassTextButton(
                  key: const ValueKey('listening-custom-endpoint'),
                  onPressed: _configureCustom,
                  child: const AppText('配置自定义语音接口'),
                ),
              const SizedBox(height: 12),
              const AppText(
                '分语言音色',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final language in languages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassTextButton(
                    key: ValueKey('listening-language-voice-$language'),
                    onPressed: () => _languageVoice(language),
                    child: Row(
                      children: [
                        AppText(readerLanguageLabel(language)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: AppText(
                            state.voiceOverrides[language]?.label ?? '自动匹配',
                            textAlign: TextAlign.end,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(CupertinoIcons.chevron_forward, size: 14),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              AppText(
                '双击正在朗读的段落可暂停／继续，双击其他文字段落从那里听起。自动跳过插图和纯符号；个别语段合成失败后继续，连续失败时暂停提示。支持锁屏、耳机按键与后台听书。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      );
  static String _time(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _LanguageVoicePicker extends StatefulWidget {
  const _LanguageVoicePicker({
    required this.controller,
    required this.language,
    this.selected,
  });
  final ListeningController controller;
  final String language;
  final SpeechVoice? selected;
  @override
  State<_LanguageVoicePicker> createState() => _LanguageVoicePickerState();
}

class _LanguageVoicePickerState extends State<_LanguageVoicePicker> {
  late Future<List<SpeechVoice>> _voices;
  @override
  void initState() {
    super.initState();
    _voices = widget.controller.voicesForLanguage(widget.language);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .64,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: ArchiveSection(
                  title: '${readerLanguageLabel(widget.language)}音色',
                  code: 'AUDIO / LANGUAGE VOICE',
                ),
              ),
              GlassIconButton(
                icon: CupertinoIcons.xmark,
                label: '关闭音色选择',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<SpeechVoice>>(
            future: _voices,
            builder: (context, snapshot) {
              final voices = snapshot.data;
              final selectedAvailable =
                  voices?.any((voice) => voice.id == widget.selected?.id) ??
                  true;
              return ListView(
                key: const ValueKey('listening-language-voice-options'),
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                children: [
                  GlassTextButton(
                    key: const ValueKey('listening-language-voice-default'),
                    selected: widget.selected == null,
                    onPressed: () => Navigator.pop(context, (voice: null)),
                    child: const AppText('自动匹配'),
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.connectionState != ConnectionState.done)
                    const InlineSkeleton(width: double.infinity, height: 48),
                  if (snapshot.hasError) ...[
                    AppText(
                      snapshot.error is SpeechFailure
                          ? (snapshot.error as SpeechFailure).message
                          : '音色列表暂时不可用',
                    ),
                    GlassTextButton(
                      onPressed: () => setState(() {
                        _voices = widget.controller.voicesForLanguage(
                          widget.language,
                        );
                      }),
                      child: const AppText('重新检测'),
                    ),
                  ],
                  if (voices != null && voices.isEmpty)
                    AppText(
                      '没有可用的${readerLanguageLabel(widget.language)}音色，该语言将跳过。',
                    ),
                  if (!selectedAvailable && widget.selected != null)
                    const AppText(
                      '原选音色暂不可用，请重新选择或恢复自动匹配。',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  for (final voice in voices ?? const <SpeechVoice>[])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassTextButton(
                        key: ValueKey('listening-language-option-${voice.id}'),
                        selected: widget.selected?.id == voice.id,
                        onPressed: () => Navigator.pop(context, (voice: voice)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText(
                              voice.label,
                              style: const TextStyle(fontSize: 14),
                            ),
                            if (voice.source == ListeningSource.system)
                              AppText(
                                '${voice.locale} · ${voice.offline ? '可离线' : '需要网络'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

/// Short decoder handoffs keep the same line and height. Only a sustained wait
/// changes the status, so changing paragraphs never inserts/removes a skeleton.
class _ListeningTransportStatus extends StatefulWidget {
  const _ListeningTransportStatus({required this.phase});
  final ListeningPhase phase;
  @override
  State<_ListeningTransportStatus> createState() =>
      _ListeningTransportStatusState();
}

class _ListeningTransportStatusState extends State<_ListeningTransportStatus> {
  Timer? _timer;
  bool _waiting = false;
  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(_ListeningTransportStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) _update();
  }

  void _update() {
    _timer?.cancel();
    _waiting = false;
    if (widget.phase == ListeningPhase.preparing) {
      _timer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _waiting = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: AppText(
      _waiting
          ? '正在缓冲语音…'
          : widget.phase == ListeningPhase.paused
          ? '已暂停'
          : widget.phase == ListeningPhase.failed
          ? '播放暂未完成'
          : '正在朗读',
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// The current paragraph keeps its solid registration plane while paused too.
class ListeningParagraphHighlight extends StatelessWidget {
  const ListeningParagraphHighlight({
    super.key,
    required this.controller,
    required this.novelId,
    required this.chapter,
    required this.paragraph,
    required this.child,
    this.interactive = true,
    this.onDoubleTap,
  });
  final ListeningController controller;
  final int novelId, chapter, paragraph;
  final Widget child;
  final bool interactive;
  final Future<void> Function()? onDoubleTap;
  @override
  Widget build(BuildContext context) =>
      SelectedValueBuilder<
        ListeningSnapshot,
        ({bool own, bool current, bool playing})
      >(
        listenable: controller.snapshot,
        select: (state) {
          final own = state.active && state.novel?.id == novelId;
          final current =
              own &&
              state.chapter == chapter &&
              state.current?.paragraph == paragraph;
          return (
            own: own,
            current: current,
            playing: current && state.requestingPlayback,
          );
        },
        child: child,
        builder: (context, state, child) {
          final plane = CustomPaint(
            key: ValueKey('listening-highlight-$paragraph'),
            painter: _ListeningPlane(
              active: state.current,
              style: ReaderSpeechHighlightStyle.of(context),
            ),
            child: child,
          );
          if (!state.own || !interactive) return plane;
          void activate() {
            unawaited(
              (onDoubleTap?.call() ??
                      controller.paragraphDoubleTap(
                        novelId: novelId,
                        chapter: chapter,
                        paragraph: paragraph,
                      ))
                  .catchError((Object error) {
                    if (context.mounted) {
                      showNovelFeedback(
                        context,
                        error is SpeechFailure ? error.message : '听书操作暂未完成，请重试',
                      );
                    }
                  }),
            );
          }

          return Semantics(
            onTap: activate,
            hint: state.current
                ? (state.playing ? '双击暂停朗读' : '双击继续朗读')
                : '双击从这一段开始朗读',
            child: GestureDetector(
              key: ValueKey('listening-paragraph-gesture-$paragraph'),
              behavior: HitTestBehavior.translucent,
              excludeFromSemantics: true,
              onDoubleTap: activate,
              child: plane,
            ),
          );
        },
      );
}

class _ListeningPlane extends CustomPainter {
  const _ListeningPlane({required this.active, required this.style});
  final bool active;
  final ReaderSpeechHighlightStyle style;
  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    final rect = Rect.fromLTWH(-8, -3, size.width + 16, size.height + 6);
    style.paint(canvas, rect);
  }

  @override
  bool shouldRepaint(_ListeningPlane oldDelegate) =>
      active != oldDelegate.active || style != oldDelegate.style;
}
