part of 'reading_report_layout.dart';

/// Editorial systems share measured facts and drawing primitives, not a card.
abstract class _ReportArtDirectionComposer extends _ReportAnalysisComposer {
  _ReportArtDirectionComposer(
    super.data,
    super.options,
    super.translate,
    super.components,
  );

  void rule(
    double x,
    double top,
    double width, {
    Color? color,
    double stroke = .8,
  }) {
    canvas.drawLine(
      Offset(x, top),
      Offset(x + width, top),
      Paint()
        ..color = color ?? colors.ink.withValues(alpha: .25)
        ..strokeWidth = stroke,
    );
  }

  void perforation(double x, double top, double width, {Color? color}) {
    for (var cursor = x; cursor < x + width; cursor += 10) {
      rule(
        cursor,
        top,
        math.min(4, x + width - cursor),
        color: color ?? colors.ink.withValues(alpha: .3),
      );
    }
  }

  void roundArt(Rect bounds, {Alignment alignment = Alignment.centerRight}) {
    canvas.save();
    canvas.clipPath(Path()..addOval(bounds));
    artPrint(bounds, alignment: alignment);
    canvas.restore();
  }

  double identityLine(
    double top, {
    double x = 32,
    double width = 536,
    bool dark = false,
  }) {
    final ink = dark ? paper : colors.ink;
    var t =
        top +
        printText(
          name,
          x,
          top,
          width: width,
          size: 16,
          color: ink,
          weight: FontWeight.w600,
        ) +
        7;
    t +=
        printText(range, x, t, width: width, size: 12, color: colors.muted) +
        10;
    if (options.note.trim().isNotEmpty) {
      t +=
          printText(
            options.note.trim(),
            x,
            t,
            width: width,
            size: 14,
            height: 1.55,
            color: ink,
          ) +
          12;
    }
    return t;
  }

  double openingFacts(
    double top, {
    double x = 32,
    double width = 536,
    bool dark = false,
  }) {
    final ink = dark ? paper : colors.ink;
    final cell = width / 3;
    final facts = <(String, String)>[
      ('${data.activeDays}', '阅读日'),
      ('${data.periodBooks}', '本期书籍'),
      ('${insights.longestStreak}', '最长连读 / 天'),
    ];
    for (var i = 0; i < facts.length; i++) {
      final left = x + i * cell;
      printText(
        facts[i].$1,
        left,
        top,
        width: cell - 14,
        size: 43,
        display: true,
        color: ink,
        height: 1,
        weight: FontWeight.w700,
      );
      printText(
        facts[i].$2,
        left,
        top + 49,
        width: cell - 14,
        size: 12,
        color: colors.muted,
      );
    }
    return top + 76;
  }

  double profileLine(
    double top, {
    double x = 32,
    double width = 536,
    bool dark = false,
  }) {
    final ink = dark ? paper : colors.ink;
    final h = printText(
      insights.headline,
      x,
      top,
      width: width,
      size: 19,
      color: ink,
      weight: FontWeight.w600,
    );
    var end = top + h + 7;
    for (final badge in insights.badges.take(2)) {
      end +=
          printText(
            '${badge.label} · ${badge.basis}',
            x,
            end,
            width: width,
            size: 12,
            color: colors.muted,
          ) +
          5;
    }
    return end;
  }

  double dispatch(
    ReadingReportModule module,
    double width, {
    bool dark = false,
  }) => switch (module) {
    ReadingReportModule.rhythm => printRhythm(width, chartHeight: 146),
    ReadingReportModule.calendar => printCalendar(width, dark: dark),
    ReadingReportModule.days => printText(
      '${data.activeDays} 天阅读 · 最长连续 ${data.longestStreak} 天',
      0,
      0,
      width: width,
    ),
    ReadingReportModule.books => printBooks(width, dark: dark, coverWidth: 42),
    ReadingReportModule.progress => printProgress(width, dark: dark),
    ReadingReportModule.collection => printCollection(width, dark: dark),
    ReadingReportModule.excerpts => printEchoes(
      width,
      dark: dark,
      leadSize: 23,
      ruled: false,
    ),
  };

