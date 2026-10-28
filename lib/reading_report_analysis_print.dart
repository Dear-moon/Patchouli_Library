part of 'reading_report_layout.dart';

/// Measured reading facts and small vector graphics shared by the eight editions.
/// Each edition still chooses its own page structure and module order.
abstract class _ReportAnalysisComposer extends _ReportPrintComposer {
  _ReportAnalysisComposer(
    super.data,
    super.options,
    super.translate,
    super.components,
  );

  Color get ruleColor => colors.ink.withValues(alpha: .18);
  Color get panelColor =>
      Color.alphaBlend(colors.accent.withValues(alpha: .06), colors.background);

  void glyph(
    int index,
    double x,
    double top, {
    double size = 20,
    Color? color,
  }) {
    canvas.save();
    canvas.translate(x, top);
    canvas.scale(size / 24);
    final line = Paint()
      ..color = color ?? colors.accent
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.7;
    switch (index % 6) {
      case 0:
        canvas.drawCircle(const Offset(12, 12), 8.5, line);
        canvas.drawPath(
          Path()
            ..moveTo(12, 6)
            ..lineTo(12, 12)
            ..lineTo(17, 15),
          line,
        );
      case 1:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 5, 18, 16),
            const Radius.circular(2),
          ),
          line,
        );
        canvas.drawLine(const Offset(3, 10), const Offset(21, 10), line);
        canvas.drawLine(const Offset(8, 2), const Offset(8, 7), line);
        canvas.drawLine(const Offset(16, 2), const Offset(16, 7), line);
        for (final p in const [
          Offset(8, 14),
          Offset(13, 14),
          Offset(8, 18),
          Offset(13, 18),
        ]) {
          canvas.drawCircle(p, .7, Paint()..color = line.color);
        }
      case 2:
        canvas.drawPath(
          Path()
            ..moveTo(12, 5)
            ..quadraticBezierTo(7, 2, 3, 4)
            ..lineTo(3, 19)
            ..quadraticBezierTo(7, 17, 12, 20)
            ..quadraticBezierTo(17, 17, 21, 19)
            ..lineTo(21, 4)
            ..quadraticBezierTo(17, 2, 12, 5)
            ..lineTo(12, 20),
          line,
        );
      case 3:
        canvas.drawPath(
          Path()
            ..moveTo(5, 3)
            ..lineTo(19, 3)
            ..lineTo(19, 21)
            ..lineTo(12, 16)
            ..lineTo(5, 21)
            ..close(),
          line,
        );
      case 4:
        for (final r in const [
          Rect.fromLTWH(3, 5, 4, 15),
          Rect.fromLTWH(10, 3, 4, 17),
          Rect.fromLTWH(17, 7, 4, 13),
        ]) {
          canvas.drawRect(r, line);
        }
        canvas.drawLine(const Offset(2, 23), const Offset(22, 23), line);
      case 5:
        for (final x in [4.0, 14.0]) {
          canvas.drawPath(
            Path()
              ..moveTo(x + 6, 5)
              ..quadraticBezierTo(x, 6, x, 14)
              ..lineTo(x + 6, 14)
              ..lineTo(x + 6, 8),
            line,
          );
        }
    }
    canvas.restore();
  }

  void editionMasthead(
    String code, {
    double x = 32,
    double top = 24,
    double width = 536,
  }) {
    glyph(2, x, top, size: 23);
    printText(
      theme.label,
      x + 33,
      top,
      width: width - 145,
      size: 13,
      weight: FontWeight.w600,
    );
    printText(
      code,
      x + 33,
      top + 20,
      width: width - 145,
      size: 8.5,
      color: colors.muted,
    );
    printText(
      '${data.today.year}',
      x + width - 78,
      top + 2,
      width: 78,
      size: 22,
      display: true,
      align: TextAlign.right,
    );
    canvas.drawLine(
      Offset(x, top + 46),
      Offset(x + width, top + 46),
      Paint()
        ..color = ruleColor
        ..strokeWidth = .7,
    );
  }

  @override
  double printHead(
    ReadingReportModule module,
    double width, {
    bool dark = false,
    String? english,
  }) {
    final ink = dark ? paper : colors.ink;
    final number = '${++serial}'.padLeft(2, '0');
    final compact = width < 240;
    final narrow = width < 170;
    final marker = options.template == ReadingReportTemplate.editorial;
    if (marker) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 1, 27, 27),
        Paint()..color = colors.accent.withValues(alpha: .12),
      );
      glyph(module.index, 4, 5, size: 19, color: colors.accent);
    } else {
      glyph(
        module.index,
        0,
        3,
        size: narrow ? 18 : 23,
        color: dark ? colors.accent : colors.accent,
      );
    }
    printText(
      number,
      width - (narrow ? 20 : 28),
      1,
      width: narrow ? 20 : 28,
      size: narrow ? 13 : 15,
      display: true,
      color: colors.accent,
      align: TextAlign.right,
    );
    final h = printText(
      module.label,
      narrow
          ? 26
          : compact
          ? 32
          : 37,
      0,
      width:
          width -
          (narrow
              ? 50
              : compact
              ? 68
              : 74),
      size: narrow
          ? 18
          : compact
          ? 19
          : 24,
      weight: FontWeight.w600,
      fixedTitle: marker,
      color: ink,
      height: 1.25,
    );
    final line = math.max(31.0, h + 5);
    canvas.drawLine(
      Offset(0, line + 8),
      Offset(width, line + 8),
      Paint()
        ..color = ink.withValues(alpha: .18)
        ..strokeWidth = .7,
    );
    return line + 25;
  }

  double profileCard(double x, double top, double width, {bool dark = false}) {
    final badges = insights.badges.take(3).toList();
    final headlineH = printMeasure(
      insights.headline,
      width - 32,
      size: width < 300 ? 21 : 25,
      weight: FontWeight.w600,
      height: 1.3,
    );
    var h = 47 + headlineH;
    for (final badge in badges) {
      h +=
          printMeasure(
            '${badge.label} · ${badge.basis}',
            width - 52,
            size: 11,
            height: 1.4,
          ) +
          9;
    }
    h += 17;
    final ink = dark ? paper : colors.ink;
    final shape = Path()
      ..moveTo(x, top)
      ..lineTo(x + width - 16, top)
      ..lineTo(x + width, top + 16)
      ..lineTo(x + width, top + h)
      ..lineTo(x, top + h)
      ..close();
    canvas.drawPath(
      shape,
      Paint()..color = dark ? paper.withValues(alpha: .07) : panelColor,
    );
    canvas.drawLine(
      Offset(x, top),
      Offset(x, top + h),
      Paint()
        ..color = colors.accent
        ..strokeWidth = 3,
    );
    printText(
      'READER / 阅读画像',
      x + 16,
      top + 13,
      width: width - 32,
      size: 9,
      color: dark ? colors.accent : colors.muted,
    );
    var cursor = top + 34;
    printText(
      insights.headline,
      x + 16,
      cursor,
      width: width - 32,
      size: width < 300 ? 21 : 25,
      weight: FontWeight.w600,
      color: ink,
      height: 1.3,
    );
    cursor += headlineH + 13;
    for (final badge in badges) {
      canvas.drawRect(
        Rect.fromLTWH(x + 16, cursor + 5, 5, 5),
        Paint()..color = colors.accent,
      );
      cursor +=
          printText(
            '${badge.label} · ${badge.basis}',
            x + 28,
            cursor,
            width: width - 44,
            size: 11,
            color: ink,
            height: 1.4,
          ) +
          9;
    }
    return top + h;
  }

  double statStrip(double x, double top, double width, {bool dark = false}) {
    final ink = dark ? paper : colors.ink;
    final items = [
      ('${data.activeDays}', '活跃阅读日', 1),
      ('${data.periodBooks}', '本期阅读书籍', 2),
      ('${insights.longestStreak}', '区间最长连续', 3),
    ];
    final cell = width / 3;
    for (var i = 0; i < items.length; i++) {
      final (value, label, icon) = items[i];
      final left = x + i * cell;
      glyph(icon, left, top + 2, size: 17, color: colors.accent);
      printText(
        value,
        left + 25,
        top - 3,
        width: cell - 33,
        size: 38,
        display: true,
        weight: FontWeight.w700,
        color: ink,
        height: 1,
      );
      printText(
        label,
        left,
        top + 42,
        width: cell - 10,
        size: 10.5,
        color: dark ? paper.withValues(alpha: .7) : colors.muted,
      );
      if (i > 0) {
        canvas.drawLine(
          Offset(left - 12, top),
          Offset(left - 12, top + 60),
          Paint()
            ..color = ink.withValues(alpha: .15)
            ..strokeWidth = .6,
        );
      }
    }
    return top + 68;
  }

  String _analysisPercent(double? v) =>
      v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';
  String _analysisDate(DateTime v) =>
      '${v.year}.${v.month.toString().padLeft(2, '0')}.${v.day.toString().padLeft(2, '0')}';
  String _analysisClock(DateTime v) =>
      '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
  String _analysisTitle(String title, [int? rank]) => options.hideBookTitles
      ? (rank == null ? '书名已隐藏' : '书目 ${rank + 1}')
      : title;
  String _analysisChange(double? v) => v == null
      ? '不可比'
      : '${v >= 0 ? '+' : '−'}${(v.abs() * 100).toStringAsFixed(1)}%';
  double _analysisLine(
    String text,
    double top,
    double width, {
    bool dark = false,
    bool heading = false,
  }) =>
      top +
      printText(
        text,
        0,
        top,
        width: width,
        size: heading ? 19 : 13,
        color: heading
            ? (dark ? paper : colors.ink)
            : (dark ? paper.withValues(alpha: .78) : colors.muted),
        weight: heading ? FontWeight.w600 : FontWeight.w400,
        height: 1.55,
      ) +
      (heading ? 16 : 10);
  double _analysisPlot(
    ReadingAnalysisChartKind kind,
    List<ReadingAnalysisDatum> values,
    double top,
    double width, {
    double height = 180,
    List<String> labels = const [],
    bool dark = false,
  }) {
    canvas.save();
    canvas.translate(0, top);
    ReadingAnalysisPainter(
      kind: kind,
      data: [
        for (final d in values)
          ReadingAnalysisDatum(
            translate(d.label),
            d.value,
            secondary: d.secondary,
            cells: d.cells,
            first: d.first,
            completed: d.completed,
          ),
      ],
      labels: labels.map(translate).toList(),
      fontFamily: components?.serifFamily ?? 'CupertinoSystemText',
      ink: dark ? paper : colors.ink,
      muted: dark ? paper.withValues(alpha: .78) : colors.muted,
      accent: colors.accent,
      background: dark ? colors.background : paper,
    ).paint(canvas, Size(width, height));
    canvas.restore();
    return top + height + 16;
  }

  double weekdayPlot(double top, double width, {bool dark = false}) {
    top = _analysisLine('一周节律 · 累计小时', top, width, dark: dark, heading: true);
    return _analysisPlot(
      ReadingAnalysisChartKind.bars,
      [
        for (var i = 0; i < 7; i++)
          ReadingAnalysisDatum(
            ['一', '二', '三', '四', '五', '六', '日'][i],
            data.analysis.weekdaysSeconds[i] == null
                ? null
                : data.analysis.weekdaysSeconds[i]! / 3600,
          ),
      ],
      top,
      width,
      height: 150,
      dark: dark,
    );
  }

  @override
  double printRhythm(
    double width, {
    double chartHeight = 146,
    bool withFacts = true,
    String? statement,
    bool withTemporal = true,
    bool temporalFirst = false,
    bool compactMonths = false,
    bool heading = true,
  }) {
    var top = heading
        ? printHead(ReadingReportModule.rhythm, width, dark: night)
        : 0.0;
    if (data.observedDays == 0) {
      return _analysisLine(
        '开始阅读后，月度、星期、时段与夜读记录会出现在这里。',
        top,
        width,
        dark: night,
      );
    }
    if (statement != null) {
      top = _analysisLine(statement, top, width, dark: night);
    }
    if (withTemporal && temporalFirst) {
      canvas.save();
      canvas.translate(0, top);
      top += printTemporalAnalysis(width, dark: night) + 20;
      canvas.restore();
    }
    top = _analysisLine('月度阅读 · 小时', top, width, dark: night, heading: true);
    top = _analysisLine(
      '${data.analysis.months.first.date.year}.${data.analysis.months.first.date.month.toString().padLeft(2, '0')}—${data.analysis.months.last.date.year}.${data.analysis.months.last.date.month.toString().padLeft(2, '0')}',
      top,
      width,
      dark: night,
    );
    top = _analysisPlot(
      ReadingAnalysisChartKind.bars,
      [
        for (final m in data.analysis.months)
          ReadingAnalysisDatum(
            '${m.date.month}',
            m.totalSeconds == null ? null : m.totalSeconds! / 3600,
          ),
      ],
      top,
      width,
      height: math.max(170, chartHeight),
      dark: night,
    );
    final cols = compactMonths && width >= 440 ? 2 : 1;
    final months = data.analysis.months,
        cellWidth = (width - (cols - 1) * 24) / cols;
    for (var i = 0; i < months.length; i += cols) {
      var rowHeight = 0.0;
      for (var col = 0; col < cols && i + col < months.length; col++) {
        final m = months[i + col];
        rowHeight = math.max(
          rowHeight,
          printText(
            '${m.date.year}.${m.date.month.toString().padLeft(2, '0')}  '
            '${m.totalSeconds == null ? '未知' : statisticsDuration(m.totalSeconds!)}\n环比 ${_analysisChange(m.changeRatio)}${m.isComplete ? '' : ' · 部分月份'}',
            col * (cellWidth + 24),
            top,
            width: cellWidth,
            size: 13,
            height: 1.5,
            color: night ? paper.withValues(alpha: .78) : colors.muted,
          ),
        );
      }
      top += rowHeight + 12;
    }
    final half = data.analysis.halves;
    if (half.isFullYear) {
      top = _analysisLine(
        '${half.year} 上半年 ${half.firstSeconds == null ? '未知' : statisticsDuration(half.firstSeconds!)}'
        ' / 下半年 ${half.secondSeconds == null ? '未知' : statisticsDuration(half.secondSeconds!)}',
        top + 8,
        width,
        dark: night,
      );
      top = _analysisLine(
        half.comparable
            ? '下半年相对上半年 ${_analysisChange(half.changeRatio)}'
            : '半年环比需两个完整半年均有记录。',
        top,
        width,
        dark: night,
      );
    }
    top = weekdayPlot(top + 14, width, dark: night);
    if (withTemporal && !temporalFirst) {
      canvas.save();
      canvas.translate(0, top);
      top += printTemporalAnalysis(width, dark: night);
      canvas.restore();
    }
    return top;
  }

  double printTemporalAnalysis(double width, {bool dark = false}) {
    final a = data.analysis;
    var top = _analysisLine('一天里的阅读时刻', 0, width, dark: dark, heading: true);
    if (!a.coverage.hasTimeDetail) {
      return _analysisLine(
        '时段、夜读与连续单次阅读从新记录开始；旧时长保留，时刻未知。',
        top,
        width,
        dark: dark,
      );
    }
    top = _analysisPlot(
      ReadingAnalysisChartKind.radial,
      [
        for (var i = 0; i < 24; i++)
          ReadingAnalysisDatum('$i时', a.hoursSeconds[i] / 3600),
      ],
      top,
      width,
      height: 260,
      dark: dark,
    );
    top = _analysisLine('24 小时累计分布 · 夜读 22:00–06:00', top, width, dark: dark);
    if (a.latestReading case final latest?) {
      top = _analysisLine(
        '最晚的一页  ${_analysisDate(latest.at)} ${_analysisClock(latest.at)}'
        '\n《${_analysisTitle(latest.title)}》',
        top + 5,
        width,
        dark: dark,
      );
    }
    if (a.longestSession case final session?) {
      top = _analysisLine(
        '最长一次  ${statisticsDuration(session.seconds)}'
        '\n${_analysisDate(session.start)} ${_analysisClock(session.start)}—'
        '${_analysisDate(session.end) != _analysisDate(session.start) ? '${_analysisDate(session.end)} ' : ''}${_analysisClock(session.end)}'
        '\n《${_analysisTitle(session.title)}》${session.isClipped ? ' · 仅计区间内时长' : ''}',
        top + 8,
        width,
        dark: dark,
      );
    }
    top = _analysisLine('夜色里的书页', top + 18, width, dark: dark, heading: true);
    top = _analysisLine(
      '${statisticsDuration(a.nightSeconds)} · 占已测时段 ${_analysisPercent(a.nightRatio)}',
      top,
      width,
      dark: dark,
    );
    top = _analysisPlot(
      ReadingAnalysisChartKind.nightOverlay,
      [
        for (final m in a.months)
          ReadingAnalysisDatum(
            '${m.date.month}',
            m.measuredSeconds / 3600,
            secondary: m.nightSeconds / 3600,
          ),
      ],
      top,
      width,
      height: 170,
      dark: dark,
    );
    top = _analysisLine('浅色：时段明细总时长 · 深色：其中夜读 · 小时', top, width, dark: dark);
    final books = a.booksByDuration.where((b) => b.nightSeconds > 0).toList()
      ..sort((x, y) => y.nightSeconds.compareTo(x.nightSeconds));
    final selected = books.take(options.bookLimit.clamp(1, 5)).toList();
    if (selected.isNotEmpty) {
      top = _analysisLine(
        '夜读书目 · 小时',
        top + 10,
        width,
        dark: dark,
        heading: true,
      );
    }
    if (selected.isNotEmpty) {
      top = _analysisPlot(
        ReadingAnalysisChartKind.horizontal,
        [
          for (final (i, b) in selected.indexed)
            ReadingAnalysisDatum(
              '${_analysisTitle(b.title, i)} · ${_analysisPercent(b.nightRatio)}',
              b.nightSeconds / 3600,
            ),
        ],
        top + 7,
        width,
        height: selected.length * 46,
        dark: dark,
      );
    }
    top = _analysisLine(
      '夜读时留下 ${a.marks.nightBookmarks} 个书签、${a.marks.nightExcerpts} 条摘录。',
      top,
      width,
      dark: dark,
    );
    return _analysisLine(
      '明细覆盖 ${a.coverage.detailedDays} 天 / ${statisticsDuration(a.measuredSeconds)}；比例仅以有时段明细的时长为分母。'
      '日期按记录地自然日拆分，最晚时刻按 06:00 起的一天排序。',
      top,
      width,
      dark: dark,
    );
  }

  @override
  double printCalendar(double width, {bool dark = false}) {
    var top = super.printCalendar(width, dark: dark);
    final a = data.analysis, streak = a.longestStreak;
    top = _analysisLine(
      '自然日覆盖 ${_analysisPercent(a.coverageRatio)} · ${a.activeDays}/${a.coverage.selectedDays} 天',
      top + 10,
      width,
      dark: dark,
    );
    if (streak.start != null) {
      top = _analysisLine(
        '最长连续 ${streak.days} 天\n${_analysisDate(streak.start!)}—${_analysisDate(streak.end!)}',
        top,
        width,
        dark: dark,
      );
    }
    return _analysisLine(
      '区间已有 ${a.coverage.observedDays} 天记录；未覆盖历史保持未知。',
      top,
      width,
      dark: dark,
    );
  }

  @override
  double printCollection(double width, {bool dark = false}) {
    final a = data.analysis;
    var top = printHead(ReadingReportModule.collection, width, dark: dark);
    top = _analysisLine('这段时间的阅读口味', top, width, dark: dark, heading: true);
    if (a.genres.isEmpty) {
      top = _analysisLine('尚无可归属到题材的单书时长。', top, width, dark: dark);
    } else {
      top = _analysisPlot(
        ReadingAnalysisChartKind.treemap,
        [
          for (final g in a.genres)
            ReadingAnalysisDatum(g.label, g.seconds.toDouble()),
        ],
        top,
        width,
        height: 235,
        dark: dark,
      );
      for (final g in a.genres) {
        top = _analysisLine(
          '${g.label}  ${statisticsDuration(g.seconds)} · ${_analysisPercent(g.ratio)}',
          top,
          width,
          dark: dark,
        );
      }
    }
    top = _analysisLine(
      '按有归属的单书时长计；每书使用当前主分类，未分类单列。分母 ${statisticsDuration(a.coverage.bookMeasuredSeconds)}。',
      top,
      width,
      dark: dark,
    );
    top = _analysisLine('当前藏书', top + 18, width, dark: dark, heading: true);
    return _analysisLine(
      '${data.collectionBooks.length} 本 · ${data.authorCount} 位作者\n在线 ${data.onlineBooks} / 本地 ${data.localBooks} · ${_analysisDate(a.snapshotAt)} 快照',
      top,
      width,
      dark: dark,
    );
  }

  double _durationBooks(
    double width, {
    bool dark = false,
    bool programme = false,
    bool covers = true,
    double coverWidth = 46,
    bool heading = true,
  }) {
    final books = data.analysis.booksByDuration
        .where((b) => b.seconds != null)
        .take(options.bookLimit)
        .toList();
    var top = heading
        ? printHead(ReadingReportModule.books, width, dark: dark)
        : 0.0;
    top = _analysisLine('按本期单书阅读时长排列', top, width, dark: dark);
    final maximum = books.map((b) => b.seconds ?? 0).fold<int>(0, math.max);
    for (final (i, book) in books.indexed) {
      final cover = covers ? components?.bookCovers.elementAtOrNull(i) : null;
      final cw = programme && i == 0 ? 84.0 : coverWidth,
          inset = cover == null ? 36.0 : cw + 14;
      if (cover != null) {
        _image(cover, 0, top, width: cw, height: cw * 1.41);
      } else {
        printText(
          '${i + 1}'.padLeft(2, '0'),
          0,
          top,
          width: 30,
          size: 22,
          color: colors.accent,
        );
      }
      var end =
          top +
          printText(
            '${cover == null ? '' : '${i + 1}. '}${_analysisTitle(book.title, i)}',
            inset,
            top,
            width: width - inset,
            size: programme && i == 0 ? 23 : 17,
            weight: FontWeight.w600,
            color: dark ? paper : colors.ink,
          ) +
          8;
      if (!options.hideAuthorNames &&
          book.book?.author.trim().isNotEmpty == true) {
        end +=
            printText(
              book.book!.author,
              inset,
              end,
              width: width - inset,
              size: 13,
              color: dark ? paper.withValues(alpha: .78) : colors.muted,
            ) +
            7;
      }
      end +=
          printText(
            book.seconds == null
                ? '单书时长未知'
                : '${statisticsDuration(book.seconds!)}${book.hasPartialTimeCoverage ? ' · 部分时长' : ''}',
            inset,
            end,
            width: width - inset,
            size: 14,
            color: dark ? paper : colors.ink,
          ) +
          13;
      canvas.drawRect(
        Rect.fromLTWH(inset, end, width - inset, 5),
        Paint()..color = colors.accent.withValues(alpha: .12),
      );
      if (maximum > 0 && book.seconds != null) {
        canvas.drawRect(
          Rect.fromLTWH(
            inset,
            end,
            (width - inset) * book.seconds! / maximum,
            5,
          ),
          Paint()..color = colors.accent,
        );
      }
      top = math.max(end + 24, top + (cover == null ? 0 : cw * 1.41) + 18);
    }
    if (books.isEmpty) top = _analysisLine('尚未留下相伴书目。', top, width, dark: dark);
    return top;
  }

  double _bookContribution(double top, double width, {bool dark = false}) {
    final a = data.analysis;
    final ranked = a.booksByDuration.where((b) => b.seconds != null).toList();
    final selected = ranked.take(5).toList();
    if (a.coverage.bookMeasuredSeconds <= 0) return top;
    top = _analysisLine('单书时间贡献', top + 8, width, dark: dark, heading: true);
    final values = [
      for (final (i, b) in selected.indexed)
        ReadingAnalysisDatum(_analysisTitle(b.title, i), b.seconds?.toDouble()),
      if (ranked.length > selected.length)
        ReadingAnalysisDatum(
          '其余书目',
          ranked
              .skip(selected.length)
              .fold<double>(0, (sum, b) => sum + (b.seconds ?? 0)),
        ),
    ];
    top = _analysisPlot(
      ReadingAnalysisChartKind.share,
      values,
      top,
      width,
      height: 40 + values.length * 26,
      dark: dark,
    );
    return _analysisLine(
      '分母：有单书归属的 ${statisticsDuration(a.coverage.bookMeasuredSeconds)}。',
      top,
      width,
      dark: dark,
    );
  }

  @override
  double printBooks(
    double width, {
    bool dark = false,
    bool covers = true,
    double coverWidth = 32,
  }) {
    var top = _durationBooks(
      width,
      dark: dark,
      covers: covers,
      coverWidth: math.max(42, coverWidth),
    );
    top = _bookContribution(top, width, dark: dark);
    canvas.save();
    canvas.translate(0, top);
    top += printBookJourney(
      width,
      dark: dark,
      withDates: !has(ReadingReportModule.progress),
    );
    canvas.restore();
    return top;
  }

  /// Ranking + contribution only; an edition may place the journey separately.
  double printBookRanking(
    double width, {
    bool dark = false,
    bool covers = true,
    bool programme = false,
    bool heading = true,
    bool withContribution = true,
    double coverWidth = 46,
  }) {
    final top = _durationBooks(
      width,
      dark: dark,
      covers: covers,
      programme: programme,
      heading: heading,
      coverWidth: coverWidth,
    );
    return withContribution ? _bookContribution(top, width, dark: dark) : top;
  }

  @override
  double printBookProgramme(double width, {bool dark = false}) {
    var top = _durationBooks(width, dark: dark, programme: true);
    top = _bookContribution(top, width, dark: dark);
    canvas.save();
    canvas.translate(0, top);
    top += printBookJourney(
      width,
      dark: dark,
      withDates: !has(ReadingReportModule.progress),
    );
    canvas.restore();
    return top;
  }

  @override
  double printBookAtlas(
    double width, {
    int columns = 3,
    bool dark = false,
    bool heading = true,
  }) {
    var top = _durationBooks(
      width,
      dark: dark,
      programme: true,
      heading: heading,
      coverWidth: 58,
    );
    top = _bookContribution(top, width, dark: dark);
    canvas.save();
    canvas.translate(0, top);
    top += printBookJourney(
      width,
      dark: dark,
      withDates: !has(ReadingReportModule.progress),
    );
    canvas.restore();
    return top;
  }

  double printBookJourney(
    double width, {
    bool dark = false,
    bool withDates = true,
  }) {
    final a = data.analysis,
        books = a.booksByDuration.take(options.bookLimit).toList();
    var top = _analysisLine('从初见到合卷', 16, width, dark: dark, heading: true);
    if (books.isEmpty) {
      return _analysisLine('开始阅读后记录书目历程。', top, width, dark: dark);
    }
    // Keep month labels readable, then balance the blocks. A rolling year has
    // thirteen calendar months; it should not repeat every book for one final
    // month when all thirteen fit on the same axis.
    final capacity = math.max(1, (width / 35).floor());
    final blockCount = (a.months.length / capacity).ceil();
    final ordinaryCount = a.months.length ~/ blockCount;
    final extra = a.months.length % blockCount;
    var start = 0;
    for (var block = 0; block < blockCount; block++) {
      final count = ordinaryCount + (block < extra ? 1 : 0);
      final months = a.months.skip(start).take(count).toList();
      start += count;
      top = _analysisLine(
        '${months.first.date.year}.${months.first.date.month.toString().padLeft(2, '0')}—${months.last.date.year}.${months.last.date.month.toString().padLeft(2, '0')}',
        top,
        width,
        dark: dark,
      );
      top = _analysisPlot(
        ReadingAnalysisChartKind.gantt,
        [
          for (final (i, b) in books.indexed)
            ReadingAnalysisDatum(
              _analysisTitle(b.title, i),
              b.seconds?.toDouble(),
              cells: [
                for (final m in months)
                  b.activeMonths.any(
                    (d) => d.year == m.date.year && d.month == m.date.month,
                  ),
              ],
              first: months.indexWhere(
                (m) =>
                    b.firstOpenedAt?.year == m.date.year &&
                    b.firstOpenedAt?.month == m.date.month,
              ),
              completed: months.indexWhere(
                (m) =>
                    b.completedAt?.year == m.date.year &&
                    b.completedAt?.month == m.date.month,
              ),
            ),
        ],
        top,
        width,
        height: 35 + books.length * 54,
        labels: months.map((m) => '${m.date.month}月').toList(),
        dark: dark,
      );
    }
    top = _analysisLine(
      '色段：当月读过 · 圆：首次已记录翻开 · 菱形：完成\n空段保留中断，不以首尾月份填满。',
      top,
      width,
      dark: dark,
    );
    if (withDates) {
      for (final (i, b) in books.indexed) {
        top = _analysisLine(
          '${_analysisTitle(b.title, i)}\n'
          '${b.firstOpenedAt == null ? '首次翻开未知${b.firstKnownAt == null ? '' : ' · 最早已知 ${_analysisDate(b.firstKnownAt!)}'}' : '首次已记录翻开 ${_analysisDate(b.firstOpenedAt!)}'}\n'
          '${b.completedAt == null
              ? b.finished == true
                    ? '已完成 · 当地日期未知'
                    : '尚无完成日期'
              : '${b.finished == true ? '完成' : '读至连载结尾'} ${_analysisDate(b.completedAt!)}'}',
          top + 5,
          width,
          dark: dark,
        );
      }
    }
    return top;
  }

  double monthlyChronicle(double width) => printRhythm(width);
  double bookSpanChronicle(double width) => printBooks(width);
  @override
  double printProgress(
    double width, {
    bool dark = false,
    double chartHeight = 146,
  }) {
    var top = super.printProgress(width, dark: dark, chartHeight: chartHeight);
    final a = data.analysis;
    top = _analysisLine('本期的初见与完成', top + 16, width, dark: dark, heading: true);
    top = _analysisLine(
      '${a.firstOpenedBooks.length} 本有首次翻开记录 · ${a.completedBooks.length} 本有完成日期记录',
      top,
      width,
      dark: dark,
    );
    for (final (i, book)
        in a.firstOpenedBooks.take(options.bookLimit).indexed) {
      top = _analysisLine(
        '${_analysisDate(book.firstOpenedAt!)} · 初见 ${_analysisTitle(book.title, i)}',
        top,
        width,
        dark: dark,
      );
    }
    for (final (i, book) in a.completedBooks.take(options.bookLimit).indexed) {
      top = _analysisLine(
        '${_analysisDate(book.completedAt!)} · 完成 ${_analysisTitle(book.title, i)}',
        top,
        width,
        dark: dark,
      );
    }
    return _analysisLine(
      '上方进度为 ${_analysisDate(a.snapshotAt)} 的当前快照；首次翻开与完成按所选区间统计。',
      top,
      width,
      dark: dark,
    );
  }

  @override
  double printEchoes(
    double width, {
    bool dark = false,
    double leadSize = 17,
    int count = 2,
    bool ruled = true,
  }) {
    var top = super.printEchoes(
      width,
      dark: dark,
      leadSize: leadSize,
      count: count,
      ruled: ruled,
    );
    final marks = data.analysis.marks;
    top = _analysisLine('本期留下的记号', top + 10, width, dark: dark, heading: true);
    top = _analysisLine(
      '${marks.bookmarks} 个书签 · ${marks.excerpts} 条摘录\n其中夜读：${marks.nightBookmarks} 个书签 · ${marks.nightExcerpts} 条摘录',
      top,
      width,
      dark: dark,
    );
    for (final (i, b) in marks.byBook.take(options.bookLimit).indexed) {
      top = _analysisLine(
        '${_analysisTitle(b.title, i)} · ${b.bookmarks} 个书签 / ${b.excerpts} 条摘录',
        top,
        width,
        dark: dark,
      );
    }
    if (marks.unknownDateCount > 0) {
      top = _analysisLine(
        '${marks.unknownDateCount} 条旧记录创建时间未知，保留在当前收藏，不分配到本期。',
        top,
        width,
        dark: dark,
      );
    }
    return top;
  }

  @override
  double printFooter(
    double top, {
    bool dark = false,
    double x = 32,
    double width = 536,
  }) {
    final ink = dark ? paper : colors.ink;
    final summary = data.observedDays == 0
        ? '下一段阅读，将成为这份记录的开篇。'
        : '这段时间，你在 ${data.activeDays} 天里留下了 ${statisticsDuration(data.periodSeconds)} 的阅读记录。';
    final h = printMeasure(summary, width - 34, size: 14, height: 1.7);
    canvas.drawRect(
      Rect.fromLTWH(x, top, width, h + 87),
      Paint()..color = dark ? paper.withValues(alpha: .05) : panelColor,
    );
    printText(
      'TO BE CONTINUED / 下一页',
      x + 17,
      top + 16,
      width: width - 34,
      size: 9,
      color: colors.accent,
    );
    printText(
      summary,
      x + 17,
      top + 39,
      width: width - 34,
      size: 14,
      height: 1.7,
      color: ink,
    );
    printText(
      data.startedAt == null
          ? '尚未记录前台时长'
          : '前台时长自 ${_date(data.startedAt!)} 起记录',
      x + 17,
      top + h + 57,
      width: width - 34,
      size: 10,
      color: dark ? paper.withValues(alpha: .6) : colors.muted,
    );
    return top + h + 114;
  }
}
