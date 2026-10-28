part of 'reading_report_layout.dart';

/// Shared report content; themes arrange these plates instead of cloning data.
abstract class _ReportPlateComposer extends _ReportComposer {
  _ReportPlateComposer(
    super.data,
    super.options,
    super.translate,
    super.components,
  );
  bool has(ReadingReportModule module) =>
      options.modules.contains(module) &&
      readingReportAvailableModules(data).contains(module);
  ReadingVisualTheme get theme => options.template.theme;
  double measurePlate(
    String value,
    double width, {
    double size = 15,
    double height = 1.4,
    FontWeight weight = FontWeight.normal,
    bool serif = false,
  }) => _typeset(
    value,
    width,
    size: size,
    height: height,
    weight: weight,
    serif: serif,
  );
  double plateText(
    String value,
    double x,
    double top, {
    double width = 536,
    double size = 15,
    double height = 1.4,
    FontWeight weight = FontWeight.normal,
    Color? color,
    bool serif = false,
  }) {
    labels.add(translate(value));
    return _typeset(
      value,
      width,
      x: x,
      top: top,
      size: size,
      height: height,
      weight: weight,
      color: color,
      serif: serif,
      paint: true,
    );
  }

  double _typeset(
    String value,
    double width, {
    double x = 0,
    double top = 0,
    double size = 15,
    double height = 1.4,
    FontWeight weight = FontWeight.normal,
    Color? color,
    bool serif = false,
    bool paint = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: translate(value),
        style: TextStyle(
          fontFamily: serif
              ? (components?.serifFamily ?? 'CupertinoSystemText')
              : 'CupertinoSystemText',
          fontFamilyFallback: const ['CupertinoSystemText'],
          fontSize: size,
          height: height,
          fontWeight: weight,
          color: color ?? colors.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    try {
      if (paint) painter.paint(canvas, Offset(x, top));
      return painter.height;
    } finally {
      painter.dispose();
    }
  }

  _ReportPlate plate(
    ReadingReportModule module,
    double width,
    double Function(double) draw,
  ) {
    final outer = canvas, recorder = ui.PictureRecorder();
    canvas = Canvas(recorder);
    final height = draw(width);
    final picture = recorder.endRecording();
    canvas = outer;
    return _ReportPlate(module, picture, width, height);
  }

  void hang(_ReportPlate block, double x, double top) {
    canvas.save();
    canvas.translate(x, top);
    canvas.drawPicture(block.picture);
    canvas.restore();
    block.picture.dispose();
    registerSection(
      block.module,
      Rect.fromLTWH(x, top, block.width, block.height),
    );
  }

  double plateHead(
    ReadingReportModule module,
    double width, {
    double size = 22,
  }) {
    plateText(
      '${(module.index + 1).toString().padLeft(2, '0')} / ${module.name.toUpperCase()}',
      0,
      0,
      size: 9,
      width: width,
      color: colors.muted,
    );
    return 23 +
        plateText(
          module.label,
          0,
          18,
          size: size,
          width: width,
          weight: FontWeight.w600,
          serif: theme.prefersSerif,
          height: 1.25,
        ) +
        5;
  }

  double rhythmPlate(
    double width, {
    double chartHeight = 130,
    bool stacked = false,
  }) {
    var top = plateHead(ReadingReportModule.rhythm, width);
    _image(components?.monthly, 0, top, width: width, height: chartHeight);
    top += chartHeight + 13;
    top +=
        plateText(
          '${data.activeDays} 天活跃 / 日均 ${data.observedDays == 0 ? '—' : statisticsDuration(data.averageSeconds)}',
          0,
          top,
          width: width,
          size: 13,
        ) +
        7;
    return top +
        plateText(
          '最长连续 ${data.longestStreak} 天 · 全部记录',
          0,
          top,
          width: width,
          size: 12,
          color: colors.muted,
        ) +
        4;
  }

  double calendarPlate(double width) {
    var top = plateHead(ReadingReportModule.calendar, width);
    for (final image in components?.calendars ?? const <ui.Image>[]) {
      final height = image.height * width / image.width;
      _image(image, 0, top, width: width, height: height);
      top += height + 10;
    }
    top +=
        plateText(range, 0, top, width: width, size: 10, color: colors.muted) +
        7;
    top +=
        plateText(
          '${data.observedDays} 天有记录 · ${data.activeDays} 天活跃',
          0,
          top,
          width: width,
          size: 12,
        ) +
        6;
    return top +
        plateText(
          '空心 尚未记录 · 浅色 0 · 深色 阅读较久',
          0,
          top,
          width: width,
          size: 10,
          color: colors.muted,
        ) +
        4;
  }

  double booksPlate(double width, {bool cover = true, double coverWidth = 84}) {
    var top = plateHead(ReadingReportModule.books, width);
    top +=
        plateText(
          '按阅读天数 · 本期',
          0,
          top,
          width: width,
          size: 11,
          color: colors.muted,
        ) +
        15;
    final books = data.booksByReadingDays.take(options.bookLimit).toList();
    if (books.isEmpty) {
      return top +
          plateText(
            '尚未留下相伴书目。',
            0,
            top,
            width: width,
            size: 15,
            color: colors.muted,
          ) +
          14;
    }
    for (var i = 0; i < books.length; i++) {
      final book = books[i];
      final image = cover && i == 0 ? components?.featuredCover : null;
      final inset = image == null ? 27.0 : coverWidth + 16;
      final bottom = top + (image == null ? 0 : coverWidth * 1.41);
      if (image != null) {
        _image(image, 0, top, width: coverWidth, height: coverWidth * 1.41);
      }
      if (image == null) {
        plateText(
          '${i + 1}'.padLeft(2, '0'),
          0,
          top + 2,
          width: 24,
          size: 10,
          color: colors.accent,
        );
      }
      var row =
          top +
          plateText(
            _bookTitle(book, i),
            inset,
            top,
            width: width - inset,
            size: 15,
            serif: theme.prefersSerif,
            weight: FontWeight.w500,
          ) +
          6;
      final author = options.hideAuthorNames ? '' : book.author?.trim() ?? '';
      row += plateText(
        '${author.isEmpty ? '' : '$author · '}${book.days} 天',
        inset,
        row,
        width: width - inset,
        size: 12,
        color: colors.muted,
      );
      top = math.max(bottom, row) + 17;
    }
    return top;
  }

  double progressPlate(double width, {double chartHeight = 148}) {
    var top = plateHead(ReadingReportModule.progress, width);
    _image(components?.progress, 0, top, width: width, height: chartHeight);
    top += chartHeight + 10;
    top +=
        plateText(
          '位置 ${data.readingBooks} 本 / 进度到末尾 ${data.finishedBooks} 本',
          0,
          top,
          width: width,
          size: 13,
        ) +
        6;
    top +=
        plateText(
          '书签 ${data.bookmarks} / 划线 ${data.underlines}',
          0,
          top,
          width: width,
          size: 13,
        ) +
        6;
    if (data.unknownProgress > 0) {
      top +=
          plateText(
            '${data.unknownProgress} 本目录待读取',
            0,
            top,
            width: width,
            size: 12,
            color: colors.muted,
          ) +
          6;
    }
    return top + 4;
  }

  List<StatisticsAuthor> get plateGenres => data.genres.length <= 5
      ? data.genres
      : [
          ...data.genres.take(4),
          StatisticsAuthor(
            '其他',
            data.genres.skip(4).fold<int>(0, (a, b) => a + b.books),
          ),
        ];
  double collectionPlate(double width) {
    var top = plateHead(ReadingReportModule.collection, width);
    top +=
        plateText(
          '${data.collectionBooks.length} 本',
          0,
          top,
          width: width,
          size: 33,
          height: 1.2,
          weight: FontWeight.w600,
        ) +
        9;
    top +=
        plateText(
          '${data.authorCount} 位已知作者 · 在线 ${data.onlineBooks} / 本地 ${data.localBooks}',
          0,
          top,
          width: width,
          size: 12,
          color: colors.muted,
        ) +
        14;
    final genres = plateGenres, total = data.collectionBooks.length;
    var x = 0.0;
    for (var i = 0; i < genres.length; i++) {
      final w = total == 0 ? 0.0 : width * genres[i].books / total;
      canvas.drawRect(
        Rect.fromLTWH(x, top, w, 8),
        Paint()..color = colors.accent.withValues(alpha: 1 - i * .15),
      );
      x += w;
    }
    top += genres.isEmpty ? 0 : 20;
    if (genres.isEmpty) {
      top +=
          plateText(
            '书架尚空。',
            0,
            top,
            width: width,
            size: 14,
            color: colors.muted,
          ) +
          8;
    }
    for (final item in genres) {
      top +=
          plateText(
            '${item.name} ${item.books}本',
            0,
            top,
            width: width,
            size: 12,
          ) +
          5;
    }
    if (data.unknownAuthors > 0) {
      top +=
          plateText(
            '${data.unknownAuthors} 本作者待读取',
            0,
            top,
            width: width,
            size: 11,
            color: colors.muted,
          ) +
          6;
    }
    return top + 4;
  }

  double excerptsPlate(
    double width, {
    double leadSize = 20,
    bool columns = false,
  }) {
    var top = plateHead(ReadingReportModule.excerpts, width);
    final excerpts = data.excerpts.take(3).toList();
    top +=
        plateText(
          '当前保存 · 全部记录 · 选录 ${excerpts.length} / ${data.excerpts.length}',
          0,
          top,
          width: width,
          size: 10,
          color: colors.muted,
        ) +
        17;
    if (excerpts.isEmpty) {
      return top +
          plateText(
            '下一段触动你的文字，会在这里留下回声。',
            0,
            top,
            width: width,
            size: leadSize,
            serif: theme.prefersSerif,
            height: 1.7,
          ) +
          15;
    }
    final column = columns && width >= 440 && excerpts.length > 1;
    final w = column ? (width - 26) / 2 : width;
    final tops = [top, top];
    for (var i = 0; i < excerpts.length; i++) {
      final index = column ? i % 2 : 0, x = column && index == 1 ? w + 26 : 0.0;
      var row = tops[index];
      final excerpt = excerpts[i];
      row +=
          plateText(
            excerpt.quote,
            x,
            row,
            width: w,
            size: i == 0 ? leadSize : math.max(15, leadSize - 3),
            serif: theme.prefersSerif,
            height: 1.7,
          ) +
          12;
      if (options.includeNotes && excerpt.note.isNotEmpty) {
        row +=
            plateText(
              excerpt.note,
              x,
              row,
              width: w,
              size: 13,
              color: colors.muted,
            ) +
            10;
      }
      row +=
          plateText(
            options.hideBookTitles
                ? '来源已隐藏'
                : '《${excerpt.title}》 · ${excerpt.chapter}',
            x,
            row,
            width: w,
            size: 11,
            color: colors.muted,
          ) +
          22;
      tops[index] = row;
    }
    return math.max(tops[0], tops[1]) + 4;
  }

  String get timePlate => !duration.observed
      ? '— 尚未记录'
      : '${duration.value} ${duration.shortUnit}${duration.remainder == null ? '' : '  ${duration.remainder} ${duration.remainderUnit}'}';
  double footerPlate(double top, {double x = 32, double width = 536}) {
    canvas.drawLine(
      Offset(x, top),
      Offset(x + width, top),
      Paint()
        ..color = colors.ink.withValues(alpha: .3)
        ..strokeWidth = .65,
    );
    return top +
        15 +
        plateText(
          options.signature ? '轻小说文库 · 私人阅读报告' : '$name · ${data.today.year}',
          x,
          top + 15,
          width: width,
          size: 11,
          color: colors.muted,
        ) +
        10;
  }

  ReadingReportLayout finishPlate(ui.PictureRecorder recorder, double height) =>
      ReadingReportLayout._(
        picture: recorder.endRecording(),
        height: height,
        colors: colors,
        options: options,
        labels: List.unmodifiable(labels),
        sections: Map.unmodifiable({
          for (final module in options.orderedModules.where(
            sections.containsKey,
          ))
            module: sections[module]!,
        }),
        sectionFragments: Map.unmodifiable({
          for (final module in options.orderedModules.where(
            sectionFragments.containsKey,
          ))
            module: List<Rect>.unmodifiable(sectionFragments[module]!),
        }),
        visibleModules: readingReportVisibleModules(data, options),
        components: components,
      );
}

class _ReportPlate {
  const _ReportPlate(this.module, this.picture, this.width, this.height);
  final ReadingReportModule module;
  final ui.Picture picture;
  final double width, height;
}