  /// The observatory puts the clock beside the two recorded time landmarks.
  double observatoryRhythm(double width) {
    var top = printHead(ReadingReportModule.rhythm, width, dark: true);
    final a = data.analysis;
    if (data.observedDays == 0) {
      return _analysisLine('开始阅读后，星图会留下你的阅读时刻。', top, width, dark: true);
    }
    if (!a.coverage.hasTimeDetail) {
      top = _analysisLine('时段记录开始后，星图会留下你读书的时刻。', top, width, dark: true);
    } else {
      final chartWidth = width * .55;
      final factsX = chartWidth + 22;
      final factsWidth = width - factsX;
      final chartEnd = _analysisPlot(
        ReadingAnalysisChartKind.radial,
        [
          for (var i = 0; i < 24; i++)
            ReadingAnalysisDatum('$i时', a.hoursSeconds[i] / 3600),
        ],
        top,
        chartWidth,
        height: 292,
        dark: true,
      );
      var factsEnd = top + 12;
      void fact(String heading, String value) {
        factsEnd +=
            printText(
              heading,
              factsX,
              factsEnd,
              width: factsWidth,
              size: 13,
              color: colors.accent,
            ) +
            8;
        factsEnd +=
            printText(
              value,
              factsX,
              factsEnd,
              width: factsWidth,
              size: 16,
              color: paper,
              height: 1.55,
            ) +
            24;
      }

      if (a.latestReading case final latest?) {
        fact(
          '最晚的一页',
          '${_analysisClock(latest.at)}  /  ${_analysisDate(latest.at)}\n《${_analysisTitle(latest.title)}》',
        );
      }
      if (a.longestSession case final session?) {
        fact(
          '最长一次',
          '${statisticsDuration(session.seconds)}\n${_analysisDate(session.start)} ${_analysisClock(session.start)}—${_analysisDate(session.start) == _analysisDate(session.end) ? '' : '${_analysisDate(session.end)} '}${_analysisClock(session.end)}\n《${_analysisTitle(session.title)}》${session.isClipped ? ' · 仅计区间内' : ''}',
        );
      }
      top = math.max(chartEnd, factsEnd) + 12;
      top = _analysisLine('24 小时累计分布 · 夜读 22:00–06:00', top, width, dark: true);
      top = _analysisLine('夜色里的书页', top + 12, width, dark: true, heading: true);
      top = _analysisLine(
        '${a.months.first.date.year}.${a.months.first.date.month.toString().padLeft(2, '0')}—${a.months.last.date.year}.${a.months.last.date.month.toString().padLeft(2, '0')}',
        top,
        width,
        dark: true,
      );
      top = _analysisPlot(
        ReadingAnalysisChartKind.nightOverlay,
        [
          for (final m in a.months)
            ReadingAnalysisDatum(
              '${m.date.month}月',
              m.measuredSeconds / 3600,
              secondary: m.nightSeconds / 3600,
            ),
        ],
        top,
        width,
        height: 168,
        dark: true,
      );
      top = _analysisLine('浅色：已测时段总时长 · 深色：其中夜读 · 小时', top, width, dark: true);
      final books = a.booksByDuration.where((b) => b.nightSeconds > 0).toList()
        ..sort((x, y) => y.nightSeconds.compareTo(x.nightSeconds));
      final selected = books.take(options.bookLimit.clamp(1, 5)).toList();
      if (selected.isNotEmpty) {
        top = _analysisLine(
          '夜读书目 · 小时',
          top + 10,
          width,
          dark: true,
          heading: true,
        );
        top = _analysisPlot(
          ReadingAnalysisChartKind.horizontal,
          [
            for (final (i, b) in selected.indexed)
              ReadingAnalysisDatum(
                '${_analysisTitle(b.title, i)} · ${_analysisPercent(b.nightRatio)}',
                b.nightSeconds / 3600,
              ),
          ],
          top + 8,
          width,
          height: selected.length * 46,
          dark: true,
        );
      }
      top = _analysisLine(
        '夜读 ${statisticsDuration(a.nightSeconds)} · ${a.marks.nightBookmarks} 个书签 / ${a.marks.nightExcerpts} 条摘录',
        top,
        width,
        dark: true,
      );
      top = _analysisLine(
        '时段明细覆盖 ${a.coverage.detailedDays} 天 / ${statisticsDuration(a.measuredSeconds)}；夜读占比只计算这些时段。最晚时刻按 06:00 起的一天排序。',
        top,
        width,
        dark: true,
      );
    }
    canvas.save();
    canvas.translate(0, top + 18);
    top +=
        18 +
        printRhythm(
          width,
          withTemporal: false,
          compactMonths: true,
          heading: false,
        );
    canvas.restore();
    return top;
  }

