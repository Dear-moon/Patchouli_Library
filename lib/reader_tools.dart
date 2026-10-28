import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_ui.dart';
import 'app_interactions.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'reader_annotation_editor.dart';
import 'reader_bookmark_excerpt.dart';
import 'local_platform.dart';
import 'reader_preferences.dart';
import 'font_settings_page.dart';
import 'glass_choices.dart';
import 'setting_menu.dart';
import 'book_documents.dart';
import 'local_books.dart' show isLocalBook;
import 'reader_languages.dart';
import 'bookmark_categories.dart';
import 'feature_pages.dart' show confirmNovelAction;

sealed class ReaderToolAction {
  const ReaderToolAction();
}

class ReaderSeekProgress extends ReaderToolAction {
  const ReaderSeekProgress(this.fraction);
  final double fraction;
}

class ReaderSeekBookProgress extends ReaderToolAction {
  const ReaderSeekBookProgress(this.chapter, this.fraction);
  final int chapter;
  final double fraction;
}

class ReaderOpenBookmark extends ReaderToolAction {
  const ReaderOpenBookmark(this.bookmark);
  final ReaderBookmark bookmark;
}

class ReaderEnterFocus extends ReaderToolAction {
  const ReaderEnterFocus();
}

class ReaderOpenFind extends ReaderToolAction {
  const ReaderOpenFind();
}

class ReaderStartAutoScroll extends ReaderToolAction {
  const ReaderStartAutoScroll();
}

class ReaderOpenIllustrations extends ReaderToolAction {
  const ReaderOpenIllustrations();
}

class ReaderOpenHandoff extends ReaderToolAction {
  const ReaderOpenHandoff();
}

class ReaderOpenListening extends ReaderToolAction {
  const ReaderOpenListening();
}

/// The chapter drawer owns scrubbing and text navigation; settings only owns
/// typography, behavior, bookmarks and audio.
class ReaderChapterProgress extends StatefulWidget {
  const ReaderChapterProgress({
    super.key,
    required this.position,
    required this.onSeek,
    required this.onFind,
    this.onPreview,
    this.onCommitted,
    this.onPreviewChanged,
    this.compact = false,
    this.chapterLabel,
    this.onPrevious,
    this.onNext,
    this.progressFraction,
  });
  final ReadingPosition? position;
  final ValueChanged<double> onSeek;
  final VoidCallback onFind;
  final ValueChanged<double>? onPreview, onCommitted;
  final ValueChanged<bool>? onPreviewChanged;
  final bool compact;
  final String? chapterLabel;
  final VoidCallback? onPrevious, onNext;

  /// New compact usage may adapt source coordinates; the legacy drawer keeps
  /// its saved pixel fraction and does not require a source anchor.
  final double? progressFraction;
  @override
  State<ReaderChapterProgress> createState() => _ReaderChapterProgressState();
}

