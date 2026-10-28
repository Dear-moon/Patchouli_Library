import 'reading_activity.dart';
import 'reading_statistics_data.dart';

/// Report-only facts derived once from the selected statistics snapshot.
/// Nothing here changes the ledger, saved positions or their counting rules.
class ReadingReportInsights {
  ReadingReportInsights._({
    required this.weekdays,
    required this.months,
    required this.books,
    required this.genres,
    required this.badges,
    required this.longestStreak,
    required this.streakStartedAt,
    required this.streakEndedAt,
    required this.mostActiveWeekday,
    required this.peakMonth,
    required this.peakMonthShare,
    required this.previousPeriodChangeRatio,
    required this.weekendShare,
    required this.headline,
  });

  factory ReadingReportInsights.from(
    ReadingStatisticsData data, {
    ReadingActivityStore? activity,
  }) {
    final weekdaySeconds = List.filled(7, 0);
    final weekdayObserved = List.filled(7, 0);
    final weekdayActive = List.filled(7, 0);
    final selectedByDay = <DateTime, int?>{};
    final monthDays = <DateTime, List<int?>>{};
    var longest = 0, run = 0;
    DateTime? runStart, streakStart, streakEnd, previousDay;
    for (var i = 0; i < data.dates.length; i++) {
      final day = statisticsDay(data.dates[i]), seconds = data.seconds[i];
      selectedByDay[day] = seconds;
      monthDays
          .putIfAbsent(DateTime(day.year, day.month), () => [])
          .add(seconds);
      if (seconds != null) {
        final weekday = day.weekday - 1;
        weekdaySeconds[weekday] += seconds;
        weekdayObserved[weekday]++;
        if (seconds > 0) weekdayActive[weekday]++;
      }
      if (seconds != null && seconds > 0) {
        if (previousDay != null &&
            _dayNumber(day) == _dayNumber(previousDay) + 1) {
          run++;
        } else {
          run = 1;
          runStart = day;
        }
        if (run > longest) {
          longest = run;
          streakStart = runStart;
          streakEnd = day;
        }
        previousDay = day;
      } else {
        run = 0;
        runStart = null;
        previousDay = null;
      }
    }

    final weekdays = List<ReadingReportWeekday>.unmodifiable([
      for (var i = 0; i < 7; i++)
        ReadingReportWeekday(
          weekday: i + 1,
          seconds: weekdayObserved[i] == 0 ? null : weekdaySeconds[i],
          observedDays: weekdayObserved[i],
          activeDays: weekdayActive[i],
        ),
    ]);
    ReadingReportWeekday? mostActiveWeekday;
    for (final weekday in weekdays) {
      if ((weekday.seconds ?? 0) > (mostActiveWeekday?.seconds ?? 0)) {
        mostActiveWeekday = weekday;
      }
    }

    final months = <ReadingReportMonth>[];
    ReadingReportMonth? peakMonth;
    for (final entry in monthDays.entries) {
      final observed = entry.value.whereType<int>().toList(growable: false);
      final seconds = observed.isEmpty
          ? null
          : observed.fold<int>(0, (sum, value) => sum + value);
      final calendarDays = DateTime(entry.key.year, entry.key.month + 1, 0).day;
      final complete =
          entry.value.length == calendarDays && observed.length == calendarDays;
      final previous = months.lastOrNull;
      final comparable =
          complete &&
          previous != null &&
          previous.isComplete &&
          DateTime(previous.date.year, previous.date.month + 1) == entry.key &&
          (previous.seconds ?? 0) > 0;
      final month = ReadingReportMonth(
        date: entry.key,
        seconds: seconds,
        selectedDays: entry.value.length,
        observedDays: observed.length,
        calendarDays: calendarDays,
        previousChangeRatio: comparable
            ? (seconds! - previous.seconds!) / previous.seconds!
            : null,
      );
      months.add(month);
      if ((seconds ?? 0) > (peakMonth?.seconds ?? 0)) peakMonth = month;
    }

    final weekendSeconds = weekdaySeconds[5] + weekdaySeconds[6];
    final weekendShare = data.periodSeconds > 0
        ? weekendSeconds / data.periodSeconds
        : null;
    final badges = <ReadingReportBadge>[
      if (longest >= 7)
        ReadingReportBadge(
          id: 'continuous',
          label: '连续阅读',
          basis: '区间最长连续 $longest 天',
          rule: '所选区间连续至少 7 个自然日有有效阅读',
        ),
      if (data.observedDays >= 7 && (data.activeRatio ?? 0) >= .7)
        ReadingReportBadge(
          id: 'regular',
          label: '常来读者',
          basis: '${data.activeDays} / ${data.observedDays} 个已记录日有阅读',
          rule: '至少记录 7 天，活跃日占已记录日不低于 70%',
        ),
      if ((weekendShare ?? 0) >= .5 &&
          weekdayObserved[5] + weekdayObserved[6] >= 2 &&
          weekdayObserved.take(5).fold<int>(0, (sum, value) => sum + value) >=
              5)
        ReadingReportBadge(
          id: 'weekend',
          label: '周末书友',
          basis: '周末占区间阅读时长 ${(weekendShare! * 100).round()}%',
          rule: '至少观察 2 个周末日及 5 个工作日，周末时长占比不低于 50%',
        ),
      if (data.periodBooks >= 3)
        ReadingReportBadge(
          id: 'companions',
          label: '多书同行',
          basis: '${data.periodBooks} 本书留下有效阅读记录',
          rule: '所选区间至少 3 本书留下有效阅读记录',
        ),
    ];
    final headline = data.observedDays == 0
        ? '等待第一段阅读'
        : data.periodSeconds == 0
        ? '这段时间还没有阅读记录'
        : switch (badges.firstOrNull?.id) {
            'continuous' => '把阅读连成日常',
            'regular' => '常回书页的人',
            'weekend' => '把周末留给书页',
            'companions' => '与多本书同行',
            _ => '留下自己的阅读节奏',
          };

    final genreTotal = data.genres.fold<int>(
      0,
      (sum, genre) => sum + genre.books,
    );
    return ReadingReportInsights._(
      weekdays: weekdays,
      months: List.unmodifiable(months),
      books: _bookInsights(data, activity, selectedByDay),
      genres: List.unmodifiable([
        for (final genre in data.genres)
          ReadingReportGenre(
            name: genre.name,
            books: genre.books,
            share: genreTotal == 0 ? 0 : genre.books / genreTotal,
          ),
      ]),
      badges: List.unmodifiable(badges),
      longestStreak: longest,
      streakStartedAt: streakStart,
      streakEndedAt: streakEnd,
      mostActiveWeekday: mostActiveWeekday,
      peakMonth: peakMonth,
      peakMonthShare: peakMonth == null || data.periodSeconds == 0
          ? null
          : peakMonth.seconds! / data.periodSeconds,
      previousPeriodChangeRatio:
          data.hasCompleteComparison && data.previousPeriodSeconds > 0
          ? (data.periodSeconds - data.previousPeriodSeconds) /
                data.previousPeriodSeconds
          : null,
      weekendShare: weekendShare,
      headline: headline,
    );
  }

