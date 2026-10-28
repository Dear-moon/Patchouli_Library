part of 'reading_report_layout.dart';

/// Identity, ruled records and an archive-hall pause: not a chart-page skin.
class _ArchivePosterComposer extends _ReferencePosterComposer {
  _ArchivePosterComposer(
    super.data,
    super.options,
    super.translate,
    super.components,
  );

  var _archiveChapter = 0;

  late final ReadingReportColors _archiveDark = ReadingReportColors.surface(
    background: const Color(0xff202925),
    ink: const Color(0xfff4f3ec),
    muted: const Color(0xffb3beb5),
    accent: colors.accent,
  );

  @override
  ReadingReportLayout compose() {
    if (readingReportVisibleModules(data, options).isEmpty) {
      return super.compose();
    }
    final recorder = ui.PictureRecorder();
    canvas = Canvas(recorder);
    _archiveChapter = 0;
    _paperGround();
    y = _archiveHero();
    if (_hasReading) {
      paintSurface(_archiveDark, () {
        y += 22;
        printText(
          'TOTAL READING TIME',
          32,
          y,
          width: 536,
          size: 11,
          color: colors.muted,
        );
        y += 22 + _total(28, y + 22, 540, size: 98, color: colors.ink) + 20;
      });
      final teal = colors.accent;
      paintSurface(
        ReadingReportColors.surface(
          background: teal,
          ink: paper,
          muted: paper.withValues(alpha: .77),
          accent: paper,
        ),
        () {
          y += 18;
          final facts = <(String, String)>[
            if (math.max(data.activeDays, _activeDays) > 0)
              ('${math.max(data.activeDays, _activeDays)}', '阅读日'),
            if (data.analysis.longestStreak.days > 0)
              ('${data.analysis.longestStreak.days}', '最长连续 / 天'),
            if (_bookCount > 0) ('$_bookCount', '相伴书目'),
            if (data.averageSeconds > 0)
              (statisticsDuration(data.averageSeconds), '已记录日均'),
          ];
          final cell = 536 / facts.length;
          var height = 0.0;
          for (final (index, fact) in facts.indexed) {
            final x = 32 + index * cell;
            final valueHeight = printText(
              fact.$1,
              x,
              y,
              width: cell - 12,
              size: fact.$1.length > 5 ? 24 : 36,
              display: fact.$1.length < 5,
              height: 1.1,
              weight: FontWeight.w700,
              color: colors.ink,
            );
            final labelHeight = printText(
              fact.$2,
              x,
              y + valueHeight + 8,
              width: cell - 12,
              size: 12,
              color: colors.muted,
            );
            height = math.max(height, valueHeight + labelHeight + 8);
          }
          y += height + 18;
        },
      );
    }
    y += 30;
    emit(ReadingReportModule.progress, _archiveProfile, gap: 30);
    emit(ReadingReportModule.days, _archiveDates, gap: 34);
    emit(ReadingReportModule.calendar, _calendarContent, gap: 34);
    emit(
      ReadingReportModule.collection,
      _archiveHall,
      x: 0,
      width: 600,
      gap: 34,
    );
    emit(ReadingReportModule.rhythm, _archiveTimeLedger, gap: 34);
    emit(ReadingReportModule.books, _archiveBookIndex, gap: 34);
    emit(ReadingReportModule.excerpts, _archiveNotes, gap: 34);
    rule(32, y, 536, color: colors.ink.withValues(alpha: .25));
    y += 19;
    printText(
      'ARCHIVE ENDS / KEEP READING',
      32,
      y,
      width: 330,
      size: 10.5,
      color: colors.muted,
    );
    printText(
      '${data.today.year}.${data.today.month.toString().padLeft(2, '0')}',
      444,
      y,
      width: 124,
      size: 11,
      color: colors.muted,
      align: TextAlign.right,
    );
    y += 27;
    y +=
        printText(
          options.signature ? '$readingExportBrandName / WENKU8' : name,
          32,
          y,
          width: 536,
          size: 13,
          weight: FontWeight.w600,
        ) +
        27;
    return finishPlate(recorder, y);
  }

