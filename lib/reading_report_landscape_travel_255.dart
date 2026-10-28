part of 'reading_report_layout.dart';

enum _LandscapeQuoteStyle { ledger, walk, postcard }

/// Text and measurement primitives shared by three otherwise separate journeys.
abstract class _LandscapeEditionComposer extends _ReferencePosterComposer {
  _LandscapeEditionComposer(
    super.data,
    super.options,
    super.translate,
    super.components,
  );

  double _editionHeading(String code, String text, double width) {
    final codeHeight = printText(
      code,
      0,
      0,
      width: width,
      size: 10.5,
      color: colors.muted,
      weight: FontWeight.w600,
    );
    return codeHeight +
        9 +
        printText(
          text,
          0,
          codeHeight + 9,
          width: width,
          size: 27,
          weight: FontWeight.w600,
          fixedTitle: options.template == ReadingReportTemplate.ink,
        ) +
        22;
  }

  void _editionFooter(String line) {
    y += 12;
    rule(32, y, 536, color: colors.muted.withValues(alpha: .35));
    y += 25;
    y += printText(
      line,
      32,
      y,
      width: 536,
      size: 23,
      height: 1.45,
      fixedTitle: options.template == ReadingReportTemplate.ink,
    );
    y += 16;
    y += printText(
      options.signature ? '$readingExportBrandName / WENKU8 · 私人阅读报告' : name,
      32,
      y,
      width: 536,
      size: 11.5,
      color: colors.muted,
    );
    y += 20;
  }

  int _monthMilliseconds(StatisticsAnalysisMonth month) =>
      math.max((month.totalSeconds ?? 0) * 1000, month.measuredMilliseconds);

  bool _monthObserved(StatisticsAnalysisMonth month) =>
      month.totalSeconds != null || month.measuredMilliseconds > 0;

  String _monthStamp(StatisticsAnalysisMonth month) =>
      '${(month.date.year % 100).toString().padLeft(2, '0')}.${month.date.month.toString().padLeft(2, '0')}';

  String _monthTime(StatisticsAnalysisMonth month) {
    final milliseconds = _monthMilliseconds(month);
    return milliseconds > 0 && milliseconds < 1000
        ? '不足1秒'
        : _compactTime(milliseconds ~/ 1000);
  }

  /// A real session distribution, typeset as five short tickets rather than a
  /// second full-width chart. Zero buckets remain useful comparisons.
  double _focusTickets(double width) {
    final sessions = data.analysis.sessionLengths;
    if (!sessions.hasData) return 0;
    var top = _analysisLine(
      '完整单次 · ${sessions.completeSessionCount}次',
      0,
      width,
      dark: night,
      heading: true,
    );
    final columns = width >= 440 ? 5 : 2;
    final cell = width / columns;
    for (var start = 0; start < sessions.buckets.length; start += columns) {
      var height = 0.0;
      for (
        var col = 0;
        col < columns && start + col < sessions.buckets.length;
        col++
      ) {
        final bucket = sessions.buckets[start + col];
        final left = col * cell;
        canvas.drawLine(
          Offset(left, top),
          Offset(left + cell - 13, top),
          Paint()
            ..color = colors.muted.withValues(alpha: .28)
            ..strokeWidth = .8,
        );
        final titleHeight = printText(
          bucket.label,
          left,
          top + 10,
          width: cell - 13,
          size: 11.5,
          color: colors.muted,
        );
        final valueHeight = printText(
          '${bucket.count}',
          left,
          top + titleHeight + 17,
          width: cell - 13,
          size: 27,
          display: true,
          color: colors.accent,
          weight: FontWeight.w600,
          height: 1,
        );
        height = math.max(height, titleHeight + valueHeight + 31);
      }
      top += height + 14;
    }
    if (sessions.excludedClippedSessionCount > 0) {
      top = _analysisLine(
        '${sessions.excludedClippedSessionCount}次区间边界截断未纳入',
        top,
        width,
        dark: night,
      );
    }
    return top;
  }

  List<(String, DateTime)> get _calendarStops {
    final active = <DateTime>[
      for (var i = 0; i < data.dates.length; i++)
        if ((data.seconds[i] ?? 0) > 0) data.dates[i],
    ];
    if (active.isEmpty) return const [];
    return [
      ('本期第一日', active.first),
      if (data.peakDate != null &&
          data.peakDate != active.first &&
          data.peakDate != active.last)
        ('停留最长的一日', data.peakDate!),
      if (active.last != active.first) ('最近阅读日', active.last),
    ];
  }