  /// A folio's monthly spine keeps the amounts and comparisons next to the dates.
  double folioChronicle(double width) {
    final a = data.analysis;
    var top = printHead(ReadingReportModule.rhythm, width);
    if (data.observedDays == 0) {
      return _analysisLine('下一段阅读，将成为这份月序的开篇。', top, width);
    }
    top = _analysisLine('月序 · 阅读时长与环比', top, width, heading: true);
    final maximum = a.months.fold<int>(
      0,
      (v, m) => math.max(v, m.totalSeconds ?? 0),
    );
    for (final m in a.months) {
      rule(0, top, width, color: colors.ink.withValues(alpha: .16));
      printText(
        '${m.date.month}'.padLeft(2, '0'),
        0,
        top + 13,
        width: 66,
        size: 36,
        display: true,
        color: colors.accent,
        height: 1,
      );
      printText(
        '${m.date.year}',
        0,
        top + 55,
        width: 66,
        size: 12,
        color: colors.muted,
      );
      var end =
          top +
          13 +
          printText(
            m.totalSeconds == null
                ? '时长未知'
                : statisticsDuration(m.totalSeconds!),
            83,
            top + 13,
            width: width - 83,
            size: 21,
            weight: FontWeight.w600,
          );
      end +=
          6 +
          printText(
            '环比 ${_analysisChange(m.changeRatio)}${m.isComplete ? '' : ' · 部分月份'}',
            83,
            end + 6,
            width: width - 83,
            size: 13,
            color: colors.muted,
          );
      if (m.totalSeconds != null && maximum > 0) {
        canvas.drawRect(
          Rect.fromLTWH(
            83,
            end + 12,
            (width - 83) * m.totalSeconds! / maximum,
            5,
          ),
          Paint()..color = colors.accent.withValues(alpha: .62),
        );
      }
      top = math.max(top + 94, end + 32);
    }
    final half = a.halves;
    if (half.isFullYear) {
      top = _analysisLine(
        '${half.year} 上半年 ${half.firstSeconds == null ? '未知' : statisticsDuration(half.firstSeconds!)} / 下半年 ${half.secondSeconds == null ? '未知' : statisticsDuration(half.secondSeconds!)}',
        top + 12,
        width,
      );
      top = _analysisLine(
        half.comparable
            ? '下半年相对上半年 ${_analysisChange(half.changeRatio)}'
            : '半年环比需两个完整半年均有记录。',
        top,
        width,
      );
    }
    top = weekdayPlot(top + 20, width);
    canvas.save();
    canvas.translate(0, top + 12);
    top += 12 + printTemporalAnalysis(width);
    canvas.restore();
    return top;
  }

  /// Two-column destination tickets, ranked by actual attributed reading time.
  double destinationBooks(double width) {
    final books = data.analysis.booksByDuration
        .where((b) => b.seconds != null)
        .take(options.bookLimit)
        .toList();
    var top = printHead(ReadingReportModule.books, width);
    canvas.save();
    canvas.translate(0, top);
    top += printBookJourney(width, withDates: false) + 20;
    canvas.restore();
    top = _analysisLine('停留最久的书中世界', top, width, heading: true);
    final tile = (width - 30) / 2;
    for (var first = 0; first < books.length; first += 2) {
      var rowEnd = top;
      for (var col = 0; col < 2 && first + col < books.length; col++) {
        final index = first + col, book = books[index], x = col * (tile + 30);
        final cover = components?.bookCovers.elementAtOrNull(index);
        perforation(x, top, tile);
        if (cover != null) _image(cover, x, top + 17, width: 55, height: 78);
        printText(
          '${index + 1}'.padLeft(2, '0'),
          x + 71,
          top + 16,
          width: tile - 71,
          size: 38,
          display: true,
          color: colors.accent,
          height: 1,
        );
        var end =
            top +
            62 +
            printText(
              statisticsDuration(book.seconds!),
              x + 71,
              top + 62,
              width: tile - 71,
              size: 14,
              weight: FontWeight.w600,
            );
        end = math.max(top + 111, end + 17);
        end +=
            printText(
              _analysisTitle(book.title, index),
              x,
              end,
              width: tile,
              size: 19,
              weight: FontWeight.w600,
              height: 1.5,
            ) +
            8;
        if (!options.hideAuthorNames &&
            book.book?.author.trim().isNotEmpty == true) {
          end +=
              printText(
                book.book!.author,
                x,
                end,
                width: tile,
                size: 13,
                color: colors.muted,
              ) +
              8;
        }
        if (book.hasPartialTimeCoverage) {
          end +=
              printText(
                '仅含已记录单书时长',
                x,
                end,
                width: tile,
                size: 12,
                color: colors.muted,
              ) +
              8;
        }
        rowEnd = math.max(rowEnd, end);
      }
      top = rowEnd + 26;
    }
    if (books.isEmpty) top = _analysisLine('开始阅读后，留下你的下一站。', top, width);
    return _bookContribution(top, width);
  }