  double _archiveHero() {
    _masthead();
    _illustration(
      readingReportHeroArt(data, options),
      const Rect.fromLTWH(260, 82, 340, 420),
      alignment: Alignment.topRight,
    );
    horizontalShade(
      const Rect.fromLTWH(236, 82, 98, 420),
      color: colors.background,
      opacity: 1,
    );
    canvas.drawRect(
      const Rect.fromLTWH(32, 96, 210, 24),
      Paint()..color = colors.ink,
    );
    printText(
      'FILE / ${data.today.year}${data.today.month.toString().padLeft(2, '0')}${data.today.day.toString().padLeft(2, '0')}',
      40,
      102,
      width: 196,
      size: 11,
      color: colors.background,
    );
    var left = 140.0;
    left += imageTitle('阅读报告', 32, left, width: 220, size: 28) + 24;
    left +=
        printText(
          name,
          32,
          left,
          width: 220,
          size: 43,
          weight: FontWeight.w700,
          height: 1.18,
        ) +
        17;
    left +=
        printText(
          range,
          32,
          left,
          width: 220,
          size: 12,
          color: colors.muted,
          height: 1.5,
        ) +
        21;
    if (options.note.trim().isNotEmpty) {
      left +=
          printText(
            options.note.trim(),
            32,
            left,
            width: 214,
            size: 14,
            color: colors.muted,
            height: 1.6,
          ) +
          18;
    }
    return math.max(502.0, left + 24);
  }

  double _archiveHeading(String title, double width) {
    final code = '${++_archiveChapter}'.padLeft(2, '0');
    printText(
      code,
      0,
      1,
      width: 38,
      size: 25,
      display: true,
      color: colors.accent,
      weight: FontWeight.w700,
    );
    return math.max(
          34.0,
          printText(
            title,
            52,
            0,
            width: width - 52,
            size: 26,
            weight: FontWeight.w600,
          ),
        ) +
        20;
  }

  double _archiveProfile(double width) {
    final top = _archiveHeading('书页上的记录', width);
    const portraitWidth = 144.0, inset = 174.0;
    _illustration(
      'char_full',
      Rect.fromLTWH(0, top, portraitWidth, 256),
      alignment: Alignment.topCenter,
    );
    printText(
      'ON FILE',
      0,
      top + 269,
      width: portraitWidth,
      size: 10.5,
      color: colors.muted,
    );
    canvas.save();
    canvas.translate(inset, top);
    final records = _progressContent(width - inset, heading: false);
    canvas.restore();
    return top + math.max(287.0, records);
  }

  double _archiveDates(double width) {
    var top = _archiveHeading('留下来的日期', width);
    top = _archiveField(
      '记录覆盖',
      '${data.observedDays} / ${data.period} 天',
      top,
      width,
    );
    if (data.peakDate case final date?) {
      top = _archiveField(
        '最长的一日',
        '${_analysisDate(date)} · ${statisticsDuration(data.peakSeconds)}',
        top,
        width,
      );
    }
    final streak = data.analysis.longestStreak;
    if (streak.start != null && streak.end != null) {
      top = _archiveField(
        '连续阅读段',
        '${_analysisDate(streak.start!)}—${_analysisDate(streak.end!)}',
        top,
        width,
      );
    }
    return top;
  }

  double _archiveField(String label, String value, double top, double width) {
    final labelHeight = printText(
      label,
      0,
      top + 2,
      width: 116,
      size: 12,
      color: colors.muted,
    );
    final valueHeight = printText(
      value,
      132,
      top,
      width: width - 132,
      size: 15,
      height: 1.45,
      weight: FontWeight.w600,
    );
    final bottom = top + math.max(labelHeight, valueHeight) + 13;
    rule(
      0,
      bottom,
      width,
      color: colors.ink.withValues(alpha: .16),
      stroke: .6,
    );
    return bottom + 13;
  }

