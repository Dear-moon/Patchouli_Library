part of 'reading_report_layout.dart';

/// Image-led print primitives. Charts remain captures of the shared app widgets.
abstract class _ReportPrintComposer extends _ReportPlateComposer {
  _ReportPrintComposer(
    super.data,
    super.options,
    super.translate,
    super.components,
  );
  final paper = const Color(0xfff1eee5), black = const Color(0xff161918);
  double printText(
    String value,
    double x,
    double top, {
    double width = 536,
    double size = 14,
    double height = 1.4,
    FontWeight weight = FontWeight.normal,
    Color? color,
    bool display = false,
    bool fixedTitle = false,
    bool measure = false,
    TextAlign align = TextAlign.left,
  }) {
    final text = translate(value);
    if (!measure) labels.add(text);
    final numeric = display && RegExp(r'^(?:\d+(?:\.\d+)?|—)$').hasMatch(text);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: display
              ? 'ReadingDisplay'
              : fixedTitle
              ? 'ReadingSerifDisplay'
              : (components?.serifFamily ?? 'CupertinoSystemText'),
          fontFamilyFallback: const ['CupertinoSystemText'],
          fontWeight: fixedTitle ? FontWeight.w700 : weight,
          fontSize: size,
          height: height,
          color: color ?? colors.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: numeric ? 1 : null,
    )..layout(minWidth: align == TextAlign.left ? 0 : width, maxWidth: width);
    try {
      if (numeric && painter.maxIntrinsicWidth > width) {
        final span = painter.text! as TextSpan;
        painter.text = TextSpan(
          text: text,
          style: span.style!.copyWith(
            fontSize: size * width / painter.maxIntrinsicWidth * .98,
          ),
        );
        painter.layout(
          minWidth: align == TextAlign.left ? 0 : width,
          maxWidth: width,
        );
      }
      if (!measure) painter.paint(canvas, Offset(x, top));
      return painter.height;
    } finally {
      painter.dispose();
    }
  }

  double printMeasure(
    String value,
    double width, {
    double size = 14,
    double height = 1.4,
    bool display = false,
    bool fixedTitle = false,
    FontWeight weight = FontWeight.normal,
  }) => printText(
    value,
    0,
    0,
    width: width,
    size: size,
    height: height,
    display: display,
    fixedTitle: fixedTitle,
    weight: weight,
    measure: true,
  );

  void artPrint(
    Rect rect, {
    Alignment alignment = Alignment.center,
    double shade = 0,
  }) {
    final image = components?.art;
    if (image == null) {
      if (components != null) throw const FormatException('主题插画尚未准备完成，请重新打开预览');
      canvas.drawRect(rect, Paint()..color = colors.ink);
      return;
    }
    final sourceSize = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, sourceSize, rect.size);
    final source = alignment.inscribe(fitted.source, Offset.zero & sourceSize);
    canvas.drawImageRect(
      image,
      source,
      rect,
      Paint()..filterQuality = FilterQuality.high,
    );
    if (shade > 0) {
      canvas.drawRect(rect, Paint()..color = black.withValues(alpha: shade));
    }
  }

  void horizontalShade(
    Rect rect, {
    Color color = const Color(0xff161918),
    double opacity = .90,
  }) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: opacity * .5),
            color.withValues(alpha: 0),
          ],
          stops: const [0, .64, 1],
        ).createShader(rect),
    );
  }

  double printHead(
    ReadingReportModule module,
    double width, {
    bool dark = false,
    String? english,
  }) {
    final index = '${module.index + 1}'.padLeft(2, '0');
    final ink = dark ? paper : colors.ink;
    switch (options.template) {
      case ReadingReportTemplate.archive:
      case ReadingReportTemplate.signal:
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 35, 38),
          Paint()..color = colors.accent,
        );
        printText(
          index,
          4,
          2,
          width: 27,
          size: 28,
          display: true,
          weight: FontWeight.w700,
          color: paper,
          height: 1,
        );
        final h = printText(
          module.label,
          47,
          6,
          width: width - 47,
          size: 23,
          weight: FontWeight.w600,
          color: ink,
          height: 1.25,
        );
        return math.max(38, h + 8) + 18;
      case ReadingReportTemplate.editorial:
        printText(
          index,
          0,
          0,
          width: 36,
          size: 39,
          display: true,
          color: colors.accent,
          height: 1,
        );
        return printText(
              module.label,
              47,
              7,
              width: width - 47,
              size: 26,
              fixedTitle: true,
              color: ink,
              height: 1.25,
            ) +
            29;
      case ReadingReportTemplate.shelf:
        canvas.drawLine(
          Offset.zero,
          Offset(width, 0),
          Paint()
            ..color = colors.accent
            ..strokeWidth = 2,
        );
        printText(
          index,
          width - 30,
          11,
          width: 30,
          size: 12,
          display: true,
          color: colors.accent,
        );
        return 12 +
            printText(
              module.label,
              0,
              12,
              width: width - 36,
              size: 23,
              weight: FontWeight.w600,
              color: ink,
            ) +
            16;
      case ReadingReportTemplate.constellation:
        printText(
          '$index / ${english ?? module.name.toUpperCase()}',
          0,
          0,
          width: width,
          size: 10,
          display: true,
          color: colors.accent,
        );
        return 19 +
            printText(
              module.label,
              0,
              19,
              width: width,
              size: 24,
              color: ink,
              height: 1.25,
              weight: FontWeight.w600,
            ) +
            17;
      case ReadingReportTemplate.score:
        printText(
          index,
          0,
          0,
          width: 37,
          size: 36,
          display: true,
          color: ink,
          weight: FontWeight.w700,
          height: 1,
        );
        canvas.drawLine(
          const Offset(42, 2),
          const Offset(42, 36),
          Paint()
            ..color = colors.accent
            ..strokeWidth = 1,
        );
        return 6 +
            printText(
              module.label,
              54,
              6,
              width: width - 54,
              size: 22,
              fixedTitle: true,
              color: ink,
            ) +
            18;
      case ReadingReportTemplate.ink:
        printText(
          index,
          width - 24,
          4,
          width: 24,
          size: 12,
          display: true,
          color: colors.accent,
        );
        return printText(
              module.label,
              0,
              0,
              width: width - 30,
              size: 24,
              fixedTitle: true,
              color: ink,
            ) +
            18;
      case ReadingReportTemplate.festival:
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 28, 28),
          Paint()..color = colors.accent,
        );
        printText(
          index,
          3,
          2,
          width: 22,
          size: 20,
          display: true,
          weight: FontWeight.w700,
          color: paper,
          height: 1,
        );
        return 1 +
            printText(
              module.label,
              39,
              0,
              width: width - 39,
              size: 25,
              weight: FontWeight.w600,
              color: ink,
            ) +
            18;
    }
  }

  String get durationUnitLine => !duration.observed
      ? '尚未记录'
      : '${duration.unit}${duration.remainder == null ? '' : ' ${duration.remainder} ${duration.remainderUnit}'}';

  double imageTitle(
    String fallback,
    double x,
    double top, {
    double width = 268,
    double size = 38,
    Color? color,
    TextAlign align = TextAlign.left,
    bool measure = false,
  }) {
    final custom = options.title.trim().isNotEmpty && title != '我的阅读档案';
    return printText(
      custom ? title : fallback,
      x,
      top,
      width: width,
      size: custom ? math.min(32, size * .8) : size,
      fixedTitle: !custom && theme.prefersSerif,
      weight: FontWeight.w600,
      color: color,
      height: 1.35,
      align: align,
      measure: measure,
    );
  }

  double imageDuration(
    double x,
    double top, {
    double width = 268,
    double size = 100,
    Color? color,
    TextAlign align = TextAlign.left,
    bool measure = false,
  }) {
    final h = printText(
      duration.value,
      x,
      top,
      width: width,
      size: duration.value.length > 4 ? size * .8 : size,
      display: true,
      weight: FontWeight.w700,
      height: 1,
      color: color,
      align: align,
      measure: measure,
    );
    return h +
        7 +
        printText(
          durationUnitLine,
          x,
          top + h + 7,
          width: width,
          size: 14,
          color: color,
          align: align,
          measure: measure,
        );
  }

  double imageIdentity(
    double top, {
    double x = 32,
    double width = 536,
    bool dark = false,
    TextAlign align = TextAlign.left,
    bool measure = false,
  }) {
    final ink = dark ? paper : colors.ink,
        muted = dark ? paper.withValues(alpha: .7) : colors.muted;
    var cursor =
        top +
        printText(
          name,
          x,
          top,
          width: width,
          size: 14,
          weight: FontWeight.w600,
          color: ink,
          align: align,
          measure: measure,
        ) +
        9;
    cursor +=
        printText(
          range,
          x,
          cursor,
          width: width,
          size: 10.5,
          color: muted,
          align: align,
          measure: measure,
        ) +
        9;
    if (options.note.trim().isNotEmpty) {
      cursor +=
          printText(
            options.note.trim(),
            x,
            cursor,
            width: width,
            size: 13,
            height: 1.6,
            color: muted,
            align: align,
            measure: measure,
          ) +
          8;
    }
    return cursor;
  }

  double printCalendar(double width, {bool dark = false}) {
    var top = printHead(ReadingReportModule.calendar, width, dark: dark);
    for (final image in components?.calendars ?? const <ui.Image>[]) {
      final h = image.height * width / image.width;
      _image(image, 0, top, width: width, height: h);
      top += h + 10;
    }
    final muted = dark ? paper.withValues(alpha: .6) : colors.muted;
    top +=
        printText(
          '${data.activeDays} 天活跃 / ${data.observedDays} 天有记录',
          0,
          top,
          width: width,
          size: 11,
          color: muted,
        ) +
        8;
    return top +
        printText(
          '空心 尚未记录 · 浅色 0 · 深色 阅读较久',
          0,
          top,
          width: width,
          size: 10,
          color: muted,
        ) +
        4;
  }

  double printRhythm(
    double width, {
    double chartHeight = 146,
    bool withFacts = true,
    String? statement,
  }) {
    var top = printHead(ReadingReportModule.rhythm, width);
    top +=
        printText(
          '月度时长 · 小时',
          0,
          top,
          width: width,
          size: 10,
          display: true,
          color: colors.muted,
        ) +
        10;
    _image(components?.monthly, 0, top, width: width, height: chartHeight);
    top += chartHeight + 20;
    if (statement != null) {
      canvas.drawLine(
        Offset(0, top),
        Offset(width, top),
        Paint()
          ..color = colors.ink.withValues(alpha: .5)
          ..strokeWidth = .65,
      );
      top +=
          18 +
          printText(
            statement,
            0,
            top + 18,
            width: width,
            size: 20,
            fixedTitle: true,
            height: 1.6,
          ) +
          14;
    }
    if (withFacts) {
      top +=
          printText(
            '已记录日均 ${data.observedDays == 0 ? '—' : statisticsDuration(data.averageSeconds)}',
            0,
            top,
            width: width,
            size: 13,
          ) +
          8;
      top +=
          printText(
            '最长连续 ${data.longestStreak} 天 · 全部记录',
            0,
            top,
            width: width,
            size: 12,
            color: colors.muted,
          ) +
          8;
    }
    return top;
  }

  double printBooks(
    double width, {
    bool dark = false,
    bool covers = true,
    double coverWidth = 32,
  }) {
    final ink = dark ? paper : colors.ink,
        muted = dark ? paper.withValues(alpha: .5) : colors.muted;
    var top = printHead(
      ReadingReportModule.books,
      width,
      dark: dark,
      english: 'COMPANIONS',
    );
    final books = data.booksByReadingDays.take(options.bookLimit).toList();
    if (books.isEmpty) {
      return top +
          printText('尚未留下相伴书目。', 0, top, width: width, size: 14, color: muted) +
          24;
    }
    for (var i = 0; i < books.length; i++) {
      final book = books[i];
      final image = covers ? components?.bookCovers.elementAtOrNull(i) : null;
      final numberWidth = 23.0, inset = image == null ? 29.0 : coverWidth + 13;
      final textX = numberWidth + inset;
      printText(
        '${i + 1}'.padLeft(2, '0'),
        0,
        top,
        width: 23,
        size: 18,
        display: true,
        weight: FontWeight.w700,
        color: colors.accent,
        height: 1.1,
      );
      if (image != null) {
        _image(
          image,
          numberWidth,
          top,
          width: coverWidth,
          height: coverWidth * 1.41,
        );
      }
      final textWidth = width - textX - 41;
      var row =
          top +
          printText(
            _bookTitle(book, i),
            textX,
            top,
            width: textWidth,
            size: 14,
            color: ink,
            weight: FontWeight.w500,
            height: 1.4,
          ) +
          5;
      if (!options.hideAuthorNames && book.author?.trim().isNotEmpty == true) {
        row +=
            printText(
              book.author!,
              textX,
              row,
              width: textWidth,
              size: 10.5,
              color: muted,
            ) +
            5;
      }
      printText(
        '${book.days}',
        width - 37,
        top - 1,
        width: 37,
        size: 25,
        display: true,
        color: ink,
        height: 1.1,
      );
      row = math.max(row, top + (image == null ? 38 : coverWidth * 1.41));
      canvas.drawLine(
        Offset(textX, row + 7),
        Offset(width, row + 7),
        Paint()
          ..color = muted.withValues(alpha: .4)
          ..strokeWidth = .6,
      );
      top = row + 19;
    }
    return top +
        printText(
          '按区间阅读天数 · 同日同书计 1 天',
          0,
          top,
          width: width,
          size: 10,
          color: muted,
        ) +
        12;
  }

  double printBookAtlas(
    double width, {
    int columns = 3,
    bool dark = false,
    bool heading = true,
  }) {
    final ink = dark ? paper : colors.ink;
    final muted = dark ? paper.withValues(alpha: .6) : colors.muted;
    var top = heading
        ? printHead(ReadingReportModule.books, width, dark: dark)
        : 0.0;
    final books = data.booksByReadingDays.take(options.bookLimit).toList();
    if (books.isEmpty) {
      return top +
          printText('尚未留下相伴书目。', 0, top, width: width, size: 14, color: muted) +
          20;
    }
    final tile = (width - 22 * (columns - 1)) / columns;
    for (var first = 0; first < books.length; first += columns) {
      var rowHeight = 0.0;
      for (var col = 0; col < columns && first + col < books.length; col++) {
        final index = first + col, book = books[index], x = col * (tile + 22);
        final image = components?.bookCovers.elementAtOrNull(index);
        if (image != null) _image(image, x, top, width: 44, height: 62);
        printText(
          '${index + 1}'.padLeft(2, '0'),
          x + 53,
          top,
          width: tile - 53,
          size: 10,
          display: true,
          color: colors.accent,
        );
        printText(
          '${book.days}',
          x + 53,
          top + 13,
          width: tile - 53,
          size: 34,
          display: true,
          weight: FontWeight.w700,
          color: ink,
          height: 1,
        );
        printText(
          '阅读日',
          x + 53,
          top + 49,
          width: tile - 53,
          size: 10,
          color: muted,
        );
        var end =
            top +
            73 +
            printText(
              _bookTitle(book, index),
              x,
              top + 73,
              width: tile,
              size: 14,
              weight: FontWeight.w600,
              color: ink,
              height: 1.45,
            );
        if (!options.hideAuthorNames &&
            book.author?.trim().isNotEmpty == true) {
          end +=
              7 +
              printText(
                book.author!,
                x,
                end + 7,
                width: tile,
                size: 10.5,
                color: muted,
              );
        }
        rowHeight = math.max(rowHeight, end - top);
      }
      top += rowHeight + 27;
    }
    return top +
        printText(
          '按区间阅读天数 · 同日同书计 1 天',
          0,
          top,
          width: width,
          size: 10,
          color: muted,
        ) +
        10;
  }

  double printBookProgramme(double width, {bool dark = false}) {
    final ink = dark ? paper : colors.ink;
    final muted = dark ? paper.withValues(alpha: .55) : colors.muted;
    var top = printHead(ReadingReportModule.books, width, dark: dark);
    final books = data.booksByReadingDays.take(options.bookLimit).toList();
    if (books.isEmpty) {
      return top +
          printText('尚未留下相伴书目。', 0, top, width: width, size: 14, color: muted) +
          20;
    }
    for (var i = 0; i < books.length; i++) {
      final book = books[i], textWidth = width - 170;
      printText(
        '${i + 1}'.padLeft(2, '0'),
        0,
        top - 2,
        width: 47,
        size: 42,
        height: 1,
        display: true,
        weight: FontWeight.w700,
        color: colors.accent,
      );
      var end =
          top +
          printText(
            _bookTitle(book, i),
            61,
            top,
            width: textWidth,
            size: 18,
            height: 1.4,
            color: ink,
            weight: FontWeight.w500,
          );
      if (!options.hideAuthorNames && book.author?.trim().isNotEmpty == true) {
        end +=
            6 +
            printText(
              book.author!,
              61,
              end + 6,
              width: textWidth,
              size: 11,
              color: muted,
            );
      }
      final image = components?.bookCovers.elementAtOrNull(i);
      if (image != null) _image(image, width - 91, top, width: 28, height: 40);
      printText(
        '${book.days}',
        width - 47,
        top,
        width: 47,
        size: 32,
        height: 1,
        display: true,
        color: ink,
        weight: FontWeight.w700,
      );
      printText(
        '阅读日',
        width - 47,
        top + 35,
        width: 47,
        size: 9.5,
        color: muted,
      );
      end = math.max(end, top + 52);
      canvas.drawLine(
        Offset(61, end + 10),
        Offset(width, end + 10),
        Paint()
          ..color = muted.withValues(alpha: .3)
          ..strokeWidth = .6,
      );
      top = end + 24;
    }
    return top +
        printText(
          '按区间阅读天数 · 同日同书计 1 天',
          61,
          top,
          width: width - 61,
          size: 10,
          color: muted,
        ) +
        12;
  }

  double printEchoes(
    double width, {
    bool dark = false,
    double leadSize = 17,
    int count = 2,
    bool ruled = true,
  }) {
    final ink = dark ? paper : colors.ink,
        muted = dark ? paper.withValues(alpha: .5) : colors.muted;
    var top = printHead(
      ReadingReportModule.excerpts,
      width,
      dark: dark,
      english: 'ECHOES',
    );
    final excerpts = data.excerpts.take(count).toList();
    top +=
        printText(
          '当前保存 · 全部记录 · 选录 ${excerpts.length} / ${data.excerpts.length}',
          0,
          top,
          width: width,
          size: 10,
          color: muted,
        ) +
        17;
    if (excerpts.isEmpty) {
      return top +
          printText('还没有保存的文字。', 0, top, width: width, size: 15, color: muted) +
          24;
    }
    for (var i = 0; i < excerpts.length; i++) {
      final start = top, excerpt = excerpts[i];
      top +=
          printText(
            excerpt.quote,
            14,
            top,
            width: width - 14,
            size: i == 0 ? leadSize : math.max(14, leadSize - 1),
            height: 1.65,
            color: ink,
          ) +
          12;
      if (options.includeNotes && excerpt.note.isNotEmpty) {
        top +=
            printText(
              excerpt.note,
              14,
              top,
              width: width - 14,
              size: 12,
              height: 1.6,
              color: muted,
            ) +
            10;
      }
      top +=
          printText(
            options.hideBookTitles
                ? '来源已隐藏'
                : '《${excerpt.title}》 · ${excerpt.chapter}',
            14,
            top,
            width: width - 14,
            size: 10.5,
            color: muted,
          ) +
          22;
      if (ruled) {
        canvas.drawRect(
          Rect.fromLTWH(0, start + 3, 2, top - start - 24),
          Paint()..color = colors.accent,
        );
      }
    }
    return top;
  }

  double printProgress(
    double width, {
    bool dark = false,
    double chartHeight = 146,
  }) {
    final ink = dark ? paper : colors.ink,
        muted = dark ? paper.withValues(alpha: .55) : colors.muted;
    var top = printHead(ReadingReportModule.progress, width, dark: dark);
    top +=
        printText(
          '${data.readingBooks} 本位置 · ${data.finishedBooks} 本进度到末尾',
          0,
          top,
          width: width,
          size: 13,
          color: ink,
        ) +
        9;
    _image(components?.progress, 0, top, width: width, height: chartHeight);
    top += chartHeight + 10;
    top +=
        printText(
          '书签 ${data.bookmarks} / 划线 ${data.underlines}',
          0,
          top,
          width: width,
          size: 12,
          color: muted,
        ) +
        7;
    if (data.unknownProgress > 0) {
      top +=
          printText(
            '${data.unknownProgress} 本目录待读取',
            0,
            top,
            width: width,
            size: 12,
            color: muted,
          ) +
          7;
    }
    return top + 6;
  }

  double printCollection(double width, {bool dark = false}) {
    final ink = dark ? paper : colors.ink,
        muted = dark ? paper.withValues(alpha: .55) : colors.muted;
    var top = printHead(ReadingReportModule.collection, width, dark: dark);
    top +=
        printText(
          '${data.collectionBooks.length} 本藏书 / ${data.authorCount} 位作者',
          0,
          top,
          width: width,
          size: 14,
          color: ink,
        ) +
        14;
    final entries = plateGenres,
        total = entries.fold<int>(0, (a, b) => a + b.books);
    var x = 0.0;
    for (var i = 0; i < entries.length; i++) {
      final w = width * entries[i].books / math.max(1, total);
      canvas.drawRect(
        Rect.fromLTWH(x, top, w - 1, 7),
        Paint()..color = colors.accent.withValues(alpha: 1 - i * .15),
      );
      x += w;
    }
    top += entries.isEmpty ? 0 : 20;
    if (entries.isEmpty) {
      top +=
          printText('书架尚空。', 0, top, width: width, size: 14, color: muted) + 8;
    }
    if (width >= 400 && entries.isNotEmpty) {
      top +=
          printText(
            entries.map((entry) => '${entry.name} ${entry.books}本').join(' / '),
            0,
            top,
            width: width,
            size: 12,
            color: ink,
          ) +
          8;
    } else {
      for (final entry in entries) {
        top +=
            printText(
              '${entry.name} ${entry.books}本',
              0,
              top,
              width: width,
              size: 12,
              color: ink,
            ) +
            6;
      }
    }
    top +=
        printText(
          '在线 ${data.onlineBooks} / 本地 ${data.localBooks}${data.unknownAuthors == 0 ? '' : ' · ${data.unknownAuthors} 本作者待读取'}',
          0,
          top + 6,
          width: width,
          size: 11,
          color: muted,
        ) +
        8;
    return top + 8;
  }

  double printFooter(
    double top, {
    bool dark = false,
    double x = 32,
    double width = 536,
  }) {
    final muted = dark ? paper.withValues(alpha: .5) : colors.muted;
    printText(
      data.startedAt == null
          ? '尚未记录前台时长'
          : '前台时长自 ${_date(data.startedAt!)} 起记录',
      x,
      top,
      width: width,
      size: 10,
      color: muted,
    );
    return top + 36;
  }
}
