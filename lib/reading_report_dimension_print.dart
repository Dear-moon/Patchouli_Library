part of 'reading_report_layout.dart';

/// Compact report-only plots of the measured detail summaries.
mixin _ReportDimensionPrint on _ReportAnalysisComposer {
  Color _dimensionInk(bool dark) => dark ? paper : colors.ink;
  Color _dimensionMuted(bool dark) =>
      dark ? paper.withValues(alpha: .72) : colors.muted;

  double _dimensionHeading(String title, double width, {bool dark = false}) =>
      printText(
        title,
        0,
        0,
        width: width,
        size: 17,
        weight: FontWeight.w600,
        color: _dimensionInk(dark),
        height: 1.25,
      ) +
      10;

  String _dimensionDuration(int milliseconds) =>
      milliseconds > 0 && milliseconds < 1000
      ? '不足1秒'
      : statisticsDuration(milliseconds ~/ 1000);

  /// No fill in an empty cell: legacy daily totals never enter this matrix.
  double printWeekHourHeatmap(double width, {bool dark = false}) {
    final matrix = data.analysis.weekHourMatrix;
    if (!matrix.hasData) return 0;
    var top = _dimensionHeading('星期 × 时段', width, dark: dark);
    final ink = _dimensionInk(dark), muted = _dimensionMuted(dark);
    const left = 23.0;
    final cell = (width - left) / 24;
    final rowHeight = width < 300 ? 12.5 : 14.0;
    for (final hour in const [0, 6, 12, 18, 23]) {
      final labelWidth = math.min(31.0, cell * 3);
      final x = (left + hour * cell - labelWidth / 2 + cell / 2)
          .clamp(left, width - labelWidth)
          .toDouble();
      printText(
        '$hour',
        x,
        top,
        width: labelWidth,
        size: 11.5,
        color: muted,
        align: TextAlign.center,
      );
    }
    top += 20;
    final maximum = matrix.milliseconds
        .expand((row) => row)
        .fold<int>(0, math.max);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    for (var day = 0; day < 7; day++) {
      final y = top + day * rowHeight;
      printText(
        weekdays[day],
        0,
        y - .5,
        width: 17,
        size: 11.5,
        color: ink,
        height: 1,
      );
      for (var hour = 0; hour < 24; hour++) {
        final value = matrix.milliseconds[day][hour];
        final bounds = Rect.fromLTWH(
          left + hour * cell + .7,
          y,
          math.max(0, cell - 1.4),
          rowHeight - 1.8,
        );
        if (value > 0) {
          canvas.drawRect(
            bounds,
            Paint()
              ..color = colors.accent.withValues(
                alpha: .22 + .78 * math.sqrt(value / maximum),
              ),
          );
        } else {
          canvas.drawRect(
            bounds,
            Paint()
              ..color = ink.withValues(alpha: .10)
              ..style = PaintingStyle.stroke
              ..strokeWidth = .45,
          );
        }
      }
    }
    top += rowHeight * 7 + 9;
    top += printText(
      '${matrix.days}天有时段记录 · 已测时长${_dimensionDuration(matrix.measuredMilliseconds)}',
      0,
      top,
      width: width,
      size: 11.5,
      color: muted,
      height: 1.4,
    );
    top += 4;
    return top +
        printText(
          '颜色越深，时长越多；空格未测得时长。',
          0,
          top,
          width: width,
          size: 11.5,
          color: muted,
          height: 1.4,
        ) +
        4;
  }

  /// The line encodes count share; the label separately gives duration share.
  double printSessionLengths(double width, {bool dark = false}) {
    final distribution = data.analysis.sessionLengths;
    if (!distribution.hasData) return 0;
    final ink = _dimensionInk(dark), muted = _dimensionMuted(dark);
    final titleWidth = width < 300 ? width - 113 : width - 150;
    var top = printText(
      '单次阅读长度',
      0,
      0,
      width: titleWidth,
      size: 17,
      weight: FontWeight.w600,
      color: ink,
      height: 1.25,
    );
    final legendHeight = printText(
      '次数 / 时长占比',
      titleWidth + 5,
      3,
      width: width - titleWidth - 5,
      size: 11.5,
      color: muted,
      align: TextAlign.right,
      height: 1.25,
    );
    top = math.max(top, legendHeight + 3) + 12;
    for (final bucket in distribution.buckets) {
      printText(
        bucket.label,
        0,
        top,
        width: width - 105,
        size: 12.5,
        color: ink,
        height: 1.2,
      );
      final share = bucket.milliseconds / distribution.completeMilliseconds;
      printText(
        '${bucket.count}次 / ${(share * 100).round()}%',
        width - 101,
        top,
        width: 101,
        size: 12.5,
        color: muted,
        align: TextAlign.right,
        height: 1.2,
      );
      if (bucket.count > 0) {
        canvas.drawRect(
          Rect.fromLTWH(
            0,
            top + 19,
            width * bucket.count / distribution.completeSessionCount,
            3,
          ),
          Paint()..color = colors.accent,
        );
      }
      top += 27;
    }
    return top +
        printText(
          '完整单次${distribution.completeSessionCount}次 · 线长为次数占比${distribution.excludedClippedSessionCount == 0 ? '' : ' · ${distribution.excludedClippedSessionCount}次边界截断未纳入'}',
          0,
          top,
          width: width,
          size: 11.5,
          color: muted,
          height: 1.4,
        ) +
        6;
  }

  double printBookDayDistribution(double width, {bool dark = false}) {
    final distribution = data.analysis.bookDayDistribution;
    if (!distribution.hasData) return 0;
    var top = _dimensionHeading('一天里的书目', width, dark: dark);
    final ink = _dimensionInk(dark), muted = _dimensionMuted(dark);
    final column = width / distribution.buckets.length;
    for (final (index, bucket) in distribution.buckets.indexed) {
      final x = index * column;
      printText(
        '${bucket.days}',
        x,
        top,
        width: column - 28,
        size: 32,
        display: true,
        color: ink,
        weight: FontWeight.w600,
        height: 1,
      );
      printText(
        '天',
        x + column - 24,
        top + 17,
        width: 18,
        size: 11.5,
        color: muted,
        height: 1,
      );
      printText(
        bucket.label,
        x,
        top + 37,
        width: column - 8,
        size: 12,
        color: muted,
        height: 1.3,
      );
      printText(
        '${(bucket.days / distribution.attributedActiveDays * 100).round()}%',
        x,
        top + 58,
        width: column - 8,
        size: 12,
        color: muted,
      );
    }
    top += 85;
    var left = 0.0;
    for (final (index, bucket) in distribution.buckets.indexed) {
      final segment = width * bucket.days / distribution.attributedActiveDays;
      if (bucket.days > 0) {
        canvas.drawRect(
          Rect.fromLTWH(left, top, segment, 7),
          Paint()..color = colors.accent.withValues(alpha: 1 - index * .25),
        );
      }
      left += segment;
    }
    top += 19;
    return top +
        printText(
          '同一天读过的不同书目 · ${distribution.attributedActiveDays}个有书目归属的阅读日${distribution.unattributedActiveDays == 0 ? '' : '；另${distribution.unattributedActiveDays}天未标书目'}',
          0,
          top,
          width: width,
          size: 11.5,
          color: muted,
          height: 1.4,
        ) +
        6;
  }

  double printMonthlyMilestones(double width, {bool dark = false}) {
    final milestones = data.analysis.monthlyMilestones;
    if (!milestones.hasData) return 0;
    final ink = _dimensionInk(dark), muted = _dimensionMuted(dark);
    final months = milestones.months;
    final showOpened = months.any((month) => month.openedBooks > 0);
    final showCompleted = months.any((month) => month.completedBooks > 0);
    final series = [
      if (showOpened)
        (
          label: '首次已记录翻开',
          summary: '首次翻开${milestones.datedOpenedBooks}本',
          color: colors.accent,
          opened: true,
        ),
      if (showCompleted)
        (
          label: '完读',
          summary: '完读${milestones.datedCompletedBooks}本',
          color: ink.withValues(alpha: .72),
          opened: false,
        ),
    ];
    if (series.isEmpty) return 0;
    var top = _dimensionHeading(
      showOpened && showCompleted
          ? '本期的初见与完成'
          : showOpened
          ? '本期的初见'
          : '本期的完成',
      width,
      dark: dark,
    );
    final eventMonths = months.where((month) => month.hasEvents).toList();
    if (eventMonths.length == 1) {
      final month = eventMonths.single;
      final facts = [
        '${month.date.year}.${month.date.month.toString().padLeft(2, '0')}',
        if (month.openedBooks > 0) '初见${month.openedBooks}本',
        if (month.completedBooks > 0) '完读${month.completedBooks}本',
      ];
      return top +
          printText(
            facts.join(' · '),
            0,
            top,
            width: width,
            size: 13,
            color: ink,
            height: 1.4,
          ) +
          6;
    }
    for (final (index, item) in series.indexed) {
      final x = index == 0 ? 0.0 : width * .64;
      final available = series.length == 1
          ? width
          : index == 0
          ? width * .64
          : width * .36;
      canvas.drawRect(
        Rect.fromLTWH(x, top + 5, 8, 8),
        Paint()..color = item.color,
      );
      printText(
        item.label,
        x + 14,
        top,
        width: available - 14,
        size: 12,
        color: muted,
        height: 1.25,
      );
    }
    top += 28;
    final maximum = months.fold<int>(
      0,
      (value, month) =>
          math.max(value, math.max(month.openedBooks, month.completedBooks)),
    );
    const plotHeight = 80.0;
    final groupWidth = width / months.length;
    final gap = math.min(2.0, groupWidth * .10);
    final barWidth = math.max(
      0.0,
      (groupWidth - gap * (series.length + 1)) / series.length,
    );
    final labelStep = math.max(1, (44 / groupWidth).ceil());
    final ticks = <(int, double)>[];
    for (final (index, month) in months.indexed) {
      final x = index * groupWidth;
      for (final (seriesIndex, item) in series.indexed) {
        final count = item.opened ? month.openedBooks : month.completedBooks;
        if (count == 0) continue;
        final h = plotHeight * count / maximum;
        canvas.drawRect(
          Rect.fromLTWH(
            x + gap + seriesIndex * (barWidth + gap),
            top + plotHeight - h,
            barWidth,
            h,
          ),
          Paint()..color = item.color,
        );
      }
      if (index % labelStep == 0 || index == months.length - 1) {
        final labelX = (x + groupWidth / 2 - 22)
            .clamp(0.0, math.max(0.0, width - 44))
            .toDouble();
        if (index == months.length - 1) {
          while (ticks.length > 1 && labelX - ticks.last.$2 < 46) {
            ticks.removeLast();
          }
        } else if (ticks.isNotEmpty && labelX - ticks.last.$2 < 46) {
          continue;
        }
        ticks.add((index, labelX));
      }
    }
    for (final (index, x) in ticks) {
      final date = months[index].date;
      printText(
        '${(date.year % 100).toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}',
        x,
        top + plotHeight + 7,
        width: 44,
        size: 11.5,
        color: muted,
        align: TextAlign.center,
        height: 1.2,
      );
    }
    canvas.drawLine(
      Offset(0, top + plotHeight),
      Offset(width, top + plotHeight),
      Paint()
        ..color = ink.withValues(alpha: .18)
        ..strokeWidth = .6,
    );
    top += plotHeight + 29;
    top += printText(
      series.map((item) => item.summary).join(' · '),
      0,
      top,
      width: width,
      size: 11.5,
      color: muted,
      height: 1.4,
    );
    return top + 6;
  }
}
