import 'reading_statistics_analysis.dart';

/// Dated book events that may be marked inside a selected civil-day range.
class ReadingReportTimelineMarkers {
  const ReadingReportTimelineMarkers({
    this.firstOpenedAt,
    this.completedAt,
    this.reachedEndAt,
  });
  final DateTime? firstOpenedAt, completedAt, reachedEndAt;
}

ReadingReportTimelineMarkers readingReportTimelineMarkers(
  StatisticsAnalysisBook book, {
  required DateTime start,
  required DateTime end,
}) {
  int day(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
  final first = day(start), last = day(end);
  DateTime? selected(DateTime? event) =>
      event != null && day(event) >= first && day(event) <= last ? event : null;
  return ReadingReportTimelineMarkers(
    firstOpenedAt: selected(book.firstOpenedAt),
    completedAt: book.finished == true ? selected(book.completedAt) : null,
    reachedEndAt: book.finished == false ? selected(book.completedAt) : null,
  );
}