  double _archiveHall(double width) {
    _illustration('bg_hall', Rect.fromLTWH(0, 0, width, 252));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, 252),
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xff202925).withValues(alpha: .94),
            const Color(0xff202925).withValues(alpha: .1),
          ],
        ).createShader(Rect.fromLTWH(0, 0, width, 252)),
    );
    printText(
      'THE READING HALL',
      32,
      25,
      width: 390,
      size: 11,
      color: paper.withValues(alpha: .74),
    );
    final inventory = data.onlineBooks + data.localBooks;
    final genres = data.analysis.genres
        .where((genre) => genre.seconds > 0)
        .toList();
    if (inventory > 0) {
      printText(
        '$inventory',
        28,
        104,
        width: 260,
        size: 80,
        display: true,
        height: 1,
        weight: FontWeight.w700,
        color: paper,
      );
      printText('本当前藏书', 32, 194, width: 280, size: 17, color: paper);
    } else if (genres.isNotEmpty) {
      printText(
        '${genres.length}',
        28,
        104,
        width: 260,
        size: 80,
        display: true,
        height: 1,
        weight: FontWeight.w700,
        color: paper,
      );
      printText('种已记录的阅读题材', 32, 194, width: 330, size: 17, color: paper);
    }
    printText(
      _analysisDate(data.analysis.snapshotAt),
      width - 200,
      220,
      width: 168,
      size: 11,
      color: paper.withValues(alpha: .72),
      align: TextAlign.right,
    );
    var top = 274.0;
    if (inventory > 0) {
      top +=
          printText(
            '在线 ${data.onlineBooks} / 本地 ${data.localBooks}${data.authorCount > 0 ? ' · ${data.authorCount} 位作者' : ''}',
            32,
            top,
            width: width - 64,
            size: 13,
            color: colors.muted,
          ) +
          19;
    }
    for (final genre in genres) {
      top +=
          printText(
            '${genre.label} · ${statisticsDuration(genre.seconds)} · ${_analysisPercent(genre.ratio)}',
            32,
            top,
            width: width - 64,
            size: 13,
            color: colors.muted,
            height: 1.45,
          ) +
          9;
    }
    return top + 8;
  }

  double _archiveTimeLedger(double width) {
    var top = _archiveHeading('时间的分档', width);
    final months = data.analysis.months
        .where(
          (month) =>
              month.totalSeconds != null || month.measuredMilliseconds > 0,
        )
        .toList();
    final maximum = months.map(_dossierNightMonthMillis).fold<int>(0, math.max);
    if (maximum > 0) {
      final peak = months.firstWhere(
        (month) => _dossierNightMonthMillis(month) == maximum,
      );
      printText(
        'PEAK MONTH',
        0,
        top + 2,
        width: 150,
        size: 10.5,
        color: colors.muted,
      );
      printText(
        '${peak.date.month}'.padLeft(2, '0'),
        0,
        top + 25,
        width: 150,
        size: 58,
        display: true,
        color: colors.accent,
        weight: FontWeight.w600,
        height: 1,
      );
      printText(
        '${peak.date.year} / 本期峰值月',
        0,
        top + 95,
        width: 150,
        size: 12,
        color: colors.muted,
      );
      printText(
        '${months.length}',
        0,
        top + 145,
        width: 150,
        size: 38,
        display: true,
        weight: FontWeight.w600,
      );
      printText(
        '个有覆盖的月份',
        0,
        top + 193,
        width: 150,
        size: 12,
        color: colors.muted,
      );
      var line = top;
      final columnWidth = width - 180;
      for (final month in months) {
        final measured = _dossierNightMonthMillis(month);
        printText(
          '${month.date.year}.${month.date.month.toString().padLeft(2, '0')}',
          180,
          line,
          width: 104,
          size: 12,
          color: colors.muted,
        );
        printText(
          _monthFigure(month) ?? '',
          288,
          line,
          width: width - 288,
          size: 12,
          align: TextAlign.right,
          weight: FontWeight.w600,
        );
        if (measured > 0) {
          canvas.drawRect(
            Rect.fromLTWH(180, line + 20, columnWidth * measured / maximum, 3),
            Paint()
              ..color = measured == maximum
                  ? colors.accent
                  : colors.ink.withValues(alpha: .52),
          );
        }
        line += 33;
      }
      top += math.max(222.0, line - top) + 22;
    }
    top = _at(top, width, _timeSummary, gap: 20);
    top = _at(top, width, (w) => printSessionLengths(w, dark: night), gap: 2);
    return top;
  }

  double _archiveBookIndex(double width) {
    var top = _archiveHeading('书籍索引', width);
    final maximum = _rankedBooks.map(_bookMilliseconds).fold<int>(0, math.max);
    for (final (index, book) in _rankedBooks.indexed) {
      printText(
        '${index + 1}'.padLeft(2, '0'),
        0,
        top + 2,
        width: 30,
        size: 22,
        display: true,
        weight: FontWeight.w600,
        color: index == 0 ? colors.accent : colors.ink,
      );
      final cover = components?.bookCovers.elementAtOrNull(index);
      if (cover != null) _image(cover, 42, top, width: 34, height: 48);
      final inset = cover == null ? 42.0 : 90.0;
      var row = top;
      if (_hasTitle(book.title) || options.hideBookTitles) {
        row +=
            printText(
              _analysisTitle(book.title, index),
              inset,
              row,
              width: width - inset - 120,
              size: 18,
              weight: FontWeight.w600,
              height: 1.3,
            ) +
            6;
      }
      if (!options.hideAuthorNames &&
          readingReportHasAuthorText(book.book?.author)) {
        row +=
            printText(
              book.book!.author,
              inset,
              row,
              width: width - inset - 120,
              size: 12,
              color: colors.muted,
            ) +
            5;
      }
      final durationHeight = printText(
        _bookDuration(book),
        width - 108,
        top + 2,
        width: 108,
        size: 13,
        align: TextAlign.right,
        height: 1.4,
        color: colors.muted,
      );
      row = math.max(row, top + math.max(48.0, durationHeight));
      final milliseconds = _bookMilliseconds(book);
      if (maximum > 0 && milliseconds > 0) {
        canvas.drawRect(
          Rect.fromLTWH(
            inset,
            row + 8,
            (width - inset) * milliseconds / maximum,
            3,
          ),
          Paint()
            ..color = index == 0
                ? colors.accent
                : colors.ink.withValues(alpha: .5),
        );
      }
      top = row + 28;
    }
    top = _analysisLine(
      '选录 ${_rankedBooks.length}/$_bookCount 本',
      top,
      width,
      dark: night,
    );
    final distribution = data.analysis.bookDayDistribution;
    if (distribution.hasData) {
      top = _analysisLine(
        distribution.buckets
            .map((bucket) => '${bucket.label} ${bucket.days}天')
            .join(' · '),
        top,
        width,
        dark: night,
      );
    }
    return top;
  }

  double _archiveNotes(double width) {
    var top = _archiveHeading('页边的短笺', width);
    _illustration(
      readingReportHeroArt(data, options),
      Rect.fromLTWH(0, top, 112, 128),
      alignment: Alignment.topRight,
    );
    final quotes = _dossierNightQuotes(data, preferNight: false);
    canvas.save();
    canvas.translate(136, top);
    var written = 0.0;
    if (quotes.isEmpty) {
      written = _echoContent(width - 136, heading: false);
    } else {
      for (final quote in quotes) {
        written +=
            printText(
              quote.quote,
              0,
              written,
              width: width - 136,
              size: 18,
              fixedTitle: true,
              height: 1.65,
            ) +
            12;
        final source = _dossierNightQuoteSource(quote, options);
        if (source.isNotEmpty) {
          written +=
              printText(
                source,
                0,
                written,
                width: width - 136,
                size: 12,
                color: colors.muted,
                height: 1.45,
              ) +
              8;
        }
        if (quote.date case final date?) {
          written +=
              printText(
                _analysisDate(date),
                0,
                written,
                width: width - 136,
                size: 11.5,
                color: colors.muted,
              ) +
              8;
        }
        if (options.includeNotes && quote.note.trim().isNotEmpty) {
          written +=
              printText(
                quote.note,
                0,
                written,
                width: width - 136,
                size: 12,
                color: colors.muted,
                height: 1.5,
              ) +
              9;
        }
        rule(
          0,
          written,
          width - 136,
          color: colors.ink.withValues(alpha: .16),
          stroke: .6,
        );
        written += 19;
      }
    }
    canvas.restore();
    return top + math.max(132.0, written);
  }
}

