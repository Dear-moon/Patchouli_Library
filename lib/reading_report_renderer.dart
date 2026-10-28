import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'app_ui.dart';
import 'catalog.dart';
import 'legacy_cover.dart';
import 'local_book_media.dart';
import 'performance_preferences.dart';
import 'reading_report_components.dart';
import 'reading_report_art.dart';
import 'reading_report_options.dart';
import 'reading_report_layout.dart';
import 'reading_report_reference_assets.dart';
import 'reading_statistics_data.dart';
import 'reading_statistics_charts.dart';

/// Layout+paint the real widget in an isolated Flutter render tree. No app route,
/// screenshot of controls, Offstage placeholder, or substitute shelf drawing.
Future<ui.Image> captureReadingReportWidget(
  BuildContext context,
  Widget widget,
  Size size,
  ThemeData theme,
) async {
  final media = MediaQuery.of(context).copyWith(
    size: size,
    devicePixelRatio: 2,
    textScaler: TextScaler.noScaling,
    padding: EdgeInsets.zero,
    viewPadding: EdgeInsets.zero,
    viewInsets: EdgeInsets.zero,
    disableAnimations: true,
  );
  final direction = Directionality.of(context);
  final view = View.of(context);
  final boundary = RenderRepaintBoundary();
  final position = RenderPositionedBox(
    alignment: Alignment.topLeft,
    child: boundary,
  );
  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      physicalConstraints: BoxConstraints.tight(size),
      devicePixelRatio: 1,
    ),
    child: position,
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  final focus = FocusManager();
  final owner = BuildOwner(focusManager: focus);
  renderView.prepareInitialFrame();
  final surface = Material(
    color: Colors.transparent,
    child: DefaultTextStyle(
      style: theme.textTheme.bodyMedium!,
      child: IgnorePointer(
        child: SizedBox.fromSize(size: size, child: widget),
      ),
    ),
  );
  final themed = Theme(
    data: theme,
    child: CupertinoTheme(
      data: CupertinoThemeData(brightness: theme.brightness),
      child: surface,
    ),
  );
  final configured = MediaQuery(
    data: media,
    child: Directionality(
      textDirection: direction,
      child: PerformanceScope(
        preferences: const PerformancePreferences(),
        explicitReduceMotion: true,
        child: themed,
      ),
    ),
  );
  final child = InheritedTheme.captureAll(
    context,
    Localizations.override(context: context, child: configured),
  );
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: child,
  ).attachToRenderTree(owner);
  void flush() {
    owner.buildScope(root);
    pipeline.flushLayout();
    pipeline.flushCompositingBits();
    pipeline.flushPaint();
  }

  try {
    flush();
    // Cached image futures/decoded frames can complete after the first build.
    await Future<void>.delayed(Duration.zero);
    flush();
    await Future<void>.delayed(Duration.zero);
    flush();
    return await boundary.toImage(pixelRatio: 2);
  } finally {
    owner.buildScope(
      root,
      () => root.update(
        RenderObjectToWidgetAdapter<RenderBox>(container: boundary),
      ),
    );
    owner.finalizeTree();
    pipeline.rootNode = null;
    renderView.child = null;
    position.child = null;
    boundary.dispose();
    position.dispose();
    renderView.dispose();
    pipeline.dispose();
    focus.dispose();
  }
}

Novel _privateBook(Novel book, ReadingReportOptions options, int index) =>
    Novel(
      id: book.id,
      title: options.hideBookTitles
          ? '书籍 ${(index + 1).toString().padLeft(2, '0')}'
          : readingReportHasMetadataText(book.title)
          ? book.title
          : (index + 1).toString().padLeft(2, '0'),
      author:
          options.hideAuthorNames || !readingReportHasAuthorText(book.author)
          ? ''
          : book.author,
      genre: book.genre,
      summary: book.summary,
      colors: book.colors,
      chapters: book.chapters,
      chapterCount: book.chapterCount,
      coverUrl: options.hideBookTitles || options.hideAuthorNames
          ? null
          : book.coverUrl,
    );

Future<void> _warmCover(BuildContext context, Novel book, double width) async {
  if (book.coverUrl == null) return;
  try {
    final bytes = book.coverUrl!.startsWith('wenku-local:')
        ? await LocalBookMedia.loadCover(book.coverUrl!)
        : await LegacyCover.bytes(book.id, url: book.coverUrl);
    if (!context.mounted) return;
    await precacheImage(
      ResizeImage.resizeIfNeeded(
        novelCoverDecodeWidth(width, 2),
        null,
        MemoryImage(bytes),
      ),
      context,
      onError: (_, _) {},
    );
  } catch (_) {
    // NovelCover owns the same cached-error -> text-cover contract in the app.
  }
}

