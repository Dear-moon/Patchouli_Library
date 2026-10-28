import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'catalog.dart';
import 'feature_pages.dart';
import 'gallery_save_button.dart';
import 'library_state.dart';
import 'local_platform.dart';
import 'local_book_edit_widgets.dart';
import 'reading_report_layout.dart';
import 'reading_report_insights.dart';
import 'reading_report_options.dart';
import 'reading_report_range.dart';
import 'reading_report_components.dart';
import 'reading_report_fonts.dart';
import 'reading_report_renderer.dart';
import 'reading_report_reference_assets.dart';
import 'reading_statistics_data.dart';
import 'reading_visual_theme.dart';
import 'reading_visual_theme_picker.dart';

class ReadingReportPage extends StatefulWidget {
  const ReadingReportPage({
    super.key,
    required this.state,
    required this.repository,
    this.now,
    this.initialRange,
  });
  final LibraryState state;
  final NovelRepository repository;
  final DateTime? now;
  final ReadingReportRange? initialRange;
  @override
  State<ReadingReportPage> createState() => _ReadingReportPageState();
}

class _ReadingReportPageState extends State<ReadingReportPage> {
  ReadingReportOptions _options = const ReadingReportOptions();
  ReadingReportLayout? _layout;
  ReadingReportComponents? _components;
  Object? _componentKey;
  int _renderTicket = 0;
  Set<ReadingReportModule> _availableModules = const {};
  final _title = TextEditingController();
  final _nickname = TextEditingController();
  final _note = TextEditingController();
  Timer? _saveTimer;
  bool _busy = false, _loaded = false, _preparing = false;
  bool _previewHintShown = false;
  bool get _ready => !_preparing && identical(_layout?.options, _options);
  String? _error;
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stored = await ReadingReportOptions.load();
      final range = widget.initialRange;
      final options = range == null
          ? stored
          : stored.copyWith(
              period: range.period,
              from: range.from,
              until: range.until,
              clearDates: !range.custom,
            );
      if (!mounted) return;
      _title.text = options.title;
      _nickname.text = options.nickname;
      _note.text = options.note;
      setState(() {
        _options = options;
        _loaded = true;
      });
      await _prepare();
    } catch (_) {
      if (mounted) setState(() => _error = '报告设置未能读取，请返回后重试');
    }
  }

  Future<void> _prepare() async {
    final ticket = ++_renderTicket;
    final options = _options;
    setState(() {
      _preparing = true;
      _error = null;
    });
    final data = ReadingStatisticsData(
      state: widget.state,
      repository: widget.repository,
      now: _options.endAt(_now),
      period: _options.daysAt(_now),
      snapshotAt: _now,
    );
    String? serifFamily;
    if (options.template.theme.prefersSerif) {
      try {
        serifFamily = await registeredReadingReportSerif(widget.state.fonts);
      } catch (_) {
        // An optional installed face never gates the platform-font export path.
      }
      if (!mounted || ticket != _renderTicket) return;
    }
    final key = (
      options.template,
      options.palette,
      options.hideBookTitles,
      options.hideAuthorNames,
      options.bookLimit,
      Object.hashAll(options.orderedModules),
      data.period,
      data.today,
      Object.hashAll(data.seconds),
      Object.hashAll(data.progressBands),
      Object.hashAll(data.collectionBooks),
      Object.hashAll(
        data.analysis.booksByDuration
            .where((value) => value.seconds != null)
            .take(options.bookLimit)
            .map((value) => (value.id, value.book)),
      ),
      serifFamily,
    );
    try {
      final components = _components != null && _componentKey == key
          ? _components!.clone()
          : await captureReadingReportComponents(
              context,
              data,
              options,
              serifFamily: serifFamily,
            );
      if (!mounted || ticket != _renderTicket) {
        components.dispose();
        return;
      }
      if (_componentKey != key) {
        _components?.dispose();
        _components = components.clone();
        _componentKey = key;
      }
      final next = ReadingReportLayout.prepare(
        data,
        options,
        components: components,
        insights: ReadingReportInsights.from(
          data,
          activity: widget.state.readingActivity,
        ),
        translate: (value) => appText(context, value),
      );
      setState(() {
        _layout?.dispose();
        _layout = next;
        _availableModules = readingReportAvailableModules(data);
      });
    } catch (error) {
      if (mounted && ticket == _renderTicket) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : '报告预览未能生成，请重试',
        );
      }
    } finally {
      if (mounted && ticket == _renderTicket) {
        setState(() => _preparing = false);
      }
    }
  }

  void _update(ReadingReportOptions value) {
    if (_busy) return;
    setState(() {
      _options = value;
      _error = null;
    });
    _prepare();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), _persist);
  }

  Future<void> _persist() async {
    try {
      await _options.save();
    } catch (_) {
      if (mounted) setState(() => _error = '自定义设置未能保存，下次打开时请重新选择');
    }
  }

  Future<void> _dates() async {
    final today = statisticsDay(_now);
    final range = await pickReadingReportRange(
      context,
      now: today,
      range: _options.range,
    );
    if (range != null && mounted) {
      _update(_options.copyWith(from: range.start, until: range.end));
    }
  }

  Future<void> _export(bool share, {String? authorizationToken}) async {
    if (_busy || !_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await _layout!.png();
      if (!mounted) return;
      final name =
          '阅读报告-${_options.template.name}-${DateTime.now().millisecondsSinceEpoch}.png';
      if (share) {
        await LocalPlatform.shareImage(bytes, name);
      } else {
        await LocalPlatform.saveImageToGallery(
          bytes,
          name,
          authorizationToken: authorizationToken,
        );
        if (mounted) showNovelFeedback(context, '已保存到相册');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : share
              ? '图片未能分享，请重试'
              : gallerySaveFailureMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _preview() {
    if (!_ready || _busy) return;
    final showHint = !_previewHintShown;
    _previewHintShown = true;
    final reduceMotion = widget.state.effectiveReduceMotion;
    pushNovelPage<void>(
      context,
      _ReadingReportPreviewPage(
        layout: _layout!,
        showHint: showHint,
        reduceMotion: reduceMotion,
      ),
      reduceMotion: reduceMotion,
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _renderTicket++;
    if (_loaded) _persist();
    _title.dispose();
    _nickname.dispose();
    _note.dispose();
    _layout?.dispose();
    _components?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '图片报告',
    code: 'READING / PERSONAL EDITION',
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1020),
        child: !_loaded || _layout == null
            ? Center(
                child: _error == null
                    ? const CupertinoActivityIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FeatureError(_error),
                          if (_loaded)
                            GlassTextButton(
                              onPressed: _prepare,
                              child: const AppText('重新生成预览'),
                            ),
                        ],
                      ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final preview = _previewPanel(context);
                  final controls = _controls(context);
                  return ListView(
                    key: const ValueKey('reading-report-editor-scroll'),
                    padding: featurePadding(context),
                    children: constraints.maxWidth >= 800
                        ? [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 330, child: preview),
                                const SizedBox(width: 36),
                                Expanded(child: controls),
                              ],
                            ),
                          ]
                        : [preview, const SizedBox(height: 32), controls],
                  );
                },
              ),
      ),
    ),
  );

  Widget _previewPanel(BuildContext context) {
    final layout = _layout!;
    final pixels = layout.pixelSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: '打开完整报告预览',
          child: JellyTapSurface(
            key: const ValueKey('reading-report-preview-open'),
            onTap: _busy ? null : _preview,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final height =
                      layout.height *
                      constraints.maxWidth /
                      ReadingReportLayout.width;
                  return SizedBox(
                    height: math.min(260, height),
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: height,
                        maxHeight: height,
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey((
                            layout.options.template,
                            layout.options.palette,
                          )),
                          tween: Tween(begin: .8, end: 1),
                          duration:
                              widget.state.reduceMotion ||
                                  MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : NovelMotion.enter,
                          builder: (context, value, child) => Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 4 * (1 - value)),
                              child: child,
                            ),
                          ),
                          child: CustomPaint(
                            key: const ValueKey('reading-report-cover-preview'),
                            size: Size(constraints.maxWidth, height),
                            painter: ReadingReportPainter(layout),
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
        const SizedBox(height: 12),
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(12) + 12,
          child: AnimatedSwitcher(
            duration: widget.state.effectiveReduceMotion
                ? Duration.zero
                : NovelMotion.contact,
            child: !_preparing
                ? const SizedBox.shrink()
                : const AppText(
                    '正在更新预览…',
                    key: ValueKey('reading-report-preparing'),
                    style: TextStyle(fontSize: 12),
                  ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: AppText(
                'PNG · ${pixels.width} × ${pixels.height}',
                style: _caption(context),
              ),
            ),
            GlassTextButton(
              compact: true,
              key: const ValueKey('reading-report-full-preview'),
              onPressed: _busy ? null : _preview,
              child: const AppText('完整预览'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_availableModules.isNotEmpty)
          AppText('报告内容', style: _caption(context)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final module in ReadingReportModule.values.where(
              _availableModules.contains,
            ))
              GlassTextButton(
                key: ValueKey('report-module-${module.name}'),
                compact: true,
                selected: _options.modules.contains(module),
                onPressed: _busy
                    ? null
                    : () {
                        final modules = {..._options.modules};
                        if (!modules.remove(module)) modules.add(module);
                        _update(_options.copyWith(modules: modules));
                      },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ArchiveIcon(
                      _options.modules.contains(module)
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      size: 14,
                      active: _options.modules.contains(module),
                    ),
                    const SizedBox(width: 5),
                    AppText(module.label, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: GallerySaveButton(
                enabled: !_busy && _ready && LocalPlatform.fileActions,
                foreground: Theme.of(context).colorScheme.onPrimary,
                background: Theme.of(context).colorScheme.primary,
                onSave: (token) => _export(false, authorizationToken: token),
                onError: (error) => setState(() {
                  _error = gallerySaveFailureMessage(error);
                }),
                builder: (onPressed) => GlassTextButton(
                  key: const ValueKey('reading-report-save'),
                  onPressed: onPressed,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ArchiveIcon(
                        CupertinoIcons.arrow_down_to_line,
                        size: 17,
                      ),
                      const SizedBox(width: 6),
                      AppText(_busy ? '正在生成…' : '保存图片'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlassTextButton(
                key: const ValueKey('reading-report-share'),
                onPressed: _busy || !_ready || !LocalPlatform.fileActions
                    ? null
                    : () => _export(true),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ArchiveIcon(CupertinoIcons.square_arrow_up, size: 17),
                    SizedBox(width: 6),
                    AppText('分享图片'),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (!LocalPlatform.fileActions)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: AppText(
              '当前平台支持预览；保存与分享请在手机或平板使用。',
              style: _caption(context),
            ),
          ),
        FeatureError(_error),
      ],
    );
  }

  TextStyle _caption(BuildContext context) => TextStyle(
    fontSize: 12,
    height: 1.6,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  ReadingVisualThemePresentation _reportThemePresentation(
    ReadingVisualTheme visual,
  ) => ReadingVisualThemePresentation.fromExportTheme(
    visual,
    at: statisticsDay(_options.endAt(_now)),
  );

  Widget _controls(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const ArchiveSection(title: '版式与配色', code: '01 / ART DIRECTION'),
      const SizedBox(height: 16),
      ReadingVisualThemePicker(
        value: _options.template.theme,
        presentationFor: _reportThemePresentation,
        onChanged: _busy
            ? null
            : (theme) => _update(
                _options.copyWith(
                  template: ReadingReportTemplate.values.firstWhere(
                    (value) => value.name == theme.id,
                  ),
                ),
              ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final palette in ReadingReportPalette.values)
            GlassTextButton(
              key: ValueKey('report-palette-${palette.name}'),
              selected: palette == _options.palette,
              compact: true,
              onPressed: _busy
                  ? null
                  : () => _update(_options.copyWith(palette: palette)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ReadingReportColors(
                        _options.copyWith(palette: palette),
                      ).accent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AppText(palette.label, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 28),
      const ArchiveSection(title: '这段时间', code: '02 / DATE RANGE'),
      const SizedBox(height: 14),
      Wrap(
        spacing: 7,
        runSpacing: 4,
        children: [
          for (final period in const [7, 30, 90, 365])
            GlassTextButton(
              key: ValueKey('report-period-$period'),
              compact: true,
              selected: _options.from == null && _options.period == period,
              onPressed: _busy
                  ? null
                  : () => _update(
                      _options.copyWith(period: period, clearDates: true),
                    ),
              child: AppText('$period 天'),
            ),
        ],
      ),
      GlassTextButton(
        key: const ValueKey('report-custom-dates'),
        selected: _options.range.custom,
        onPressed: _busy ? null : _dates,
        child: Row(
          children: [
            const ArchiveIcon(CupertinoIcons.calendar, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: AppText(
                _options.from == null
                    ? '自定日期区间'
                    : '${_options.from!.year}.${_options.from!.month}.${_options.from!.day} — ${_options.until!.year}.${_options.until!.month}.${_options.until!.day}',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 26),
      const ArchiveSection(title: '写上你的名字', code: '03 / PERSONAL DETAILS'),
      const SizedBox(height: 14),
      _field(
        '标题',
        _title,
        36,
        (value) => _options.copyWith(title: value),
        'report-title',
      ),
      _field(
        '昵称（可留空）',
        _nickname,
        24,
        (value) => _options.copyWith(nickname: value),
        'report-nickname',
      ),
      _field(
        '寄语（可留空）',
        _note,
        80,
        (value) => _options.copyWith(note: value),
        'report-note',
        lines: 2,
      ),
      const SizedBox(height: 20),
      const ArchiveSection(title: '分享与隐私', code: '04 / SHARING & PRIVACY'),
      const SizedBox(height: 14),
      AppText('书单显示数量', style: _caption(context)),
      Wrap(
        spacing: 7,
        runSpacing: 4,
        children: [
          for (final count in const [3, 5, 10, 20])
            GlassTextButton(
              compact: true,
              selected: count == _options.bookLimit,
              onPressed: _busy
                  ? null
                  : () => _update(_options.copyWith(bookLimit: count)),
              child: AppText('$count 本'),
            ),
        ],
      ),
      const SizedBox(height: 14),
      _toggle(
        context,
        '隐藏书名',
        _options.hideBookTitles,
        (value) => _update(_options.copyWith(hideBookTitles: value)),
        'report-hide-books',
      ),
      _toggle(
        context,
        '隐藏作者姓名',
        _options.hideAuthorNames,
        (value) => _update(_options.copyWith(hideAuthorNames: value)),
        'report-hide-authors',
      ),
      _toggle(
        context,
        '摘录中显示批注文字',
        _options.includeNotes,
        (value) => _update(_options.copyWith(includeNotes: value)),
        'report-include-notes',
      ),
      const SizedBox(height: 12),
      AppText('时长来自前台阅读记录；书单优先按本期已知单书时长排列。未知日期保持空白。', style: _caption(context)),
      const SizedBox(height: 28),
    ],
  );

  Widget _field(
    String label,
    TextEditingController controller,
    int maximum,
    ReadingReportOptions Function(String) next,
    String key, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: LocalBookEditField(
      inputKey: ValueKey(key),
      label: label,
      controller: controller,
      enabled: !_busy,
      maxLength: maximum,
      maxLines: lines,
      minLines: lines,
      placeholder: switch (key) {
        'report-title' => '给这份报告起个名字',
        'report-nickname' => '填写你的昵称',
        _ => '写一句想留给自己的话',
      },
      onChanged: (value) => _update(next(value)),
    ),
  );

  Widget _toggle(
    BuildContext context,
    String label,
    bool value,
    ValueChanged<bool> change,
    String key,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(child: AppText(label)),
        const SizedBox(width: 14),
        AppControls.toggle(
          context,
          key: ValueKey(key),
          value: value,
          onChanged: _busy ? null : change,
        ),
      ],
    ),
  );
}

class _ReadingReportPreviewPage extends StatefulWidget {
  const _ReadingReportPreviewPage({
    required this.layout,
    required this.showHint,
    required this.reduceMotion,
  });
  final ReadingReportLayout layout;
  final bool showHint;
  final bool reduceMotion;
  @override
  State<_ReadingReportPreviewPage> createState() =>
      _ReadingReportPreviewPageState();
}

class _ReadingReportPreviewPageState extends State<_ReadingReportPreviewPage> {
  final _transform = TransformationController();
  VoidCallback? _dismissHint;

  @override
  void initState() {
    super.initState();
    if (!widget.showHint) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      _dismissHint = showNovelFeedback(
        context,
        '双指缩放，拖动查看整张报告',
        duration: const Duration(milliseconds: 1800),
        reduceMotion: widget.reduceMotion,
      );
    });
  }

  @override
  void dispose() {
    _dismissHint?.call();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    key: const ValueKey('reading-report-full-preview-page'),
    title: '完整预览',
    code: 'PNG / FULL REPORT',
    child: Padding(
      padding: featurePadding(context),
      child: LayoutBuilder(
        builder: (context, constraints) => InteractiveViewer(
          key: const ValueKey('reading-report-zoom'),
          transformationController: _transform,
          constrained: false,
          minScale: 1,
          maxScale: 3,
          alignment: Alignment.topLeft,
          child: Semantics(
            image: true,
            label: widget.layout.labels.join('，'),
            child: SizedBox(
              width: constraints.maxWidth,
              height:
                  widget.layout.height *
                  constraints.maxWidth /
                  ReadingReportLayout.width,
              child: CustomPaint(
                key: const ValueKey('reading-report-full-image'),
                painter: ReadingReportPainter(widget.layout),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
