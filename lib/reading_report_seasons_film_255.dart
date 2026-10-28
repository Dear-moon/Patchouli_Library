part of 'reading_report_layout.dart';

class _SFEvent {
  const _SFEvent(this.at, this.kind, this.book);
  final DateTime at;
  final String kind;
  final StatisticsAnalysisBook book;
  String get key => '$kind/${book.id}/${at.toIso8601String()}';
}

int _sfDay(DateTime at) =>
    DateTime.utc(at.year, at.month, at.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

bool _sfWithin(DateTime at, DateTime first, DateTime last) =>
    _sfDay(at) >= _sfDay(first) && _sfDay(at) <= _sfDay(last);

/// Shared facts and small print primitives, not a shared chapter sequence.
mixin _SeasonFilmFacts on _ReferencePosterComposer {
  late final List<_SFEvent> _sfEvents =
      [
            for (final book in data.analysis.firstOpenedBooks)
              _SFEvent(book.firstOpenedAt!, '初见', book),
            for (final book in data.analysis.completedBooks)
              _SFEvent(book.completedAt!, '完读', book),
            for (final book in data.analysis.reachedEndBooks)
              if (book.finished == false)
                _SFEvent(book.completedAt!, '连载结尾', book),
          ]
          .where(
            (event) => _sfWithin(event.at, data.dates.first, data.dates.last),
          )
          .toList()
        ..sort((a, b) {
          final day = _sfDay(a.at).compareTo(_sfDay(b.at));
          if (day != 0) return day;
          final minute = (a.at.hour * 60 + a.at.minute).compareTo(
            b.at.hour * 60 + b.at.minute,
          );
          return minute != 0 ? minute : a.book.id.compareTo(b.book.id);
        });

  int _sfMonthKey(DateTime at) => at.year * 12 + at.month;

  int _sfMonthMs(StatisticsAnalysisMonth month) =>
      math.max((month.totalSeconds ?? 0) * 1000, month.measuredMilliseconds);

  String _sfDuration(int ms) =>
      ms > 0 && ms < 1000 ? '不足1秒' : statisticsDuration(ms ~/ 1000);

  String _sfBookName(StatisticsAnalysisBook book) {
    final rank = _rankedBooks.indexWhere((item) => item.id == book.id);
    if (options.hideBookTitles) {
      return rank >= 0
          ? '书目 ${(rank + 1).toString().padLeft(2, '0')}'
          : '书名已隐藏';
    }
    return _hasTitle(book.title) ? book.title : '';
  }

  String _sfEventLine(_SFEvent event) {
    final book = _sfBookName(event.book);
    return '${_analysisDate(event.at)} · ${event.kind}${book.isEmpty ? '' : ' $book'}';
  }

  String _sfEventSummary(List<_SFEvent> events) => [
    for (final kind in const ['初见', '完读', '连载结尾'])
      if (events.any((event) => event.kind == kind))
        '$kind${events.where((event) => event.kind == kind).length}本',
  ].join(' · ');

  double _sfEventRows(
    List<_SFEvent> events,
    double width, {
    bool centered = false,
  }) {
    if (events.isEmpty) return 0;
    var top = 0.0;
    final lines = events.length <= 6
        ? events.map(_sfEventLine).toList()
        : [
            _sfEventSummary(events),
            '最早 · ${_sfEventLine(events.first)}',
            '最近 · ${_sfEventLine(events.last)}',
          ];
    for (final line in lines) {
      top +=
          printText(
            line,
            0,
            top,
            width: width,
            size: 12.5,
            height: 1.5,
            color: colors.muted,
            align: centered ? TextAlign.center : TextAlign.left,
          ) +
          7;
    }
    return top;
  }

  double _sfPositions(double width, {bool film = false}) {
    final known = data.progressBands.fold<int>(0, (sum, value) => sum + value);
    if (known == 0) return 0;
    var top =
        printText(
          film ? 'CURRENT FRAME / 当前书页' : '此刻夹着的页签',
          0,
          0,
          width: width,
          size: 16,
          weight: FontWeight.w600,
        ) +
        16;
    final cell = width / 4;
    for (var i = 0; i < 4; i++) {
      final x = cell * i;
      printText(
        '${data.progressBands[i]}',
        x,
        top,
        width: cell - 8,
        size: 29,
        display: true,
        color: colors.accent,
        weight: FontWeight.w700,
        height: 1,
      );
      printText(
        '${i * 25}–${(i + 1) * 25}%',
        x,
        top + 36,
        width: cell - 8,
        size: 11.5,
        color: colors.muted,
      );
      if (data.progressBands[i] > 0) {
        canvas.drawRect(
          Rect.fromLTWH(
            x,
            top + 61,
            (cell - 12) * data.progressBands[i] / known,
            3,
          ),
          Paint()..color = colors.accent,
        );
      }
    }
    top += 79;
    return top +
        printText(
          '${_analysisDate(data.analysis.snapshotAt)} · $known本的阅读位置快照',
          0,
          top,
          width: width,
          size: 11.5,
          color: colors.muted,
        ) +
        8;
  }

  double _sfInventory(double width, {bool film = false}) {
    var top = 0.0;
    final inventory = data.onlineBooks + data.localBooks;
    final genres = data.analysis.genres
        .where((genre) => genre.seconds > 0)
        .toList();
    if (inventory == 0 && genres.isEmpty) return 0;
    top +=
        printText(
          film ? 'ART DEPARTMENT / 书架' : '手帖最后一页 · 书架',
          0,
          top,
          width: width,
          size: 16,
          weight: FontWeight.w600,
        ) +
        11;
    if (inventory > 0) {
      top +=
          printText(
            '$inventory本藏书${data.authorCount > 0 ? ' · ${data.authorCount}位作者' : ''}',
            0,
            top,
            width: width,
            size: 20,
            weight: FontWeight.w600,
          ) +
          7;
      top +=
          printText(
            '在线 ${data.onlineBooks} / 本地 ${data.localBooks} · ${_analysisDate(data.analysis.snapshotAt)} 快照',
            0,
            top,
            width: width,
            size: 12,
            color: colors.muted,
          ) +
          14;
    }
    for (final genre in genres) {
      top +=
          printText(
            '${genre.label} · ${_sfDuration(genre.seconds * 1000)} · ${_analysisPercent(genre.ratio)}',
            0,
            top,
            width: width,
            size: 12.5,
            color: colors.muted,
          ) +
          7;
    }
    return top;
  }

  StatisticsMarkRecord? _sfQuoteRecord(StatisticsExcerpt excerpt) {
    final records = data.analysis.marks.items
        .where(
          (mark) =>
              mark.quote.trim() == excerpt.quote &&
              mark.title == excerpt.title &&
              mark.chapter == excerpt.chapter,
        )
        .toList();
    return records.length == 1 ? records.single : null;
  }

  double _sfQuotes(double width, {bool film = false}) {
    var top = 0.0;
    final quotes = data.excerpts.take(2).toList();
    for (final (index, excerpt) in quotes.indexed) {
      if (index > 0) {
        rule(0, top + 2, width, color: colors.muted.withValues(alpha: .3));
        top += 28;
      }
      top +=
          printText(
            film ? '“${excerpt.quote}”' : excerpt.quote,
            0,
            top,
            width: width,
            size: film
                ? 24
                : index == 0
                ? 27
                : 21,
            fixedTitle: true,
            height: 1.6,
            align: film ? TextAlign.center : TextAlign.left,
          ) +
          14;
      if (options.includeNotes && excerpt.note.trim().isNotEmpty) {
        top +=
            printText(
              excerpt.note,
              0,
              top,
              width: width,
              size: 13,
              height: 1.6,
              color: colors.muted,
              align: film ? TextAlign.center : TextAlign.left,
            ) +
            12;
      }
      final source = [
        if (options.hideBookTitles)
          '来源已隐藏'
        else if (_hasTitle(excerpt.title))
          '《${excerpt.title}》',
        if (!options.hideBookTitles && excerpt.chapter.trim().isNotEmpty)
          excerpt.chapter,
        if (_sfQuoteRecord(excerpt)?.createdAt case final at?)
          _analysisDate(at.localDateTime),
      ];
      if (source.isNotEmpty) {
        top +=
            printText(
              source.join(' · '),
              0,
              top,
              width: width,
              size: 12,
              color: colors.muted,
              align: film ? TextAlign.center : TextAlign.left,
            ) +
            19;
      }
    }
    final marks = data.analysis.marks;
    final counts = [
      if (marks.bookmarks > 0) '${marks.bookmarks}个书签',
      if (marks.excerpts > 0) '${marks.excerpts}条摘录',
    ];
    if (counts.isNotEmpty) {
      top +=
          printText(
            '本期记号 · ${counts.join(' / ')}',
            0,
            top,
            width: width,
            size: 12,
            color: colors.muted,
            align: film ? TextAlign.center : TextAlign.left,
          ) +
          9;
    } else if (data.bookmarks + data.underlines > 0) {
      top +=
          printText(
            '当前收藏 · ${[if (data.bookmarks > 0) '${data.bookmarks}个书签', if (data.underlines > 0) '${data.underlines}条划线'].join(' / ')}',
            0,
            top,
            width: width,
            size: 12,
            color: colors.muted,
            align: film ? TextAlign.center : TextAlign.left,
          ) +
          9;
    }
    return top;
  }

  void _sfFooter({bool film = false}) {
    rule(32, y, 536, color: colors.muted.withValues(alpha: .35));
    y += 20;
    y +=
        printText(
          film ? 'THE END' : '下一页，留给将来的自己。',
          32,
          y,
          width: 536,
          size: film ? 14 : 25,
          fixedTitle: !film,
          color: film ? colors.accent : colors.ink,
          align: film ? TextAlign.center : TextAlign.left,
          weight: FontWeight.w600,
        ) +
        20;
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
          align: film ? TextAlign.center : TextAlign.left,
        ) +
        22;
  }
}