  double _dateStamp(double width, {bool vertical = false}) {
    var top = _editionHeading('DATE / RECORDED DAYS', '日程印记', width);
    top = _analysisLine(
      '${math.max(data.activeDays, _activeDays)} 个阅读日',
      top,
      width,
      dark: night,
    );
    for (final stop in _calendarStops) {
      top += printText(
        stop.$1,
        0,
        top,
        width: width,
        size: 11.5,
        color: colors.muted,
      );
      top += 6;
      top += printText(
        _analysisDate(stop.$2),
        0,
        top,
        width: width,
        size: vertical ? 17 : 20,
        display: true,
        color: colors.accent,
        weight: FontWeight.w600,
      );
      top += 19;
    }
    final streak = data.analysis.longestStreak;
    if (streak.start != null && streak.end != null) {
      top = _analysisLine(
        '最长连续 ${streak.days}天\n${_analysisDate(streak.start!)}—${_analysisDate(streak.end!)}',
        top,
        width,
        dark: night,
      );
    }
    return top;
  }

  double _inventoryTicket(double width) {
    var top = _editionHeading('INVENTORY / SNAPSHOT', '此刻的书架', width);
    if (data.onlineBooks + data.localBooks > 0) {
      top = _analysisLine(
        '${data.onlineBooks + data.localBooks} 本藏书${data.authorCount > 0 ? ' · ${data.authorCount}位作者' : ''}',
        top,
        width,
        dark: night,
      );
      top = _analysisLine(
        '在线 ${data.onlineBooks} / 本地 ${data.localBooks}',
        top,
        width,
        dark: night,
      );
    }
    for (final genre in data.analysis.genres.where(
      (item) => item.seconds > 0,
    )) {
      top = _analysisLine(
        '${genre.label} · ${_compactTime(genre.seconds)}',
        top,
        width,
        dark: night,
      );
    }
    return top +
        printText(
          '${_analysisDate(data.analysis.snapshotAt)} 库存快照',
          0,
          top,
          width: width,
          size: 11.5,
          color: colors.muted,
        ) +
        8;
  }

  double _markCount(double top, double width) {
    final marks = data.analysis.marks;
    final facts = marks.items.isNotEmpty
        ? [
            '${marks.items.length} 个本期记号',
            if (marks.excerpts > 0) '其中 ${marks.excerpts} 条含原文',
          ]
        : [
            if (data.bookmarks + data.underlines > 0)
              '${data.bookmarks + data.underlines} 个收藏记号',
          ];
    if (facts.isEmpty) return top;
    return _analysisLine(facts.join(' · '), top, width, dark: night);
  }

  String _quoteSource(StatisticsExcerpt excerpt) => [
    if (options.hideBookTitles)
      '来源已隐藏'
    else if (_hasTitle(excerpt.title))
      '《${excerpt.title}》',
    if (!options.hideBookTitles && excerpt.chapter.trim().isNotEmpty)
      excerpt.chapter,
  ].join(' · ');