/// A full night scene, a clock observatory and a moon-led line index.
class _NightPosterComposer extends _ReferencePosterComposer {
  _NightPosterComposer(
    super.data,
    super.options,
    super.translate,
    super.components,
  );

  @override
  ReadingReportLayout compose() {
    if (readingReportVisibleModules(data, options).isEmpty) {
      return super.compose();
    }
    final recorder = ui.PictureRecorder();
    canvas = Canvas(recorder);
    y = _nightScene();
    y += 34;
    emit(ReadingReportModule.rhythm, _nightObservatory, gap: 38);
    emit(ReadingReportModule.days, _nightDates, gap: 36);
    emit(ReadingReportModule.calendar, _calendarContent, gap: 36);
    emit(ReadingReportModule.progress, _nightRecords, width: 348, gap: 34);
    emit(
      ReadingReportModule.collection,
      _nightShelfStamp,
      x: 192,
      width: 376,
      gap: 36,
    );
    emit(ReadingReportModule.books, _nightMoonIndex, gap: 40);
    emit(
      ReadingReportModule.excerpts,
      _nightQuotes,
      x: 62,
      width: 476,
      gap: 38,
    );
    rule(32, y, 536, color: colors.ink.withValues(alpha: .18));
    y += 28;
    y +=
        printText(
          '愿下一页，仍有一盏灯。',
          32,
          y,
          width: 464,
          size: 24,
          weight: FontWeight.w600,
          height: 1.4,
        ) +
        20;
    _nightMoon(550, y - 18, 16);
    y +=
        printText(
          options.signature
              ? '$readingExportBrandName / WENKU8 · 私人阅读报告'
              : name,
          32,
          y,
          width: 536,
          size: 12,
          color: colors.muted,
        ) +
        29;
    return finishPlate(recorder, y);
  }