/// A warm notebook: a year spread, seasonal landscapes, marginalia and book slips.
class _SeasonPosterComposer extends _ReferencePosterComposer
    with _SeasonFilmFacts {
  _SeasonPosterComposer(
    super.data,
    super.options,
    super.translate,
    super.components,
  );

  final _placedEvents = <String>{};

  Color _seasonColor(String season) =>
      options.palette != ReadingReportPalette.pine
      ? colors.accent
      : switch (season) {
          '春' => const Color(0xff6c9eaa),
          '夏' => const Color(0xff6c8870),
          '秋' => const Color(0xffb47c3e),
          _ => const Color(0xff8d819c),
        };

  @override
  ReadingReportLayout compose() {
    if (readingReportVisibleModules(data, options).isEmpty) {
      return super.compose();
    }
    final recorder = ui.PictureRecorder();
    canvas = Canvas(recorder);
    _paperGround();
    glyph(2, 32, 23, size: 22, color: colors.accent);
    printText(
      readingExportBrandName,
      64,
      21,
      width: 350,
      size: 15,
      weight: FontWeight.w600,
    );
    printText(
      'PERSONAL READING REPORT',
      64,
      45,
      width: 350,
      size: 10,
      color: colors.muted,
    );
    final years = data.dates.first.year == data.dates.last.year
        ? '${data.dates.first.year}'
        : '${data.dates.first.year} / ${data.dates.last.year}';
    final yearHeight = printText(
      years,
      32,
      91,
      width: 536,
      size: years.length == 4 ? 111 : 65,
      display: true,
      color: colors.accent,
      height: 1,
      weight: FontWeight.w700,
    );
    y = 91 + yearHeight + 15;
    y += imageTitle('阅读报告', 32, y, width: 536, size: 35) + 23;
    _illustration(
      readingReportHeroArt(data, options),
      Rect.fromLTWH(0, y, 600, 600 * 608 / 1080),
    );
    y += 600 * 608 / 1080 + 22;
    y = _identity(y);
    if (_hasReading) {
      printText('这本手帖的阅读时长', 32, y, width: 230, size: 12, color: colors.muted);
      y += 22 + _total(32, y + 22, 260, size: 58, color: colors.accent) + 18;
    }
    if (has(ReadingReportModule.days)) {
      final top = y;
      final days = math.max(data.activeDays, _activeDays);
      y +=
          printText(
            '$days个阅读日${data.analysis.longestStreak.days > 0 ? ' · 最长连续${data.analysis.longestStreak.days}天' : ''}',
            32,
            y,
            width: 536,
            size: 14,
            color: colors.muted,
          ) +
          17;
      registerSection(
        ReadingReportModule.days,
        Rect.fromLTWH(32, top, 536, y - top - 7),
      );
    }
    y += 17;
    final groups = <String, List<ReadingReportSeason>>{};
    for (final span in readingReportSeasons(data)) {
      groups.putIfAbsent(span.label, () => []).add(span);
    }
    if (has(ReadingReportModule.rhythm) ||
        has(ReadingReportModule.days) ||
        has(ReadingReportModule.progress)) {
      for (final group in groups.entries) {
        _seasonSpread(group.key, group.value);
      }
    }
    if (has(ReadingReportModule.progress)) {
      final unplaced = _sfEvents
          .where((event) => !_placedEvents.contains(event.key))
          .toList();
      if (unplaced.isNotEmpty) {
        emit(ReadingReportModule.progress, (width) {
          var top =
              printText(
                '页边记事',
                0,
                0,
                width: width,
                size: 21,
                fixedTitle: true,
              ) +
              14;
          return _at(top, width, (w) => _sfEventRows(unplaced, w), gap: 0);
        });
      }
    }
    if (has(ReadingReportModule.rhythm) &&
        (data.analysis.hourMilliseconds.any((value) => value > 0) ||
            data.analysis.longestSession != null)) {
      paintSurface(paperSurface, () {
        y += 26;
        emit(ReadingReportModule.rhythm, (width) {
          final top =
              printText(
                'MARGIN / 页边的日常',
                0,
                0,
                width: width,
                size: 12,
                color: colors.muted,
              ) +
              18;
          return _at(top, width, _timeSummary, gap: 0);
        });
      });
      y += 22;
    }
    emit(ReadingReportModule.calendar, _calendarContent, gap: 32);
    emit(ReadingReportModule.books, _bookSlips);
    if (has(ReadingReportModule.progress)) {
      emit(ReadingReportModule.progress, (width) => _sfPositions(width));
    }
    if (has(ReadingReportModule.excerpts)) {
      y += 12;
      emit(
        ReadingReportModule.excerpts,
        (width) {
          final top =
              printText(
                '留在折角的一句话',
                0,
                0,
                width: width,
                size: 15,
                color: colors.muted,
              ) +
              26;
          return _at(top, width, (w) => _sfQuotes(w), gap: 0);
        },
        x: 92,
        width: 448,
        gap: 35,
      );
    }
    emit(ReadingReportModule.collection, (width) => _sfInventory(width));
    y += 12;
    _sfFooter();
    return finishPlate(recorder, y + 12);
  }

  void _seasonSpread(String label, List<ReadingReportSeason> spans) {
    final accent = _seasonColor(label);
    final repeatOfCover =
        spans.first.asset == readingReportHeroArt(data, options);
    if (!repeatOfCover) {
      _illustration(
        spans.first.asset,
        Rect.fromLTWH(0, y, 600, 600 * 608 / 1080),
      );
      y += 600 * 608 / 1080 + 20;
    }
    final titleY = y;
    printText(
      label,
      32,
      y,
      width: 120,
      size: 45,
      fixedTitle: true,
      color: accent,
      height: 1,
    );
    final years = <int>{
      for (final span in spans) span.start.year,
      for (final span in spans) span.end.year,
    };
    printText(
      years.join(' / '),
      369,
      y + 13,
      width: 199,
      size: 13,
      color: colors.muted,
      align: TextAlign.right,
    );
    y += 64;
    if (has(ReadingReportModule.days)) {
      final top = y;
      y +=
          printText(
            spans
                .map(
                  (span) =>
                      '${_analysisDate(span.start)}—${_analysisDate(span.end)}',
                )
                .join('\n'),
            32,
            y,
            width: 536,
            size: 12.5,
            color: colors.muted,
          ) +
          15;
      registerSection(
        ReadingReportModule.days,
        Rect.fromLTWH(32, top, 536, y - top - 6),
      );
    }
    if (has(ReadingReportModule.rhythm)) {
      final top = y;
      final ms = spans.fold<int>(0, (sum, span) => sum + span.milliseconds);
      final figure = ms >= 1000
          ? readingReportDuration(ms ~/ 1000, observed: true)
          : null;
      final h = printText(
        figure?.value ?? '不足1秒',
        32,
        y,
        width: 164,
        size: figure == null ? 30 : 62,
        display: figure != null,
        color: accent,
        height: 1,
        weight: FontWeight.w700,
      );
      if (figure != null) {
        printText(
          '${figure.unit}${figure.remainder == null ? '' : ' ${figure.remainder} ${figure.remainderUnit}'}',
          32,
          y + h + 9,
          width: 164,
          size: 13,
          color: accent,
        );
      }
      final keys = <int>{
        for (final month in data.analysis.months)
          if (spans.any(
            (span) =>
                _sfMonthKey(month.date) >= _sfMonthKey(span.start) &&
                _sfMonthKey(month.date) <= _sfMonthKey(span.end),
          ))
            _sfMonthKey(month.date),
      };
      final months = data.analysis.months
          .where(
            (month) =>
                keys.contains(_sfMonthKey(month.date)) &&
                (month.totalSeconds != null || month.measuredMilliseconds > 0),
          )
          .toList();
      final maximum = data.analysis.months
          .map(_sfMonthMs)
          .fold<int>(0, math.max);
      var right = y + 3;
      for (final month in months) {
        printText(
          '${(month.date.year % 100).toString().padLeft(2, '0')}.${month.date.month.toString().padLeft(2, '0')}',
          224,
          right,
          width: 60,
          size: 12,
          color: colors.muted,
        );
        final value = _sfMonthMs(month);
        canvas.drawRect(
          Rect.fromLTWH(286, right + 7, 146, 4),
          Paint()..color = colors.muted.withValues(alpha: .12),
        );
        if (value > 0 && maximum > 0) {
          canvas.drawRect(
            Rect.fromLTWH(286, right + 7, 146 * value / maximum, 4),
            Paint()..color = accent,
          );
        }
        printText(
          _sfDuration(value),
          442,
          right,
          width: 126,
          size: 12,
          color: colors.ink,
          align: TextAlign.right,
        );
        right += 28;
      }
      y = math.max(y + h + 33, right + 4);
      registerSection(
        ReadingReportModule.rhythm,
        Rect.fromLTWH(32, top, 536, y - top),
      );
      y += 20;
    }
    if (has(ReadingReportModule.progress)) {
      final events = _sfEvents
          .where(
            (event) =>
                spans.any((span) => _sfWithin(event.at, span.start, span.end)),
          )
          .toList();
      if (events.isNotEmpty) {
        final top = y;
        y +=
            printText(
              '这一季的页边记事',
              32,
              y,
              width: 536,
              size: 14,
              weight: FontWeight.w600,
              color: accent,
            ) +
            12;
        canvas.save();
        canvas.translate(32, y);
        final height = _sfEventRows(events, 536);
        canvas.restore();
        y += height;
        registerSection(
          ReadingReportModule.progress,
          Rect.fromLTWH(32, top, 536, y - top),
        );
        _placedEvents.addAll(events.map((event) => event.key));
        y += 16;
      }
    }
    if (y == titleY + 64) y += 7;
    y += 28;
  }

  double _bookSlips(double width) {
    var top =
        printText('这一册里相伴的书', 0, 0, width: width, size: 25, fixedTitle: true) +
        22;
    final cell = (width - 28) / 2;
    for (var first = 0; first < _rankedBooks.length; first += 2) {
      var rowHeight = 0.0;
      for (
        var column = 0;
        column < 2 && first + column < _rankedBooks.length;
        column++
      ) {
        final index = first + column,
            book = _rankedBooks[index],
            x = column * (cell + 28);
        final title = _sfBookName(book);
        var height =
            printText(
              '${index + 1}'.padLeft(2, '0'),
              x,
              top,
              width: cell,
              size: 13,
              display: true,
              color: colors.accent,
            ) +
            18;
        if (title.isNotEmpty) {
          height +=
              printText(
                title,
                x,
                top + height,
                width: cell,
                size: 19,
                fixedTitle: true,
                height: 1.35,
              ) +
              10;
        }
        if (!options.hideAuthorNames &&
            readingReportHasAuthorText(book.book?.author)) {
          height +=
              printText(
                book.book!.author,
                x,
                top + height,
                width: cell,
                size: 12,
                color: colors.muted,
              ) +
              8;
        }
        final duration = _bookDuration(book);
        if (duration.isNotEmpty) {
          height +=
              printText(
                duration,
                x,
                top + height,
                width: cell,
                size: 13,
                color: colors.muted,
              ) +
              12;
        } else if (book.activeDates.isNotEmpty) {
          height +=
              printText(
                '${book.activeDates.length}个已记录阅读日',
                x,
                top + height,
                width: cell,
                size: 13,
                color: colors.muted,
              ) +
              12;
        }
        rule(x, top + height, cell, color: colors.accent.withValues(alpha: .4));
        rowHeight = math.max(rowHeight, height + 16);
      }
      top += rowHeight + 11;
    }
    return top +
        printText(
          '书目选录 ${_rankedBooks.length}/$_bookCount 本',
          0,
          top,
          width: width,
          size: 11.5,
          color: colors.muted,
        ) +
        6;
  }
}