class _ReaderChapterProgressState extends State<ReaderChapterProgress> {
  bool _adjusting = false;
  final _hint = OverlayPortalController();
  final _hintLink = LayerLink();
  late final _preview = ValueNotifier<double>(
    widget.progressFraction ?? widget.position?.fraction ?? 0,
  );

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Widget _progressHint(BuildContext context) => Positioned(
    left: 0,
    top: 0,
    child: CompositedTransformFollower(
      link: _hintLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topCenter,
      followerAnchor: Alignment.bottomCenter,
      offset: const Offset(0, -10),
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width - 32,
            ),
            child: ValueListenableBuilder<double>(
              valueListenable: _preview,
              builder: (context, value, _) => LiquidGlass(
                key: const ValueKey('reader-progress-drag-hint'),
                radius: 24,
                blur: GlassAppearance.of(context).blur,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: AppText(
                        '${widget.chapterLabel ?? '本章'} · ${(value * 100).round()}%',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => widget.compact
      ? ControlMaterialScope.chrome(
          child: OverlayPortal(
            controller: _hint,
            overlayChildBuilder: _progressHint,
            child: CompositedTransformTarget(
              link: _hintLink,
              child: LiquidGlass(
                radius: 24,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    GlassIconButton(
                      key: const ValueKey('reader-previous-chapter'),
                      icon: CupertinoIcons.backward_end,
                      label: '上一章',
                      liveGlass: false,
                      transparent: true,
                      haptic: HapticCue.pageTurn,
                      onPressed: widget.onPrevious,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: ReaderValueSlider(
                        sliderKey: const ValueKey(
                          'reader-chrome-progress-slider',
                        ),
                        label: '本章进度',
                        inline: true,
                        showLabels: false,
                        value:
                            widget.progressFraction ??
                            widget.position?.fraction ??
                            0,
                        reconcileValue: widget.progressFraction != null,
                        min: 0,
                        max: 1,
                        divisions: 500,
                        hapticSteps: 100,
                        format: (value) => '${(value * 100).round()}%',
                        onPreview: (value) {
                          _preview.value = value;
                          widget.onPreview?.call(value);
                        },
                        onCommitted:
                            widget.position == null &&
                                widget.progressFraction == null
                            ? null
                            : widget.onCommitted ?? widget.onSeek,
                        onInteractionChanged: (active) {
                          if (active) {
                            _preview.value =
                                widget.progressFraction ??
                                widget.position?.fraction ??
                                0;
                            _hint.show();
                          } else {
                            _hint.hide();
                          }
                          widget.onPreviewChanged?.call(active);
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    GlassIconButton(
                      key: const ValueKey('reader-next-chapter'),
                      icon: CupertinoIcons.forward_end,
                      label: '下一章',
                      liveGlass: false,
                      transparent: true,
                      haptic: HapticCue.pageTurn,
                      onPressed: widget.onNext,
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
      : Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CustomPaint(
                painter: _AdjustmentPlate(
                  _adjusting
                      ? Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: .98)
                      : Colors.transparent,
                ),
                child: ReaderValueSlider(
                  sliderKey: const ValueKey('reader-progress-slider'),
                  label: '本章进度',
                  value: widget.position?.fraction ?? 0,
                  min: 0,
                  max: 1,
                  divisions: 500,
                  hapticSteps: 100,
                  format: (v) => '${(v * 100).round()}%',
                  onPreview: widget.onPreview,
                  onCommitted: widget.position == null
                      ? null
                      : widget.onCommitted ?? widget.onSeek,
                  onInteractionChanged: (active) {
                    setState(() => _adjusting = active);
                    widget.onPreviewChanged?.call(active);
                  },
                ),
              ),
              Visibility(
                visible: !_adjusting,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        GlassTextButton(
                          onPressed: widget.position == null
                              ? null
                              : () => widget.onSeek(0),
                          child: const AppText('回到章首'),
                        ),
                        GlassTextButton(
                          onPressed: widget.position == null
                              ? null
                              : () => widget.onSeek(1),
                          child: const AppText('跳至章末'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GlassTextButton(
                      key: const ValueKey('reader-open-find'),
                      onPressed: widget.position == null ? null : widget.onFind,
                      child: const AppText('章内查找'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
}

/// A bounded settings sheet. Typography drafts preview the article while
/// preferences are committed once, when the gesture ends.
enum ReaderToolsScope { all, appearance, listening, operations, bookmarks }

class ReaderTools extends StatefulWidget {
  const ReaderTools({
    super.key,
    required this.novel,
    required this.state,
    required this.position,
    required this.onAddBookmark,
    required this.onFontSize,
    required this.onLineHeight,
    required this.onReset,
    this.initialBookmarks = false,
    this.onFontPreview,
    this.onLineHeightPreview,
    this.onPreviewChanged,
    this.onPreferencesChanged,
    this.onIllustrations,
    this.listeningBuilder,
    this.initialTab,
    this.scope = ReaderToolsScope.all,
    this.canHandoff = false,
    this.onStyleScopeChanged,
    this.onReaderTypefaceChanged,
    this.languages = const {},
    this.onHiddenLanguagesChanged,
    this.rangeContextResolver,
  });
  final Novel novel;
  final LibraryState state;
  final ReadingPosition? position;
  final Future<ReaderBookmark?> Function() onAddBookmark;
  final ValueChanged<double> onFontSize;
  final ValueChanged<double> onLineHeight;
  final VoidCallback onReset;
  final VoidCallback? onIllustrations;
  final bool initialBookmarks;
  final WidgetBuilder? listeningBuilder;
  final String? initialTab;
  final ReaderToolsScope scope;
  final bool canHandoff;
  final ValueChanged<double>? onFontPreview, onLineHeightPreview;
  final ValueChanged<bool>? onPreviewChanged;
  final void Function(ReaderPreferences, bool persist)? onPreferencesChanged;
  final Future<void> Function(bool)? onStyleScopeChanged;
  final Future<void> Function(String)? onReaderTypefaceChanged;
  final Set<String> languages;
  final Future<void> Function(Set<String>, {String? onlyLanguage})?
  onHiddenLanguagesChanged;
  final ReaderAnnotationContextResolver? rangeContextResolver;

  @override
  State<ReaderTools> createState() => _ReaderToolsState();
}

class _ReaderControlsChanges extends ChangeNotifier {
  void refresh() => notifyListeners();
}

class _ReaderToolsState extends State<ReaderTools>
    with SingleTickerProviderStateMixin {
  final _controlsChanges = _ReaderControlsChanges();
  final _bodyKey = GlobalKey();
  late final AnimationController _expand;
  Rect? _categoryOrigin;

  @override
  void initState() {
    super.initState();
    _expand = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1,
    );
    widget.state.readerSettingsChanges.addListener(_settingsChanged);
    if (widget.scope == ReaderToolsScope.listening) {
      _category = 'listening';
    } else if (widget.scope == ReaderToolsScope.operations) {
      _category = 'turn';
    } else if (widget.scope == ReaderToolsScope.bookmarks) {
      _category = 'bookmarks';
    } else if (widget.initialTab != null || widget.initialBookmarks) {
      _category = switch (widget.initialTab) {
        'listening' => 'listening',
        'behavior' => 'turn',
        'layout' => 'page',
        'screen' => 'page',
        final String category => category,
        _ => 'bookmarks',
      };
    }
  }

  void _settingsChanged() {
    // The active slider owns its draft; the other controls are hidden during
    // article preview. Catch them up once on release instead of rebuilding
    // every glass choice for every pointer sample.
    if (_activeAdjustment == null) _controlsChanges.refresh();
  }

  @override
  void didUpdateWidget(ReaderTools oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.readerSettingsChanges.removeListener(_settingsChanged);
      widget.state.readerSettingsChanges.addListener(_settingsChanged);
    }
  }

  @override
  void dispose() {
    widget.state.readerSettingsChanges.removeListener(_settingsChanged);
    _controlsChanges.dispose();
    _expand.dispose();
    super.dispose();
  }

  static const _systemControls = MethodChannel(
    'org.mewx.wenku8/reader_controls',
  );
  late final Future<bool> _floatingNavigation = () async {
    if (!LocalPlatform.android) return false;
    try {
      return (await _systemControls.invokeMapMethod<String, Object?>(
            'navigationCapabilities',
          ))?['systemFloatingNavigation'] ==
          true;
    } catch (_) {
      return false;
    }
  }();
  ReaderPreferences get _readerPreferences =>
      widget.state.readerPreferencesFor(widget.novel.id);
  double get _fontSize => widget.state.readerFontSizeFor(widget.novel.id);
  double get _lineHeight => widget.state.readerLineHeightFor(widget.novel.id);
  bool _changingScope = false;
  bool _changingLanguages = false;
  bool _backgroundExpanded = false, _backgroundBusy = false;
  Future<List<String>>? _backgrounds;
  final _backgroundFiles = <String, Future<File?>>{};
  String? _category;
  bool _adding = false;
  String? _storageError;
  Key? _activeAdjustment;
  String _marginEdge = '左右';

  void _toggleBackgrounds() {
    setState(() {
      _backgroundExpanded = !_backgroundExpanded;
      // Opening settings must not scan a directory for a collapsed section.
      // Keep the result while collapsing so the existing reverse animation
      // still contains its thumbnails.
      if (_backgroundExpanded) _backgrounds ??= widget.state.backgrounds.list();
    });
  }

  Future<void> _importBackground() async {
    if (_backgroundBusy) return;
    setState(() => _backgroundBusy = true);
    final documents = BookDocuments();
    try {
      final selected = await documents.pickImage();
      if (selected == null) return;
      try {
        final id = await widget.state.backgrounds.import(selected.path!);
        if (!mounted) return;
        _preferences(_readerPreferences.copyWith(backgroundImage: id));
        setState(() {
          _backgrounds = widget.state.backgrounds.list();
        });
      } finally {
        await documents.releaseBooks([selected]);
      }
    } catch (e) {
      if (mounted) {
        showNovelFeedback(
          context,
          e is FormatException ? e.message : '背景导入未完成，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _backgroundBusy = false);
    }
  }

  Future<void> _removeBackground() async {
    final id = _readerPreferences.backgroundImage;
    if (id == null || _backgroundBusy) return;
    if (!await confirmNovelAction(
      context,
      title: '删除这张阅读背景？',
      message: '使用它的书籍恢复纯色背景，原始图片不受影响。',
      confirmLabel: '删除背景',
      reduceMotion: widget.state.reduceMotion,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _backgroundBusy = true);
    try {
      await widget.state.removeReaderBackground(id);
      if (mounted) {
        setState(() {
          _backgrounds = widget.state.backgrounds.list();
        });
      }
    } catch (_) {
      if (mounted) showNovelFeedback(context, '背景删除未完成，请重试');
    } finally {
      if (mounted) setState(() => _backgroundBusy = false);
    }
  }

  List<Widget> _backgroundOptions() => [
    _adjustment(
      GlassTextButton(
        key: const ValueKey('reader-background-options'),
        onPressed: _toggleBackgrounds,
        child: Row(
          children: [
            const ArchiveIcon(CupertinoIcons.photo, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: AppText(
                '阅读背景',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            ArchiveIcon(
              _backgroundExpanded
                  ? CupertinoIcons.chevron_up
                  : CupertinoIcons.chevron_down,
              size: 14,
            ),
          ],
        ),
      ),
    ),
    AnimatedOptionSection(
      expanded: _backgroundExpanded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _adjustment(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                FutureBuilder<List<String>>(
                  future: _backgrounds,
                  builder: (context, snapshot) => SizedBox(
                    height: 76,
                    child: AppScrollHaptics(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: 1 + (snapshot.data?.length ?? 0),
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final id = index == 0
                              ? null
                              : snapshot.data![index - 1];
                          return SizedBox(
                            width: 64,
                            child: GlassTextButton(
                              key: ValueKey(
                                'reader-background-${id ?? 'plain'}',
                              ),
                              selected:
                                  _readerPreferences.backgroundImage == id,
                              onPressed: _backgroundBusy
                                  ? null
                                  : () => _preferences(
                                      id == null
                                          ? _readerPreferences.copyWith(
                                              clearBackground: true,
                                            )
                                          : _readerPreferences.copyWith(
                                              backgroundImage: id,
                                            ),
                                    ),
                              child: id == null
                                  ? const AppText(
                                      '纯色',
                                      style: TextStyle(fontSize: 12),
                                    )
                                  : FutureBuilder(
                                      future: _backgroundFiles.putIfAbsent(
                                        id,
                                        () => widget.state.backgrounds.file(id),
                                      ),
                                      builder: (context, file) =>
                                          file.data == null
                                          ? const ArchiveIcon(
                                              CupertinoIcons.photo,
                                              size: 20,
                                            )
                                          : ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: Image.file(
                                                file.data!,
                                                width: 44,
                                                height: 54,
                                                fit: BoxFit.cover,
                                                cacheWidth: 132,
                                                errorBuilder: (_, _, _) =>
                                                    const ArchiveIcon(
                                                      CupertinoIcons.photo,
                                                      size: 20,
                                                    ),
                                              ),
                                            ),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: GlassTextButton(
                        key: const ValueKey('reader-import-background'),
                        onPressed: _backgroundBusy ? null : _importBackground,
                        child: AppText(
                          _backgroundBusy ? '正在处理图片' : '导入背景图片',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    if (_readerPreferences.backgroundImage != null)
                      GlassIconButton(
                        icon: CupertinoIcons.trash,
                        label: '删除当前背景',
                        onPressed: _backgroundBusy ? null : _removeBackground,
                      ),
                  ],
                ),
              ],
            ),
          ),
          AnimatedOptionSection(
            expanded: _readerPreferences.backgroundImage != null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _adjustment(
                  ReaderChoicePicker<BoxFit>(
                    name: 'reader-background-fit',
                    label: '图片布局',
                    value: _readerPreferences.backgroundFit,
                    options: const {BoxFit.cover: '填满', BoxFit.contain: '完整'},
                    onChanged: (fit) => _preferences(
                      _readerPreferences.copyWith(backgroundFit: fit),
                    ),
                  ),
                ),
                _adjustment(
                  ReaderValueSlider(
                    sliderKey: const ValueKey('reader-background-opacity'),
                    label: '背景浓度',
                    value: _readerPreferences.backgroundOpacity,
                    min: .05,
                    max: 1,
                    format: (v) => '${(v * 100).round()}%',
                    onPreview: (v) => _preferences(
                      _readerPreferences.copyWith(backgroundOpacity: v),
                      persist: false,
                    ),
                    onCommitted: (v) => _preferences(
                      _readerPreferences.copyWith(backgroundOpacity: v),
                    ),
                    onInteractionChanged: (v) => _preview(
                      const ValueKey('reader-background-opacity'),
                      v,
                    ),
                  ),
                  const ValueKey('reader-background-opacity'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ];
  double _marginValue(ReaderPreferences p) => switch (_marginEdge) {
    '左' => p.leftMargin,
    '右' => p.rightMargin,
    '上' => p.marginTop,
    '下' => p.marginBottom,
    _ => p.bindingMargin,
  };
  ReaderPreferences _withMargin(double v) {
    final p = _readerPreferences;
    return switch (_marginEdge) {
      '左' => p.copyWith(marginLeft: v),
      '右' => p.copyWith(marginRight: v),
      '上' => p.copyWith(marginTop: v),
      '下' => p.copyWith(marginBottom: v),
      _ => p.copyWith(margin: v),
    };
  }

  void _preferences(ReaderPreferences value, {bool persist = true}) {
    if (widget.onPreferencesChanged != null) {
      widget.onPreferencesChanged!(value, persist);
    } else {
      unawaited(
        widget.state
            .setReaderPreferences(
              value,
              persist: persist,
              bookId: widget.novel.id,
            )
            .catchError((Object _) {
              if (mounted) showNovelFeedback(context, '阅读偏好保存失败，请重试');
            }),
      );
    }
  }

  Future<void> _changeStyleScope(bool book) async {
    if (_changingScope) return;
    setState(() => _changingScope = true);
    try {
      if (widget.onStyleScopeChanged case final change?) {
        await change(book);
      } else {
        await widget.state.setIndependentReaderStyle(widget.novel.id, book);
      }
    } catch (_) {
      if (mounted) showNovelFeedback(context, '排版范围未保存，请重试');
    } finally {
      if (mounted) setState(() => _changingScope = false);
    }
  }

  Future<void> _showLanguage(String? code) async {
    if (_changingLanguages) return;
    final next = <String>{
      if (code != null)
        for (final language in widget.languages)
          if (language != code) language,
    };
    setState(() => _changingLanguages = true);
    try {
      if (widget.onHiddenLanguagesChanged case final change?) {
        await change(next, onlyLanguage: code);
      } else {
        await widget.state.setHiddenReaderLanguages(
          widget.novel.id,
          next,
          onlyLanguage: code,
        );
      }
    } catch (_) {
      if (mounted) showNovelFeedback(context, '语言显示设置未保存，请重试');
    } finally {
      if (mounted) setState(() => _changingLanguages = false);
    }
  }

  Widget _languageOptions() {
    final hidden = widget.state.hiddenReaderLanguagesFor(widget.novel.id);
    final languages = widget.languages.toList();
    final only = widget.state.onlyReaderLanguageFor(widget.novel.id);
    final visible = languages
        .where((code) => only == null ? !hidden.contains(code) : code == only)
        .toList();
    return Padding(
      key: const ValueKey('reader-book-languages'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppText(
            '本书语言',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GlassTextButton(
                key: const ValueKey('reader-language-all'),
                selected: visible.length == languages.length,
                onPressed: _changingLanguages
                    ? null
                    : () => _showLanguage(null),
                child: const AppText('全部语言'),
              ),
              for (final code in languages)
                GlassTextButton(
                  key: ValueKey('reader-language-only-$code'),
                  selected: visible.length == 1 && visible.single == code,
                  onPressed: _changingLanguages
                      ? null
                      : () => _showLanguage(code),
                  child: AppText('仅${readerLanguageLabel(code)}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _preview(Key key, bool active) {
    if (!mounted) return;
    setState(() => _activeAdjustment = active ? key : null);
    widget.onPreviewChanged?.call(active);
  }

  Widget _adjustment(Widget child, [Key? key]) {
    final active = _activeAdjustment != null;
    final visible = !active || key == _activeAdjustment;
    return Visibility(
      visible: visible,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: CustomPaint(
        painter: _AdjustmentPlate(
          active && visible
              ? Theme.of(context).colorScheme.surface.withValues(alpha: .98)
              : Colors.transparent,
        ),
        child: child,
      ),
    );
  }

  Future<void> _add() async {
    if (_adding || widget.position == null) return;
    setState(() {
      _adding = true;
      _storageError = null;
    });
    try {
      final mark = await widget.onAddBookmark();
      if (mounted && mark == null) {
        setState(() => _storageError = '阅读位置正在恢复，请稍后再试');
      }
    } catch (_) {
      if (mounted) setState(() => _storageError = '书签保存失败，请重试');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _editBookmark(ReaderBookmark mark) async {
    setState(() => _storageError = null);
    try {
      await showReaderAnnotationEditor(
        context,
        state: widget.state,
        novelId: widget.novel.id,
        novel: widget.novel,
        bookmark: mark,
        rangeContextResolver: widget.rangeContextResolver,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _storageError = '书签与批注暂时无法打开，请重试');
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          !constraints.hasBoundedHeight || constraints.maxHeight < 260;
      final detail = _category != null;
      final nested =
          detail &&
          widget.scope != ReaderToolsScope.listening &&
          widget.scope != ReaderToolsScope.operations &&
          widget.scope != ReaderToolsScope.bookmarks;
      final title = widget.scope == ReaderToolsScope.operations
          ? '操作'
          : detail
          ? _categoryTitle(_category!)
          : _rootTitle;
      final body = AnimatedBuilder(
        animation: _controlsChanges,
        builder: (context, _) => KeyedSubtree(
          key: ValueKey('reader-settings-content-${_category ?? 'grid'}'),
          child: switch (_category) {
            null => _categoryGrid(context, compact: compact),
            'bookmarks' => _bookmarks(context),
            'listening' =>
              widget.listeningBuilder?.call(context) ?? const SizedBox.shrink(),
            'screen' => _settingsItems(
              _behaviorItems(context, 'screen'),
              compact: compact,
            ),
            _ => _layout(context, compact: compact, category: _category!),
          },
        ),
      );
      final contents = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _adjustment(
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Row(
                children: [
                  if (nested)
                    GlassIconButton(
                      key: const ValueKey('reader-settings-back'),
                      icon: CupertinoIcons.chevron_back,
                      label: widget.scope == ReaderToolsScope.appearance
                          ? '返回外观分类'
                          : '返回阅读设置分类',
                      onPressed: _returnCategories,
                    )
                  else
                    const SizedBox(width: 10),
                  Expanded(
                    child: AppText(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_category == 'bookmarks')
                    GlassIconButton(
                      key: const ValueKey('reader-add-bookmark'),
                      icon: CupertinoIcons.add,
                      label: _adding ? '正在保存书签' : '添加当前位置书签',
                      liveGlass: false,
                      transparent: true,
                      onPressed: _adding || widget.position == null
                          ? null
                          : _add,
                    ),
                  GlassIconButton(
                    key: const ValueKey('reader-settings-close'),
                    icon: CupertinoIcons.xmark,
                    label: '关闭$title',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
          if (compact)
            SizedBox(key: _bodyKey, child: _animatedBody(body))
          else
            Flexible(
              child: SizedBox(key: _bodyKey, child: _animatedBody(body)),
            ),
        ],
      );
      final panel = compact
          ? SingleChildScrollView(
              key: const ValueKey('reader-settings-scroll'),
              primary: false,
              child: contents,
            )
          : contents;
      return PopScope<ReaderToolAction>(
        canPop: !nested,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && nested) {
            _returnCategories();
          }
        },
        child:
            widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context)
            ? panel
            : AnimatedSize(
                duration: const Duration(milliseconds: 320),
                // The sheet itself stays bottom-anchored. Keep its header at
                // the visible top while the body grows; bottom alignment would
                // paint the header above AnimatedSize's clip during expansion.
                alignment: Alignment.topCenter,
                curve: Curves.easeOutCubic,
                child: panel,
              ),
      );
    },
  );

  static const _categories = <(String, String, IconData)>[
    ('font', '字体', CupertinoIcons.textformat),
    ('paragraph', '段落', CupertinoIcons.text_alignleft),
    ('page', '屏幕', CupertinoIcons.rectangle),
    ('theme', '主题', CupertinoIcons.paintbrush),
    ('turn', '翻页', CupertinoIcons.arrow_left_right),
    ('listening', '听书', CupertinoIcons.headphones),
    ('bookmarks', '书签', CupertinoIcons.bookmark),
  ];

  String get _rootTitle =>
      widget.scope == ReaderToolsScope.appearance ? '外观' : '阅读设置';

  List<(String, String, IconData)> get _visibleCategories =>
      widget.scope == ReaderToolsScope.appearance
      ? _categories
            .where(
              (item) => const {
                'font',
                'paragraph',
                'page',
                'theme',
              }.contains(item.$1),
            )
            .toList()
      : _categories;

  String _categoryTitle(String id) =>
      _categories.where((item) => item.$1 == id).firstOrNull?.$2 ?? '阅读设置';

  void _returnCategories() {
    _expand.stop();
    setState(() {
      _category = null;
      _activeAdjustment = null;
    });
    widget.onPreviewChanged?.call(false);
  }

  void _openCategory(String id, BuildContext tileContext) {
    final tile = tileContext.findRenderObject();
    _categoryOrigin = tile is RenderBox
        ? tile.localToGlobal(Offset.zero) & tile.size
        : null;
    setState(() => _category = id);
    if (widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      _expand.value = 1;
    } else {
      _expand.forward(from: 0);
    }
  }

  Widget _categoryGrid(BuildContext context, {required bool compact}) {
    final p = _readerPreferences;
    final categories = _visibleCategories;
    final summaries = <String, String>{
      'font': '${_fontSize.round()} pt · ${p.textWeight.label}',
      'paragraph': '${_lineHeight.toStringAsFixed(2)} 倍行距',
      'page': '页边距 · 状态栏 · 阅读信息',
      'theme': p.paper.label,
      'turn': p.mode.label,
      'screen': p.hideSystemStatus ? '隐藏状态栏' : '显示状态栏',
      'listening': widget.listeningBuilder == null ? '当前不可用' : '语音 · 播放设置',
      'bookmarks': '${widget.state.bookmarksFor(widget.novel.id).length} 个已保存',
    };
    return _settingsItems(
      [
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
            // The real sheet has safe-area/margin insets beyond the viewport.
            // Keep a two-character heading on one line instead of shrinking it.
            final minimumCardWidth =
                MediaQuery.textScalerOf(context).scale(16) * 2 + 56;
            var columns = constraints.maxWidth >= 620 ? 4 : 2;
            while (columns > 1 &&
                (constraints.maxWidth - (columns - 1) * 10) / columns <
                    minimumCardWidth) {
              columns = columns == 4 ? 2 : 1;
            }
            return GridView.builder(
              key: const ValueKey('reader-settings-category-grid'),
              // The sheet/list already owns its insets. Inheriting the reader's
              // system padding here leaves a second status-bar-sized gap.
              padding: EdgeInsets.zero,
              primary: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: categories.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 104 + math.max(0, textScale - 1) * 64,
              ),
              itemBuilder: (context, index) {
                final item = categories[index];
                final enabled =
                    item.$1 != 'listening' || widget.listeningBuilder != null;
                return Builder(
                  builder: (tileContext) => JellyTapSurface(
                    key: ValueKey('reader-settings-category-${item.$1}'),
                    onTap: enabled
                        ? () => _openCategory(item.$1, tileContext)
                        : null,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: enabled ? .42 : .22),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ArchiveIcon(item.$3, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppText(
                                    item.$2,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            AppText(
                              summaries[item.$1]!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
      compact: compact,
      shrinkWrap: true,
    );
  }

  Widget _animatedBody(Widget child) {
    if (_category == null ||
        widget.state.reduceMotion ||
        MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return AnimatedBuilder(
      animation: _expand,
      child: child,
      builder: (context, child) {
        final progress = Curves.easeOutCubic.transform(_expand.value);
        return ClipPath(
          key: const ValueKey('reader-settings-category-reveal'),
          clipper: _CategoryRevealClipper(_categoryOrigin, _bodyKey, progress),
          child: Opacity(opacity: .35 + progress * .65, child: child),
        );
      },
    );
  }

  Widget _settingsItems(
    List<Widget> children, {
    required bool compact,
    bool shrinkWrap = false,
  }) {
    const padding = EdgeInsets.fromLTRB(24, 4, 24, 24);
    if (compact) {
      return Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }
    // Only visible controls take part in layout/paint. A single scroll-view
    // Column also laid out every offscreen slider and glass choice on entry.
    return ListView(
      key: const ValueKey('reader-settings-scroll'),
      primary: false,
      shrinkWrap: shrinkWrap,
      padding: padding,
      children: children,
    );
  }

  Widget _layout(
    BuildContext context, {
    required bool compact,
    required String category,
  }) => _settingsItems([
    if (category == 'page')
      _adjustment(
        GlassChoiceGroup<String>(
          enabled: !_changingScope,
          name: 'reader-style-scope',
          label: '排版范围',
          value: widget.state.independentReaderStyle(widget.novel.id)
              ? 'book'
              : 'shared',
          options: const {'shared': '通用', 'book': '本书'},
          optionName: (value) => value,
          labelSize: 14,
          optionSize: 12,
          onChanged: (value) => _changeStyleScope(value == 'book'),
        ),
      ),
    if (category == 'turn' || category == 'theme')
      _adjustment(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (category == 'turn')
              ReaderChoicePicker<ReaderMode>(
                name: 'reader-mode',
                label: '阅读方式',
                value: _readerPreferences.mode,
                options: {
                  for (final mode in ReaderMode.values) mode: mode.label,
                },
                onChanged: (mode) =>
                    _preferences(_readerPreferences.copyWith(mode: mode)),
              ),
            if (category == 'turn')
              AnimatedOptionSection(
                expanded: _readerPreferences.mode == ReaderMode.vertical,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppText(
                      '文字由上往下，列由右往左；向右滑动翻到下一页。',
                      style: TextStyle(fontSize: 12, height: 1.6),
                    ),
                    ReaderChoicePicker<ReaderVerticalLatinOrientation>(
                      name: 'reader-vertical-latin-orientation',
                      label: '英数方向',
                      value: _readerPreferences.verticalLatinOrientation,
                      options: {
                        for (final direction
                            in ReaderVerticalLatinOrientation.values)
                          direction: direction.label,
                      },
                      onChanged: (direction) => _preferences(
                        _readerPreferences.copyWith(
                          verticalLatinOrientation: direction,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (category == 'turn')
              AnimatedOptionSection(
                expanded: _readerPreferences.mode.paginated,
                child: ReaderChoicePicker<ReaderPageEffect>(
                  name: 'reader-page-effect',
                  label: '翻页效果',
                  value: _readerPreferences.pageEffect,
                  options: {
                    for (final effect in ReaderPageEffect.values)
                      effect: effect.label,
                  },
                  onChanged: (effect) => _preferences(
                    _readerPreferences.copyWith(pageEffect: effect),
                  ),
                ),
              ),
            if (category == 'turn')
              AnimatedOptionSection(
                expanded:
                    _readerPreferences.mode.paginated &&
                    _readerPreferences.pageEffect != ReaderPageEffect.none,
                child: ReaderChoicePicker<ReaderPageSpeed>(
                  name: 'reader-page-speed',
                  label: '翻页速度',
                  value: _readerPreferences.pageSpeed,
                  options: {
                    for (final speed in ReaderPageSpeed.values)
                      speed: speed.label,
                  },
                  onChanged: (speed) => _preferences(
                    _readerPreferences.copyWith(pageSpeed: speed),
                  ),
                ),
              ),
            if (category == 'theme')
              ReaderChoicePicker<ReaderPaper>(
                name: 'reader-paper',
                label: '阅读配色',
                value: _readerPreferences.paper,
                options: {
                  for (final paper in ReaderPaper.values) paper: paper.label,
                },
                onChanged: (paper) =>
                    _preferences(_readerPreferences.copyWith(paper: paper)),
              ),
          ],
        ),
      ),
    if (category == 'font' && widget.languages.length > 1)
      _adjustment(_languageOptions()),
    if (category == 'theme') ..._backgroundOptions(),
    if (category == 'font')
      _adjustment(
        GlassTextButton(
          key: const ValueKey('reader-font-choice'),
          onPressed: () => pushNovelPage<void>(
            context,
            FontSettingsPage(
              state: widget.state,
              readerOnly: true,
              bookId: widget.novel.id,
              onReaderTypefaceChanged: widget.onReaderTypefaceChanged,
            ),
            reduceMotion: widget.state.reduceMotion,
          ),
          child: Row(
            children: [
              const ArchiveIcon(CupertinoIcons.textformat, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: AppText(
                  '阅读字体',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              const ArchiveIcon(CupertinoIcons.chevron_forward, size: 14),
            ],
          ),
        ),
      ),
    if (category == 'theme')
      AnimatedOptionSection(
        expanded: _readerPreferences.darkPaper(
          Theme.of(context).brightness == Brightness.dark,
        ),
        child: _adjustment(
          ReaderValueSlider(
            sliderKey: const ValueKey('reader-night-text-brightness'),
            label: '夜读文字亮度',
            value: _readerPreferences.nightTextBrightness,
            min: .35,
            max: 1,
            format: (v) => '${(v * 100).round()}%',
            onPreview: (v) => _preferences(
              _readerPreferences.copyWith(nightTextBrightness: v),
              persist: false,
            ),
            onCommitted: (v) => _preferences(
              _readerPreferences.copyWith(nightTextBrightness: v),
            ),
            onInteractionChanged: (v) =>
                _preview(const ValueKey('reader-night-text-brightness'), v),
          ),
          const ValueKey('reader-night-text-brightness'),
        ),
      ),
    if (category == 'font')
      _adjustment(
        LanguageSettingMenu(
          key: const ValueKey('reader-language'),
          state: widget.state,
        ),
      ),
    if (category == 'font')
      _adjustment(
        ReaderValueSlider(
          sliderKey: const ValueKey('reader-font-slider'),
          label: '字体大小',
          value: _fontSize,
          min: minimumReaderFontSize,
          max: maximumReaderFontSize,
          divisions: (maximumReaderFontSize - minimumReaderFontSize).round(),
          format: (value) => '${value.round()} pt',
          onCommitted: widget.onFontSize,
          onPreview: widget.onFontPreview,
          onInteractionChanged: (value) =>
              _preview(const ValueKey('reader-font-slider'), value),
        ),
        const ValueKey('reader-font-slider'),
      ),
    if (category == 'paragraph')
      _adjustment(
        ReaderValueSlider(
          sliderKey: const ValueKey('reader-line-height-slider'),
          label: _readerPreferences.mode == ReaderMode.vertical ? '列距' : '行距',
          value: _lineHeight,
          min: 1.3,
          max: 2.2,
          format: (value) => '${value.toStringAsFixed(2)} 倍',
          onCommitted: widget.onLineHeight,
          onPreview: widget.onLineHeightPreview,
          onInteractionChanged: (value) =>
              _preview(const ValueKey('reader-line-height-slider'), value),
        ),
        const ValueKey('reader-line-height-slider'),
      ),
    if (category == 'page')
      _adjustment(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            AppControls.segments<String>(
              context,
              groupValue: _marginEdge,
              children: {
                for (final edge in ['左右', '左', '右', '上', '下'])
                  edge: AppText(
                    edge,
                    key: ValueKey('reader-margin-edge-$edge'),
                    style: const TextStyle(fontSize: 12),
                  ),
              },
              onValueChanged: (edge) {
                if (edge != null) setState(() => _marginEdge = edge);
              },
            ),
            ReaderValueSlider(
              key: ValueKey('reader-margin-control-$_marginEdge'),
              sliderKey: const ValueKey('reader-margin-slider'),
              label: '页边距 · $_marginEdge',
              value: _marginValue(_readerPreferences),
              min: 0,
              max: 80,
              divisions: 40,
              format: (v) => '${v.round()} px',
              onPreview: (v) => _preferences(_withMargin(v), persist: false),
              onInteractionChanged: (v) =>
                  _preview(const ValueKey('reader-margin-slider'), v),
              onCommitted: (v) => _preferences(_withMargin(v)),
            ),
          ],
        ),
        const ValueKey('reader-margin-slider'),
      ),
    if (category == 'paragraph')
      _adjustment(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReaderValueSlider(
              sliderKey: const ValueKey('reader-paragraph-gap-slider'),
              label: '段落间距',
              value: _readerPreferences.paragraphGap,
              min: 0,
              max: 32,
              divisions: 16,
              format: (v) => _readerPreferences.paragraphGapOverride
                  ? '${v.round()} px'
                  : '原书',
              onPreview: (v) => _preferences(
                _readerPreferences.copyWith(
                  paragraphGap: v,
                  paragraphGapOverride: true,
                ),
                persist: false,
              ),
              onInteractionChanged: (v) =>
                  _preview(const ValueKey('reader-paragraph-gap-slider'), v),
              onCommitted: (v) => _preferences(
                _readerPreferences.copyWith(
                  paragraphGap: v,
                  paragraphGapOverride: true,
                ),
              ),
            ),
            Visibility(
              visible: _activeAdjustment == null,
              maintainSize: true,
              maintainState: true,
              maintainAnimation: true,
              child: Align(
                alignment: Alignment.centerRight,
                child: GlassTextButton(
                  key: const ValueKey('reader-paragraph-gap-original'),
                  compact: true,
                  onPressed: _readerPreferences.paragraphGapOverride
                      ? () => _preferences(
                          _readerPreferences.copyWith(
                            paragraphGap: 12,
                            paragraphGapOverride: false,
                          ),
                        )
                      : null,
                  child: const AppText('恢复原书段距'),
                ),
              ),
            ),
          ],
        ),
        const ValueKey('reader-paragraph-gap-slider'),
      ),
    if (category == 'font')
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _adjustment(
            ReaderChoicePicker<ReaderTextWeight>(
              name: 'reader-text-weight',
              label: '字重',
              value: _readerPreferences.textWeight,
              options: {
                for (final weight in ReaderTextWeight.values)
                  weight: weight.label,
              },
              onChanged: (weight) =>
                  _preferences(_readerPreferences.copyWith(textWeight: weight)),
            ),
          ),
          _adjustment(
            ReaderValueSlider(
              sliderKey: const ValueKey('reader-letter-spacing'),
              label: '字间距',
              value: _readerPreferences.letterSpacing,
              min: -.5,
              max: 3,
              divisions: 35,
              format: (v) => '${v.toStringAsFixed(1)} px',
              onPreview: (v) => _preferences(
                _readerPreferences.copyWith(letterSpacing: v),
                persist: false,
              ),
              onCommitted: (v) =>
                  _preferences(_readerPreferences.copyWith(letterSpacing: v)),
              onInteractionChanged: (v) =>
                  _preview(const ValueKey('reader-letter-spacing'), v),
            ),
            const ValueKey('reader-letter-spacing'),
          ),
        ],
      ),
    if (category == 'paragraph')
      _adjustment(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _switch(
              context,
              '首行缩进',
              _readerPreferences.indent,
              (v) => _preferences(_readerPreferences.copyWith(indent: v)),
            ),
            _switch(
              context,
              _readerPreferences.mode == ReaderMode.vertical ? '上下对齐' : '两端对齐',
              _readerPreferences.justify,
              (v) => _preferences(_readerPreferences.copyWith(justify: v)),
            ),
          ],
        ),
      ),
    if (category == 'turn') ..._behaviorItems(context, 'turn'),
    if (category == 'page') ..._behaviorItems(context, 'screen'),
    if (category != 'turn')
      _adjustment(
        Align(
          alignment: Alignment.centerRight,
          child: GlassTextButton(
            onPressed: widget.onReset,
            child: const AppText('恢复默认排版'),
          ),
        ),
      ),
  ], compact: compact);

  Widget _bookmarks(BuildContext context) => AnimatedBuilder(
    animation: widget.state.bookmarkChanges,
    builder: (context, _) {
      final marks = widget.state.bookmarksFor(widget.novel.id);
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      // Fit a few compact previews without intrinsically laying out a long list.
      final previewHeight =
          36 +
          marks
              .take(4)
              .fold<double>(
                0,
                (height, mark) =>
                    height +
                    66 +
                    (mark.quote.isEmpty ? 0 : 62 * scale) +
                    (mark.note.isEmpty ? 0 : 28 * scale),
              );
      return SizedBox(
        height: marks.isEmpty
            ? 132
            : math.min(
                math.min(480, MediaQuery.sizeOf(context).height * .56),
                previewHeight,
              ),
        child: CustomScrollView(
          key: const ValueKey('reader-bookmarks-scroll'),
          primary: false,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppText(
                      '本书 ${marks.length} 条记录',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_storageError != null)
                      AppText(
                        _storageError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (marks.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 28),
                sliver: SliverToBoxAdapter(
                  child: AppText('点右上角＋保存当前位置，或长按正文添加标记与批注。'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                sliver: SliverList.builder(
                  itemCount: marks.length,
                  itemBuilder: (context, index) {
                    final mark = marks[index];
                    final chapter = widget.state.chapterForPosition(
                      widget.novel,
                      mark.position,
                    );
                    return JellyTapSurface(
                      key: ValueKey('reader-bookmark-${mark.id}'),
                      onTap: chapter == null
                          ? null
                          : () {
                              Navigator.pop(context, ReaderOpenBookmark(mark));
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              key: ValueKey(
                                'reader-bookmark-heading-${mark.id}',
                              ),
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AppText(
                                        mark.chapterTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      AppText(
                                        chapter == null
                                            ? '章节已从目录移除'
                                            : '第 ${chapter + 1} 章 · ${(mark.position.fraction * 100).round()}%',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                GlassIconButton(
                                  key: ValueKey(
                                    'reader-bookmark-category-${mark.id}',
                                  ),
                                  icon: CupertinoIcons.folder,
                                  label: '分类书签 ${mark.id}',
                                  liveGlass: false,
                                  transparent: true,
                                  onPressed: () => organizeBookmark(
                                    context,
                                    widget.state,
                                    widget.novel.id,
                                    mark,
                                  ),
                                ),
                                GlassIconButton(
                                  key: ValueKey(
                                    'reader-bookmark-edit-${mark.id}',
                                  ),
                                  icon: CupertinoIcons.pencil,
                                  label: '查看与编辑书签 ${mark.id}',
                                  liveGlass: false,
                                  transparent: true,
                                  onPressed: () => _editBookmark(mark),
                                ),
                              ],
                            ),
                            ReaderBookmarkExcerpt(
                              mark: mark,
                              quoteMaxLines: 2,
                              noteMaxLines: 1,
                              compact: true,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _switch(
    BuildContext context,
    String title,
    bool value,
    ValueChanged<bool> changed,
  ) => Row(
    children: [
      Expanded(child: AppText(title)),
      AppControls.toggle(context, value: value, onChanged: changed),
    ],
  );

  List<Widget> _behaviorItems(BuildContext context, String category) {
    final prefs = _readerPreferences;
    return [
      if (category == 'turn' &&
          isLocalBook(widget.novel.id) &&
          widget.listeningBuilder != null)
        GlassTextButton(
          key: const ValueKey('reader-local-listening'),
          onPressed: () => Navigator.pop(context, const ReaderOpenListening()),
          child: const Row(
            children: [
              ArchiveIcon(CupertinoIcons.headphones, size: 20),
              SizedBox(width: 12),
              AppText('听书'),
            ],
          ),
        ),
      if (category == 'turn' && widget.canHandoff)
        GlassTextButton(
          key: const ValueKey('reader-handoff-entry'),
          onPressed: () => Navigator.pop(context, const ReaderOpenHandoff()),
          child: const Row(
            children: [
              ArchiveIcon(CupertinoIcons.device_laptop, size: 20),
              SizedBox(width: 12),
              Expanded(child: AppText('在其他设备续读')),
            ],
          ),
        ),
      if (category == 'screen')
        _adjustment(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _switch(
                context,
                '隐藏系统状态栏',
                prefs.hideSystemStatus,
                (v) => _preferences(prefs.copyWith(hideSystemStatus: v)),
              ),
              const AppText(
                '章节名始终显示在底部。隐藏系统状态栏后，可单独选择是否显示阅读时间和电量。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
              FutureBuilder<bool>(
                future: _floatingNavigation,
                builder: (context, value) => value.data != true
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          const AppText(
                            '系统悬浮球需在「系统和更新 → 系统导航方式 → 悬浮导航」中关闭。',
                            style: TextStyle(fontSize: 12, height: 1.6),
                          ),
                          GlassTextButton(
                            onPressed: () async {
                              try {
                                await _systemControls.invokeMethod<void>(
                                  'navigationSettings',
                                );
                              } catch (_) {
                                if (context.mounted) {
                                  showNovelFeedback(context, '请在手机设置中搜索「悬浮导航」');
                                }
                              }
                            },
                            child: const AppText('打开系统设置'),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      if (category == 'screen')
        AnimatedOptionSection(
          expanded: prefs.hideSystemStatus,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _adjustment(
                Padding(
                  key: const ValueKey('reader-status-visibility'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _switch(
                    context,
                    '显示时间与电量',
                    prefs.showStatusInfo,
                    (v) => _preferences(prefs.copyWith(showStatusInfo: v)),
                  ),
                ),
              ),
              AnimatedOptionSection(
                expanded: prefs.showStatusInfo,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _adjustment(
                      ReaderValueSlider(
                        sliderKey: const ValueKey('reader-status-font-size'),
                        label: '阅读信息字号',
                        value: prefs.statusFontSize,
                        min: 9,
                        max: 18,
                        divisions: 9,
                        format: (v) => '${v.round()} pt',
                        onPreview: (v) => _preferences(
                          prefs.copyWith(statusFontSize: v),
                          persist: false,
                        ),
                        onCommitted: (v) =>
                            _preferences(prefs.copyWith(statusFontSize: v)),
                        onInteractionChanged: (v) => _preview(
                          const ValueKey('reader-status-font-size'),
                          v,
                        ),
                      ),
                      const ValueKey('reader-status-font-size'),
                    ),
                    _adjustment(
                      ReaderValueSlider(
                        sliderKey: const ValueKey('reader-status-top-offset'),
                        label: '阅读信息上下位置',
                        value: prefs.statusTopOffset,
                        min: -8,
                        max: 24,
                        divisions: 32,
                        format: (v) => v == 0
                            ? '居中'
                            : '${v > 0 ? '下移' : '上移'} ${v.abs().round()}',
                        onPreview: (v) => _preferences(
                          prefs.copyWith(statusTopOffset: v),
                          persist: false,
                        ),
                        onCommitted: (v) =>
                            _preferences(prefs.copyWith(statusTopOffset: v)),
                        onInteractionChanged: (v) => _preview(
                          const ValueKey('reader-status-top-offset'),
                          v,
                        ),
                      ),
                      const ValueKey('reader-status-top-offset'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (category == 'screen')
        AnimatedOptionSection(
          expanded: prefs.showReaderStatus,
          child: _adjustment(
            ReaderValueSlider(
              sliderKey: const ValueKey('reader-status-inset'),
              label: '阅读信息左右留边',
              value: prefs.statusSideInset,
              min: 0,
              max: 96,
              divisions: 48,
              format: (v) => v == 0 ? '自动' : '+${v.round()}',
              onPreview: (v) => _preferences(
                prefs.copyWith(statusSideInset: v),
                persist: false,
              ),
              onCommitted: (v) =>
                  _preferences(prefs.copyWith(statusSideInset: v)),
              onInteractionChanged: (v) =>
                  _preview(const ValueKey('reader-status-inset'), v),
            ),
            const ValueKey('reader-status-inset'),
          ),
        ),
      ...[
        if (category == 'screen') ...[
          if (LocalPlatform.readerAppearance)
            AnimatedBuilder(
              animation: widget.state.readerBehaviorChanges,
              builder: (context, _) => Row(
                children: [
                  const Expanded(child: AppText('阅读时保持亮屏')),
                  AppControls.toggle(
                    context,
                    key: const ValueKey('reader-keep-screen-on'),
                    value: widget.state.keepScreenOn,
                    onChanged: (value) async {
                      try {
                        await widget.state.setKeepScreenOn(value);
                      } catch (_) {
                        if (context.mounted) {
                          showNovelFeedback(context, '亮屏设置保存失败，请重试');
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          GlassTextButton(
            onPressed: () => Navigator.pop(context, const ReaderEnterFocus()),
            child: const AppText('专注阅读 · 隐藏控件'),
          ),
          const Divider(height: 24),
        ],
        if (category == 'turn') ...[
          Row(
            children: [
              const Expanded(child: AppText('章节入场动画')),
              AppControls.toggle(
                context,
                key: const ValueKey('reader-chapter-entrance'),
                value: prefs.chapterEntrance,
                onChanged: (value) =>
                    _preferences(prefs.copyWith(chapterEntrance: value)),
              ),
            ],
          ),
          const AppText(
            '只控制打开章节时的额外入场；跨章仍沿用翻页效果。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
          _switch(
            context,
            '分区点按翻页',
            prefs.tapPaging,
            (v) => _preferences(prefs.copyWith(tapPaging: v)),
          ),
          AppText(
            prefs.tapPaging && prefs.tapBothSidesNext
                ? '左右两侧前进，中间显示控件；滑动翻页不变。'
                : '常规布局点按中间显示控件；竖排左右翻页方向相反。',
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
          AnimatedOptionSection(
            expanded: prefs.tapPaging,
            child: Row(
              children: [
                const Expanded(child: AppText('左右点按均为下一页')),
                AppControls.toggle(
                  context,
                  key: const ValueKey('reader-tap-both-sides-next'),
                  value: prefs.tapBothSidesNext,
                  onChanged: (value) =>
                      _preferences(prefs.copyWith(tapBothSidesNext: value)),
                ),
              ],
            ),
          ),
          AnimatedOptionSection(
            expanded: prefs.tapPaging && !prefs.tapBothSidesNext,
            child: Wrap(
              spacing: 8,
              children: [
                for (final layout in ReaderTapLayout.values)
                  Semantics(
                    selected: prefs.tapLayout == layout,
                    child: GlassTextButton(
                      key: ValueKey('reader-tap-layout-${layout.name}'),
                      compact: true,
                      selected: prefs.tapLayout == layout,
                      onPressed: () =>
                          _preferences(prefs.copyWith(tapLayout: layout)),
                      child: AppText(
                        layout.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          AnimatedOptionSection(
            expanded:
                prefs.tapPaging &&
                !prefs.tapBothSidesNext &&
                prefs.tapLayout != ReaderTapLayout.standard,
            child: AppText(
              '${prefs.tapLayout == ReaderTapLayout.rightHand ? '右' : '左'}半屏上部回退、下部前进，另一侧显示控件。',
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
          ),
          if (LocalPlatform.volumePaging)
            _switch(
              context,
              '音量键翻页',
              prefs.volumePaging,
              (v) => _preferences(prefs.copyWith(volumePaging: v)),
            ),
          const Divider(height: 24),
          ReaderValueSlider(
            sliderKey: const ValueKey('reader-auto-scroll-speed'),
            label: prefs.mode.paginated ? '自动翻页间隔' : '自动滚动速度',
            value: prefs.mode.paginated
                ? 600 / prefs.autoScrollSpeed
                : prefs.autoScrollSpeed,
            min: prefs.mode.paginated ? 7.5 : 8,
            max: prefs.mode.paginated ? 75 : 80,
            divisions: 36,
            format: (v) =>
                prefs.mode.paginated ? '${v.round()} 秒' : '${v.round()} px/s',
            onCommitted: (v) => _preferences(
              prefs.copyWith(
                autoScrollSpeed: prefs.mode.paginated ? 600 / v : v,
              ),
            ),
          ),
          GlassTextButton(
            key: const ValueKey('reader-auto-scroll-start'),
            onPressed: widget.position == null
                ? null
                : () => Navigator.pop(context, const ReaderStartAutoScroll()),
            child: AppText(prefs.mode.paginated ? '开始自动翻页' : '开始自动滚动'),
          ),
          const AppText(
            '点按正文、手动滑动或切到后台即可暂停。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
          const Divider(height: 24),
        ],
        if (category == 'screen') ...[
          if (LocalPlatform.readerAppearance)
            _switch(
              context,
              '左边缘滑动调亮度',
              prefs.edgeBrightness,
              (v) => _preferences(prefs.copyWith(edgeBrightness: v)),
            ),
          if (LocalPlatform.readerAppearance)
            _switch(
              context,
              '亮度跟随系统',
              prefs.brightness == null,
              (v) => _preferences(
                prefs.copyWith(brightness: .7, systemBrightness: v),
              ),
            ),
        ],
      ].map((child) => _adjustment(child)),
      if (category == 'screen' && LocalPlatform.readerAppearance)
        AnimatedOptionSection(
          expanded: prefs.brightness != null,
          child: _adjustment(
            ReaderValueSlider(
              sliderKey: const ValueKey('reader-brightness'),
              label: '阅读亮度',
              value: prefs.brightness ?? .7,
              min: 0,
              max: 1,
              format: (v) => '${(v * 100).round()}%',
              onPreview: (v) => _preferences(
                _readerPreferences.copyWith(brightness: v),
                persist: false,
              ),
              onInteractionChanged: (v) =>
                  _preview(const ValueKey('reader-brightness'), v),
              onCommitted: (v) =>
                  _preferences(_readerPreferences.copyWith(brightness: v)),
            ),
            const ValueKey('reader-brightness'),
          ),
        ),
    ];
  }
}

/// Reveals the detail surface outward from the selected card, without laying
/// out the controls at intermediate sizes or adding another backdrop filter.
class _CategoryRevealClipper extends CustomClipper<Path> {
  const _CategoryRevealClipper(
    this.origin,
    this.coordinateSpace,
    this.progress,
  );
  final Rect? origin;
  final GlobalKey coordinateSpace;
  final double progress;

  @override
  Path getClip(Size size) {
    final bounds = Offset.zero & size;
    final body = coordinateSpace.currentContext?.findRenderObject();
    // Resolve during paint, after the sheet has its new height. This keeps the
    // very first frame at the tapped card even while the surface grows upward.
    final start = origin != null && body is RenderBox && body.hasSize
        ? body.globalToLocal(origin!.topLeft) & origin!.size
        : bounds;
    final rect = Rect.lerp(start, bounds, progress)!;
    return Path()..addRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(18 * (1 - progress))),
    );
  }

  @override
  bool shouldReclip(_CategoryRevealClipper old) =>
      origin != old.origin || progress != old.progress;
}

class ReaderChoicePicker<T extends Enum> extends StatelessWidget {
  const ReaderChoicePicker({
    super.key,
    required this.name,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String name, label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => GlassChoiceGroup<T>(
    name: name,
    label: label,
    value: value,
    options: options,
    optionName: (option) => option.name,
    onChanged: onChanged,
    labelSize: 14,
    optionSize: 12,
    leading: value is ReaderPaper
        ? (option) {
            final paper = option as ReaderPaper;
            final dark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: ReaderPreferences(paper: paper).background(dark),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            );
          }
        : null,
  );
}

class _AdjustmentPlate extends CustomPainter {
  const _AdjustmentPlate(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(12),
        const Radius.circular(16),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_AdjustmentPlate oldDelegate) =>
      color != oldDelegate.color;
}

class ReaderValueSlider extends StatefulWidget {
  const ReaderValueSlider({
    super.key,
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onCommitted,
    this.divisions,
    this.onPreview,
    this.onInteractionChanged,
    this.hapticSteps,
    this.inline = false,
    this.leading,
    this.reconcileValue = false,
    this.showLabels = true,
  });
  final Key sliderKey;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double>? onCommitted;
  final ValueChanged<double>? onPreview;
  final ValueChanged<bool>? onInteractionChanged;
  final int? hapticSteps;
  final bool inline;
  final Widget? leading;
  final bool reconcileValue;
  final bool showLabels;

  @override
  State<ReaderValueSlider> createState() => _ReaderValueSliderState();
}

class _ReaderValueSliderState extends State<ReaderValueSlider> {
  late double _draft = widget.value;
  bool _dragging = false;
  bool _pointerCancelled = false;
  bool _previewChanged = false;
  double get _unit => (widget.max - widget.min) / (widget.divisions ?? 20);
  int _notch(double value) =>
      ((value - widget.min) /
              (widget.max - widget.min) *
              (widget.hapticSteps ?? widget.divisions ?? 20))
          .round();

  void _change(double value) {
    final next = value.clamp(widget.min, widget.max);
    final previous = _draft;
    final firstDragChange = _dragging && !_previewChanged;
    if (_dragging && next != _draft) _previewChanged = true;
    setState(() => _draft = next);
    // The reader owns both its explicit progress cadence and semantic steps;
    // the glass adapter is muted so one changed value cannot pulse twice.
    if (next != previous &&
        (firstDragChange || !_dragging || _notch(next) != _notch(previous))) {
      AppHaptics.play(
        context,
        next == widget.min || next == widget.max
            ? HapticCue.boundary
            : HapticCue.detent,
      );
    }
    // Accessibility increments have no pointer drag/end callback.
    if (_dragging) {
      widget.onPreview?.call(_draft);
    } else {
      widget.onCommitted?.call(_draft);
    }
  }

  void _adjust(double direction) {
    _change((_draft + direction * _unit).clamp(widget.min, widget.max));
  }

  void _finish() {
    if (!_dragging) return;
    _dragging = false;
    if (_previewChanged) widget.onCommitted?.call(_draft);
    widget.onInteractionChanged?.call(false);
  }

  @override
  void dispose() {
    if (_dragging && _previewChanged) {
      // Back navigation can remove the slider before the control's end callback.
      // Retain the last visible value without calling the disposed sheet.
      final commit = widget.onCommitted, draft = _draft;
      scheduleMicrotask(() => commit?.call(draft));
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(ReaderValueSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging &&
        (oldWidget.value != widget.value || widget.reconcileValue)) {
      _draft = widget.value;
    }
  }

  Widget _slider(BuildContext context) => SizedBox(
    height: widget.inline ? 48 : 52,
    child: Semantics(
      key: ValueKey('reader-slider-semantics-${widget.label}'),
      label: widget.label,
      value: widget.format(_draft),
      increasedValue: widget.format(
        (_draft + _unit).clamp(widget.min, widget.max),
      ),
      decreasedValue: widget.format(
        (_draft - _unit).clamp(widget.min, widget.max),
      ),
      slider: true,
      enabled: widget.onCommitted != null,
      onIncrease: widget.onCommitted == null || _draft >= widget.max
          ? null
          : () => _adjust(1),
      onDecrease: widget.onCommitted == null || _draft <= widget.min
          ? null
          : () => _adjust(-1),
      child: ExcludeSemantics(
        child: Listener(
          onPointerCancel: (_) {
            _pointerCancelled = _dragging;
            _finish();
          },
          child: AppControls.slider(
            context,
            key: widget.sliderKey,
            value: _draft.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            haptics: false,
            compact: widget.inline,
            onChanged: widget.onCommitted == null ? null : _change,
            onChangeStart: (_) {
              _pointerCancelled = false;
              _dragging = true;
              _previewChanged = false;
              widget.onInteractionChanged?.call(true);
            },
            onChangeEnd: (value) {
              if (_pointerCancelled) return;
              if (_dragging) {
                _draft = value.clamp(widget.min, widget.max);
                _finish();
              } else {
                widget.onCommitted?.call(value);
              }
            },
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.showLabels) return _slider(context);
    final value = AppText(
      widget.format(_draft),
      maxLines: 1,
      style: TextStyle(
        fontSize: widget.inline ? 13 : 12,
        fontWeight: widget.inline ? FontWeight.w600 : null,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    if (widget.inline) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final leading = widget.leading ?? AppText(widget.label);
          double textWidth(String text) {
            final painter = TextPainter(
              text: TextSpan(
                text: text,
                style: DefaultTextStyle.of(
                  context,
                ).style.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final width = painter.width;
            painter.dispose();
            return width;
          }

          final label = leading is AppText ? leading.data : widget.label;
          final valueWidth = textWidth('100%');
          final trailing = widget.reconcileValue
              ? SizedBox(
                  width: valueWidth,
                  child: Align(alignment: Alignment.centerRight, child: value),
                )
              : value;
          final required = textWidth(label) + valueWidth + 8 + 140;
          // Keep a useful track and readable labels. At larger type the same
          // capsule grows by a label row instead of compressing either target.
          if (constraints.maxWidth < required) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: leading),
                    trailing,
                  ],
                ),
                _slider(context),
              ],
            );
          }
          return Row(
            children: [
              leading,
              const SizedBox(width: 4),
              Expanded(child: _slider(context)),
              const SizedBox(width: 4),
              trailing,
            ],
          );
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AppText(
                  widget.label,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              value,
            ],
          ),
          const SizedBox(height: 4),
          _slider(context),
        ],
      ),
    );
  }
}