  double _nightScene() {
    const height = 920.0;
    _illustration(
      readingReportHeroArt(data, options),
      const Rect.fromLTWH(0, 0, 600, height),
      alignment: Alignment.topCenter,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 600, height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.background.withValues(alpha: .36),
            colors.background.withValues(alpha: 0),
            colors.background.withValues(alpha: .06),
            colors.background,
          ],
          stops: const [0, .34, .68, 1],
        ).createShader(const Rect.fromLTWH(0, 0, 600, height)),
    );
    _masthead(color: paper);
    final heading = imageTitle(
      '阅读报告',
      32,
      92,
      width: 536,
      size: 25,
      color: paper,
    );
    var top = 92 + heading + 30;
    final event = data.analysis.latestReading;
    final nightEvent =
        event != null && (event.at.hour >= 22 || event.at.hour < 6)
        ? event
        : null;
    if (nightEvent != null) {
      printText(
        'LATEST / ${_analysisDate(nightEvent.at)}',
        34,
        top - 16,
        width: 400,
        size: 11,
        color: colors.accent,
      );
      printText(
        _analysisClock(nightEvent.at),
        28,
        top,
        width: 408,
        size: 132,
        display: true,
        weight: FontWeight.w700,
        height: 1,
        color: paper,
      );
    } else if (_hasReading) {
      _total(28, top, 408, size: 116, color: paper);
    }
    top = height - 170;
    if (nightEvent != null) {
      top +=
          printText(
            '这段日子，最晚的一次夜读。',
            32,
            top,
            width: 536,
            size: 22,
            color: paper,
            weight: FontWeight.w600,
          ) +
          17;
    }
    top = _identity(top);
    return math.max(height, top + 26);
  }

  double _nightObservatory(double width) {
    final a = data.analysis;
    var top = 0.0;
    final hasHours = a.hourMilliseconds.any((milliseconds) => milliseconds > 0);
    if (hasHours) {
      top +=
          printText(
            '入夜之后',
            0,
            top,
            width: width,
            size: 29,
            weight: FontWeight.w600,
          ) +
          12;
      printText(
        'HOURS / 22:00–06:00',
        0,
        top,
        width: 238,
        size: 11,
        color: colors.muted,
      );
      final ratio = a.nightRatio!;
      printText(
        (ratio * 100).toStringAsFixed(1),
        0,
        top + 29,
        width: 202,
        size: 70,
        display: true,
        color: colors.accent,
        weight: FontWeight.w600,
        height: 1,
      );
      printText(
        '%',
        205,
        top + 72,
        width: 30,
        size: 24,
        color: colors.accent,
        weight: FontWeight.w600,
      );
      printText(
        '已测夜读占比',
        0,
        top + 112,
        width: 230,
        size: 14,
        color: colors.muted,
      );
      printText(
        _dimensionDuration(a.nightMilliseconds),
        0,
        top + 140,
        width: 230,
        size: 18,
        weight: FontWeight.w600,
      );
      canvas.save();
      canvas.translate(width - 264, top - 7);
      _analysisPlot(
        ReadingAnalysisChartKind.radial,
        [
          for (var hour = 0; hour < 24; hour++)
            ReadingAnalysisDatum('$hour时', a.hourMilliseconds[hour] / 3600000),
        ],
        0,
        264,
        height: 264,
        dark: true,
      );
      canvas.restore();
      top += 272;
    }
    final instruments = <(String, String, String)>[
      if (_hasReading &&
          a.latestReading != null &&
          (a.latestReading!.at.hour >= 22 || a.latestReading!.at.hour < 6))
        (
          '本期总阅读',
          data.periodSeconds == 0
              ? '不足1秒'
              : statisticsDuration(data.periodSeconds),
          'READING TIME',
        ),
      if (a.longestSession case final session?)
        (
          '最长一次',
          _dimensionDuration(session.milliseconds),
          session.isClipped
              ? '区间内片段'
              : '${_analysisDate(session.start)} ${_analysisClock(session.start)}',
        ),
    ];
    final nightMonths = a.months
        .where((month) => month.nightMilliseconds > 0)
        .toList();
    if (nightMonths.isNotEmpty) {
      final maximum = nightMonths
          .map((month) => month.nightMilliseconds)
          .fold<int>(0, math.max);
      final month = nightMonths.firstWhere(
        (month) => month.nightMilliseconds == maximum,
      );
      instruments.add((
        '夜读最多的月份',
        '${month.date.year}.${month.date.month.toString().padLeft(2, '0')}',
        _dimensionDuration(maximum),
      ));
    } else if (!hasHours) {
      final months = a.months
          .where((month) => _dossierNightMonthMillis(month) > 0)
          .toList();
      if (months.isNotEmpty) {
        final maximum = months
            .map(_dossierNightMonthMillis)
            .fold<int>(0, math.max);
        final month = months.firstWhere(
          (month) => _dossierNightMonthMillis(month) == maximum,
        );
        instruments.add((
          '阅读最多的月份',
          '${month.date.year}.${month.date.month.toString().padLeft(2, '0')}',
          _dimensionDuration(maximum),
        ));
      }
    }
    if (instruments.isNotEmpty) {
      final cell = (width - 26 * (instruments.length - 1)) / instruments.length;
      var row = 0.0;
      for (final (index, fact) in instruments.indexed) {
        final x = index * (cell + 26);
        final label = printText(
          fact.$1,
          x,
          top,
          width: cell,
          size: 12,
          color: colors.muted,
        );
        final value = printText(
          fact.$2,
          x,
          top + label + 9,
          width: cell,
          size: 20,
          weight: FontWeight.w600,
          height: 1.25,
        );
        final detail = printText(
          fact.$3,
          x,
          top + label + value + 18,
          width: cell,
          size: 11.5,
          color: colors.muted,
          height: 1.4,
        );
        row = math.max(row, label + value + detail + 18);
      }
      top += row + 30;
    }
    final lengths = a.sessionLengths;
    if (lengths.hasData) {
      top +=
          printText(
            '单次片段 / 完整会话次数',
            0,
            top,
            width: width,
            size: 13,
            color: colors.muted,
          ) +
          19;
      final cell = (width - 40) / lengths.buckets.length;
      for (final (index, bucket) in lengths.buckets.indexed) {
        final x = index * (cell + 10);
        printText(
          bucket.label,
          x,
          top,
          width: cell,
          size: 11.5,
          color: colors.muted,
        );
        printText(
          '${bucket.count}',
          x,
          top + 28,
          width: cell,
          size: 27,
          display: true,
          weight: FontWeight.w600,
        );
        if (bucket.count > 0) {
          canvas.drawRect(
            Rect.fromLTWH(
              x,
              top + 65,
              cell * bucket.count / lengths.completeSessionCount,
              3,
            ),
            Paint()..color = colors.accent,
          );
        }
      }
      top += 88;
      if (lengths.excludedClippedSessionCount > 0) {
        top +=
            printText(
              '${lengths.excludedClippedSessionCount}段边界截断未计入长度分布',
              0,
              top,
              width: width,
              size: 11.5,
              color: colors.muted,
            ) +
            9;
      }
    }
    return top;
  }

  double _nightDates(double width) {
    var top =
        printText(
          '灯亮过的日子',
          0,
          0,
          width: width,
          size: 24,
          weight: FontWeight.w600,
        ) +
        13;
    top +=
        printText(range, 0, top, width: width, size: 12, color: colors.muted) +
        19;
    if (data.period <= 14) {
      for (var day = 0; day < data.dates.length; day++) {
        final seconds = data.seconds[day];
        if (seconds == null || seconds <= 0) continue;
        top = _analysisLine(
          '${_analysisDate(data.dates[day])} · ${statisticsDuration(seconds)}',
          top,
          width,
          dark: true,
        );
      }
    } else {
      final maximum = data.seconds.whereType<int>().fold<int>(0, math.max);
      if (maximum > 0) {
        final stride = width / data.dates.length;
        rule(
          0,
          top + 47,
          width,
          color: colors.muted.withValues(alpha: .2),
          stroke: .5,
        );
        for (var day = 0; day < data.dates.length; day++) {
          final seconds = data.seconds[day];
          if (seconds == null || seconds <= 0) continue;
          final height = 43 * seconds / maximum;
          final bar = math.min(3.0, stride * .65);
          canvas.drawRect(
            Rect.fromLTWH(
              day * stride + (stride - bar) / 2,
              top + 47 - height,
              bar,
              height,
            ),
            Paint()..color = colors.accent.withValues(alpha: .72),
          );
        }
        top += 65;
      }
    }
    final streak = data.analysis.longestStreak;
    final facts = [
      '${math.max(data.activeDays, _activeDays)}个阅读日',
      '${data.observedDays}/${data.period}天有记录',
      if (streak.start != null && streak.end != null)
        '连续${streak.days}天 · ${_analysisDate(streak.start!)}—${_analysisDate(streak.end!)}',
    ];
    return _analysisLine(facts.join(' · '), top, width, dark: true);
  }

  double _nightRecords(double width) {
    var top =
        printText(
          '书页留下的时间',
          0,
          0,
          width: width,
          size: 23,
          weight: FontWeight.w600,
        ) +
        18;
    final known = data.progressBands.fold<int>(0, (sum, count) => sum + count);
    if (known > 0) {
      printText('当前章节位置', 0, top, width: width, size: 12, color: colors.muted);
      top += 24;
      final cell = width / 4;
      for (var index = 0; index < 4; index++) {
        printText(
          '${data.progressBands[index]}',
          index * cell,
          top,
          width: cell - 8,
          size: 25,
          display: true,
          weight: FontWeight.w600,
        );
        printText(
          '${index * 25}–${(index + 1) * 25}%',
          index * cell,
          top + 36,
          width: cell - 8,
          size: 11.5,
          color: colors.muted,
        );
      }
      top += 66;
      top = _analysisLine(
        '${_analysisDate(data.analysis.snapshotAt)} · 进度快照',
        top,
        width,
        dark: true,
      );
    }
    final a = data.analysis;
    final events = a.firstOpenedBooks.length + a.completedBooks.length;
    if (events > 3) {
      top = _at(
        top,
        width,
        (w) => printMonthlyMilestones(w, dark: true),
        gap: 8,
      );
    } else if (events > 0) {
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
          dark: true,
        );
      }
    }
    for (final book
        in a.reachedEndBooks
            .where((book) => book.finished == false)
            .take(options.bookLimit)) {
      final title = _milestoneBook(book);
      top = _analysisLine(
        '${_analysisDate(book.completedAt!)} · 连载结尾${title.isEmpty ? '' : ' $title'}',
        top,
        width,
        dark: true,
      );
    }
    rule(0, top, width, color: colors.ink.withValues(alpha: .17), stroke: .6);
    return top + 7;
  }

  double _nightShelfStamp(double width) {
    var top =
        printText(
          '此刻的书架',
          0,
          0,
          width: width,
          size: 22,
          weight: FontWeight.w600,
        ) +
        19;
    final inventory = data.onlineBooks + data.localBooks;
    if (inventory > 0) {
      printText(
        '$inventory',
        0,
        top,
        width: 88,
        size: 52,
        display: true,
        color: colors.accent,
        height: 1,
        weight: FontWeight.w600,
      );
      printText('本当前藏书', 102, top + 8, width: width - 102, size: 15);
      printText(
        '在线 ${data.onlineBooks} / 本地 ${data.localBooks}',
        102,
        top + 36,
        width: width - 102,
        size: 12,
        color: colors.muted,
      );
      top += 74;
      if (data.authorCount > 0) {
        top = _analysisLine('${data.authorCount}位作者', top, width, dark: true);
      }
    }
    for (final genre in data.analysis.genres.where(
      (genre) => genre.seconds > 0,
    )) {
      top = _analysisLine(
        '${genre.label} · ${statisticsDuration(genre.seconds)}',
        top,
        width,
        dark: true,
      );
    }
    top +=
        printText(
          '${_analysisDate(data.analysis.snapshotAt)} 库存快照',
          0,
          top,
          width: width,
          size: 11.5,
          color: colors.muted,
        ) +
        14;
    rule(0, top, width, color: colors.accent.withValues(alpha: .45), stroke: 1);
    return top + 9;
  }

  double _nightMoonIndex(double width) {
    _nightMoon(width - 81, 76, 67);
    printText(
      'BOOKS / WITH YOU',
      0,
      1,
      width: width - 150,
      size: 11,
      color: colors.muted,
    );
    printText(
      '相伴的书',
      0,
      27,
      width: width - 150,
      size: 29,
      weight: FontWeight.w600,
    );
    var top = 139.0;
    for (final (index, book) in _rankedBooks.indexed) {
      printText(
        '${index + 1}'.padLeft(2, '0'),
        0,
        top + 3,
        width: 27,
        size: 14,
        color: index == 0 ? colors.accent : colors.muted,
        weight: FontWeight.w600,
      );
      var row = top;
      if (_hasTitle(book.title) || options.hideBookTitles) {
        row +=
            printText(
              _analysisTitle(book.title, index),
              38,
              top,
              width: width - 200,
              size: 17,
              height: 1.35,
              weight: FontWeight.w600,
            ) +
            6;
      }
      if (!options.hideAuthorNames &&
          readingReportHasAuthorText(book.book?.author)) {
        row +=
            printText(
              book.book!.author,
              38,
              row,
              width: width - 200,
              size: 12,
              color: colors.muted,
            ) +
            5;
      }
      final time = book.nightMilliseconds > 0
          ? '夜读 ${_dimensionDuration(book.nightMilliseconds)}'
          : _bookDuration(book);
      final timeHeight = printText(
        time,
        width - 147,
        top + 2,
        width: 147,
        size: 13,
        color: colors.muted,
        align: TextAlign.right,
        height: 1.4,
      );
      row = math.max(row, top + math.max(38.0, timeHeight));
      rule(
        0,
        row + 10,
        width,
        color: colors.ink.withValues(alpha: .16),
        stroke: .6,
      );
      top = row + 24;
    }
    top = _analysisLine(
      '书目选录 ${_rankedBooks.length}/$_bookCount 本',
      top + 3,
      width,
      dark: true,
    );
    final distribution = data.analysis.bookDayDistribution;
    if (distribution.hasData) {
      top = _analysisLine(
        '同日相伴 · ${distribution.buckets.map((bucket) => '${bucket.label} ${bucket.days}天').join(' / ')}',
        top,
        width,
        dark: true,
      );
    }
    return top;
  }

  double _nightQuotes(double width) {
    final quotes = _dossierNightQuotes(data, preferNight: true);
    var top =
        printText(
          quotes.any((quote) => quote.night) ? '夜里，留下这些句子。' : '留在页边的句子。',
          0,
          0,
          width: width,
          size: 25,
          weight: FontWeight.w600,
        ) +
        26;
    if (quotes.isEmpty) return top + _echoContent(width, heading: false);
    for (final (index, quote) in quotes.indexed) {
      printText(
        '“',
        0,
        top - 8,
        width: 50,
        size: 64,
        fixedTitle: true,
        color: colors.accent,
      );
      top += 43;
      top +=
          printText(
            quote.quote,
            0,
            top,
            width: width,
            size: index == 0 ? 27 : 21,
            fixedTitle: true,
            height: 1.65,
          ) +
          19;
      final source = _dossierNightQuoteSource(quote, options);
      if (source.isNotEmpty) {
        top +=
            printText(
              source,
              0,
              top,
              width: width,
              size: 12,
              color: colors.muted,
              height: 1.5,
            ) +
            9;
      }
      if (quote.date case final date?) {
        top +=
            printText(
              _analysisDate(date),
              0,
              top,
              width: width,
              size: 11.5,
              color: colors.muted,
            ) +
            8;
      }
      if (options.includeNotes && quote.note.trim().isNotEmpty) {
        top +=
            printText(
              quote.note,
              0,
              top,
              width: width,
              size: 12,
              color: colors.muted,
              height: 1.5,
            ) +
            9;
      }
      rule(
        0,
        top + 3,
        width,
        color: colors.ink.withValues(alpha: .18),
        stroke: .6,
      );
      top += 25;
    }
    return top;
  }

  void _nightMoon(double x, double top, double radius) {
    final center = Offset(x, top);
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = colors.ink.withValues(alpha: .13),
    );
    for (final crater in const [
      (dx: -.35, dy: -.27, size: .21),
      (dx: .31, dy: .06, size: .14),
      (dx: -.06, dy: .4, size: .16),
      (dx: .39, dy: -.43, size: .1),
    ]) {
      canvas.drawCircle(
        center + Offset(crater.dx * radius, crater.dy * radius),
        radius * crater.size,
        Paint()..color = colors.background.withValues(alpha: .37),
      );
    }
  }
}