class _SFCut {
  _SFCut(this.first, this.last);
  final DateTime first;
  DateTime last;
  int milliseconds = 0;
  bool observed = false;
  DateTime? moment;
}

class _SFAct {
  _SFAct({
    required this.index,
    required this.first,
    required this.last,
    required this.milliseconds,
    required this.moment,
    required this.events,
    required this.cuts,
    required this.readingDays,
  });
  final int index, milliseconds, readingDays;
  final DateTime first, last;
  final DateTime? moment;
  final List<_SFEvent> events;
  final List<_SFCut> cuts;
}

/// Film grammar owns its running order: slate, genuine acts, CUTs and credits.
class _FilmPosterComposer extends _ReferencePosterComposer
    with _SeasonFilmFacts {
  _FilmPosterComposer(
    super.data,
    super.options,
    super.translate,
    super.components,
  );

  List<_SFAct> _acts() {
    final ordinary = data.dates.length ~/ 3, extra = data.dates.length % 3;
    final result = <_SFAct>[];
    final event = data.analysis.latestReading;
    for (var index = 0; index < 3; index++) {
      final start = ordinary * index + math.min(index, extra).toInt();
      final end = start + ordinary + (index < extra ? 1 : 0);
      if (end <= start) continue;
      final first = data.dates[start], last = data.dates[end - 1];
      final moment = event != null && _sfWithin(event.at, first, last)
          ? event.at
          : null;
      var ms = data.seconds
          .sublist(start, end)
          .whereType<int>()
          .fold<int>(0, (sum, seconds) => sum + seconds * 1000);
      if (moment != null && data.analysis.weekHourMatrix.days == 1) {
        ms = math.max(ms, data.analysis.measuredMilliseconds);
      }
      final events = has(ReadingReportModule.progress)
          ? _sfEvents
                .where((event) => _sfWithin(event.at, first, last))
                .toList()
          : <_SFEvent>[];
      final cuts = <int, _SFCut>{};
      for (var i = start; i < end; i++) {
        final day = data.dates[i];
        final cut = cuts.putIfAbsent(_sfMonthKey(day), () => _SFCut(day, day));
        cut.last = day;
        if (data.seconds[i] case final seconds?) {
          cut.observed = true;
          cut.milliseconds += seconds * 1000;
        }
      }
      for (final cut in cuts.values) {
        final selectedMonthDates = data.dates
            .where((day) => _sfMonthKey(day) == _sfMonthKey(cut.first))
            .toList();
        final month = data.analysis.months
            .where((value) => _sfMonthKey(value.date) == _sfMonthKey(cut.first))
            .firstOrNull;
        if (month != null &&
            selectedMonthDates.isNotEmpty &&
            _sfDay(cut.first) == _sfDay(selectedMonthDates.first) &&
            _sfDay(cut.last) == _sfDay(selectedMonthDates.last)) {
          cut.milliseconds = math.max(cut.milliseconds, _sfMonthMs(month));
        } else if (cut.milliseconds == 0 &&
            month != null &&
            month.measuredMilliseconds > 0) {
          // The monthly detail cannot be allocated to this partial CUT. A
          // rounded day total of zero must not erase its possible subsecond read.
          cut.observed = false;
        }
        if (moment != null && _sfMonthKey(moment) == _sfMonthKey(cut.first)) {
          cut.moment = moment;
          if (data.analysis.weekHourMatrix.days == 1) {
            cut.milliseconds = math.max(
              cut.milliseconds,
              data.analysis.measuredMilliseconds,
            );
          }
        }
      }
      ms = math.max(
        ms,
        cuts.values.fold<int>(0, (sum, cut) => sum + cut.milliseconds),
      );
      if (ms <= 0 && moment == null && events.isEmpty) continue;
      result.add(
        _SFAct(
          index: index,
          first: first,
          last: last,
          milliseconds: ms,
          moment: moment,
          events: events,
          cuts: cuts.values.toList(),
          readingDays: data.seconds
              .sublist(start, end)
              .where((seconds) => (seconds ?? 0) > 0)
              .length,
        ),
      );
    }
    return result;
  }

  @override
  ReadingReportLayout compose() {
    if (readingReportVisibleModules(data, options).isEmpty) {
      return super.compose();
    }
    final recorder = ui.PictureRecorder();
    canvas = Canvas(recorder);
    _masthead();
    y = 92;
    _slate();
    y +=
        imageTitle('阅读报告', 32, y, width: 536, size: 49, color: colors.ink) + 17;
    y = _identity(y);
    if (_hasReading) {
      printText(
        'RUNNING TIME / 本期放映时长',
        32,
        y,
        width: 536,
        size: 12,
        color: colors.muted,
      );
      y += 23 + _total(32, y + 23, 536, size: 93, color: colors.accent) + 24;
    }
    final story =
        has(ReadingReportModule.rhythm) ||
        has(ReadingReportModule.days) ||
        has(ReadingReportModule.progress);
    final acts = story ? _acts() : <_SFAct>[];
    if (acts.isEmpty || acts.first.index != 0) {
      _illustration(
        readingReportHeroArt(data, options),
        Rect.fromLTWH(32, y, 536, 536 * 608 / 1080),
      );
      y += 536 * 608 / 1080 + 27;
    }
    final peak = acts
        .expand((act) => act.cuts)
        .map((cut) => cut.milliseconds)
        .fold<int>(0, math.max);
    for (final act in acts) {
      _act(act, peak);
    }
    if (has(ReadingReportModule.rhythm) &&
        (data.analysis.hourMilliseconds.any((value) => value > 0) ||
            data.analysis.longestSession != null)) {
      y += 13;
      emit(ReadingReportModule.rhythm, (width) {
        final top =
            printText(
              'EXPOSURE / 放映时刻',
              0,
              0,
              width: width,
              size: 12,
              color: colors.accent,
            ) +
            20;
        return _at(top, width, _timeSummary, gap: 0);
      });
      final lengths = data.analysis.sessionLengths;
      if (lengths.hasData) {
        emit(
          ReadingReportModule.rhythm,
          (width) {
            var top =
                printText(
                  'TAKE LENGTH / 完整单次',
                  0,
                  0,
                  width: width,
                  size: 14,
                  color: colors.accent,
                ) +
                15;
            for (final bucket in lengths.buckets) {
              printText(
                bucket.label,
                0,
                top,
                width: width * .55,
                size: 12.5,
                color: colors.muted,
              );
              final h = printText(
                '${bucket.count}次',
                width * .55,
                top,
                width: width * .45,
                size: 12.5,
                align: TextAlign.right,
                color: colors.ink,
              );
              top += h + 7;
            }
            return top;
          },
          x: 110,
          width: 380,
          gap: 31,
        );
      }
    }
    y += 11;
    printText(
      'END CREDITS',
      32,
      y,
      width: 536,
      size: 15,
      color: colors.accent,
      align: TextAlign.center,
      weight: FontWeight.w600,
    );
    y += 42;
    emit(ReadingReportModule.books, _credits, gap: 34);
    emit(
      ReadingReportModule.calendar,
      _calendarContent,
      x: 64,
      width: 472,
      gap: 34,
    );
    if (has(ReadingReportModule.excerpts)) {
      emit(
        ReadingReportModule.excerpts,
        (width) => _sfQuotes(width, film: true),
        x: 64,
        width: 472,
        gap: 36,
      );
    }
    emit(
      ReadingReportModule.progress,
      (width) => _sfPositions(width, film: true),
      x: 64,
      width: 472,
      gap: 28,
    );
    emit(
      ReadingReportModule.collection,
      (width) => _sfInventory(width, film: true),
      x: 84,
      width: 432,
      gap: 36,
    );
    y +=
        printText(
          '终',
          32,
          y,
          width: 536,
          size: 41,
          fixedTitle: true,
          align: TextAlign.center,
        ) +
        28;
    _sfFooter(film: true);
    _filmEdges(y);
    return finishPlate(recorder, y + 12);
  }

  void _slate() {
    final top = y;
    const cell = 536 / 3;
    final fields = [
      ('PRODUCTION', readingExportBrandName),
      ('RANGE', '${data.period}天'),
      ('DIRECTED BY', name),
    ];
    final bodyHeight = fields
        .map(
          (field) => printMeasure(
            field.$2,
            cell - 21,
            size: 14,
            weight: FontWeight.w600,
          ),
        )
        .fold<double>(0, math.max);
    final height = math.max(67.0, bodyHeight + 41);
    canvas.drawRect(
      Rect.fromLTWH(32, top, 536, height),
      Paint()..color = colors.ink.withValues(alpha: .055),
    );
    canvas.drawRect(
      Rect.fromLTWH(32, top, 536, height),
      Paint()
        ..color = colors.muted.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
    for (final (index, field) in fields.indexed) {
      final x = 43 + index * cell;
      printText(
        field.$1,
        x,
        top + 9,
        width: cell - 21,
        size: 9,
        color: colors.muted,
      );
      printText(
        field.$2,
        x,
        top + 29,
        width: cell - 21,
        size: 14,
        color: colors.ink,
        weight: FontWeight.w600,
      );
      if (index > 0) {
        canvas.drawLine(
          Offset(32 + index * cell, top),
          Offset(32 + index * cell, top + height),
          Paint()
            ..color = colors.muted.withValues(alpha: .55)
            ..strokeWidth = .8,
        );
      }
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(32, top + height + 7, 536, 10));
    for (var x = 17.0; x < 590; x += 29) {
      canvas.drawPath(
        Path()
          ..moveTo(x, top + height + 17)
          ..lineTo(x + 14, top + height + 7)
          ..lineTo(x + 29, top + height + 7)
          ..lineTo(x + 15, top + height + 17)
          ..close(),
        Paint()..color = colors.accent.withValues(alpha: .8),
      );
    }
    canvas.restore();
    y += height + 41;
  }

  void _act(_SFAct act, int maximum) {
    const names = ['相遇', '远行', '归来'];
    const scenes = ['char_pv_open', 'char_pv_train', 'char_pv_end'];
    final top = y;
    printText(
      '${act.index + 1}'.padLeft(2, '0'),
      32,
      y,
      width: 81,
      size: 54,
      fixedTitle: true,
      color: colors.accent,
      height: 1,
    );
    printText(
      '第${act.index + 1}幕 · ${names[act.index]}',
      120,
      y + 8,
      width: 275,
      size: 25,
      fixedTitle: true,
    );
    printText(
      'ACT ${act.index + 1}',
      122,
      y + 46,
      width: 250,
      size: 10,
      color: colors.muted,
    );
    if (has(ReadingReportModule.rhythm)) {
      final figure = act.milliseconds > 0
          ? _sfDuration(act.milliseconds)
          : act.moment == null
          ? ''
          : '${_analysisClock(act.moment!)} · 已记录时刻';
      if (figure.isNotEmpty) {
        printText(
          'RUNTIME',
          403,
          y + 9,
          width: 165,
          size: 9,
          color: colors.muted,
          align: TextAlign.right,
        );
        printText(
          figure,
          388,
          y + 31,
          width: 180,
          size: 16,
          color: colors.accent,
          align: TextAlign.right,
        );
        registerSection(
          ReadingReportModule.rhythm,
          Rect.fromLTWH(388, y + 8, 180, 53),
        );
      }
    }
    y = top + 77;
    if (has(ReadingReportModule.days)) {
      final dateTop = y;
      y +=
          printText(
            '${_analysisDate(act.first)}—${_analysisDate(act.last)}${act.readingDays > 0 ? ' · ${act.readingDays}个有时长的阅读日' : ''}',
            32,
            y,
            width: 536,
            size: 12,
            color: colors.muted,
          ) +
          12;
      registerSection(
        ReadingReportModule.days,
        Rect.fromLTWH(32, dateTop, 536, y - dateTop - 5),
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(26, y, 548, 536 * 608 / 1080 + 20),
      Paint()..color = const Color(0xff030405),
    );
    _illustration(
      scenes[act.index],
      Rect.fromLTWH(32, y + 10, 536, 536 * 608 / 1080),
    );
    y += 536 * 608 / 1080 + 29;
    if (has(ReadingReportModule.progress) && act.events.isNotEmpty) {
      final eventTop = y;
      printText(
        'SUBTITLES / 页间字幕',
        47,
        y,
        width: 506,
        size: 10,
        color: colors.accent,
      );
      y += 21;
      canvas.save();
      canvas.translate(47, y);
      final height = _sfEventRows(act.events, 506, centered: true);
      canvas.restore();
      y += height + 5;
      registerSection(
        ReadingReportModule.progress,
        Rect.fromLTWH(47, eventTop, 506, y - eventTop),
      );
      y += 15;
    }
    if (has(ReadingReportModule.rhythm)) {
      final cuts = act.cuts
          .where(
            (cut) => cut.observed || cut.moment != null || cut.milliseconds > 0,
          )
          .toList();
      if (cuts.isNotEmpty) {
        final cutTop = y;
        final columns = math.min(2, cuts.length);
        final cell = (536 - (columns - 1) * 18) / columns;
        for (var first = 0; first < cuts.length; first += columns) {
          var rowHeight = 0.0;
          for (
            var column = 0;
            column < columns && first + column < cuts.length;
            column++
          ) {
            final cut = cuts[first + column], x = 32 + column * (cell + 18);
            final peak = cut.milliseconds > 0 && cut.milliseconds == maximum;
            final frame = Rect.fromLTWH(x, y, cell, 101);
            canvas.drawRect(
              frame,
              Paint()..color = colors.ink.withValues(alpha: .04),
            );
            canvas.drawRect(
              frame,
              Paint()
                ..color = (peak ? colors.accent : colors.muted).withValues(
                  alpha: peak ? .8 : .25,
                )
                ..style = PaintingStyle.stroke
                ..strokeWidth = .8,
            );
            printText(
              peak
                  ? 'PEAK CUT'
                  : 'CUT ${(first + column + 1).toString().padLeft(2, '0')}',
              x + 11,
              y + 9,
              width: cell - 22,
              size: 10,
              color: peak ? colors.accent : colors.muted,
            );
            printText(
              '${cut.first.year}.${cut.first.month.toString().padLeft(2, '0')} · ${cut.first.day}—${cut.last.day}',
              x + 11,
              y + 29,
              width: cell - 22,
              size: 12,
              color: colors.muted,
            );
            final figure = cut.milliseconds > 0
                ? _sfDuration(cut.milliseconds)
                : cut.moment != null
                ? '${_analysisClock(cut.moment!)} · 已记录时刻'
                : '0秒';
            printText(
              figure,
              x + 11,
              y + 51,
              width: cell - 22,
              size: 18,
              color: colors.ink,
              weight: FontWeight.w600,
            );
            if (cut.milliseconds > 0 && maximum > 0) {
              canvas.drawRect(
                Rect.fromLTWH(
                  x + 11,
                  y + 86,
                  (cell - 22) * cut.milliseconds / maximum,
                  3,
                ),
                Paint()..color = colors.accent,
              );
            }
            rowHeight = 101;
          }
          y += rowHeight + 15;
        }
        registerSection(
          ReadingReportModule.rhythm,
          Rect.fromLTWH(32, cutTop, 536, y - cutTop - 5),
        );
      }
    }
    y += 29;
  }

  double _credits(double width) {
    var top =
        printText(
          '本期相伴书目',
          0,
          0,
          width: width,
          size: 20,
          fixedTitle: true,
          align: TextAlign.center,
        ) +
        27;
    for (final (index, book) in _rankedBooks.indexed) {
      final role = index == 0
          ? 'FEATURE'
          : 'BOOK ${(index + 1).toString().padLeft(2, '0')}';
      printText(
        role,
        0,
        top + 5,
        width: 116,
        size: 10,
        color: colors.muted,
        align: TextAlign.right,
      );
      final title = _sfBookName(book);
      var row = 0.0;
      if (title.isNotEmpty) {
        row +=
            printText(
              title,
              139,
              top,
              width: width - 139,
              size: index == 0 ? 25 : 19,
              fixedTitle: true,
              height: 1.3,
            ) +
            9;
      }
      final details = [
        if (!options.hideAuthorNames &&
            readingReportHasAuthorText(book.book?.author))
          book.book!.author,
        if (_bookDuration(book).isNotEmpty) _bookDuration(book),
        if (_bookDuration(book).isEmpty && book.activeDates.isNotEmpty)
          '${book.activeDates.length}个已记录阅读日',
      ];
      if (details.isNotEmpty) {
        row +=
            printText(
              details.join(' · '),
              139,
              top + row,
              width: width - 139,
              size: 12.5,
              color: colors.muted,
            ) +
            11;
      }
      top += math.max(row, 32) + 13;
    }
    return top +
        printText(
          '书目选录 ${_rankedBooks.length}/$_bookCount 本',
          0,
          top,
          width: width,
          size: 11.5,
          color: colors.muted,
          align: TextAlign.center,
        ) +
        8;
  }

  void _filmEdges(double height) {
    const strip = Color(0xff292b2f);
    canvas.drawRect(Rect.fromLTWH(0, 0, 18, height), Paint()..color = strip);
    canvas.drawRect(Rect.fromLTWH(582, 0, 18, height), Paint()..color = strip);
    for (var top = 8.0; top < height; top += 26) {
      for (final x in [4.0, 586.0]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, top, 10, 14),
            const Radius.circular(1.5),
          ),
          Paint()..color = colors.background,
        );
      }
    }
  }
}