  double _quoteCards(double width, _LandscapeQuoteStyle style) {
    final excerpts = data.excerpts.take(2).toList();
    var top = 0.0;
    if (excerpts.isEmpty) {
      top = _editionHeading('NOTES / SAVED MARKS', '留下的记号', width);
      return _markCount(top, width);
    }
    if (style == _LandscapeQuoteStyle.ledger) {
      top = _editionHeading('POSTSCRIPT / READING NOTES', '航次的余音', width);
    }
    for (final (index, excerpt) in excerpts.indexed) {
      final cardTop = top;
      final postcard = style == _LandscapeQuoteStyle.postcard;
      final walking = style == _LandscapeQuoteStyle.walk;
      final inset = postcard
          ? 22.0
          : walking
          ? 20.0
          : 24.0;
      if (postcard) {
        printText(
          'POSTCARD / ${index + 1}',
          inset,
          top + 20,
          width: width - 100,
          size: 10.5,
          color: colors.muted,
          weight: FontWeight.w600,
        );
        canvas.drawRect(
          Rect.fromLTWH(width - 74, top + 17, 54, 36),
          Paint()
            ..color = colors.muted.withValues(alpha: .45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8,
        );
        printText(
          'W8',
          width - 66,
          top + 26,
          width: 38,
          size: 15,
          display: true,
          color: colors.accent,
          align: TextAlign.center,
        );
        top += 75;
      } else {
        if (walking) top += index == 0 ? 34 : 12;
        printText(
          '“',
          inset - 5,
          top - 8,
          width: 55,
          size: walking && index == 0 ? 80 : 54,
          fixedTitle: true,
          color: colors.accent,
        );
        top += walking && index == 0 ? 45 : 32;
      }
      top += printText(
        excerpt.quote,
        inset,
        top,
        width: width - inset * 2,
        size: walking && index == 0
            ? 31
            : postcard
            ? 24
            : 22,
        height: walking ? 1.65 : 1.55,
        fixedTitle: walking,
        weight: walking && index == 0 ? FontWeight.w600 : FontWeight.normal,
      );
      top += 20;
      if (options.includeNotes && excerpt.note.trim().isNotEmpty) {
        top += printText(
          excerpt.note,
          inset,
          top,
          width: width - inset * 2,
          size: 13,
          height: 1.6,
          color: colors.muted,
        );
        top += 13;
      }
      final source = _quoteSource(excerpt);
      if (source.isNotEmpty) {
        top += printText(
          source,
          inset,
          top,
          width: width - inset * 2,
          size: 12,
          height: 1.4,
          color: colors.muted,
        );
        top += 15;
      }
      top += postcard
          ? 22
          : walking
          ? 32
          : 15;
      if (postcard) {
        canvas.drawRect(
          Rect.fromLTWH(0, cardTop, width, top - cardTop),
          Paint()
            ..color = colors.muted.withValues(alpha: .40)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .9,
        );
      } else if (style == _LandscapeQuoteStyle.ledger) {
        canvas.drawLine(
          Offset(0, cardTop + 16),
          Offset(0, top - 12),
          Paint()
            ..color = colors.accent
            ..strokeWidth = 3,
        );
      }
      top += postcard ? 25 : 18;
    }
    return _markCount(top + 3, width);
  }

  double _bookFacts(
    StatisticsAnalysisBook book,
    int index,
    double x,
    double top,
    double width, {
    double titleSize = 18,
    bool dates = false,
  }) {
    if (_hasTitle(book.title) || options.hideBookTitles) {
      top += printText(
        _analysisTitle(book.title, index),
        x,
        top,
        width: width,
        size: titleSize,
        height: 1.35,
        weight: FontWeight.w600,
      );
      top += 7;
    }
    if (!options.hideAuthorNames &&
        readingReportHasAuthorText(book.book?.author)) {
      top += printText(
        book.book!.author,
        x,
        top,
        width: width,
        size: 11.5,
        color: colors.muted,
      );
      top += 6;
    }
    if (_bookDuration(book).isNotEmpty) {
      top += printText(
        _bookDuration(book),
        x,
        top,
        width: width,
        size: 13,
        color: colors.accent,
      );
      top += 9;
    }
    if (dates && book.activeDates.isNotEmpty) {
      final first = book.activeDates.first, last = book.activeDates.last;
      top += printText(
        '${_analysisDate(first)}${first == last ? '' : '—${_analysisDate(last)}'}',
        x,
        top,
        width: width,
        size: 11.5,
        color: colors.muted,
        height: 1.4,
      );
      top += 9;
    }
    return top;
  }

  void _twoColumns(
    ReadingReportModule left,
    double Function(double) drawLeft,
    ReadingReportModule right,
    double Function(double) drawRight, {
    double leftWidth = 254,
    double gap = 28,
  }) {
    final hasLeft = has(left), hasRight = has(right);
    if (!hasLeft && !hasRight) return;
    if (!hasLeft) {
      emit(right, drawRight);
      return;
    }
    if (!hasRight) {
      emit(left, drawLeft);
      return;
    }
    final top = y;
    final rightWidth = 536 - gap - leftWidth;
    final a = plate(left, leftWidth, drawLeft);
    final b = plate(right, rightWidth, drawRight);
    if (a.height > 0) {
      hang(a, 32, top);
    } else {
      a.picture.dispose();
    }
    if (b.height > 0) {
      hang(b, 32 + leftWidth + gap, top);
    } else {
      b.picture.dispose();
    }
    y = top + math.max(a.height, b.height) + 30;
  }
}

/// An industrial ledger: a broad harbour, a date margin and a cargo manifest.
class _HarborPosterComposer extends _LandscapeEditionComposer {
  _HarborPosterComposer(
    super.data,
    super.options,
    super.translate,
    super.components,
  );

