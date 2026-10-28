part of 'reading_report_layout.dart';

/// A real dated calendar, independent of the edition's reading-day summary.
/// Uses the same daily ledger as the statistics screen, including unknown days.
mixin _ReportCalendarPrint on _ReportArtDirectionComposer {
  double drawReadingCalendar(double width, {bool heading = true}) {
    var top = 0.0;
    if (heading) {
      top =
          printText(
            '阅读日历',
            0,
            top,
            width: width,
            size: 24,
            weight: FontWeight.w600,
          ) +
          7;
      top +=
          printText(
            'READING DAYS / DAILY RECORD',
            0,
            top,
            width: width,
            size: 10,
            color: colors.muted,
          ) +
          24;
    }
    // Long ranges use a compact year strip so a calendar does not crowd out
    // the edition's story. Short ranges retain readable individual date cells.
    if (data.period > 93) return _yearCalendar(width, top);
    final months = <DateTime, List<int>>{};
    for (var i = 0; i < data.dates.length; i++) {
      final date = data.dates[i];
      months.putIfAbsent(DateTime(date.year, date.month), () => []).add(i);
    }
    final maximum = data.seconds.whereType<int>().fold<int>(0, math.max);
    final columns = months.length == 1 ? 1 : 2;
    const gap = 28.0;
    final monthWidth = (width - gap * (columns - 1)) / columns;
    final pitch = math.min(35.0, monthWidth / 7);
    final cell = math.min(25.0, pitch - 4);
    final entries = months.entries.toList();
    final round = options.template == ReadingReportTemplate.constellation;
    for (var first = 0; first < entries.length; first += columns) {
      var rowHeight = 0.0;
      for (var col = 0; col < columns && first + col < entries.length; col++) {
        final entry = entries[first + col];
        final month = entry.key;
        final x = col * (monthWidth + gap);
        final left = x + (monthWidth - pitch * 7) / 2;
        printText(
          '${month.year} / ${month.month.toString().padLeft(2, '0')}',
          x,
          top,
          width: monthWidth,
          size: 16,
          weight: FontWeight.w600,
        );
        rule(x, top + 29, monthWidth, color: colors.ink.withValues(alpha: .2));
        for (var day = 0; day < 7; day++) {
          printText(
            const ['一', '二', '三', '四', '五', '六', '日'][day],
            left + day * pitch,
            top + 38,
            width: pitch,
            size: 11,
            color: colors.muted,
            align: TextAlign.center,
          );
        }
        final offset = month.weekday - 1;
        for (final index in entry.value) {
          final date = data.dates[index];
          final position = offset + date.day - 1;
          final rect = Rect.fromLTWH(
            left + (position % 7) * pitch + (pitch - cell) / 2,
            top + 61 + (position ~/ 7) * (cell + 7),
            cell,
            cell,
          );
          final seconds = data.seconds[index];
          final active = seconds != null && seconds > 0;
          final paint = Paint()
            ..color = active
                ? Color.lerp(
                    colors.background,
                    colors.accent,
                    .3 + .7 * math.sqrt(seconds / maximum),
                  )!
                : colors.ink.withValues(alpha: seconds == null ? .08 : .28)
            ..style = active ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = .65;
          if (round) {
            canvas.drawCircle(rect.center, cell / 2, paint);
          } else {
            canvas.drawRect(rect, paint);
          }
          final textColor = active
              ? (paint.color.computeLuminance() > .4
                    ? const Color(0xff242725)
                    : const Color(0xfffaf9f2))
              : colors.ink.withValues(alpha: seconds == null ? .38 : .85);
          printText(
            '${date.day}',
            rect.left,
            rect.top + (cell - 12) / 2,
            width: cell,
            size: 11,
            height: 1,
            color: textColor,
            align: TextAlign.center,
          );
        }
        final lastDay = entry.value.last;
        final rows = ((offset + data.dates[lastDay].day) / 7).ceil();
        rowHeight = math.max(rowHeight, 61 + rows * (cell + 7) + 25);
      }
      top += rowHeight;
    }
    return top +
        printText(
          '浅框：未记录 · 深框：已记录 0 · 色深：阅读时长',
          0,
          top,
          width: width,
          size: 11.5,
          color: colors.muted,
        );
  }

  double _yearCalendar(double width, double top) {
    final maximum = data.seconds.whereType<int>().fold<int>(0, math.max);
    final blocks = (data.dates.length / 371).ceil();
    final length = (data.dates.length / blocks).ceil();
    for (var start = 0; start < data.dates.length; start += length) {
      final end = math.min(start + length, data.dates.length);
      final dates = data.dates.sublist(start, end);
      String date(DateTime value) =>
          '${value.year}.${value.month}.${value.day}';
      top +=
          printText(
            '${date(dates.first)} — ${date(dates.last)}',
            0,
            top,
            width: width,
            size: 12,
            color: colors.muted,
          ) +
          16;
      final offset = dates.first.weekday - 1;
      final weeks = ((dates.length + offset) / 7).ceil();
      final pitch = math.min(18.0, (width - 25) / weeks);
      final cell = math.min(14.0, pitch - 2);
      const row = 17.0;
      final left = 25 + math.max(0.0, (width - 25 - weeks * pitch) / 2);
      var previousLabelRight = -100.0;
      for (var i = 0; i < dates.length; i++) {
        if (i != 0 && dates[i].day != 1) continue;
        // A few trailing days of the first month must not steal the next
        // month's label; the exact range above already identifies that edge.
        if (i == 0 && dates[i].day > 15) continue;
        final x = math.min(left + ((i + offset) ~/ 7) * pitch, width - 30);
        if (x < previousLabelRight + 5) continue;
        printText(
          '${dates[i].month}月',
          x,
          top,
          width: 30,
          size: 11,
          color: colors.muted,
        );
        previousLabelRight = x + 24;
      }
      top += 24;
      for (final day in [0, 2, 4, 6]) {
        printText(
          const ['一', '二', '三', '四', '五', '六', '日'][day],
          left - 25,
          top + day * row,
          width: 20,
          size: 11,
          color: colors.muted,
          height: 1,
        );
      }
      for (var i = 0; i < dates.length; i++) {
        final position = i + offset;
        final rect = Rect.fromLTWH(
          left + (position ~/ 7) * pitch,
          top + (position % 7) * row,
          cell,
          12,
        );
        final seconds = data.seconds[start + i];
        final active = seconds != null && seconds > 0;
        final paint = Paint()
          ..color = active
              ? Color.lerp(
                  colors.background,
                  colors.accent,
                  .25 + .75 * math.sqrt(seconds / maximum),
                )!
              : colors.ink.withValues(alpha: seconds == null ? .08 : .28)
          ..style = active ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = .65;
        if (options.template == ReadingReportTemplate.constellation) {
          canvas.drawCircle(rect.center, math.min(cell, 12) / 2, paint);
        } else {
          canvas.drawRect(rect, paint);
        }
      }
      top += row * 7 + 24;
    }
    return top +
        printText(
          '浅框：未记录 · 深框：已记录 0 · 色深：阅读时长',
          0,
          top,
          width: width,
          size: 11.5,
          color: colors.muted,
        );
  }
}
