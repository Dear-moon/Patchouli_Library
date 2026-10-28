part of 'reading_report_layout.dart';

class _PaperCutPosterComposer extends _ReferencePosterComposer {
  _PaperCutPosterComposer(
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
    _cutHero();
    final paperTop = y;
    paintSurface(paperSurface, () {
      y += 31;
      y +=
          printText(range, 32, y, width: 536, size: 12, color: colors.muted) +
          14;
      if (options.note.trim().isNotEmpty) {
        y +=
            printText(
              options.note.trim(),
              32,
              y,
              width: 536,
              size: 16,
              height: 1.5,
            ) +
            25;
      }
      _numberCutouts();
      emit(ReadingReportModule.calendar, _calendarContent, gap: 34);
      emit(ReadingReportModule.excerpts, _paperQuote, gap: 36);
      emit(ReadingReportModule.books, _bookIndex, gap: 32);
      emit(ReadingReportModule.progress, _pageSlips, gap: 30);
      emit(ReadingReportModule.collection, _shelfStamp, gap: 22);
      y += 25;
    });
    _tornEdge(paperTop, paperSurface.background, below: true);
    final darkTop = y;
    _tornEdge(darkTop, paperSurface.background, below: false);
    y += 39;
    emit(ReadingReportModule.rhythm, _nightStrips, gap: 20);
    _birdCity();
    y += 26;
    rule(32, y, 536, color: colors.muted.withValues(alpha: .4));
    y += 20;
    y +=
        printText(
          options.signature ? '$readingExportBrandName / WENKU8' : name,
          32,
          y,
          width: 536,
          size: 14,
          weight: FontWeight.w600,
          color: colors.ink,
        ) +
        12;
    return finishPlate(recorder, y + 20);
  }

  void _cutHero() {
    final height = _hasReading ? 720.0 : 650.0;
    _illustration(
      'char_papercut',
      Rect.fromLTWH(0, 0, 600, height),
      alignment: Alignment.topCenter,
    );
    glyph(2, 32, 25, size: 23, color: colors.ink);
    final titleHeight = imageTitle(
      '阅读报告',
      69,
      20,
      width: 345,
      size: 23,
      color: colors.ink,
    );
    final captionTop = 26 + titleHeight;
    printText(
      '$readingExportBrandName · PERSONAL REPORT',
      69,
      captionTop,
      width: 360,
      size: 10.5,
      color: colors.muted,
    );
    printText(
      '${data.today.year}',
      471,
      25,
      width: 97,
      size: 24,
      display: true,
      align: TextAlign.right,
    );
    final nameTop = math.max(100.0, captionTop + 34);
    printText(
      name,
      32,
      nameTop,
      width: 235,
      size: 13,
      weight: FontWeight.w600,
      color: colors.muted,
    );
    if (_hasReading) {
      _total(25, nameTop + 24, 272, size: 134, color: colors.ink);
    }
    y = height;
  }

  void _tornEdge(double at, Color paper, {required bool below}) {
    final path = Path();
    if (below) {
      path.moveTo(0, at + 17);
      path.lineTo(0, at - 4);
      for (var x = 0.0; x <= 600; x += 17) {
        path.lineTo(
          x,
          at +
              ((x ~/ 17) % 3 == 0
                  ? -9
                  : (x ~/ 17).isEven
                  ? 3
                  : -3),
        );
      }
      path.lineTo(600, at + 17);
    } else {
      path.moveTo(0, at - 17);
      path.lineTo(600, at - 17);
      for (var x = 600.0; x >= 0; x -= 18) {
        path.lineTo(x, at + ((x ~/ 18).isEven ? 9 : -3));
      }
    }
    canvas.drawPath(path..close(), Paint()..color = paper);
  }