  late final ReadingReportColors _ledger = ReadingReportColors.surface(
    background: const Color(0xffe5ebe7),
    ink: const Color(0xff21332f),
    muted: const Color(0xff61716b),
    accent: options.palette == ReadingReportPalette.pine
        ? const Color(0xff3c6a5c)
        : Color.lerp(
            const Color(0xff21332f),
            ReadingReportColors(options).accent,
            .4,
          )!,
  );

  @override
  ReadingReportLayout compose() {
    if (readingReportVisibleModules(data, options).isEmpty && !_hasReading) {
      return super.compose();
    }
    final recorder = ui.PictureRecorder();
    canvas = Canvas(recorder);
    _masthead();
    _illustration(
      readingReportHeroArt(data, options),
      const Rect.fromLTWH(0, 87, 600, 338),
    );
    y = 455;
    final titleHeight = imageTitle('阅读\n报告', 32, y, width: 118, size: 34);
    final nameTop = y + titleHeight + 16;
    final nameHeight = printText(
      name,
      32,
      nameTop,
      width: 118,
      size: 14,
      height: 1.4,
    );
    final rangeTop = nameTop + nameHeight + 13;
    final rangeH = printText(
      range,
      32,
      rangeTop,
      width: 118,
      size: 11.5,
      height: 1.45,
      color: colors.muted,
    );
    printText(
      'READING / VOYAGE',
      193,
      y + 3,
      width: 375,
      size: 11,
      color: colors.muted,
    );
    final total = _hasReading
        ? _total(188, y + 28, 380, size: 103)
        : printText(
            '在书页停靠',
            193,
            y + 43,
            width: 375,
            size: 34,
            weight: FontWeight.w600,
          );
    final headerHeight = math.max(
      217.0,
      math.max(rangeTop - y + rangeH, 28 + total),
    );
    canvas.drawLine(
      Offset(166, y),
      Offset(166, y + headerHeight),
      Paint()
        ..color = colors.muted.withValues(alpha: .45)
        ..strokeWidth = .8,
    );
    y += headerHeight + 25;
    if (options.note.trim().isNotEmpty) {
      y +=
          printText(
            options.note.trim(),
            193,
            y,
            width: 375,
            size: 14,
            color: colors.muted,
            height: 1.65,
          ) +
          27;
    }
    if (has(ReadingReportModule.days) ||
        has(ReadingReportModule.books) ||
        has(ReadingReportModule.calendar)) {
      paintSurface(_ledger, () {
        y += 32;
        _twoColumns(
          ReadingReportModule.days,
          (w) => _dateStamp(w, vertical: w < 200),
          ReadingReportModule.books,
          _cargoManifest,
          leftWidth: 138,
          gap: 30,
        );
        emit(ReadingReportModule.calendar, _calendarContent);
        y += 6;
      });
    }
    if (has(ReadingReportModule.rhythm)) {
      y += 35;
      emit(ReadingReportModule.rhythm, _voyageTime);
    }
    if (has(ReadingReportModule.progress)) {
      paintSurface(_ledger, () {
        y += 30;
        emit(ReadingReportModule.progress, _checkpointLog);
      });
    }
    y += 22;
    emit(ReadingReportModule.collection, _inventoryTicket);
    if (has(ReadingReportModule.excerpts)) {
      paintSurface(_ledger, () {
        y += 28;
        emit(
          ReadingReportModule.excerpts,
          (w) => _quoteCards(w, _LandscapeQuoteStyle.ledger),
        );
      });
    }
    _editionFooter('下一页，继续启航。');
    return finishPlate(recorder, y + 20);
  }

  double _cargoManifest(double width) {
    var top = _editionHeading('MANIFEST / BOOK INDEX', '相伴书目清单', width);
    for (final (index, book) in _rankedBooks.indexed) {
      rule(0, top, width, color: colors.muted.withValues(alpha: .32));
      printText(
        '${index + 1}'.padLeft(2, '0'),
        0,
        top + 13,
        width: 28,
        size: 20,
        display: true,
        color: colors.accent,
      );
      top =
          _bookFacts(book, index, 43, top + 13, width - 43, titleSize: 18) + 15;
    }
    return _analysisLine(
      '选录 ${_rankedBooks.length}/$_bookCount 本',
      top + 3,
      width,
      dark: night,
    );
  }