  final List<ReadingReportWeekday> weekdays;
  final List<ReadingReportMonth> months;
  final List<ReadingReportBook> books;
  final List<ReadingReportGenre> genres;
  final List<ReadingReportBadge> badges;
  final int longestStreak;
  final DateTime? streakStartedAt, streakEndedAt;
  final ReadingReportWeekday? mostActiveWeekday;
  final ReadingReportMonth? peakMonth;
  final double? peakMonthShare, previousPeriodChangeRatio, weekendShare;
  final String headline;

  ReadingReportBook? bookFor(int id) =>
      books.where((book) => book.id == id).firstOrNull;
}

class ReadingReportWeekday {
  const ReadingReportWeekday({
    required this.weekday,
    required this.seconds,
    required this.observedDays,
    required this.activeDays,
  });
  final int weekday, observedDays, activeDays;
  final int? seconds;
  String get label =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];
  double? get averageSeconds =>
      observedDays == 0 ? null : seconds! / observedDays;
}

class ReadingReportMonth {
  const ReadingReportMonth({
    required this.date,
    required this.seconds,
    required this.selectedDays,
    required this.observedDays,
    required this.calendarDays,
    required this.previousChangeRatio,
  });
  final DateTime date;
  final int? seconds;
  final int selectedDays, observedDays, calendarDays;
  final double? previousChangeRatio;
  bool get isComplete =>
      selectedDays == calendarDays && observedDays == calendarDays;
}

