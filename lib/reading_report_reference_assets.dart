import 'reading_report_options.dart';
import 'reading_export_theme.dart';
import 'reading_statistics_data.dart';

bool readingReportHasMetadataText(String? value) =>
    value != null &&
    value.trim().isNotEmpty &&
    !const {'书名待读取', '作者待读取'}.contains(value.trim());

bool readingReportHasAuthorText(String? value) =>
    readingReportHasMetadataText(value) &&
    !const {'未知', '未知作者'}.contains(value!.trim());

/// One snapshot resolves the same canonical cover for picker, preview and PNG.
String readingReportHeroArt(
  ReadingStatisticsData data,
  ReadingReportOptions options,
) => readingExportArt(
  options.template.theme,
  at: data.today,
).split('/').last.replaceAll('.webp', '');

Set<String> readingReportArtKeys(
  ReadingStatisticsData data,
  ReadingReportOptions options,
) {
  final visible = readingReportVisibleModules(data, options);
  final hero = readingReportHeroArt(data, options);
  // Empty editions only paint their canonical cover. Do not decode scenes for
  // chapters the reader has not selected (or does not have data to display).
  if (visible.isEmpty) return {hero};
  return {
    hero,
    ...switch (options.template) {
      ReadingReportTemplate.archive => {
        if (visible.contains(ReadingReportModule.progress)) 'char_full',
        if (visible.contains(ReadingReportModule.collection)) 'bg_hall',
      },
      ReadingReportTemplate.constellation => <String>{},
      ReadingReportTemplate.shelf => <String>{},
      ReadingReportTemplate.editorial => {
        for (final season in readingReportSeasons(data)) season.asset,
      },
      ReadingReportTemplate.score => {
        'char_pv_open',
        'char_pv_train',
        'char_pv_end',
      },
      ReadingReportTemplate.signal => {'char_papercut', 'char_birds'},
      ReadingReportTemplate.ink => <String>{},
      ReadingReportTemplate.festival => {'char_pv_train', 'char_pv_end'},
    },
  };
}

/// Union of legacy active-book dates and newly measured positive detail.
Set<int> readingReportActiveBookIds(ReadingStatisticsData data) =>
    Set.unmodifiable({
      for (final book in data.analysis.booksByDuration)
        if (book.activeDates.isNotEmpty ||
            book.measuredMilliseconds > 0 ||
            (book.seconds ?? 0) > 0)
          book.id,
    });

/// A selected preference can be unavailable without changing the saved choice.
Set<ReadingReportModule> readingReportAvailableModules(
  ReadingStatisticsData data,
) {
  final a = data.analysis;
  return {
    if (data.periodSeconds > 0 ||
        a.weekHourMatrix.hasData ||
        a.sessionLengths.hasData ||
        a.latestReading != null ||
        a.longestSession != null)
      ReadingReportModule.rhythm,
    if (data.periodSeconds > 0 || a.measuredMilliseconds > 0)
      ReadingReportModule.days,
    if (data.periodSeconds > 0 || a.measuredMilliseconds > 0)
      ReadingReportModule.calendar,
    if (readingReportActiveBookIds(data).isNotEmpty) ReadingReportModule.books,
    if (data.progressBands.any((count) => count > 0) ||
        a.monthlyMilestones.hasData ||
        a.firstOpenedBooks.isNotEmpty ||
        a.completedBooks.isNotEmpty ||
        a.reachedEndBooks.any((book) => book.finished == false))
      ReadingReportModule.progress,
    if (data.onlineBooks + data.localBooks > 0 ||
        a.genres.any((genre) => genre.seconds > 0))
      ReadingReportModule.collection,
    if (data.excerpts.any((excerpt) => excerpt.quote.trim().isNotEmpty) ||
        data.bookmarks + data.underlines > 0 ||
        a.marks.items.isNotEmpty)
      ReadingReportModule.excerpts,
  };
}

Set<ReadingReportModule> readingReportVisibleModules(
  ReadingStatisticsData data,
  ReadingReportOptions options,
) => readingReportAvailableModules(data).intersection(options.modules);

class ReadingReportSeason {
  const ReadingReportSeason({
    required this.label,
    required this.asset,
    required this.start,
    required this.end,
    required this.seconds,
    int? milliseconds,
  }) : milliseconds = milliseconds ?? seconds * 1000;
  final String label, asset;
  final DateTime start, end;
  final int seconds, milliseconds;
}

(String, String) _season(int month) => switch (month) {
  3 || 4 || 5 => ('春', 'char_season_spring'),
  6 || 7 || 8 => ('夏', 'char_season_summer'),
  9 || 10 || 11 => ('秋', 'char_season_autumn'),
  _ => ('冬', 'char_season_winter'),
};

/// Consecutive seasonal spans, clipped to the selected civil dates.
/// A span without any actual reading is omitted instead of inventing a season.
List<ReadingReportSeason> readingReportSeasons(ReadingStatisticsData data) {
  final result = <ReadingReportSeason>[];
  var start = 0;
  while (start < data.dates.length) {
    final initial = data.dates[start];
    final season = _season(initial.month);
    final seasonYear = initial.month == 12 ? initial.year + 1 : initial.year;
    var end = start + 1;
    while (end < data.dates.length) {
      final date = data.dates[end];
      if (_season(date.month).$1 != season.$1 ||
          (date.month == 12 ? date.year + 1 : date.year) != seasonYear) {
        break;
      }
      end++;
    }
    final seconds = data.seconds
        .sublist(start, end)
        .whereType<int>()
        .fold<int>(0, (sum, value) => sum + value);
    final firstMonth = initial.year * 12 + initial.month;
    final lastMonth = data.dates[end - 1].year * 12 + data.dates[end - 1].month;
    final measuredMilliseconds = data.analysis.months
        .where(
          (month) =>
              month.date.year * 12 + month.date.month >= firstMonth &&
              month.date.year * 12 + month.date.month <= lastMonth,
        )
        .fold<int>(0, (sum, month) => sum + month.measuredMilliseconds);
    if (seconds > 0 || measuredMilliseconds > 0) {
      result.add(
        ReadingReportSeason(
          label: season.$1,
          asset: season.$2,
          start: initial,
          end: data.dates[end - 1],
          seconds: seconds,
          milliseconds: seconds > 0 ? seconds * 1000 : measuredMilliseconds,
        ),
      );
    }
    start = end;
  }
  return List.unmodifiable(result);
}