  double _voyageTime(double width) {
    var top = _editionHeading('WATCH / TIME LEDGER', '时间刻度', width);
    final months = data.analysis.months.where(_monthObserved).toList();
    final maximum = months.map(_monthMilliseconds).fold<int>(0, math.max);
    if (maximum > 0) {
      for (final month in months) {
        printText(
          _monthStamp(month),
          0,
          top + 1,
          width: 58,
          size: 12,
          display: true,
          color: colors.muted,
        );
        printText(
          _monthTime(month),
          70,
          top + 1,
          width: 105,
          size: 12,
          color: colors.ink,
        );
        if (months.length > 1) {
          final bounds = Rect.fromLTWH(184, top + 7, width - 184, 4);
          canvas.drawRect(
            bounds,
            Paint()..color = colors.muted.withValues(alpha: .13),
          );
          if (_monthMilliseconds(month) > 0) {
            canvas.drawRect(
              Rect.fromLTWH(
                bounds.left,
                bounds.top,
                bounds.width * _monthMilliseconds(month) / maximum,
                bounds.height,
              ),
              Paint()..color = colors.accent,
            );
          }
        }
        top += 28;
      }
      top += 21;
    }
    top = _at(top, width, _timeSummary, gap: 18);
    return _at(top, width, _focusTickets, gap: 4);
  }

  double _checkpointLog(double width) {
    var top = _editionHeading('CHECKPOINTS / PAGE LOG', '航次中的书页', width);
    final known = data.progressBands.fold<int>(0, (sum, count) => sum + count);
    if (known > 0) {
      final cell = width / 4;
      for (var index = 0; index < 4; index++) {
        final x = index * cell;
        final count = data.progressBands[index];
        printText(
          '$count',
          x,
          top,
          width: cell - 12,
          size: 31,
          display: true,
          color: colors.accent,
          weight: FontWeight.w600,
        );
        printText(
          '${index * 25}–${(index + 1) * 25}%',
          x,
          top + 41,
          width: cell - 12,
          size: 11.5,
          color: colors.muted,
        );
        rule(x, top + 66, cell - 15, color: colors.muted.withValues(alpha: .2));
        if (count > 0) {
          canvas.drawRect(
            Rect.fromLTWH(x, top + 64.5, (cell - 15) * count / known, 3),
            Paint()..color = colors.accent,
          );
        }
      }
      top += 84;
      top = _analysisLine(
        '${_analysisDate(data.analysis.snapshotAt)} · $known 本的阅读位置快照',
        top,
        width,
        dark: night,
      );
      top += 12;
    }
    return _at(
      top,
      width,
      (w) => _progressContent(w, heading: false, positions: false),
      gap: 0,
    );
  }
}

/// A walking journal: actual reading dates and books become a broken path,
/// while the quotation is a spacious pause between its two halves.
class _MountainPosterComposer extends _LandscapeEditionComposer {
  _MountainPosterComposer(
    super.data,
    super.options,
    super.translate,
    super.components,
  );

  @override
  ReadingReportLayout compose() {
    if (readingReportVisibleModules(data, options).isEmpty && !_hasReading) {
      return super.compose();
    }
    final recorder = ui.PictureRecorder();
    canvas = Canvas(recorder);
    _paperGround();
    _masthead();
    y = 92;
    y += imageTitle('阅读报告', 32, y, width: 536, size: 51) + 28;
    _illustration(
      readingReportHeroArt(data, options),
      Rect.fromLTWH(0, y, 600, 338),
    );
    y += 378;
    printText(
      '把日子，慢慢读成一条路。',
      32,
      y,
      width: 536,
      size: 19,
      fixedTitle: true,
      height: 1.5,
    );
    y += 49;
    if (_hasReading) {
      final height = _total(32, y, 290, size: 91, color: colors.accent);
      final identityHeight = _identity(y + 11, x: 357, width: 211) - y;
      y += math.max(height, identityHeight) + 45;
    } else {
      y = _identity(y) + 30;
    }
    emit(ReadingReportModule.days, _walkingDates, gap: 32);
    emit(ReadingReportModule.calendar, _calendarContent, gap: 32);
    final split = math.min(2, _rankedBooks.length);
    emit(ReadingReportModule.books, (w) => _walkingBooks(w, 0, split), gap: 10);
    emit(
      ReadingReportModule.excerpts,
      (w) => _quoteCards(w, _LandscapeQuoteStyle.walk),
      x: 48,
      width: 504,
      gap: 40,
    );
    if (_rankedBooks.length > split) {
      emit(
        ReadingReportModule.books,
        (w) => _walkingBooks(w, split, _rankedBooks.length),
        gap: 35,
      );
    }
    emit(ReadingReportModule.rhythm, _walkingTime, gap: 35);
    emit(
      ReadingReportModule.progress,
      (w) {
        var top = _editionHeading('ALONG THE WAY / PAGE MARKS', '走到这里了', w);
        return _at(top, w, (width) => _progressContent(width, heading: false));
      },
      x: 70,
      width: 460,
      gap: 48,
    );
    emit(
      ReadingReportModule.collection,
      _inventoryTicket,
      x: 285,
      width: 283,
      gap: 34,
    );
    _editionFooter('走得慢一点，也会遇见下一页。');
    return finishPlate(recorder, y + 20);
  }

