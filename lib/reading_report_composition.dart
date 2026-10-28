part of 'reading_report_layout.dart';

/// Report composition is editorial; the charts and covers are real app captures.
class _ReportComposer {
  _ReportComposer(this.data, this.options, this.translate, this.components)
    : colors = ReadingReportColors(options);
  final ReadingStatisticsData data;
  final ReadingReportOptions options;
  final String Function(String) translate;
  final ReadingReportComponents? components;
  final ReadingReportColors colors;
  late final ReadingReportInsights insights;
  final labels = <String>[];
  final sections = <ReadingReportModule, Rect>{};
  final sectionFragments = <ReadingReportModule, List<Rect>>{};
  void registerSection(ReadingReportModule module, Rect bounds) {
    sections.putIfAbsent(module, () => bounds);
    sectionFragments.putIfAbsent(module, () => []).add(bounds);
  }

  late Canvas canvas;
  static const margin = 46.0, content = 508.0;
  double y = 32;
  int serial = 0;
  bool get story => options.template == ReadingReportTemplate.editorial;
  bool get shelf => options.template == ReadingReportTemplate.shelf;
  bool get night => options.template == ReadingReportTemplate.constellation;
  ReadingReportDuration get duration => readingReportDuration(
    data.periodSeconds,
    observed: data.observedDays > 0,
  );
  String get name =>
      options.nickname.trim().isEmpty ? '一位读者' : options.nickname.trim();
  String get title =>
      options.title.trim().isEmpty ? '我的阅读档案' : options.title.trim();
  String get range => '${_date(data.dates.first)} — ${_date(data.today)}';
  String _date(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  String _bookTitle(StatisticsBookDays value, int index) =>
      options.hideBookTitles
      ? '书籍 ${(index + 1).toString().padLeft(2, '0')}'
      : value.title?.trim().isNotEmpty == true
      ? value.title!
      : '书名待读取';

  ReadingReportLayout compose() {
    final recorder = ui.PictureRecorder();
    canvas = Canvas(recorder);
    _header();
    _intro();
    for (final module in options.orderedModules) {
      final top = y;
      final outer = canvas;
      final recording = ui.PictureRecorder();
      canvas = Canvas(recording);
      if (shelf) y += 18;
      _heading(module);
      switch (module) {
        case ReadingReportModule.rhythm:
          _rhythm();
        case ReadingReportModule.calendar:
          _calendar();
        case ReadingReportModule.days:
          _paragraph('${data.activeDays} 天阅读 · 最长连续 ${data.longestStreak} 天');
        case ReadingReportModule.books:
          _books();
        case ReadingReportModule.collection:
          _collection();
        case ReadingReportModule.progress:
          _progress();
        case ReadingReportModule.excerpts:
          _excerpts();
      }
      if (shelf) y += 18;
      final picture = recording.endRecording();
      canvas = outer;
      if (shelf) {
        final rect = Rect.fromLTRB(margin - 14, top, 568, y);
        _panel(rect, fill: .62);
        canvas.drawRect(
          rect.deflate(5),
          Paint()
            ..color = colors.ink.withValues(alpha: .1)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .5,
        );
        for (final corner in [rect.topLeft, rect.bottomRight]) {
          canvas.drawLine(
            corner + const Offset(5, 9),
            corner + const Offset(12, 2),
            Paint()
              ..color = colors.accent.withValues(alpha: .55)
              ..strokeWidth = .7,
          );
        }
      }
      canvas.drawPicture(picture);
      picture.dispose();
      sections[module] = Rect.fromLTRB(margin, top, 554, y);
      y += story
          ? 38
          : shelf
          ? 24
          : 30;
    }
    _footer();
    return ReadingReportLayout._(
      picture: recorder.endRecording(),
      height: y + 28,
      colors: colors,
      options: options,
      labels: List.unmodifiable(labels),
      sections: Map.unmodifiable(sections),
      components: components,
    );
  }

  double _text(
    String value,
    double x,
    double top, {
    double size = 15,
    double? width,
    Color? color,
    FontWeight weight = FontWeight.normal,
    bool code = false,
    bool serif = false,
    double height = 1.4,
    TextAlign align = TextAlign.left,
    int? maxLines,
  }) {
    final text = translate(value);
    labels.add(text);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: code
              ? 'monospace'
              : serif || story
              ? (components?.serifFamily ?? 'CupertinoSystemText')
              : 'CupertinoSystemText',
          fontFamilyFallback: const ['CupertinoSystemText'],
          fontSize: size,
          color: color ?? colors.ink,
          fontWeight: weight,
          height: height,
          letterSpacing: code ? .6 : 0,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    );
    try {
      final maximum = width ?? 554 - x;
      painter.layout(
        minWidth: align == TextAlign.center ? maximum : 0,
        maxWidth: maximum,
      );
      painter.paint(canvas, Offset(x, top));
      return painter.height;
    } finally {
      painter.dispose();
    }
  }