  void _numberCutouts() {
    final a = data.analysis;
    final markCount = a.marks.items.isNotEmpty
        ? a.marks.items.length
        : data.bookmarks + data.underlines;
    final facts =
        <
          ({
            String label,
            String value,
            String detail,
            ReadingReportModule module,
          })
        >[
          if (has(ReadingReportModule.days))
            (
              label: 'DAYS / 阅读日',
              value: '${math.max(data.activeDays, _activeDays)}',
              detail: '有阅读记录的日子',
              module: ReadingReportModule.days,
            ),
          if (has(ReadingReportModule.days) && a.longestStreak.days > 0)
            (
              label: 'STREAK / 连续',
              value: '${a.longestStreak.days}',
              detail:
                  '${_analysisDate(a.longestStreak.start!)}—${_analysisDate(a.longestStreak.end!)}',
              module: ReadingReportModule.days,
            ),
          if (has(ReadingReportModule.books))
            (
              label: 'BOOKS / 相伴',
              value: '$_bookCount',
              detail: '本期实际读过的书',
              module: ReadingReportModule.books,
            ),
          if (has(ReadingReportModule.excerpts) && markCount > 0)
            (
              label: 'MARKS / 页边记号',
              value: '$markCount',
              detail: a.marks.items.isNotEmpty ? '本期留下的记号' : '当前保存的记号',
              module: ReadingReportModule.excerpts,
            ),
          if (has(ReadingReportModule.rhythm) && a.nightRatio != null)
            (
              label: 'NIGHT / 夜读',
              value: '${(a.nightRatio! * 100).toStringAsFixed(1)}%',
              detail: '22:00–06:00 · 已测时段',
              module: ReadingReportModule.rhythm,
            ),
          if (has(ReadingReportModule.rhythm) && a.latestReading != null)
            (
              label: 'LATEST / 最晚',
              value: _analysisClock(a.latestReading!.at),
              detail: _analysisDate(a.latestReading!.at),
              module: ReadingReportModule.rhythm,
            ),
        ];
    if (facts.length < 6 &&
        has(ReadingReportModule.progress) &&
        a.firstOpenedBooks.isNotEmpty) {
      facts.add((
        label: 'FIRST / 初见',
        value: '${a.firstOpenedBooks.length}',
        detail: '本期首次已记录翻开',
        module: ReadingReportModule.progress,
      ));
    }
    if (facts.length < 6 &&
        has(ReadingReportModule.collection) &&
        data.onlineBooks + data.localBooks > 0) {
      facts.add((
        label: 'SHELF / 现在',
        value: '${data.onlineBooks + data.localBooks}',
        detail: '${_analysisDate(a.snapshotAt)} 藏书快照',
        module: ReadingReportModule.collection,
      ));
    }
    if (facts.isEmpty) return;
    printText(
      '01',
      32,
      y,
      width: 43,
      size: 29,
      display: true,
      weight: FontWeight.w700,
    );
    y +=
        printText(
          '剪下来的数字',
          85,
          y,
          width: 483,
          size: 27,
          weight: FontWeight.w700,
        ) +
        12;
    y +=
        printText(
          'CUT-OUTS / MEASURED MOMENTS',
          32,
          y,
          width: 536,
          size: 10,
          color: colors.muted,
        ) +
        19;
    final columns = facts.length == 1 ? 1 : 2;
    final width = (536 - (columns - 1) * 20) / columns;
    for (final (i, fact) in facts.indexed) {
      final row = i ~/ columns;
      final centeredLast =
          facts.length.isOdd && i == facts.length - 1 && columns == 2;
      final x = centeredLast
          ? (600 - width) / 2
          : 32 + (i % columns) * (width + 20);
      final top = y + row * 140;
      _cutout(
        fact.label,
        fact.value,
        fact.detail,
        Rect.fromLTWH(x, top, width, 120),
        i,
      );
      registerSection(
        fact.module,
        Rect.fromLTWH(x - 6, top - 6, width + 14, 136),
      );
    }
    y += ((facts.length + columns - 1) ~/ columns) * 140 + 37;
  }