  double _walkingDates(double width) {
    var top = _editionHeading('DAYS / FOOTSTEPS', '日子留下的脚印', width);
    final stops = _calendarStops;
    const lineX = 112.0;
    if (stops.length > 1) {
      canvas.drawLine(
        Offset(lineX, top + 8),
        Offset(lineX, top + (stops.length - 1) * 73 + 8),
        Paint()
          ..color = colors.muted.withValues(alpha: .35)
          ..strokeWidth = 1,
      );
    }
    for (final stop in stops) {
      canvas.drawCircle(
        Offset(lineX, top + 9),
        4,
        Paint()..color = colors.accent,
      );
      printText(
        stop.$1,
        0,
        top + 2,
        width: 96,
        size: 11.5,
        color: colors.muted,
      );
      printText(
        _analysisDate(stop.$2),
        137,
        top,
        width: width - 137,
        size: 24,
        display: true,
        color: colors.accent,
      );
      top += 73;
    }
    final streak = data.analysis.longestStreak;
    return _analysisLine(
      '${math.max(data.activeDays, _activeDays)} 个阅读日${streak.days > 0 ? ' · 最长连续 ${streak.days} 天' : ''}',
      top,
      width,
      dark: night,
    );
  }

  double _walkingBooks(double width, int start, int end) {
    if (start >= end) return 0;
    var top = 10.0;
    if (start == 0) {
      top = _editionHeading('BOOKS / WAYPOINTS', '经过的书中世界', width);
    }
    final middle = width / 2;
    for (var index = start; index < end; index++) {
      final book = _rankedBooks[index];
      final left = index.isEven;
      final nodeY = top + 19;
      final textX = left ? 0.0 : middle + 36;
      final textWidth = middle - 36;
      printText(
        '${index + 1}'.padLeft(2, '0'),
        middle - 22,
        top + 5,
        width: 44,
        size: 21,
        display: true,
        align: TextAlign.center,
        color: colors.accent,
      );
      canvas.drawCircle(
        Offset(middle, nodeY + 31),
        3.5,
        Paint()..color = colors.accent,
      );
      canvas.drawLine(
        Offset(left ? textWidth + 9 : middle + 10, nodeY + 31),
        Offset(left ? middle - 10 : textX - 9, nodeY + 31),
        Paint()
          ..color = colors.muted.withValues(alpha: .35)
          ..strokeWidth = .8,
      );
      final bottom = _bookFacts(
        book,
        index,
        textX,
        top,
        textWidth,
        titleSize: index == 0 ? 22 : 18,
        dates: true,
      );
      final rowHeight = math.max(115.0, bottom - top + 27);
      canvas.drawLine(
        Offset(middle, nodeY + 43),
        Offset(middle, top + rowHeight),
        Paint()
          ..color = colors.muted.withValues(alpha: .25)
          ..strokeWidth = 1,
      );
      top += rowHeight;
    }
    return top + 15;
  }

