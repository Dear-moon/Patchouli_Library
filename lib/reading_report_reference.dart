part of 'reading_report_layout.dart';

/// The supplied M–R editions are adapted to the app's single complete drawing.
/// Artwork, paper edges, film perforations and the six editorial structures are
/// retained; every figure, time span and section comes from the selected ledger.
class _ReferencePosterComposer extends _ReportArtDirectionComposer
    with _ReportDimensionPrint, _ReportCalendarPrint {
  _ReferencePosterComposer(
    super.data,
    super.options,
    super.translate,
    super.components,
  );

  ReadingReportColors? _sectionColors;
  @override
  ReadingReportColors get colors => _sectionColors ?? super.colors;
  late final ReadingReportColors paperSurface = ReadingReportColors.surface(
    background: const Color(0xfff1f0e9),
    ink: const Color(0xff242725),
    muted: const Color(0xff70786e),
    accent: options.palette == ReadingReportPalette.pine
        ? const Color(0xff617269)
        : Color.lerp(const Color(0xff242725), super.colors.accent, .6)!,
  );

  void paintSurface(ReadingReportColors surface, void Function() draw) {
    final outer = canvas, previous = _sectionColors, top = y;
    final recorder = ui.PictureRecorder();
    canvas = Canvas(recorder);
    _sectionColors = surface;
    late ui.Picture picture;
    try {
      draw();
      picture = recorder.endRecording();
    } catch (_) {
      if (recorder.isRecording) recorder.endRecording().dispose();
      rethrow;
    } finally {
      canvas = outer;
      _sectionColors = previous;
    }
    try {
      canvas.drawRect(
        Rect.fromLTWH(0, top, 600, y - top),
        Paint()..color = surface.background,
      );
      canvas.drawPicture(picture);
    } finally {
      picture.dispose();
    }
  }

  void emit(
    ReadingReportModule module,
    double Function(double) draw, {
    double x = 32,
    double width = 536,
    double gap = 24,
  }) {
    if (!has(module)) return;
    final block = plate(module, width, draw);
    if (block.height <= 0) {
      block.picture.dispose();
      return;
    }
    hang(block, x, y);
    y += block.height + gap;
  }

  @override
  bool get night => colors.isDark;
  int get _activeDays =>
      data.analysis.bookDayDistribution.attributedActiveDays +
      data.analysis.bookDayDistribution.unattributedActiveDays;
  late final Set<int> _activeBookIds = readingReportActiveBookIds(data);
  late final List<StatisticsAnalysisBook> _rankedBooks = data
      .analysis
      .booksByDuration
      .where((book) => _activeBookIds.contains(book.id))
      .take(options.bookLimit)
      .toList();
  int get _bookCount => _activeBookIds.length;
  bool get _hasReading =>
      data.periodSeconds > 0 || data.analysis.measuredMilliseconds > 0;
  bool _hasTitle(String value) => readingReportHasMetadataText(value);
  String get _displayTitle =>
      options.title.trim().isEmpty || options.title.trim() == '我的阅读档案'
      ? '阅读报告'
      : options.title.trim();

  @override
  double imageTitle(
    String fallback,
    double x,
    double top, {
    double width = 268,
    double size = 38,
    Color? color,
    TextAlign align = TextAlign.left,
    bool measure = false,
  }) {
    final standard = _displayTitle == '阅读报告';
    final value = standard && fallback.contains('\n')
        ? '阅读\n报告'
        : _displayTitle;
    return printText(
      value,
      x,
      top,
      width: width,
      size: standard ? size : math.min(32, size * .8),
      fixedTitle:
          standard && readingExportTheme(options.template.theme).prefersSerif,
      weight: FontWeight.w600,
      color: color,
      height: 1.35,
      align: align,
      measure: measure,
    );
  }

  @override
  ReadingReportLayout compose() {
    // Editions own their chapter grammar. This route is only the lightweight
    // cover for an empty selection or a ledger with no drawable facts.
    assert(readingReportVisibleModules(data, options).isEmpty);
    final recorder = ui.PictureRecorder();
    canvas = Canvas(recorder);
    _paperGround();
    y = _quietOpening() + 32;
    y +=
        printText(
          options.modules.isEmpty ? '这一页，只留给此刻的你。' : '这段时间，还没有可展开的阅读记录。',
          32,
          y,
          width: 536,
          size: 21,
          color: colors.muted,
          height: 1.6,
        ) +
        30;
    y = _ending(y);
    return finishPlate(recorder, y + 28);
  }

  void _paperGround() {
    if (night) return;
    final paint = Paint()..color = colors.ink.withValues(alpha: .035);
    for (var top = 19.0; top < 12000; top += 37) {
      canvas.drawLine(
        Offset(0, top),
        Offset(600, top - .4),
        paint..strokeWidth = .35,
      );
    }
  }

  void _illustration(
    String key,
    Rect bounds, {
    Alignment alignment = Alignment.center,
    double shade = 0,
  }) {
    final image =
        components?.illustration(key) ??
        (key == readingReportHeroArt(data, options) ? components?.art : null);
    if (image == null) return;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, size, bounds.size);
    canvas.save();
    canvas.clipRect(bounds);
    canvas.drawImageRect(
      image,
      alignment.inscribe(fitted.source, Offset.zero & size),
      bounds,
      Paint()..filterQuality = FilterQuality.high,
    );
    if (shade > 0) {
      canvas.drawRect(bounds, Paint()..color = black.withValues(alpha: shade));
    }
    canvas.restore();
  }

  void _masthead({double top = 21, Color? color}) {
    final ink = color ?? colors.ink;
    glyph(2, 32, top + 1, size: 22, color: colors.accent);
    printText(
      readingExportBrandName,
      64,
      top,
      width: 170,
      size: 15,
      weight: FontWeight.w600,
      color: ink,
    );
    printText(
      'PERSONAL READING REPORT',
      64,
      top + 23,
      width: 350,
      size: 10,
      color: colors.muted,
    );
    printText(
      '${data.today.year}',
      476,
      top + 2,
      width: 92,
      size: 26,
      display: true,
      align: TextAlign.right,
      color: ink,
    );
  }

  double _identity(double top, {double x = 32, double width = 536}) {
    top +=
        printText(
          name,
          x,
          top,
          width: width,
          size: 18,
          weight: FontWeight.w600,
        ) +
        7;
    top +=
        printText(range, x, top, width: width, size: 12, color: colors.muted) +
        12;
    if (options.note.trim().isNotEmpty) {
      top +=
          printText(
            options.note.trim(),
            x,
            top,
            width: width,
            size: 14,
            color: colors.muted,
            height: 1.6,
          ) +
          12;
    }
    return top;
  }

  double _total(
    double x,
    double top,
    double width, {
    double size = 94,
    Color? color,
  }) {
    if (!_hasReading) return 0;
    if (data.periodSeconds == 0 && data.analysis.measuredMilliseconds > 0) {
      return printText(
        '不足1秒',
        x,
        top,
        width: width,
        size: 45,
        color: color,
        weight: FontWeight.w600,
      );
    }
    return imageDuration(x, top, width: width, size: size, color: color);
  }

  double _quietOpening() {
    _masthead(color: night ? paper : null);
    final art = readingReportHeroArt(data, options);
    final landscape =
        options.template == ReadingReportTemplate.shelf ||
        options.template == ReadingReportTemplate.ink;
    _illustration(
      art,
      landscape
          ? const Rect.fromLTWH(32, 104, 536, 301.5)
          : const Rect.fromLTWH(318, 98, 250, 270),
      alignment: Alignment.topRight,
    );
    final heading = imageTitle(
      options.template.label,
      32,
      landscape ? 430 : 116,
      width: landscape ? 536 : 263,
      size: 43,
      color: colors.ink,
    );
    var top = landscape
        ? 430 + heading + 23
        : math.max(238.0, 116 + heading + 23);
    top +=
        printText(
          name,
          34,
          top,
          width: landscape ? 536 : 250,
          size: 18,
          weight: FontWeight.w600,
        ) +
        9;
    top +=
        printText(
          range,
          34,
          top,
          width: landscape ? 536 : 250,
          size: 12,
          color: colors.muted,
        ) +
        15;
    top = math.max(top, 392);
    return top;
  }

  @override
  double printHead(
    ReadingReportModule module,
    double width, {
    bool dark = false,
    String? english,
  }) {
    serial++;
    final n = serial.toString().padLeft(2, '0');
    final serif = options.template == ReadingReportTemplate.editorial;
    final headSize = width < 300 ? 21.0 : 25.0;
    printText(
      n,
      0,
      1,
      width: 34,
      size: 30,
      display: true,
      color: colors.accent,
      height: 1,
    );
    final h = printText(
      module.label,
      47,
      1,
      width: width - 47,
      size: headSize,
      weight: FontWeight.w600,
      fixedTitle: serif,
      height: 1.25,
    );
    printText(
      english ?? module.name.toUpperCase(),
      48,
      math.max(32, h + 5),
      width: width - 48,
      size: 10,
      color: colors.muted,
    );
    return math.max(32, h + 5) + 21;
  }

  double _at(
    double top,
    double width,
    double Function(double) draw, {
    double gap = 16,
  }) {
    canvas.save();
    canvas.translate(0, top);
    final height = draw(width);
    canvas.restore();
    return top + height + (height > 0 ? gap : 0);
  }

  String? _monthFigure(StatisticsAnalysisMonth month) {
    if (month.totalSeconds == null && month.measuredMilliseconds == 0) {
      return null;
    }
    final ms = math.max(
      (month.totalSeconds ?? 0) * 1000,
      month.measuredMilliseconds,
    );
    return ms > 0 && ms < 1000 ? '＜1s' : _compactTime(ms ~/ 1000);
  }

  String _compactTime(int seconds) => seconds < 60
      ? '${seconds}s'
      : seconds < 3600
      ? '${seconds ~/ 60}m'
      : '${seconds ~/ 3600}h${seconds ~/ 60 % 60 == 0 ? '' : '${seconds ~/ 60 % 60}m'}';

  double _timeSummary(double width) {
    final a = data.analysis;
    final hasDial = a.hourMilliseconds.any((value) => value > 0);
    final event = a.latestReading;
    final nightHero =
        options.template == ReadingReportTemplate.constellation &&
        event != null &&
        (event.at.hour >= 22 || event.at.hour < 6);
    final facts = <(String, String)>[
      if (event != null && !nightHero)
        (
          '最晚的一页',
          '${_analysisDate(event.at)} ${_analysisClock(event.at)}${_hasTitle(event.title) || options.hideBookTitles ? '\n${_analysisTitle(event.title)}' : ''}',
        ),
      if (a.longestSession case final session?)
        (
          '最长一次',
          '${_dimensionDuration(session.milliseconds)}${session.isClipped ? ' · 区间内' : ''}\n${_analysisDate(session.start)} ${_analysisClock(session.start)}—${_analysisDate(session.end) == _analysisDate(session.start) ? '' : '${_analysisDate(session.end)} '}${_analysisClock(session.end)}${_hasTitle(session.title) || options.hideBookTitles ? '\n${_analysisTitle(session.title)}' : ''}',
        ),
    ];
    if (!hasDial && facts.isEmpty) return 0;
    var top = hasDial
        ? _analysisLine('一天里的阅读时刻', 0, width, dark: night, heading: true)
        : 0.0;
    final wide = width >= 440;
    final dialSize = wide ? 250.0 : math.min(width, 280.0);
    final x = hasDial && wide ? dialSize + 26 : 0.0;
    final factWidth = width - x;
    var cursor = top;
    if (hasDial) {
      _analysisPlot(
        ReadingAnalysisChartKind.radial,
        [
          for (var hour = 0; hour < 24; hour++)
            ReadingAnalysisDatum('$hour时', a.hourMilliseconds[hour] / 3600000),
        ],
        top,
        dialSize,
        height: dialSize,
        dark: night,
      );
      if (!wide) cursor += dialSize + 16;
      if (a.nightRatio != null) {
        cursor +=
            printText(
              '夜读 22:00–06:00',
              x,
              cursor,
              width: factWidth,
              size: 13,
              weight: FontWeight.w600,
              color: colors.accent,
            ) +
            7;
        cursor +=
            printText(
              '${_dimensionDuration(a.nightMilliseconds)} · ${_analysisPercent(a.nightRatio)}',
              x,
              cursor,
              width: factWidth,
              size: 13,
              color: colors.muted,
            ) +
            17;
      }
    }
    for (final fact in facts) {
      cursor +=
          printText(
            fact.$1,
            x,
            cursor,
            width: factWidth,
            size: 13,
            weight: FontWeight.w600,
            color: colors.accent,
          ) +
          7;
      cursor +=
          printText(
            fact.$2,
            x,
            cursor,
            width: factWidth,
            size: 13,
            height: 1.5,
            color: colors.muted,
          ) +
          15;
    }
    return math.max(cursor, hasDial ? top + dialSize : 0.0) + 10;
  }

  double _calendarContent(double width, {bool heading = true}) {
    return drawReadingCalendar(width, heading: heading);
  }

  String _bookDuration(StatisticsAnalysisBook b) => _bookMilliseconds(b) > 0
      ? '${_dimensionDuration(_bookMilliseconds(b))}${b.hasPartialTimeCoverage ? ' · 部分时长' : ''}'
      : b.activeDates.isNotEmpty
      ? '${b.activeDates.length} 天相伴'
      : '';

  int _bookMilliseconds(StatisticsAnalysisBook book) =>
      math.max(book.measuredMilliseconds, (book.seconds ?? 0) * 1000);

  @override
  double printBookJourney(
    double width, {
    bool dark = false,
    bool withDates = true,
  }) {
    final months = data.analysis.months;
    final books = _rankedBooks
        .where((book) => book.activeMonths.isNotEmpty)
        .toList();
    if (books.isEmpty) return 0;
    var top = _analysisLine('相伴月份', 6, width, dark: night, heading: true);
    final capacity = math.max(1, (width / 35).floor());
    final blocks = (months.length / capacity).ceil();
    final ordinary = months.length ~/ blocks, extra = months.length % blocks;
    var start = 0;
    for (var block = 0; block < blocks; block++) {
      final count = ordinary + (block < extra ? 1 : 0);
      final span = months.skip(start).take(count).toList();
      start += count;
      top = _analysisLine(
        '${span.first.date.year}.${span.first.date.month.toString().padLeft(2, '0')}—${span.last.date.year}.${span.last.date.month.toString().padLeft(2, '0')}',
        top,
        width,
        dark: night,
      );
      final cell = (width - 28) / count;
      for (var month = 0; month < count; month++) {
        printText(
          '${span[month].date.month}',
          28 + month * cell,
          top,
          width: cell,
          size: 11.5,
          color: colors.muted,
          align: TextAlign.center,
        );
      }
      top += 25;
      for (final book in books) {
        final index = _rankedBooks.indexWhere((entry) => entry.id == book.id);
        printText(
          '${index + 1}'.padLeft(2, '0'),
          0,
          top,
          width: 23,
          size: 12,
          display: true,
          color: colors.muted,
        );
        for (var month = 0; month < count; month++) {
          final date = span[month].date;
          final active = book.activeMonths.any(
            (at) => at.year == date.year && at.month == date.month,
          );
          final bounds = Rect.fromLTWH(30 + month * cell, top + 5, cell - 4, 8);
          final paint = Paint()
            ..color = active
                ? colors.accent
                : colors.muted.withValues(alpha: .13);
          if (!active) {
            paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = .6;
          }
          canvas.drawRect(bounds, paint);
        }
        top += 24;
      }
      top += 8;
    }
    return _analysisLine('序号对应上方书单 · 色段：当月读过', top, width, dark: night);
  }

  String _milestoneBook(StatisticsAnalysisBook book) {
    if (has(ReadingReportModule.books)) {
      final index = _rankedBooks.indexWhere((b) => b.id == book.id);
      if (index >= 0) return '书目${(index + 1).toString().padLeft(2, '0')}';
    }
    return _hasTitle(book.title) || options.hideBookTitles
        ? _analysisTitle(book.title)
        : '';
  }

  double _progressContent(
    double width, {
    bool heading = true,
    bool positions = true,
  }) {
    var top = heading
        ? printHead(ReadingReportModule.progress, width, dark: night)
        : 0.0;
    final a = data.analysis;
    final knownPositions = data.progressBands.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    if (positions && knownPositions > 0) {
      top = _analysisLine('当前阅读位置 $knownPositions 本', top, width, dark: night);
      if (components?.progress case final image?) {
        final height = image.height * width / image.width;
        _image(image, 0, top, width: width, height: height);
        top += height + 12;
      }
      top = _analysisLine(
        '${_analysisDate(a.snapshotAt)} 进度快照',
        top,
        width,
        dark: night,
      );
    }
    final eventCount = a.firstOpenedBooks.length + a.completedBooks.length;
    if (eventCount > 3) {
      top = _at(
        top,
        width,
        (w) => printMonthlyMilestones(w, dark: night),
        gap: 10,
      );
    } else if (eventCount > 0) {
      final title = a.firstOpenedBooks.isEmpty
          ? '本期的完成'
          : a.completedBooks.isEmpty
          ? '本期的初见'
          : '本期的初见与完成';
      top = _analysisLine(title, top, width, dark: night, heading: true);
      final events = <(DateTime, String, StatisticsAnalysisBook)>[
        for (final book in a.firstOpenedBooks)
          (book.firstOpenedAt!, '初见', book),
        for (final book in a.completedBooks) (book.completedAt!, '完读', book),
      ]..sort((left, right) => left.$1.compareTo(right.$1));
      for (final event in events) {
        final title = _milestoneBook(event.$3);
        top = _analysisLine(
          '${_analysisDate(event.$1)} · ${event.$2}${title.isEmpty ? '' : ' $title'}',
          top,
          width,
          dark: night,
        );
      }
    }
    final serial = a.reachedEndBooks
        .where((book) => book.finished == false)
        .toList();
    if (serial.isNotEmpty) {
      top = _analysisLine(
        '读至连载结尾 ${serial.length}本',
        top,
        width,
        dark: night,
        heading: true,
      );
      for (final book in serial.take(options.bookLimit)) {
        final title = _milestoneBook(book);
        top = _analysisLine(
          '${_analysisDate(book.completedAt!)}${title.isEmpty ? '' : ' · $title'}',
          top,
          width,
          dark: night,
        );
      }
    }
    return top;
  }

  double _collectionContent(double width, {bool heading = true}) {
    var top = heading
        ? printHead(ReadingReportModule.collection, width, dark: night)
        : 0.0;
    final a = data.analysis;
    if (a.genres.any((g) => g.seconds > 0)) {
      top = _analysisLine('阅读口味 · 已测时长', top, width, dark: night);
      for (final g in a.genres.where((genre) => genre.seconds > 0)) {
        top = _analysisLine(
          '${g.label} · ${_compactTime(g.seconds)} · ${_analysisPercent(g.ratio)}',
          top,
          width,
          dark: night,
        );
      }
    }
    if (data.onlineBooks + data.localBooks > 0) {
      top = _analysisLine('当前藏书', top + 8, width, dark: night, heading: true);
      top = _analysisLine(
        '${data.onlineBooks + data.localBooks} 本${data.authorCount > 0 ? ' · ${data.authorCount} 位作者' : ''}\n在线 ${data.onlineBooks} / 本地 ${data.localBooks}',
        top,
        width,
        dark: night,
      );
      top +=
          printText(
            '${_analysisDate(a.snapshotAt)} 库存快照',
            0,
            top,
            width: width,
            size: 11.5,
            color: colors.muted,
          ) +
          12;
    }
    return top;
  }

  double _echoContent(double width, {bool heading = true}) {
    var top = heading
        ? printHead(ReadingReportModule.excerpts, width, dark: night)
        : 0.0;
    final excerpts = data.excerpts.take(2).toList();
    for (final excerpt in excerpts) {
      printText(
        '“',
        0,
        top - 3,
        width: 45,
        size: 55,
        fixedTitle: true,
        color: colors.accent,
      );
      top += 13;
      top +=
          printText(
            excerpt.quote,
            28,
            top,
            width: width - 28,
            size: 20,
            height: 1.7,
          ) +
          14;
      if (options.includeNotes && excerpt.note.isNotEmpty) {
        top +=
            printText(
              excerpt.note,
              28,
              top,
              width: width - 28,
              size: 13,
              color: colors.muted,
              height: 1.6,
            ) +
            11;
      }
      final source = [
        if (options.hideBookTitles)
          '来源已隐藏'
        else if (_hasTitle(excerpt.title))
          '《${excerpt.title}》',
        if (!options.hideBookTitles && excerpt.chapter.trim().isNotEmpty)
          excerpt.chapter,
      ];
      if (source.isNotEmpty) {
        top +=
            printText(
              source.join(' · '),
              28,
              top,
              width: width - 28,
              size: 12,
              color: colors.muted,
            ) +
            26;
      }
    }
    final marks = data.analysis.marks;
    if (marks.items.isNotEmpty) {
      top = _analysisLine('本期留下的记号', top, width, dark: night, heading: true);
      top = _analysisLine(
        [
          if (marks.bookmarks > 0) '${marks.bookmarks} 个书签',
          if (marks.excerpts > 0) '${marks.excerpts} 条摘录',
        ].join(' · '),
        top,
        width,
        dark: night,
      );
      final nightMarks = [
        if (marks.nightBookmarks > 0) '${marks.nightBookmarks}个书签',
        if (marks.nightExcerpts > 0) '${marks.nightExcerpts}条摘录',
      ];
      if (nightMarks.isNotEmpty) {
        top = _analysisLine(
          '其中夜读时留下 ${nightMarks.join(' · ')}',
          top,
          width,
          dark: night,
        );
      }
      for (final (i, b) in marks.byBook.take(options.bookLimit).indexed) {
        top = _analysisLine(
          [
            if (_hasTitle(b.title) || options.hideBookTitles)
              _analysisTitle(b.title, i),
            if (b.bookmarks > 0) '${b.bookmarks} 个书签',
            if (b.excerpts > 0) '${b.excerpts} 条摘录',
          ].join(' · '),
          top,
          width,
          dark: night,
        );
      }
    }
    if (marks.items.isEmpty && data.bookmarks + data.underlines > 0) {
      top = _analysisLine(
        '当前收藏 · ${[if (data.bookmarks > 0) '${data.bookmarks} 个书签', if (data.underlines > 0) '${data.underlines} 条划线'].join(' · ')}',
        top,
        width,
        dark: night,
      );
    }
    if (excerpts.isNotEmpty) {
      top +=
          printText(
            '当前保存 · 全部记录${options.includeNotes ? ' · 含批注文字' : ''}',
            0,
            top,
            width: width,
            size: 11.5,
            color: colors.muted,
          ) +
          10;
    }
    return top;
  }

  double _ending(double top) {
    if (options.template == ReadingReportTemplate.signal &&
        sections.isNotEmpty) {
      _illustration('char_birds', Rect.fromLTWH(32, top, 536, 155));
      top += 180;
    } else if (options.template == ReadingReportTemplate.festival &&
        sections.isNotEmpty) {
      _illustration('char_pv_end', Rect.fromLTWH(32, top, 536, 185));
      top += 207;
    }
    rule(32, top, 536, color: colors.ink.withValues(alpha: .2));
    top += 22;
    top +=
        printText(
          '下一页，仍是你的书与时间。',
          32,
          top,
          width: 536,
          size: 21,
          height: 1.5,
          color: colors.ink,
        ) +
        17;
    top +=
        printText(
          options.signature
              ? '$readingExportBrandName / WENKU8 · 私人阅读报告'
              : name,
          32,
          top,
          width: 536,
          size: 12,
          color: colors.muted,
        ) +
        9;
    return top;
  }
}