class ReadingReportBadge {
  const ReadingReportBadge({
    required this.id,
    required this.label,
    required this.basis,
    required this.rule,
  });
  final String id, label, basis, rule;
}

class ReadingReportBook {
  ReadingReportBook({
    required this.id,
    required this.readingDays,
    required this.recordedSeconds,
    required this.measuredDays,
    required this.hasPartialTimeCoverage,
    required Iterable<DateTime> activeDates,
  }) : activeDates = List.unmodifiable(activeDates),
       activeMonths = List.unmodifiable({
         for (final day in activeDates) DateTime(day.year, day.month),
       });

  final int id, readingDays, measuredDays;

  /// Only measured per-book intervals. A legacy daily total is never allocated.
  /// Present this as “已记录” time, including when every selected day is covered.
  final int? recordedSeconds;

  /// Conservatively true if any relevant day has unassigned rounded seconds,
  /// or lacks a per-book measurement. Rounding may also leave a one-second gap.
  final bool hasPartialTimeCoverage;
  final List<DateTime> activeDates, activeMonths;
  DateTime? get firstReadAt => activeDates.firstOrNull;
  DateTime? get lastReadAt => activeDates.lastOrNull;
}

class ReadingReportGenre {
  const ReadingReportGenre({
    required this.name,
    required this.books,
    required this.share,
  });
  final String name;
  final int books;

  /// Share of known current collection books, not of reading time.
  final double share;
}

List<ReadingReportBook> _bookInsights(
  ReadingStatisticsData data,
  ReadingActivityStore? activity,
  Map<DateTime, int?> selectedByDay,
) {
  bool selected(DateTime date) => selectedByDay[statisticsDay(date)] != null;
  final days =
      activity?.days.where((day) => selected(day.date)).toList() ??
      const <ReadingActivityDay>[];
  final measuredByBook = <int, Map<DateTime, int>>{};
  final allocatedByDay = <DateTime, int>{};
  for (final book in data.booksByReadingDays) {
    final measured = <DateTime, int>{
      for (final day
          in activity?.daysForBook(book.id) ?? const <ReadingActivityDay>[])
        if (selected(day.date)) statisticsDay(day.date): day.seconds,
    };
    measuredByBook[book.id] = measured;
    for (final entry in measured.entries) {
      allocatedByDay.update(
        entry.key,
        (sum) => sum + entry.value,
        ifAbsent: () => entry.value,
      );
    }
  }
  return List.unmodifiable([
    for (final book in data.booksByReadingDays)
      () {
        final activeDates = [
          for (final day in days)
            if (day.bookIds.contains(book.id)) statisticsDay(day.date),
        ]..sort();
        final measured = measuredByBook[book.id]!;
        return ReadingReportBook(
          id: book.id,
          readingDays: book.days,
          recordedSeconds: measured.isEmpty
              ? null
              : measured.values.fold<int>(0, (sum, value) => sum + value),
          measuredDays: measured.length,
          hasPartialTimeCoverage:
              activity == null ||
              measured.length < book.days ||
              activeDates.any(
                (date) =>
                    !measured.containsKey(date) ||
                    allocatedByDay[date] != selectedByDay[date],
              ),
          activeDates: activeDates,
        );
      }(),
  ]);
}

int _dayNumber(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;