  double _walkingTime(double width) {
    var top = _editionHeading('MONTHS / SMALL PAUSES', '途中停留的时间', width);
    final months = data.analysis.months;
    final maximum = months.map(_monthMilliseconds).fold<int>(0, math.max);
    if (maximum > 0) {
      final columns = math.max(1, (width / 76).floor());
      final cell = width / columns;
      for (var first = 0; first < months.length; first += columns) {
        for (var col = 0; col < columns && first + col < months.length; col++) {
          final month = months[first + col];
          final value = _monthMilliseconds(month);
          final center = Offset(col * cell + cell / 2, top + 25);
          if (value > 0) {
            canvas.drawCircle(
              center,
              17 * math.sqrt(value / maximum),
              Paint()..color = colors.accent.withValues(alpha: .73),
            );
          } else if (_monthObserved(month)) {
            canvas.drawCircle(
              center,
              3,
              Paint()
                ..color = colors.muted.withValues(alpha: .35)
                ..style = PaintingStyle.stroke
                ..strokeWidth = .7,
            );
          }
          printText(
            _monthStamp(month),
            col * cell,
            top + 53,
            width: cell,
            size: 11.5,
            align: TextAlign.center,
            color: colors.muted,
          );
          if (_monthObserved(month)) {
            printText(
              _monthTime(month),
              col * cell,
              top + 74,
              width: cell,
              size: 11.5,
              align: TextAlign.center,
            );
          }
        }
        top += 109;
      }
      top = _analysisLine('着色圆面积按已记录时长', top, width, dark: night);
      top += 18;
    }
    top = _at(top, width, _timeSummary, gap: 28);
    return _at(top, width, _focusTickets, gap: 8);
  }
}

/// A train ticket and a chain of destinations, not another three-act film.
class _TravelPosterComposer extends _LandscapeEditionComposer {
  _TravelPosterComposer(
    super.data,
    super.options,
    super.translate,
    super.components,
  );

  late final ReadingReportColors _ticket = ReadingReportColors.surface(
    background: const Color(0xfff5f2e9),
    ink: const Color(0xff2b4149),
    muted: const Color(0xff6c7c7b),
    accent: options.palette == ReadingReportPalette.pine
        ? const Color(0xffb96f44)
        : Color.lerp(
            const Color(0xff2b4149),
            ReadingReportColors(options).accent,
            .6,
          )!,
  );

  @override
  ReadingReportLayout compose() {
    if (readingReportVisibleModules(data, options).isEmpty && !_hasReading) {
      return super.compose();
    }
    final recorder = ui.PictureRecorder();
    canvas = Canvas(recorder);
    _masthead();
    y = 90;
    y += imageTitle('阅读报告', 32, y, width: 536, size: 48) + 24;
    _illustration(
      readingReportHeroArt(data, options),
      Rect.fromLTWH(0, y, 600, 338),
    );
    y += 312;
    paintSurface(_ticket, () {
      y += 28;
      perforation(32, y, 536);
      y += 23;
      printText(
        'PASSENGER / $name',
        32,
        y,
        width: 536,
        size: 14,
        weight: FontWeight.w600,
      );
      y += 29;
      printText('本期旅程', 32, y, width: 202, size: 12, color: colors.muted);
      final durationHeight = _hasReading
          ? _total(28, y + 22, 300, size: 98)
          : printText(
              '从一页出发',
              32,
              y + 23,
              width: 300,
              size: 31,
              weight: FontWeight.w600,
            );
      final rangeHeight = printText(
        range,
        360,
        y + 28,
        width: 208,
        size: 15,
        height: 1.55,
        color: colors.muted,
      );
      if (has(ReadingReportModule.books) && _bookCount > 0) {
        printText(
          '$_bookCount 本相伴书目',
          360,
          y + rangeHeight + 45,
          width: 208,
          size: 16,
          color: colors.accent,
        );
      }
      y += math.max(22 + durationHeight, 90 + rangeHeight) + 24;
      if (options.note.trim().isNotEmpty) {
        y +=
            printText(
              options.note.trim(),
              32,
              y,
              width: 536,
              size: 14,
              color: colors.muted,
              height: 1.65,
            ) +
            24;
      }
      perforation(32, y, 536);
      y += 33;
    });
    y += 30;
    emit(ReadingReportModule.books, _bookStations, gap: 35);
    if (has(ReadingReportModule.rhythm) ||
        has(ReadingReportModule.days) ||
        has(ReadingReportModule.collection) ||
        has(ReadingReportModule.calendar)) {
      paintSurface(_ticket, () {
        y += 32;
        emit(ReadingReportModule.rhythm, _railTime, gap: 28);
        _twoColumns(
          ReadingReportModule.days,
          (w) => _dateStamp(w),
          ReadingReportModule.collection,
          _inventoryTicket,
          leftWidth: 254,
          gap: 28,
        );
        emit(ReadingReportModule.calendar, _calendarContent);
        y += 3;
      });
    }
    y += 32;
    emit(
      ReadingReportModule.progress,
      (w) {
        var top = _editionHeading('VALIDATION / PAGE STAMPS', '书页签注', w);
        return _at(top, w, (width) => _progressContent(width, heading: false));
      },
      x: 48,
      width: 504,
      gap: 38,
    );
    if (has(ReadingReportModule.excerpts)) {
      paintSurface(_ticket, () {
        y += 30;
        emit(
          ReadingReportModule.excerpts,
          (w) => _quoteCards(w, _LandscapeQuoteStyle.postcard),
          x: 48,
          width: 504,
          gap: 22,
        );
      });
    }
    if (sections.isNotEmpty) {
      y += 20;
      _illustration('char_pv_end', Rect.fromLTWH(0, y, 600, 246));
      y += 275;
    }
    _editionFooter('下一站，仍有书页。');
    return finishPlate(recorder, y + 20);
  }