  void _line(
    double top, {
    double left = margin,
    double right = 554,
    double alpha = .2,
  }) => canvas.drawLine(
    Offset(left, top),
    Offset(right, top),
    Paint()
      ..color = colors.ink.withValues(alpha: alpha)
      ..strokeWidth = .65,
  );
  void _panel(Rect rect, {double fill = .32}) {
    canvas.drawRect(
      rect,
      Paint()
        ..color = (night ? colors.ink : Colors.white).withValues(
          alpha: night ? .035 : fill,
        ),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = colors.ink.withValues(alpha: .16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .65,
    );
  }

  void _paragraph(String value, {double size = 18, Color? color}) {
    y +=
        _text(
          value,
          margin + (story ? 20 : 0),
          y,
          size: size,
          width: content - (story ? 20 : 0),
          color: color,
          height: story ? 1.9 : 1.6,
        ) +
        16;
  }

  void _badge(
    String value,
    double x,
    double top, {
    bool solid = false,
    double width = 100,
  }) {
    canvas.drawRect(
      Rect.fromLTWH(x, top, width, 23),
      Paint()..color = solid ? colors.ink : colors.ink.withValues(alpha: .06),
    );
    _text(
      value,
      x + 7,
      top + 4,
      size: 9,
      code: true,
      width: width - 14,
      color: solid ? colors.background : colors.ink,
      maxLines: 1,
    );
  }

  void _image(
    ui.Image? image,
    double x,
    double top, {
    required double width,
    required double height,
  }) {
    if (image == null) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(x, top, width, height),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  double _durationFigure(double x, double top, {required bool large}) {
    final time = duration;
    labels.add(translate(time.label));
    final painter = TextPainter(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'CupertinoSystemText',
          fontSize: large ? 122 : 66,
          fontWeight: FontWeight.w700,
          height: 1.05,
          color: colors.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        children: !time.observed
            ? [
                const TextSpan(text: '—'),
                TextSpan(
                  text: ' ${translate('尚未记录')}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.normal,
                    color: colors.muted,
                  ),
                ),
              ]
            : large
            ? [
                TextSpan(text: time.value),
                TextSpan(
                  text: ' ${time.shortUnit}',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.normal,
                    color: colors.muted,
                  ),
                ),
              ]
            : [
                TextSpan(text: time.value),
                TextSpan(
                  text: ' ${translate(time.unit)} ',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                if (time.remainder != null)
                  TextSpan(
                    text: time.remainder,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (time.remainderUnit != null)
                  TextSpan(
                    text: ' ${translate(time.remainderUnit!)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
              ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 554 - x);
    try {
      painter.paint(canvas, Offset(x, top));
      return painter.height;
    } finally {
      painter.dispose();
    }
  }

  void _header() {
    if (story) {
      _text(
        '序章 · ${data.today.year} 年度阅读',
        margin,
        y,
        size: 11,
        color: colors.muted,
      );
      _text(
        'PRIVATE EDITION',
        394,
        y,
        size: 9,
        code: true,
        color: colors.muted,
      );
      y += 78;
      _text(
        'READING / ANNUAL / ${data.today.year}',
        margin,
        y,
        size: 10,
        code: true,
        color: colors.muted,
      );
      y += 30;
      y +=
          _text(
            data.observedDays == 0
                ? '这一页，\n等你翻开'
                : '这些日子，\n你读了 ${duration.value} ${duration.unit}',
            margin,
            y,
            size: 43,
            weight: FontWeight.w700,
            height: 1.45,
          ) +
          22;
      _line(y, right: 92, alpha: .5);
      y += 24;
      y +=
          _text(
            title == '我的阅读档案' ? '$name 的阅读年鉴' : title,
            margin,
            y,
            size: 17,
            weight: FontWeight.w600,
          ) +
          6;
      y += _text(range, margin, y, size: 11, color: colors.muted) + 35;
      return;
    }
    if (shelf) {
      y +=
          _text(
            '${data.today.year} · 我的藏书',
            margin,
            y,
            size: 29,
            weight: FontWeight.w700,
          ) +
          3;
      _text(
        'EX LIBRIS / PERSONAL SHELF',
        margin,
        y,
        size: 9,
        code: true,
        color: colors.muted,
      );
      y += 26;
      final image = components?.shelf;
      final height = image == null
          ? 300.0
          : math.min(390.0, image.height * 550 / image.width);
      final width = image == null ? 350.0 : image.width * height / image.height;
      _image(image, (600 - width) / 2, y, width: width, height: height);
      if (data.collectionBooks.isEmpty) {
        _text('书架还在等第一本书', margin, y + 130, size: 22, color: colors.muted);
      }
      y += height + 22;
      y +=
          _text(
            title == '我的阅读档案'
                ? '这一架，收藏了 ${data.collectionBooks.length} 本故事。'
                : title,
            margin,
            y,
            size: 23,
            weight: FontWeight.w700,
          ) +
          10;
      y +=
          _text('$name  /  $range', margin, y, size: 11, color: colors.muted) +
          20;
      return;
    }
    _text(
      night ? '夜读档案' : '阅读档案',
      margin,
      y,
      size: 23,
      weight: FontWeight.w700,
    );
    _badge('${data.today.year}', 448, y + 1, width: 106, solid: !night);
    y += 34;
    _text(
      night ? 'ARCHIVE / NIGHT EDITION' : 'PERSONAL ARCHIVE / ANNUAL',
      margin,
      y,
      size: 9,
      code: true,
      color: colors.muted,
    );
    y += night ? 45 : 47;
    _text(
      night ? '${data.today.year} / TOTAL HOURS' : 'REPORT / FISCAL YEAR',
      margin,
      y,
      size: 10,
      code: true,
      color: colors.muted,
    );
    y += 23;
    y += night
        ? _durationFigure(margin - 5, y, large: true) + 7
        : _text(
                '${data.today.year}',
                margin - 5,
                y,
                size: 110,
                weight: FontWeight.w700,
                height: 1.05,
              ) +
              7;
    if (night) {
      y +=
          _text(
            title == '我的阅读档案' ? '$name，把时间留给了书页。' : title,
            margin,
            y,
            size: 22,
            weight: FontWeight.w600,
          ) +
          12;
      y += _text(range, margin, y, size: 11, color: colors.muted) + 20;
    } else {
      y +=
          _text(
            title == '我的阅读档案' ? '$name 的阅读记录' : title,
            margin,
            y,
            size: 22,
            weight: FontWeight.w600,
          ) +
          6;
      y +=
          _text(
            '$range  /  ${data.period} 天区间',
            margin,
            y,
            size: 11,
            color: colors.muted,
          ) +
          24;
      final top = y;
      _panel(Rect.fromLTWH(margin, top, content, 125));
      _text(
        'TOTAL / READING TIME',
        margin + 16,
        top + 13,
        size: 10,
        code: true,
        color: colors.muted,
      );
      _durationFigure(margin + 14, top + 35, large: false);
      y += 144;
    }
  }

  void _intro() {
    if (story) {
      _paragraph(
        data.observedDays == 0
            ? '这一页还没有读完。下一次翻书，会留下第一段时间。'
            : '你在 ${data.activeDays} 天里打开书页，与 ${data.periodBooks} 本书相伴。那些看似平常的片刻，合在一起，是 ${statisticsDuration(data.periodSeconds)}。',
        size: 20,
      );
    } else if (shelf) {
      _metrics(
        ['进度到末尾', '阅读时长', '当前书签'],
        ['${data.finishedBooks} 本', duration.compact, '${data.bookmarks} 条'],
      );
    } else if (night) {
      _pills([
        '${data.activeDays} 天活跃',
        '${data.periodBooks} 本相伴',
        '${data.bookmarks + data.underlines} 条书签划线',
      ]);
    }
    if (options.note.trim().isNotEmpty) {
      y +=
          _text(
            options.note.trim(),
            margin,
            y,
            size: story ? 17 : 13,
            color: colors.muted,
            height: 1.6,
          ) +
          18;
    }
    y += story ? 15 : 4;
  }

  void _heading(ReadingReportModule module) {
    serial++;
    final label = module.label;
    if (story) {
      const ordinal = ['第一章', '第二章', '第三章', '第四章', '第五章', '第六章'];
      y +=
          _text(
            '${ordinal[(serial - 1).clamp(0, 5)]} · $label',
            margin,
            y,
            size: 27,
            weight: FontWeight.w700,
          ) +
          5;
      _text(
        'CHAPTER ${serial.toString().padLeft(2, '0')} / ${module.name.toUpperCase()}',
        margin,
        y,
        size: 9,
        code: true,
        color: colors.muted,
      );
      y += 29;
    } else {
      if (!shelf) _line(y - 8);
      _text(
        '${shelf ? 'EX LIBRIS' : serial.toString().padLeft(2, '0')} / ${shelf ? 'NO. ${serial.toString().padLeft(2, '0')}' : module.name.toUpperCase()}',
        margin,
        y,
        size: 9,
        code: true,
        color: colors.muted,
      );
      y += 20;
      y += _text(label, margin, y, size: 22, weight: FontWeight.w700) + 14;
    }
  }

  void _metrics(List<String> captions, List<String> values) {
    const gap = 10.0, width = (content - gap * 2) / 3;
    for (var i = 0; i < 3; i++) {
      final x = margin + i * (width + gap);
      if (!story) _panel(Rect.fromLTWH(x, y, width, 62), fill: .28);
      _text(
        values[i],
        x + 10,
        y + 10,
        size: 21,
        width: width - 20,
        weight: FontWeight.w700,
        maxLines: 1,
      );
      _text(
        captions[i],
        x + 10,
        y + 39,
        size: 10,
        width: width - 20,
        color: colors.muted,
        maxLines: 1,
      );
    }
    y += 76;
  }

  void _pills(List<String> values) {
    var x = margin;
    for (final value in values) {
      final width = math.min(
        content,
        math.max(90.0, value.characters.length * 11.0 + 22),
      );
      if (x + width > 554) {
        x = margin;
        y += 33;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, width, 27),
          const Radius.circular(15),
        ),
        Paint()..color = colors.ink.withValues(alpha: night ? .11 : .055),
      );
      _text(value, x + 11, y + 5, size: 11, width: width - 22, maxLines: 1);
      x += width + 7;
    }
    y += 39;
  }

  void _rhythm() {
    if (story) {
      _paragraph(
        data.observedDays == 0
            ? '等第一段时间被记录，曲线才会开始。'
            : '在 ${data.observedDays} 个已记录的自然日里，你有 ${data.activeDays} 天与书相遇，平均每天阅读 ${statisticsDuration(data.averageSeconds)}。最长的一日，是 ${data.peakDate == null ? '—' : statisticsDate(data.peakDate!)} 的 ${statisticsDuration(data.peakSeconds)}。',
      );
    } else if (night) {
      final top = y;
      _panel(Rect.fromLTWH(margin, top, content, 320));
      _image(components?.ring, 170, top + 4, width: 260, height: 260);
      _text(
        '${data.activeDays} 天活跃 / ${data.observedDays} 天记录',
        margin + 20,
        top + 265,
        size: 13,
        width: content - 40,
        align: TextAlign.center,
      );
      _text(
        data.activeDays == 0
            ? '活跃日均 —'
            : '活跃日均 ${statisticsDuration(data.activeAverageSeconds)}',
        margin + 20,
        top + 289,
        size: 11,
        width: content - 40,
        color: colors.muted,
        align: TextAlign.center,
      );
      y += 338;
    } else {
      _metrics(
        ['阅读活跃天', '最长连续 · 全部记录', '已记录日均'],
        [
          '${data.activeDays} 天',
          '${data.longestStreak} 天',
          data.observedDays == 0 ? '—' : '${data.averageSeconds ~/ 60} 分',
        ],
      );
    }
    final image = components?.monthly;
    final chartHeight = image == null
        ? (story ? 130.0 : 158.0)
        : image.height * content / image.width;
    if (!story) {
      _text(
        'MONTHLY / HOURS',
        margin,
        y,
        size: 9,
        code: true,
        color: colors.muted,
      );
      y += 19;
    }
    _image(image, margin, y, width: content, height: chartHeight);
    y += chartHeight + 8;
    final measured =
        data.months
            .where((month) => month.seconds != null && month.seconds! > 0)
            .toList()
          ..sort((a, b) => b.seconds!.compareTo(a.seconds!));
    if (measured.isNotEmpty) {
      final peak = measured.first;
      y +=
          _text(
            '${peak.date.year}.${peak.date.month.toString().padLeft(2, '0')} · ${statisticsDuration(peak.seconds!)}，是阅读最多的月份。',
            margin,
            y,
            size: 11,
            color: colors.muted,
          ) +
          8;
    }
  }

  void _books() {
    if (data.booksByReadingDays.isEmpty) {
      _paragraph('书单还在等待第一段真实的阅读。', size: 16, color: colors.muted);
      return;
    }
    final books = data.booksByReadingDays.take(options.bookLimit).toList();
    if (story) {
      _paragraph(
        '陪你较多天的，是《${_bookTitle(books.first, 0)}》。在这段记录里，你与它相遇 ${books.first.days} 天。',
      );
    }
    for (final (i, book) in books.indexed) {
      final title = _bookTitle(book, i);
      if (story) {
        _text(
          (i + 1).toString().padLeft(2, '0'),
          margin,
          y + 5,
          size: 9,
          code: true,
          color: colors.muted,
        );
        _text('《$title》', margin + 32, y, size: 18, width: 370, maxLines: 1);
        _text(
          '${book.days} 天',
          476,
          y + 2,
          size: 17,
          width: 78,
          align: TextAlign.right,
          weight: FontWeight.w600,
        );
        _line(y + 32, left: margin + 32, alpha: .13);
        y += 48;
        continue;
      }
      final cover = components?.bookCovers.elementAtOrNull(i);
      if (i == 0) {
        final top = y;
        _panel(
          Rect.fromLTWH(margin, top, content, 143),
          fill: shelf ? .18 : .22,
        );
        _image(cover, margin + 14, top + 13, width: 78, height: 110);
        _badge('NO. 01', margin + 110, top + 13, solid: true, width: 72);
        _text(
          title,
          margin + 110,
          top + 45,
          size: 23,
          width: 370,
          maxLines: 1,
          weight: FontWeight.w700,
        );
        final details = [
          if (!options.hideAuthorNames && book.author?.isNotEmpty == true)
            book.author!,
          if (book.book?.genre.trim().isNotEmpty == true) book.book!.genre,
        ].join(' · ');
        if (details.isNotEmpty) {
          _text(
            details,
            margin + 110,
            top + 79,
            size: 11,
            color: colors.muted,
            maxLines: 1,
          );
        }
        _text(
          '${book.days} 天相伴',
          margin + 110,
          top + 102,
          size: 23,
          color: colors.accent,
          weight: FontWeight.w700,
        );
        y += 157;
      } else {
        _text(
          (i + 1).toString().padLeft(2, '0'),
          margin,
          y + 21,
          size: 9,
          code: true,
          width: 22,
          color: colors.muted,
        );
        _image(cover, margin + 27, y + 2, width: 35, height: 49);
        _text(
          title,
          margin + 75,
          y + 3,
          size: 15,
          width: 340,
          maxLines: 1,
          weight: FontWeight.w600,
        );
        if (!options.hideAuthorNames && book.author?.isNotEmpty == true) {
          _text(
            book.author!,
            margin + 75,
            y + 27,
            size: 10,
            width: 300,
            color: colors.muted,
            maxLines: 1,
          );
        }
        _text(
          '${book.days}',
          490,
          y + 5,
          size: 22,
          width: 64,
          align: TextAlign.right,
          weight: FontWeight.w600,
        );
        _text(
          '天',
          516,
          y + 34,
          size: 9,
          width: 38,
          align: TextAlign.right,
          color: colors.muted,
        );
        canvas.drawRect(
          Rect.fromLTWH(margin + 75, y + 48, 329, 2),
          Paint()..color = colors.ink.withValues(alpha: .09),
        );
        canvas.drawRect(
          Rect.fromLTWH(
            margin + 75,
            y + 48,
            329 * book.days / books.first.days,
            2,
          ),
          Paint()..color = colors.accent.withValues(alpha: .7),
        );
        y += 65;
      }
    }
    y +=
        _text(
          '按区间阅读天数 · 同日同书计 1 天 · ${books.length}/${data.booksByReadingDays.length} 本',
          margin,
          y + 2,
          size: 10,
          color: colors.muted,
        ) +
        9;
  }

  void _collection() {
    final total = data.genres.fold(0, (sum, genre) => sum + genre.books);
    if (data.collectionBooks.isEmpty) {
      _paragraph(
        '书架还在等第一本书。加入藏书后，这里会留下你的书目与分类。',
        size: 16,
        color: colors.muted,
      );
      return;
    }
    if (story) {
      final names = data.genres
          .take(3)
          .map((genre) => '${genre.name} ${genre.books} 本')
          .join('，');
      _paragraph(
        total == 0
            ? '书架还是一张空白的目录，等待下一本书。'
            : '当前的书架有 ${data.collectionBooks.length} 本藏书。翻开这份目录，常见的风景是${names.isEmpty ? '尚未分类的故事' : names}。',
      );
    } else {
      _text(
        'CURRENT COLLECTION / ${data.collectionBooks.length} BOOKS',
        margin,
        y,
        size: 9,
        code: true,
        color: colors.muted,
      );
      y += 23;
    }
    if (total > 0) {
      var x = margin;
      for (final (i, genre) in data.genres.indexed) {
        final width = content * genre.books / total;
        canvas.drawRect(
          Rect.fromLTWH(x, y, math.max(0, width - 2), 12),
          Paint()
            ..color = colors.accent.withValues(
              alpha: (1 - i * .12).clamp(.18, 1),
            ),
        );
        x += width;
      }
      y += 26;
      for (var i = 0; i < math.min(6, data.genres.length); i++) {
        final genre = data.genres[i];
        final col = i % 3;
        final row = i ~/ 3;
        final x = margin + col * 173;
        canvas.drawRect(
          Rect.fromLTWH(x, y + row * 26 + 5, 6, 6),
          Paint()
            ..color = colors.accent.withValues(
              alpha: (1 - i * .12).clamp(.18, 1),
            ),
        );
        _text(
          '${genre.name} ${(genre.books / total * 100).round()}%',
          x + 13,
          y + row * 26,
          size: 12,
          width: 153,
          maxLines: 1,
        );
      }
      y += (math.min(6, data.genres.length) / 3).ceil() * 26 + 8;
    }
    if (total == 0) {
      _paragraph(
        '已有 ${data.collectionBooks.length} 本藏书，分类信息尚待读取。',
        size: 16,
        color: colors.muted,
      );
    }
    if (!story) {
      y +=
          _text('当前藏书分类 · 按本数统计', margin, y, size: 10, color: colors.muted) + 7;
    }
  }

  void _progress() {
    if (story) {
      _paragraph(
        '书架上，${data.readingBooks} 本书保留着阅读位置，${data.finishedBooks} 本当前进度到末尾。${data.bookmarks} 条书签与 ${data.underlines} 条划线，是你在页边留下的记号。',
      );
    } else {
      _metrics(
        ['有阅读位置', '进度到末尾', '当前书签 / 划线'],
        [
          '${data.readingBooks} 本',
          '${data.finishedBooks} 本',
          '${data.bookmarks} / ${data.underlines}',
        ],
      );
    }
    _image(components?.progress, margin, y, width: content, height: 132);
    y += 143;
    y +=
        _text(
          '当前章节进度分布${data.unknownProgress == 0 ? '' : ' · ${data.unknownProgress} 本目录待读取'}',
          margin,
          y,
          size: 10,
          color: colors.muted,
        ) +
        6;
  }

  void _excerpts() {
    y +=
        _text(
          '当前保存 · 全部记录${options.includeNotes ? ' · 含批注文字' : ''}',
          margin,
          y,
          size: 10,
          color: colors.muted,
        ) +
        23;
    if (data.excerpts.isEmpty) {
      _paragraph('还没有保存的文字。下一段触动你的句子，可以留在这里。', size: 16, color: colors.muted);
      return;
    }
    final count = math.min(story || shelf ? 3 : 2, data.excerpts.length);
    for (var i = 0; i < count; i++) {
      final excerpt = data.excerpts[i];
      final top = y;
      final left = margin + 20;
      if (!story) {
        _text(
          'READING / EXCERPT',
          left,
          y + 10,
          size: 8,
          code: true,
          color: colors.muted,
        );
        y += 31;
      }
      y +=
          _text(
            excerpt.quote,
            left,
            y + 4,
            size: story ? 19 : 17,
            width: content - 40,
            serif: true,
            height: 1.8,
            maxLines: 4,
          ) +
          17;
      if (options.includeNotes && excerpt.note.isNotEmpty) {
        y +=
            _text(
              excerpt.note,
              left,
              y,
              size: 12,
              width: content - 40,
              color: colors.muted,
              maxLines: 2,
            ) +
            13;
      }
      final source = options.hideBookTitles
          ? '来源已隐藏'
          : '《${excerpt.title}》 · ${excerpt.chapter}';
      y +=
          _text(
            source,
            left,
            y,
            size: 10,
            width: content - 64,
            color: colors.muted,
            maxLines: 1,
          ) +
          16;
      if (story) {
        canvas.drawLine(
          Offset(margin + 3, top + 3),
          Offset(margin + 3, y - 10),
          Paint()
            ..color = colors.accent.withValues(alpha: .45)
            ..strokeWidth = 1,
        );
      } else {
        canvas.drawRect(
          Rect.fromLTRB(margin, top, 554, y),
          Paint()
            ..color = colors.ink.withValues(alpha: .14)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .6,
        );
        if (shelf) {
          canvas.drawRect(
            Rect.fromLTWH(margin, top, 5, y - top),
            Paint()..color = colors.accent,
          );
        }
        _text(
          '${i + 1}/$count',
          511,
          y - 23,
          size: 8,
          code: true,
          color: colors.muted,
          width: 32,
        );
      }
      y += story ? 17 : 14;
    }
  }

  void _calendar() {
    if (story) _paragraph('${data.activeDays} 个与书相遇的日子，在这里连成一页日历。');
    _text(
      '$range · ${data.activeDays} 天活跃',
      margin,
      y,
      size: 10,
      code: true,
      color: colors.muted,
    );
    y += 25;
    final images = components?.calendars ?? const <ui.Image>[];
    if (images.isEmpty) y += 100;
    for (final image in images) {
      final height = image.height * content / image.width;
      _image(image, margin, y, width: content, height: height);
      y += height + 12;
    }
    y +=
        _text(
          '空心：尚未记录  ·  浅色：0  ·  深色：阅读较久',
          margin,
          y,
          size: 10,
          color: colors.muted,
        ) +
        6;
  }

  void _footer() {
    y += story ? 14 : 6;
    if (story) {
      y += _text('终章', margin, y, size: 27, weight: FontWeight.w700) + 8;
      _text('EPILOGUE', margin, y, size: 9, code: true, color: colors.muted);
      y += 34;
      _paragraph('故事没有结束。下一页，仍是你的书与时间。', size: 20);
    } else {
      _badge('${data.today.year}', margin, y, width: 102, solid: true);
      if (options.nickname.trim().isNotEmpty) {
        _badge(name, margin + 106, y, width: 140);
      }
      y += 43;
      y +=
          _text(
            night
                ? '晚安，明天见'
                : shelf
                ? '这一架的书，已封存'
                : '档案已归档',
            margin,
            y,
            size: 28,
            weight: FontWeight.w700,
          ) +
          4;
      _text(
        night ? 'ARCHIVE / LIGHTS OUT' : 'ARCHIVE / SEALED',
        margin,
        y,
        size: 9,
        code: true,
        color: colors.muted,
      );
      y += 30;
    }
    y +=
        _text(
          data.startedAt == null
              ? '时长从首次前台阅读开始记录。'
              : '前台时长 · 自 ${_date(data.startedAt!)} 起记录',
          margin,
          y,
          size: 9,
          color: colors.muted,
        ) +
        8;
  }
}