Future<ReadingReportComponents> captureReadingReportComponents(
  BuildContext context,
  ReadingStatisticsData data,
  ReadingReportOptions options, {
  String? serifFamily,
}) async {
  final colors = ReadingReportColors(options);
  final dark = colors.isDark;
  final original = Theme.of(context);
  final scheme = original.colorScheme.copyWith(
    brightness: dark ? Brightness.dark : Brightness.light,
    surface: colors.background,
    onSurface: colors.ink,
    onSurfaceVariant: colors.muted,
    primary: colors.accent,
  );
  final theme = original.copyWith(
    brightness: scheme.brightness,
    colorScheme: scheme,
    textTheme: original.textTheme.apply(
      bodyColor: colors.ink,
      displayColor: colors.ink,
    ),
  );
  final owned = <ui.Image>[];
  final visible = readingReportVisibleModules(data, options);
  final spec = readingReportCaptureSpec(options);
  Future<ui.Image> capture(Widget widget, Size size) async {
    if (!context.mounted) throw const FormatException('报告页面已关闭');
    final image = await captureReadingReportWidget(
      context,
      widget,
      size,
      theme,
    );
    owned.add(image);
    return image;
  }

  try {
    final artKey = readingReportHeroArt(data, options);
    final art = await loadReadingReportArt(
      context,
      'assets/report/$artKey.webp',
    );
    owned.add(art);
    final illustrations = <String, ui.Image>{};
    for (final key in readingReportArtKeys(data, options)) {
      if (key == artKey) continue;
      if (!context.mounted) throw const FormatException('报告页面已关闭');
      final image = await loadReadingReportArt(
        context,
        'assets/report/$key.webp',
      );
      illustrations[key] = image;
      owned.add(image);
    }
    final monthly =
        visible.contains(ReadingReportModule.rhythm) && spec.captureMonthly
        ? await capture(
            ReadingMonthlyChart(
              dates: data.months.map((value) => value.date).toList(),
              seconds: data.months.map((value) => value.seconds).toList(),
              reduceMotion: true,
              presentation: switch (options.template) {
                ReadingReportTemplate.archive =>
                  ReadingChartPresentation.archive,
                ReadingReportTemplate.shelf => ReadingChartPresentation.shelf,
                ReadingReportTemplate.editorial =>
                  ReadingChartPresentation.narrative,
                ReadingReportTemplate.constellation =>
                  ReadingChartPresentation.night,
                ReadingReportTemplate.signal =>
                  ReadingChartPresentation.archive,
                ReadingReportTemplate.score =>
                  ReadingChartPresentation.narrative,
                ReadingReportTemplate.ink => ReadingChartPresentation.narrative,
                ReadingReportTemplate.festival =>
                  ReadingChartPresentation.shelf,
              },
              height: spec.monthlySize.height,
            ),
            spec.monthlySize,
          )
        : null;
    final calendars = <ui.Image>[];
    for (
      var start = 0;
      visible.contains(ReadingReportModule.calendar) &&
          spec.captureCalendar &&
          start < data.period;
    ) {
      var end = data.period;
      if (data.period > 366) {
        end = math.min(start + 364, data.period);
        while (end < data.period &&
            data.dates[end].weekday != DateTime.monday) {
          end--;
        }
      }
      final dates = data.dates.sublist(start, end);
      calendars.add(
        await capture(
          ReadingActivityCalendar(
            dates: dates,
            seconds: data.seconds.sublist(start, end),
            selectedDate: null,
            onSelected: (_) {},
            reduceMotion: true,
            showDateAnchors: true,
          ),
          readingCalendarSize(dates, spec.calendarWidth, showDateAnchors: true),
        ),
      );
      start = end;
    }
    final bands = ReadingProgressBands(
      bands: data.progressBands,
      reduceMotion: true,
      compact: true,
      labelSize: spec.progressLabelSize,
    );
    final progressTheme = theme.copyWith(
      colorScheme: scheme.copyWith(
        surface: colors.ink,
        onSurface: colors.background,
      ),
    );
    final progress =
        visible.contains(ReadingReportModule.progress) &&
            spec.captureProgress &&
            data.progressBands.any((value) => value > 0)
        ? await capture(
            spec.invertProgress
                ? Theme(
                    data: progressTheme,
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: colors.background,
                      ),
                      child: bands,
                    ),
                  )
                : bands,
            spec.progressSize,
          )
        : null;
    final ring =
        dark && spec.captureRing && visible.contains(ReadingReportModule.rhythm)
        ? await capture(
            ReadingActivityRing(
              ratio: data.activeRatio,
              reduceMotion: true,
              size: spec.ringSize.width,
              segmented: true,
              caption: '活跃日 / 已记录自然日',
            ),
            spec.ringSize,
          )
        : null;
    final covers = <ui.Image>[];
    final activeBookIds = readingReportActiveBookIds(data);
    if (visible.contains(ReadingReportModule.books) && spec.captureBookCovers) {
      for (final (index, top)
          in data.analysis.booksByDuration
              .where((value) => activeBookIds.contains(value.id))
              .take(options.bookLimit)
              .indexed) {
        final source =
            top.book ??
            Novel(
              id: top.id,
              title: top.title,
              author: '',
              genre: '',
              summary: '',
              colors: [colors.accent, colors.ink],
            );
        final book = _privateBook(source, options, index);
        if (!context.mounted) throw const FormatException('报告页面已关闭');
        final coverSize = spec.coverSize;
        await _warmCover(context, book, coverSize.width);
        covers.add(
          await capture(
            NovelCover(book, width: coverSize.width, height: coverSize.height),
            coverSize,
          ),
        );
      }
    }
    return ReadingReportComponents(
      monthly: monthly,
      calendars: calendars,
      progress: progress,
      ring: ring,
      bookCovers: covers,
      serifFamily: serifFamily,
      art: art,
      artKey: artKey,
      illustrations: Map.unmodifiable(illustrations),
    );
  } catch (_) {
    for (final image in owned) {
      image.dispose();
    }
    rethrow;
  }
}

Future<ReadingReportLayout> renderReadingReport(
  BuildContext context,
  ReadingStatisticsData data,
  ReadingReportOptions options,
) async {
  final components = await captureReadingReportComponents(
    context,
    data,
    options,
  );
  try {
    return ReadingReportLayout.prepare(
      data,
      options,
      components: components,
      translate: (value) => appText(context, value),
    );
  } catch (_) {
    components.dispose();
    rethrow;
  }
}