  void _cutout(
    String label,
    String value,
    String detail,
    Rect bounds,
    int index,
  ) {
    canvas.save();
    canvas.translate(bounds.center.dx, bounds.center.dy);
    canvas.rotate((index.isEven ? -.55 : .45) * math.pi / 180);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);
    canvas.drawRect(
      bounds.shift(const Offset(4, 5)),
      Paint()..color = colors.ink.withValues(alpha: .25),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..color = index.isOdd ? const Color(0xffaeb7ad) : colors.background,
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..color = colors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9,
    );
    printText(
      label,
      bounds.left + 14,
      bounds.top + 11,
      width: bounds.width - 28,
      size: 10,
      color: const Color(0xff5d685f),
    );
    printText(
      value,
      bounds.left + 11,
      bounds.top + 31,
      width: bounds.width - 24,
      size: value.length > 5 ? 44 : 47,
      display: true,
      weight: FontWeight.w700,
      height: 1,
    );
    printText(
      detail,
      bounds.left + 16,
      bounds.bottom - 27,
      width: bounds.width - 29,
      size: 10.5,
      color: const Color(0xff5d685f),
      height: 1.2,
    );
    canvas.restore();
  }

  StatisticsMarkRecord? _quoteRecord(StatisticsExcerpt excerpt) {
    final matches = data.analysis.marks.items
        .where(
          (mark) =>
              mark.quote.trim() == excerpt.quote &&
              mark.title == excerpt.title &&
              mark.chapter == excerpt.chapter,
        )
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  double _paperQuote(double width) {
    final quotes = data.excerpts
        .where((entry) => entry.quote.trim().isNotEmpty)
        .take(2)
        .toList();
    if (quotes.isEmpty) return 0;
    var top =
        printText(
          'A LINE TO KEEP / 留在页边',
          0,
          0,
          width: width,
          size: 10,
          color: colors.muted,
        ) +
        20;
    for (final (i, excerpt) in quotes.indexed) {
      if (i == 0) {
        printText(
          '“',
          0,
          top - 5,
          width: 80,
          size: 87,
          fixedTitle: true,
          height: .8,
        );
        top += 54;
      }
      top +=
          printText(
            excerpt.quote,
            0,
            top,
            width: width,
            size: i == 0 ? 32 : 20,
            fixedTitle: true,
            weight: i == 0 ? FontWeight.w600 : FontWeight.normal,
            height: 1.6,
          ) +
          22;
      if (options.includeNotes && excerpt.note.isNotEmpty) {
        top +=
            printText(
              excerpt.note,
              0,
              top,
              width: width,
              size: 13,
              height: 1.5,
              color: colors.muted,
            ) +
            14;
      }
      rule(0, top, width, color: colors.muted.withValues(alpha: .6));
      top += 12;
      final source = [
        if (options.hideBookTitles)
          '来源已隐藏'
        else if (_hasTitle(excerpt.title))
          '《${excerpt.title}》',
        if (!options.hideBookTitles && excerpt.chapter.trim().isNotEmpty)
          excerpt.chapter,
      ];
      final record = _quoteRecord(excerpt);
      final sourceHeight = source.isEmpty
          ? 0.0
          : printText(
              source.join(' · '),
              0,
              top,
              width: width * .64 - 18,
              size: 12,
              color: colors.muted,
              height: 1.5,
            );
      final dateHeight = record?.createdAt == null
          ? 0.0
          : printText(
              '记于 ${_analysisDate(record!.createdAt!.localDateTime)}',
              width * .64,
              top,
              width: width * .36,
              size: 12,
              color: colors.muted,
              align: TextAlign.right,
            );
      top += math.max(sourceHeight, dateHeight) + 35;
    }
    return top;
  }

  double _bookIndex(double width) {
    final books = _rankedBooks;
    if (books.isEmpty) return 0;
    var top =
        printText(
          'BOOK INDEX / 相伴书目',
          0,
          0,
          width: width,
          size: 11,
          color: colors.muted,
        ) +
        17;
    rule(0, top, width, color: colors.ink.withValues(alpha: .7));
    top += 17;
    final column = (width - 30) / 2;
    final first = books.first;
    var left =
        top +
        printText(
          '01',
          0,
          top,
          width: column,
          size: 45,
          display: true,
          weight: FontWeight.w700,
        ) +
        10;
    if (_hasTitle(first.title) || options.hideBookTitles) {
      left +=
          printText(
            _analysisTitle(first.title, 0),
            0,
            left,
            width: column,
            size: 23,
            weight: FontWeight.w600,
            height: 1.4,
          ) +
          9;
    }
    if (!options.hideAuthorNames &&
        readingReportHasAuthorText(first.book?.author)) {
      left +=
          printText(
            first.book!.author,
            0,
            left,
            width: column,
            size: 12,
            color: colors.muted,
          ) +
          7;
    }
    if (_bookDuration(first).isNotEmpty) {
      left +=
          printText(
            _bookDuration(first),
            0,
            left,
            width: column,
            size: 13,
            color: colors.muted,
          ) +
          10;
    }
    var right = top;
    for (final (i, book) in books.skip(1).indexed) {
      right +=
          printText(
            '${(i + 2).toString().padLeft(2, '0')}  ${_hasTitle(book.title) || options.hideBookTitles ? _analysisTitle(book.title, i + 1) : ''}',
            column + 30,
            right,
            width: column,
            size: 15,
            height: 1.35,
          ) +
          5;
      if (_bookDuration(book).isNotEmpty) {
        right +=
            printText(
              _bookDuration(book),
              column + 30,
              right,
              width: column,
              size: 11.5,
              color: colors.muted,
            ) +
            13;
      }
    }
    top = math.max(left, right) + 13;
    final distribution = data.analysis.bookDayDistribution;
    if (distribution.hasData) {
      top +=
          printText(
            distribution.buckets
                .map((bucket) => '${bucket.label} ${bucket.days}天')
                .join(' / '),
            0,
            top,
            width: width,
            size: 11.5,
            color: colors.muted,
          ) +
          15;
    }
    top +=
        printText(
          '本期书单 ${books.length}/$_bookCount 本',
          0,
          top,
          width: width,
          size: 11,
          color: colors.muted,
        ) +
        12;
    return top;
  }

  double _pageSlips(double width) {
    var top =
        printText(
          'PAGES / 纸页上的足迹',
          0,
          0,
          width: width,
          size: 11,
          color: colors.muted,
        ) +
        15;
    rule(0, top, width, color: colors.muted.withValues(alpha: .6));
    top += 15;
    final bands = data.progressBands;
    if (bands.any((count) => count > 0)) {
      final cell = (width - 24) / 4;
      for (var i = 0; i < 4; i++) {
        final x = i * (cell + 8);
        canvas.drawRect(
          Rect.fromLTWH(x, top, cell, 69),
          Paint()..color = colors.ink.withValues(alpha: .07),
        );
        printText(
          '${bands[i]}',
          x + 8,
          top + 6,
          width: cell - 16,
          size: 27,
          display: true,
          weight: FontWeight.w600,
        );
        printText(
          ['0–25%', '25–50%', '50–75%', '75–100%'][i],
          x + 8,
          top + 44,
          width: cell - 16,
          size: 11,
          color: colors.muted,
        );
      }
      top += 80;
      top +=
          printText(
            '${_analysisDate(data.analysis.snapshotAt)} 阅读位置快照',
            0,
            top,
            width: width,
            size: 11,
            color: colors.muted,
          ) +
          17;
    }
    return _at(
      top,
      width,
      (w) => _progressContent(w, heading: false, positions: false),
      gap: 0,
    );
  }

  double _shelfStamp(double width) {
    var top =
        printText(
          'THE SHELF NOW / 此刻的书架',
          0,
          0,
          width: width,
          size: 11,
          color: colors.muted,
        ) +
        15;
    rule(0, top, width, color: colors.muted.withValues(alpha: .6));
    top += 15;
    return _at(
      top,
      width,
      (w) => _collectionContent(w, heading: false),
      gap: 0,
    );
  }

  double _nightStrips(double width) {
    var top = 0.0;
    final months = data.analysis.months;
    final values = [
      for (final month in months)
        math.max((month.totalSeconds ?? 0) * 1000, month.measuredMilliseconds),
    ];
    final maximum = values.fold<int>(0, math.max);
    if (maximum > 0) {
      printText(
        '02',
        0,
        top,
        width: 43,
        size: 29,
        display: true,
        weight: FontWeight.w700,
      );
      top +=
          printText(
            '${months.length}张时间纸条',
            53,
            top,
            width: width - 53,
            size: 29,
            weight: FontWeight.w700,
          ) +
          11;
      top +=
          printText(
            'STRIPS / MONTHS IN THIS PERIOD',
            0,
            top,
            width: width,
            size: 10,
            color: colors.muted,
          ) +
          18;
      const plot = 162.0;
      final step = width / months.length;
      final peak = values.indexOf(maximum);
      for (final (i, month) in months.indexed) {
        final value = values[i];
        final h = plot * value / maximum;
        final bar = math.min(34.0, step * .68);
        if (value > 0) {
          canvas.drawRect(
            Rect.fromLTWH(i * step + (step - bar) / 2, top + plot - h, bar, h),
            Paint()
              ..color = colors.ink.withValues(
                alpha: i == peak ? 1 : .22 + .09 * (i % 3),
              ),
          );
        }
        printText(
          '${month.date.month}',
          i * step,
          top + plot + 8,
          width: step,
          size: 12,
          color: colors.muted,
          align: TextAlign.center,
        );
      }
      top += plot + 35;
      canvas.drawRect(
        Rect.fromLTWH(0, top, 3, 37),
        Paint()..color = colors.ink,
      );
      top +=
          printText(
            '本期阅读最多：${_analysisDate(months[peak].date).substring(0, 7)} · ${_dimensionDuration(maximum)}',
            13,
            top + 5,
            width: width - 13,
            size: 14,
            color: colors.ink,
          ) +
          34;
    }
    final hasHours = data.analysis.hourMilliseconds.any((ms) => ms > 0);
    final hasSessions = data.analysis.sessionLengths.hasData;
    if (hasHours || hasSessions) {
      top += 17;
      rule(0, top, width, color: colors.muted.withValues(alpha: .35));
      top += 24;
      final column = (width - 30) / 2;
      if (hasHours) {
        printText(
          '一天里的阅读时刻',
          0,
          top,
          width: column,
          size: 17,
          weight: FontWeight.w600,
        );
        _analysisPlot(
          ReadingAnalysisChartKind.radial,
          [
            for (var hour = 0; hour < 24; hour++)
              ReadingAnalysisDatum(
                '$hour时',
                data.analysis.hourMilliseconds[hour] / 3600000,
              ),
          ],
          top + 32,
          column,
          height: 236,
          dark: true,
        );
      }
      var sessionHeight = 0.0;
      if (hasSessions) {
        canvas.save();
        canvas.translate(hasHours ? column + 30 : 0, top);
        sessionHeight = printSessionLengths(
          hasHours ? column : width,
          dark: true,
        );
        canvas.restore();
      }
      top += math.max(hasHours ? 278.0 : 0.0, sessionHeight) + 20;
    }
    return top;
  }

  void _birdCity() {
    final image = components?.illustration('char_birds');
    final height = image == null ? 337.8 : 600.0 * image.height / image.width;
    _illustration('char_birds', Rect.fromLTWH(0, y, 600, height));
    printText(
      'TO BE CONTINUED',
      344,
      y + 39,
      width: 224,
      size: 10,
      color: colors.muted,
      align: TextAlign.right,
    );
    printText(
      '把读过的，\n折成纸鸟带走。',
      332,
      y + 64,
      width: 236,
      size: 29,
      fixedTitle: true,
      weight: FontWeight.w600,
      height: 1.45,
      align: TextAlign.right,
    );
    y += height;
  }
}