  double _bookStations(double width) {
    var top = _editionHeading('STATIONS / BOOK WORLDS', '在书中停靠', width);
    final lineX = 18.0;
    for (final (index, book) in _rankedBooks.indexed) {
      final rowTop = top;
      canvas.drawCircle(
        Offset(lineX, rowTop + 13),
        12,
        Paint()..color = colors.accent,
      );
      printText(
        '${index + 1}',
        7,
        rowTop + 4,
        width: 22,
        size: 14,
        display: true,
        align: TextAlign.center,
        color: colors.background,
        weight: FontWeight.w600,
      );
      top =
          _bookFacts(
            book,
            index,
            56,
            rowTop,
            width - 56,
            titleSize: index == 0 ? 25 : 20,
            dates: true,
          ) +
          24;
      if (index < _rankedBooks.length - 1) {
        canvas.drawLine(
          Offset(lineX, rowTop + 27),
          Offset(lineX, top + 3),
          Paint()
            ..color = colors.accent.withValues(alpha: .55)
            ..strokeWidth = 1.5,
        );
      }
      rule(
        56,
        top - 11,
        width - 56,
        color: colors.muted.withValues(alpha: .25),
      );
    }
    return top +
        printText(
          '选录 ${_rankedBooks.length}/$_bookCount 站',
          56,
          top,
          width: width - 56,
          size: 12,
          color: colors.muted,
        ) +
        7;
  }

  double _railTime(double width) {
    var top = _editionHeading('TIMETABLE / READING ROUTE', '月份站台', width);
    final months = data.analysis.months;
    if (months.any((month) => _monthMilliseconds(month) > 0)) {
      final columns = math.max(1, (width / 120).floor());
      final cell = width / columns;
      for (var first = 0; first < months.length; first += columns) {
        final count = math.min(columns, months.length - first);
        final firstX = cell / 2, lastX = cell * (count - .5);
        if (count > 1) {
          canvas.drawLine(
            Offset(firstX, top + 17),
            Offset(lastX, top + 17),
            Paint()
              ..color = colors.muted.withValues(alpha: .35)
              ..strokeWidth = 1,
          );
        }
        for (var col = 0; col < count; col++) {
          final month = months[first + col];
          final positive = _monthMilliseconds(month) > 0;
          final center = Offset(cell * (col + .5), top + 17);
          final mark = Paint()
            ..color = positive
                ? colors.accent
                : colors.muted.withValues(alpha: .4);
          if (!positive) {
            mark
              ..style = PaintingStyle.stroke
              ..strokeWidth = .8;
          }
          if (positive || _monthObserved(month)) {
            canvas.drawCircle(center, positive ? 5 : 3, mark);
          }
          printText(
            _monthStamp(month),
            col * cell,
            top + 38,
            width: cell,
            size: 14,
            display: true,
            align: TextAlign.center,
          );
          if (_monthObserved(month)) {
            printText(
              _monthTime(month),
              col * cell,
              top + 64,
              width: cell,
              size: 12,
              color: colors.muted,
              align: TextAlign.center,
            );
          }
        }
        top += 104;
      }
      top += 14;
    }
    top = _at(top, width, _timeSummary, gap: 24);
    return _at(top, width, _focusTickets, gap: 6);
  }
}