int _dossierNightMonthMillis(StatisticsAnalysisMonth month) =>
    math.max((month.totalSeconds ?? 0) * 1000, month.measuredMilliseconds);

class _DossierNightQuote {
  const _DossierNightQuote(
    this.quote,
    this.note,
    this.title,
    this.chapter,
    this.date, {
    this.night = false,
  });
  final String quote, note, title, chapter;
  final DateTime? date;
  final bool night;
}

List<_DossierNightQuote> _dossierNightQuotes(
  ReadingStatisticsData data, {
  required bool preferNight,
}) {
  final night = data.analysis.marks.items
      .where(
        (mark) =>
            mark.isExcerpt &&
            mark.createdAt != null &&
            (mark.createdAt!.hour >= 22 || mark.createdAt!.hour < 6),
      )
      .take(2)
      .toList();
  if (preferNight && night.isNotEmpty) {
    return [
      for (final mark in night)
        _DossierNightQuote(
          mark.quote,
          mark.note,
          mark.title,
          mark.chapter,
          mark.createdAt!.localDateTime,
          night: true,
        ),
    ];
  }
  return [
    for (final excerpt in data.excerpts.take(2))
      (() {
        final dated = data.analysis.marks.items
            .where(
              (mark) =>
                  mark.quote.trim() == excerpt.quote.trim() &&
                  mark.title == excerpt.title &&
                  mark.chapter == excerpt.chapter,
            )
            .toList();
        return _DossierNightQuote(
          excerpt.quote,
          excerpt.note,
          excerpt.title,
          excerpt.chapter,
          dated.length == 1 ? dated.single.createdAt?.localDateTime : null,
        );
      })(),
  ];
}

String _dossierNightQuoteSource(
  _DossierNightQuote quote,
  ReadingReportOptions options,
) => [
  if (options.hideBookTitles)
    '来源已隐藏'
  else if (readingReportHasMetadataText(quote.title))
    '《${quote.title}》',
  if (!options.hideBookTitles && quote.chapter.trim().isNotEmpty) quote.chapter,
].join(' · ');