  @override
  double printHead(
    ReadingReportModule module,
    double width, {
    bool dark = false,
    String? english,
  }) {
    if (!const {
      ReadingReportTemplate.constellation,
      ReadingReportTemplate.signal,
      ReadingReportTemplate.score,
      ReadingReportTemplate.ink,
      ReadingReportTemplate.festival,
    }.contains(options.template)) {
      return super.printHead(module, width, dark: dark, english: english);
    }
    final ink = dark ? paper : colors.ink;
    final n = '${++serial}'.padLeft(2, '0');
    switch (options.template) {
      case ReadingReportTemplate.constellation:
        canvas.drawCircle(
          const Offset(16, 17),
          15,
          Paint()..color = colors.accent.withValues(alpha: .16),
        );
        printText(
          n,
          0,
          8,
          width: 32,
          size: 15,
          display: true,
          color: colors.accent,
          align: TextAlign.center,
        );
        final h = printText(
          module.label,
          45,
          1,
          width: width - 45,
          size: 26,
          color: ink,
          weight: FontWeight.w600,
        );
        rule(
          45,
          h + 9,
          width - 45,
          color: colors.accent.withValues(alpha: .45),
        );
        return math.max(40, h + 25);
      case ReadingReportTemplate.signal:
        final h = printText(
          module.label,
          0,
          17,
          width: width - 62,
          size: 28,
          color: ink,
          weight: FontWeight.w700,
        );
        printText(
          n,
          width - 50,
          8,
          width: 50,
          size: 40,
          display: true,
          color: colors.accent,
          height: 1,
          align: TextAlign.right,
        );
        rule(0, 0, 54, color: colors.accent, stroke: 5);
        rule(65, 0, width - 65, color: ink, stroke: 1);
        return 17 + h + 22;
      case ReadingReportTemplate.score:
        printText(
          n,
          0,
          -2,
          width: 68,
          size: 58,
          display: true,
          color: colors.accent,
          weight: FontWeight.w700,
          height: 1,
        );
        final h = printText(
          module.label,
          80,
          9,
          width: width - 80,
          size: 27,
          color: ink,
          weight: FontWeight.w600,
        );
        rule(80, h + 18, width - 80, color: ink, stroke: 2);
        return math.max(62, h + 36);
      case ReadingReportTemplate.ink:
        canvas.drawRect(
          const Rect.fromLTWH(0, 3, 29, 29),
          Paint()..color = colors.accent,
        );
        printText(
          const ['壹', '贰', '叁', '肆', '伍', '陆'][module.index],
          3,
          6,
          width: 23,
          size: 18,
          fixedTitle: true,
          color: paper,
          align: TextAlign.center,
        );
        final h = printText(
          module.label,
          43,
          0,
          width: width - 43,
          size: 29,
          fixedTitle: true,
          color: ink,
        );
        return h + 26;
      case ReadingReportTemplate.festival:
        canvas.drawCircle(
          const Offset(16, 16),
          16,
          Paint()..color = colors.accent,
        );
        printText(
          n,
          1,
          7,
          width: 30,
          size: 16,
          display: true,
          color: Colors.white,
          align: TextAlign.center,
        );
        final h = printText(
          module.label,
          45,
          -1,
          width: width - 45,
          size: 27,
          color: ink,
          weight: FontWeight.w600,
        );
        perforation(45, h + 11, width - 45);
        return math.max(43, h + 28);
      default:
        return super.printHead(module, width, dark: dark, english: english);
    }
  }

  double closing(
    double top, {
    double x = 32,
    double width = 536,
    bool dark = false,
  }) {
    rule(x, top, width, color: colors.accent, stroke: 2);
    var end = top + 19;
    end +=
        printText(
          options.signature ? '轻小说文库' : name,
          x,
          end,
          width: width,
          size: 17,
          color: dark ? paper : colors.ink,
          weight: FontWeight.w600,
        ) +
        8;
    end +=
        printText(
          data.startedAt == null
              ? '尚未记录前台阅读时长'
              : '阅读时长自 ${_date(data.startedAt!)} 起记录',
          x,
          end,
          width: width,
          size: 12,
          color: colors.muted,
        ) +
        27;
    return end;
  }
}
