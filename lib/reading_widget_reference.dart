import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'reading_widget_design.dart';
import 'reading_widget_skin.dart';
import 'reading_widget_snapshot.dart';

enum ReadingDesktopSize {
  small(Size(170, 170)),
  medium(Size(364, 170)),
  large(Size(364, 382));

  const ReadingDesktopSize(this.size);
  final Size size;
}

/// The user's widgets.css tokens and widgets.js compositions. Only assets and
/// measured content are substituted; all three hosts consume this same face.
class ReadingDesktopCard extends StatelessWidget {
  const ReadingDesktopCard({
    super.key,
    required this.data,
    required this.size,
    this.brightness,
    this.quoteText,
    this.quoteSource = '',
    this.quoteCount = 0,
    this.paintQuote = true,
  });
  final Brightness? brightness;
  final String? quoteText;
  final String quoteSource;
  final int quoteCount;
  final bool paintQuote;
  final ReadingWidgetSnapshot data;
  final ReadingDesktopSize size;
  ReadingWidgetSkin get skin => data.skin;
  bool get small => size == ReadingDesktopSize.small;
  bool get large => size == ReadingDesktopSize.large;
  ReadingWidgetPalette get p =>
      ReadingWidgetPalette(skin, data.localDay, brightness);
  List<ReadingWidgetDay> get week => data.heatmap.window(1);
  int? get weekSeconds => week.every((day) => day.verifiedSeconds == null)
      ? null
      : week.fold<int>(0, (sum, day) => sum + (day.verifiedSeconds ?? 0));
  String get season => [
    '春 · SPRING',
    '夏 · SUMMER',
    '秋 · AUTUMN',
    '冬 · WINTER',
  ][seasonIndex(data.localDay)];
  String get code => switch (skin) {
    ReadingWidgetSkin.seasons => season,
    ReadingWidgetSkin.night =>
      '${data.generatedAt.hour.toString().padLeft(2, '0')}:${data.generatedAt.minute.toString().padLeft(2, '0')}',
    ReadingWidgetSkin.film =>
      'CUT ${data.localDay.difference(DateTime(data.localDay.year)).inDays + 1}',
    ReadingWidgetSkin.paper =>
      'P.${data.localDay.difference(DateTime(data.localDay.year)).inDays + 1}',
    _ => 'WK-${widgetDate(data.localDay).substring(5).replaceAll('-', '')}',
  };
  String get line => data.generatedAt.hour >= 22 || data.generatedAt.hour < 5
      ? '关灯以后，才是正文时间。'
      : data.dailyGoalMinutes > 0 &&
            (data.verifiedTodaySeconds ?? -1) >= data.dailyGoalMinutes * 60
      ? '今天的 ${data.dailyGoalMinutes} 分钟读满啦，奖励自己一章。'
      : (data.qualifiedStreakDays ?? 0) >= 7
      ? '连续 ${data.qualifiedStreakDays} 天！今天也来一章吧。'
      : data.showBookDetails && (data.currentBook?.chapter.isNotEmpty ?? false)
      ? '书签还夹在${data.currentBook!.chapter}，等你回来。'
      : '把时间留给喜欢的故事。';
  TextStyle textStyle(
    double fontSize, {
    Color? color,
    FontWeight weight = FontWeight.w400,
    double height = 1.2,
  }) => TextStyle(
    fontSize: fontSize,
    color: color ?? p.ink,
    fontWeight: weight,
    height: height,
  );
  Widget text(
    String value,
    double fontSize, {
    Color? color,
    FontWeight weight = FontWeight.w400,
    int lines = 1,
  }) => Text(
    value,
    maxLines: lines,
    overflow: TextOverflow.ellipsis,
    style: textStyle(fontSize, color: color, weight: weight),
  );
  Widget get gap => SizedBox(height: large ? 8 : 6);
  EdgeInsets get padding => EdgeInsets.fromLTRB(
    large ? 18 : 16,
    skin == ReadingWidgetSkin.film ? 19 : 14,
    large ? 18 : 16,
    skin == ReadingWidgetSkin.film
        ? 17
        : large
        ? 16
        : 14,
  );
  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size.size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: ColoredBox(
        color: p.bg,
        child: DefaultTextStyle(
          style: textStyle(
            12,
          ).copyWith(fontFamily: DefaultTextStyle.of(context).style.fontFamily),
          child: Stack(
            children: [
              Positioned.fill(
                child: switch (data.design) {
                  ReadingWidgetDesign.week => rhythm(),
                  ReadingWidgetDesign.calendar => calendar(),
                  ReadingWidgetDesign.memory => memory(),
                  ReadingWidgetDesign.quote => quote(),
                  _ => today(),
                },
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ReferenceDecoration(
                      p,
                      skin,
                      small,
                      data.design,
                      seasonName(data.localDay),
                      DefaultTextStyle.of(context).style.fontFamily,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget quote() {
    return Stack(
      children: [
        if (large)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 150,
            child: art(band: true),
          ),
        Positioned(
          left: 16,
          right: 16,
          top: large ? 166 : 16,
          child: header('今日摘录', right: !small),
        ),
        if (small || large)
          Positioned(
            left: 34,
            top: large ? 188 : 36,
            child: Text(
              '“',
              style: TextStyle(
                fontFamily: 'ReadingSerifDisplay',
                fontSize: 38,
                color: p.accent,
                height: 1,
              ),
            ),
          ),
        if (!small && !large)
          Positioned(
            left: 16,
            top: 40,
            width: 3,
            height: 80,
            child: ColoredBox(color: p.accent),
          ),
        if (paintQuote) ...[
          Positioned(
            left: small || large ? 16 : 30,
            right: 16,
            top: large
                ? 230
                : small
                ? 62
                : 50,
            height: large ? 82 : 51,
            child: Text(
              quoteText ?? '在阅读中留下喜欢的句子',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style:
                  textStyle(
                    large
                        ? 20
                        : small
                        ? 14
                        : 16,
                    height: 1.35,
                    weight: FontWeight.w600,
                  ).copyWith(
                    fontFamilyFallback: const [
                      'Noto Serif CJK SC',
                      'Songti SC',
                      'serif',
                    ],
                  ),
            ),
          ),
          if (quoteSource.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              top: large ? 322 : 118,
              child: text(quoteSource, 10, color: p.muted),
            ),
          if (large && quoteCount > 0)
            Positioned(
              left: 16,
              bottom: 20,
              child: text('共 $quoteCount 条摘录', 11, color: p.muted),
            ),
        ],
        if (paintQuote && quoteCount > 1)
          Positioned(
            right: 16,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: p.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.refresh_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  text('换一条', 11, color: Colors.white),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget header(String label, {bool right = true}) => SizedBox(
    height: 16,
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.asset(
            'assets/branding/app-icon.png',
            width: 16,
            height: 16,
            cacheWidth: 48,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: text(label, 12, weight: FontWeight.w700)),
        if (right && !small) ...[
          const SizedBox(width: 4),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: skin == ReadingWidgetSkin.seasons ? 6 : 5,
            ),
            decoration: BoxDecoration(
              color: skin == ReadingWidgetSkin.archive ? p.ink : null,
              border: skin == ReadingWidgetSkin.seasons
                  ? Border.all(color: p.accent)
                  : null,
              borderRadius: BorderRadius.circular(
                skin == ReadingWidgetSkin.seasons ? 99 : 2,
              ),
            ),
            child: text(
              code,
              9.5,
              color: skin == ReadingWidgetSkin.archive ? p.bg : p.accent,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ],
    ),
  );
  Widget number(String value, {String unit = '分钟', double? fontSize}) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontFamily: 'ReadingDisplay',
            fontSize: fontSize ?? (large ? 50 : 44),
            fontWeight: FontWeight.w700,
            height: 1,
            letterSpacing: -.44,
            color: skin == ReadingWidgetSkin.seasons ? p.accent : p.ink,
          ),
        ),
      ),
      if (unit.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 3, right: 5),
          child: text(
            unit,
            12,
            color: skin == ReadingWidgetSkin.night ? p.accent : p.muted,
            weight: FontWeight.w600,
          ),
        ),
    ],
  );
  Widget timeNumber(int seconds, {double? fontSize}) => seconds < 3600
      ? number(widgetMinutes(seconds), fontSize: fontSize)
      : Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            number('${seconds ~/ 3600}', unit: 'h', fontSize: fontSize),
            number(
              '${seconds ~/ 60 % 60}'.padLeft(2, '0'),
              unit: 'm',
              fontSize: fontSize,
            ),
          ],
        );
  Widget goalBar() => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: SizedBox(
      height: 6,
      child: LinearProgressIndicator(
        value: ((data.verifiedTodaySeconds ?? 0) / (data.dailyGoalMinutes * 60))
            .clamp(0, 1),
        minHeight: 6,
        color: p.accent,
        backgroundColor: p.track,
      ),
    ),
  );
  Widget streakPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color:
          skin == ReadingWidgetSkin.archive || skin == ReadingWidgetSkin.paper
          ? p.ink
          : p.accent,
      borderRadius: BorderRadius.circular(
        skin == ReadingWidgetSkin.paper ? 2 : 99,
      ),
    ),
    child: text(
      '连续 ${data.qualifiedStreakDays} 天',
      11,
      color: skin == ReadingWidgetSkin.night || skin == ReadingWidgetSkin.film
          ? const Color(0xFF17130C)
          : Colors.white,
      weight: FontWeight.w700,
    ),
  );
  Widget goalRing() {
    final ratio =
        ((data.verifiedTodaySeconds ?? 0) / (data.dailyGoalMinutes * 60)).clamp(
          0.0,
          1.0,
        );
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: ratio,
              strokeWidth: 7,
              strokeCap: StrokeCap.round,
              color: p.accent,
              backgroundColor: p.track,
            ),
          ),
          Text(
            '${(ratio * 100).round()}%',
            style: TextStyle(
              fontFamily: 'ReadingDisplay',
              fontSize: 17,
              color: p.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget today() {
    final measured = data.verifiedTodaySeconds != null;
    final goal = readingDailyGoal(data.dailyGoalMinutes) > 0;
    if (small) {
      return Padding(
        padding: padding.copyWith(left: 15, right: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header('今日阅读', right: false),
            gap,
            if (measured) ...[
              number(widgetMinutes(data.verifiedTodaySeconds)),
              gap,
            ],
            if (goal && measured) ...[goalBar(), gap],
            if (goal)
              text(
                readingGoalCaption(
                  data.dailyGoalMinutes,
                  data.verifiedTodaySeconds,
                ),
                11.5,
                color: p.muted,
              ),
            const Spacer(),
            if ((data.qualifiedStreakDays ?? 0) > 0) streakPill(),
          ],
        ),
      );
    }
    if (!large) {
      return Row(
        children: [
          SizedBox(
            width: 138,
            height: 170,
            child: art(band: false, zoom: 1.55),
          ),
          Expanded(
            child: Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header('今日阅读'),
                  const SizedBox(height: 5),
                  if (measured) ...[
                    number(widgetMinutes(data.verifiedTodaySeconds)),
                    const SizedBox(height: 5),
                  ],
                  if (goal && measured) ...[
                    goalBar(),
                    const SizedBox(height: 5),
                  ],
                  if (goal)
                    text(
                      readingGoalCaption(
                        data.dailyGoalMinutes,
                        data.verifiedTodaySeconds,
                      ),
                      11.5,
                      color: p.muted,
                    ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (data.qualifiedStreakDays != null)
                        metric('${data.qualifiedStreakDays}', '天', '连续阅读'),
                      if (data.qualifiedStreakDays != null &&
                          weekSeconds != null)
                        const SizedBox(width: 14),
                      if (weekSeconds != null)
                        metric(
                          '${weekSeconds! ~/ 3600}:${(weekSeconds! ~/ 60 % 60).toString().padLeft(2, '0')}',
                          '',
                          '本周时长',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 150,
          child: Stack(
            children: [
              Positioned.fill(child: art(band: true)),
              Positioned(left: 14, right: 14, bottom: 10, child: bubble()),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header('今日阅读'),
                gap,
                SizedBox(
                  height: 66,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (measured)
                              number(
                                widgetMinutes(data.verifiedTodaySeconds),
                                fontSize: 50,
                              ),
                            text(
                              [
                                if (goal) '目标 ${data.dailyGoalMinutes} 分钟',
                                if ((data.qualifiedStreakDays ?? 0) > 0)
                                  '连续 ${data.qualifiedStreakDays} 天',
                              ].join(' · '),
                              11.5,
                              color: p.muted,
                            ),
                          ],
                        ),
                      ),
                      if (goal && measured) goalRing(),
                    ],
                  ),
                ),
                gap,
                if (weekSeconds != null) SizedBox(height: 62, child: bars()),
                const Spacer(),
                if (data.showBookDetails && data.currentBook != null)
                  currentBook(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget metric(String value, String unit, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      number(value, unit: unit, fontSize: 22),
      text(label, 10.5, color: p.muted),
    ],
  );
  Widget bubble() => Transform.rotate(
    angle: skin == ReadingWidgetSkin.paper ? -math.pi / 150 : 0,
    child: Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 7),
      decoration: BoxDecoration(
        color: p.bubble,
        border: skin == ReadingWidgetSkin.seasons
            ? Border.all(color: p.accent, width: 1.5)
            : skin == ReadingWidgetSkin.film
            ? Border(left: BorderSide(color: p.accent, width: 3))
            : null,
        boxShadow: skin == ReadingWidgetSkin.paper
            ? const [BoxShadow(color: Color(0x2E000000), offset: Offset(2, 3))]
            : null,
        borderRadius:
            skin == ReadingWidgetSkin.paper || skin == ReadingWidgetSkin.film
            ? BorderRadius.circular(skin == ReadingWidgetSkin.paper ? 3 : 4)
            : BorderRadius.only(
                topLeft: Radius.circular(
                  skin == ReadingWidgetSkin.seasons
                      ? 4
                      : skin == ReadingWidgetSkin.paper
                      ? 3
                      : 12,
                ),
                topRight: const Radius.circular(14),
                bottomLeft: const Radius.circular(14),
                bottomRight: const Radius.circular(14),
              ),
      ),
      child: text(
        line,
        13.5,
        weight: FontWeight.w700,
        lines: 2,
        color: p.bubbleInk,
      ),
    ),
  );
  Widget currentBook() => Row(
    children: [
      Icon(Icons.menu_book_rounded, size: 24, color: p.accent),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            text(data.currentBook!.title, 12.5, weight: FontWeight.w700),
            if (data.currentBook!.chapter.isNotEmpty)
              text(data.currentBook!.chapter, 11, color: p.muted),
          ],
        ),
      ),
    ],
  );
  Widget bars({bool values = false}) => LayoutBuilder(
    builder: (context, constraints) {
      final maximum = week
          .map((day) => day.verifiedSeconds ?? 0)
          .fold(1, math.max);
      final height = math.max(
        1.0,
        constraints.maxHeight - 16 - (values ? 14 : 0),
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 6 ? 0 : 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (values && week[i].verifiedSeconds != null)
                      text(
                        widgetMinutes(week[i].verifiedSeconds),
                        9.5,
                        color: p.muted,
                      ),
                    const Spacer(),
                    Container(
                      width: 24,
                      height: week[i].verifiedSeconds == null
                          ? 4
                          : math.max(
                              4,
                              week[i].verifiedSeconds! / maximum * height,
                            ),
                      decoration: BoxDecoration(
                        color: week[i].verifiedSeconds == null
                            ? null
                            : i == data.localDay.weekday - 1
                            ? p.accent
                            : p.bar,
                        border: week[i].verifiedSeconds == null
                            ? Border.all(
                                color: p.muted.withValues(alpha: .5),
                                width: .6,
                              )
                            : null,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 3),
                    text(
                      ['一', '二', '三', '四', '五', '六', '日'][i],
                      10,
                      color: p.muted,
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
  String? get comparison {
    final previous = data.heatmap.window(2).take(7).take(data.localDay.weekday);
    final current = week.take(data.localDay.weekday);
    if (previous.any((day) => day.verifiedSeconds == null) ||
        current.any((day) => day.verifiedSeconds == null)) {
      return null;
    }
    final before = previous.fold<int>(
      0,
      (sum, day) => sum + day.verifiedSeconds!,
    );
    if (before == 0) return null;
    final change = (((weekSeconds ?? 0) - before) * 100 / before).round();
    return '比上周同期 ${change > 0 ? '+' : ''}$change%';
  }

  String? get peakDay {
    final values = week.where((day) => (day.verifiedSeconds ?? 0) > 0).toList();
    if (values.isEmpty) return null;
    values.sort((a, b) => b.verifiedSeconds!.compareTo(a.verifiedSeconds!));
    final peak = values.first;
    return '周${['一', '二', '三', '四', '五', '六', '日'][peak.date.weekday - 1]}读得最多 · ${widgetMinutes(peak.verifiedSeconds)} 分';
  }

  Widget rhythm() {
    if (small) {
      return Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header('本周阅读', right: false),
            gap,
            if (weekSeconds != null) ...[
              timeNumber(weekSeconds!),
              gap,
              Expanded(child: bars()),
            ],
          ],
        ),
      );
    }
    if (!large) {
      return Padding(
        padding: padding,
        child: Row(
          children: [
            SizedBox(
              width: (size.size.width - 44) * .4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header('本周阅读', right: false),
                  const SizedBox(height: 10),
                  if (weekSeconds != null)
                    timeNumber(weekSeconds!, fontSize: 44),
                  const SizedBox(height: 10),
                  if (comparison != null)
                    text(comparison!, 11.5, color: p.muted, lines: 2),
                  if (peakDay != null) ...[
                    const SizedBox(height: 6),
                    text(peakDay!, 11.5, color: p.muted, lines: 2),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (weekSeconds != null) Expanded(child: bars(values: true)),
          ],
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header('本周阅读'),
          gap,
          if (weekSeconds != null) ...[
            Row(
              children: [
                Expanded(child: timeNumber(weekSeconds!)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (comparison != null)
                      text(comparison!, 11.5, color: p.muted),
                    if ((data.qualifiedStreakDays ?? 0) > 0)
                      text(
                        '连续 ${data.qualifiedStreakDays} 天',
                        11.5,
                        color: p.muted,
                      ),
                  ],
                ),
              ],
            ),
            gap,
            SizedBox(height: 96, child: bars(values: true)),
            const Spacer(),
            text('近 5 周', 11, color: p.muted, weight: FontWeight.w700),
            gap,
            heatmap(),
            gap,
            legend(),
          ],
        ],
      ),
    );
  }

  Widget calendar() => !small && !large
      ? Padding(
          padding: padding,
          child: Row(
            children: [
              SizedBox(
                width: 116,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header('阅读日历', right: false),
                    const SizedBox(height: 12),
                    text(
                      '${data.localDay.month} 月',
                      30,
                      weight: FontWeight.w700,
                    ),
                    const Spacer(),
                    text('${data.localDay.year}', 11.5, color: p.muted),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [heatmap(), gap, legend()],
                ),
              ),
            ],
          ),
        )
      : Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header('阅读日历'),
              gap,
              text(
                '${data.localDay.year} / ${data.localDay.month}',
                small ? 22 : 30,
                weight: FontWeight.w700,
              ),
              const Spacer(),
              if (data.heatmap
                  .window(5)
                  .any((day) => day.verifiedSeconds != null)) ...[
                heatmap(compact: small),
                gap,
                if (!small) legend(),
              ],
              const Spacer(),
              text(
                '截至 ${widgetDate(data.localDay).substring(5).replaceAll('-', '.')}',
                11.5,
                color: p.muted,
              ),
            ],
          ),
        );
  Widget heatmap({bool compact = false}) {
    final days = data.heatmap.window(5);
    return Column(
      children: [
        Row(
          children: [
            for (final label in ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(child: text(label, 9.5, color: p.muted)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < 5; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: column == 6 ? 0 : 4),
                      child: _HeatCell(
                        day: days[row * 7 + column],
                        p: p,
                        height: compact ? 6 : 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget legend() => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      text('少', 10, color: p.muted),
      for (var i = 0; i < 5; i++)
        Container(
          width: 13,
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: p.level(i),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      text('多', 10, color: p.muted),
    ],
  );
  Widget memory() => Padding(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header('阅读纪念'),
        const Spacer(),
        if (data.latestCompletion != null) ...[
          if (data.showBookDetails &&
              (data.latestCompletion!.title?.isNotEmpty ?? false))
            text(
              data.latestCompletion!.title!,
              large ? 28 : 19,
              weight: FontWeight.w800,
              lines: large ? 3 : 2,
            )
          else
            text(
              data.latestCompletion!.finished ? '每一页，都算数。' : '故事未完，阅读继续。',
              large ? 28 : 19,
              weight: FontWeight.w800,
              lines: large ? 3 : 2,
            ),
          gap,
          text(
            widgetDate(data.latestCompletion!.completedAt).replaceAll('-', '.'),
            11.5,
            color: p.muted,
          ),
        ],
        const Spacer(),
        if (!small) SizedBox(height: large ? 150 : 36, child: art(band: true)),
      ],
    ),
  );
  Widget art({required bool band, double zoom = 1}) =>
      _ReferenceArt(skin: skin, date: data.localDay, band: band, zoom: zoom);
}

class ReadingWidgetPalette {
  ReadingWidgetPalette(this.skin, this.date, [this.brightness]);
  final Brightness? brightness;
  bool get dark => brightness == Brightness.dark;
  bool get light => brightness == Brightness.light;
  final ReadingWidgetSkin skin;
  final DateTime date;
  static const seasons = [
    Color(0xFFC98A9E),
    Color(0xFF3F86B8),
    Color(0xFFC58A35),
    Color(0xFF3E8E8E),
  ];
  Color get bg => dark
      ? const Color(0xFF171B21)
      : light &&
            (skin == ReadingWidgetSkin.night || skin == ReadingWidgetSkin.film)
      ? const Color(0xFFF0EEE8)
      : Color(switch (skin) {
          ReadingWidgetSkin.night => 0xFF10141A,
          ReadingWidgetSkin.film => 0xFF0B0B0C,
          ReadingWidgetSkin.paper => 0xFFEBEAE5,
          ReadingWidgetSkin.seasons => 0xFFF4EFE5,
          _ => 0xFFF0EEE8,
        });
  Color get ink => dark
      ? const Color(0xFFF2EFE8)
      : light
      ? const Color(0xFF202329)
      : Color(switch (skin) {
          ReadingWidgetSkin.night || ReadingWidgetSkin.film => 0xFFF2EFE8,
          ReadingWidgetSkin.paper => 0xFF1B1B1B,
          ReadingWidgetSkin.seasons => 0xFF26272B,
          _ => 0xFF17191B,
        });
  Color get muted => dark
      ? const Color(0xFFB0B6BF)
      : light
      ? const Color(0xFF62676B)
      : Color(switch (skin) {
          ReadingWidgetSkin.night => 0xFF8E97A6,
          ReadingWidgetSkin.film => 0xFF928F88,
          ReadingWidgetSkin.paper => 0xFF6C6C68,
          ReadingWidgetSkin.seasons => 0xFF75716A,
          _ => 0xFF62676B,
        });
  Color get accent => skin == ReadingWidgetSkin.seasons
      ? seasons[seasonIndex(date)]
      : Color(switch (skin) {
          ReadingWidgetSkin.night => 0xFFE8A33D,
          ReadingWidgetSkin.film => 0xFFE8B84A,
          ReadingWidgetSkin.paper => 0xFF5E6F5E,
          _ => 0xFF2E8C8A,
        });
  Color get track => dark
      ? const Color(0xFF303740)
      : light
      ? const Color(0xFFDCD9D0)
      : Color(switch (skin) {
          ReadingWidgetSkin.night => 0xFF252C37,
          ReadingWidgetSkin.film => 0xFF272727,
          ReadingWidgetSkin.paper => 0xFFD7D6CF,
          ReadingWidgetSkin.seasons => 0xFFE3DCCD,
          _ => 0xFFDCD9D0,
        });
  Color get bar => dark
      ? const Color(0xFF5D6C72)
      : light
      ? const Color(0xFFB7C8C6)
      : Color(switch (skin) {
          ReadingWidgetSkin.night => 0xFF3B4452,
          ReadingWidgetSkin.film => 0xFF3C3A36,
          ReadingWidgetSkin.paper => 0xFFB9C1B6,
          ReadingWidgetSkin.seasons => 0xFFC6D6D3,
          _ => 0xFFB7C8C6,
        });
  Color get bubble =>
      dark &&
          (skin == ReadingWidgetSkin.seasons || skin == ReadingWidgetSkin.paper)
      ? const Color(0xF0262D35)
      : Color(switch (skin) {
          ReadingWidgetSkin.seasons => 0xFFFFFAF0,
          ReadingWidgetSkin.paper => 0xFFFBFAF6,
          ReadingWidgetSkin.film => 0xBD000000,
          ReadingWidgetSkin.night => 0xD60E1218,
          _ => 0xDE101418,
        });
  Color get bubbleInk =>
      skin == ReadingWidgetSkin.seasons || skin == ReadingWidgetSkin.paper
      ? ink
      : const Color(0xFFF4F2EC);
  Color level(int level) => level == 0
      ? track
      : Color.lerp(track, accent, [0.0, .3, .55, .78, 1.0][level])!;
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({required this.day, required this.p, required this.height});
  final ReadingWidgetDay day;
  final ReadingWidgetPalette p;
  final double height;
  @override
  Widget build(BuildContext context) {
    final level = readingWidgetHeatLevel(day.verifiedSeconds);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: level == null ? null : p.level(level),
        border: level == null
            ? Border.all(color: p.muted.withValues(alpha: .5), width: .6)
            : null,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _ReferenceArt extends StatelessWidget {
  const _ReferenceArt({
    required this.skin,
    required this.date,
    required this.band,
    required this.zoom,
  });
  final ReadingWidgetSkin skin;
  final DateTime date;
  final bool band;
  final double zoom;
  String get asset =>
      'assets/report/${switch (skin) {
        ReadingWidgetSkin.seasons => 'char_season_${['spring', 'summer', 'autumn', 'winter'][seasonIndex(date)]}',
        ReadingWidgetSkin.night => band ? 'char_night_roof' : 'char_night_desk',
        ReadingWidgetSkin.film => band ? 'char_pv_open' : 'char_pv_train',
        ReadingWidgetSkin.paper => 'char_papercut',
        _ => 'char_cover',
      }}.webp';
  @override
  Widget build(BuildContext context) {
    final landscape =
        skin == ReadingWidgetSkin.seasons || skin == ReadingWidgetSkin.film;
    final ratio = landscape
        ? 1080 / 608
        : skin == ReadingWidgetSkin.night
        ? 427 / 760
        : 570 / 760;
    final focus = switch (skin) {
      ReadingWidgetSkin.seasons => switch (seasonIndex(date)) {
        0 => const Offset(.67, .28),
        1 => const Offset(.66, .28),
        2 => const Offset(.70, .27),
        _ => const Offset(.70, .28),
      },
      ReadingWidgetSkin.night =>
        band ? const Offset(.32, .44) : const Offset(.62, .45),
      ReadingWidgetSkin.film =>
        band ? const Offset(.57, .3) : const Offset(.64, .21),
      ReadingWidgetSkin.paper =>
        band ? const Offset(.64, .34) : const Offset(.64, .21),
      _ => const Offset(.68, .18),
    };
    return LayoutBuilder(
      builder: (context, bounds) {
        final scale =
            math.max(bounds.maxWidth / ratio, bounds.maxHeight) * zoom;
        final width = scale * ratio, height = scale;
        final x = (bounds.maxWidth * .5 - focus.dx * width).clamp(
          bounds.maxWidth - width,
          0.0,
        );
        final y = (bounds.maxHeight * (band ? .3 : .38) - focus.dy * height)
            .clamp(bounds.maxHeight - height, 0.0);
        return ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: x,
                top: y,
                width: width,
                height: height,
                child: Image.asset(asset, fit: BoxFit.fill, cacheWidth: 1080),
              ),
              if (skin == ReadingWidgetSkin.paper)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PaperEdge(
                      band,
                      ReadingWidgetPalette(skin, date).bg,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PaperEdge extends CustomPainter {
  const _PaperEdge(this.band, this.color);
  final bool band;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final points = band
        ? const [
            Offset(0, .55),
            Offset(.05, .2),
            Offset(.11, .65),
            Offset(.17, .3),
            Offset(.24, .75),
            Offset(.31, .25),
            Offset(.38, .6),
            Offset(.45, .15),
            Offset(.52, .7),
            Offset(.59, .35),
            Offset(.66, .8),
            Offset(.73, .3),
            Offset(.8, .65),
            Offset(.87, .2),
            Offset(.94, .6),
            Offset(1, .3),
            Offset(1, 1),
            Offset(0, 1),
          ]
        : const [
            Offset(.4, 0),
            Offset(1, 0),
            Offset(1, 1),
            Offset(.3, 1),
            Offset(.75, .92),
            Offset(.2, .84),
            Offset(.7, .76),
            Offset(.25, .66),
            Offset(.8, .57),
            Offset(.3, .48),
            Offset(.7, .4),
            Offset(.2, .3),
            Offset(.75, .21),
            Offset(.3, .12),
          ];
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = band
          ? points[i].dx * size.width
          : size.width - 10 + points[i].dx * 10;
      final y = band
          ? size.height - 11 + points[i].dy * 11
          : points[i].dy * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PaperEdge old) => old.band != band || old.color != color;
}

class _ReferenceDecoration extends CustomPainter {
  _ReferenceDecoration(
    this.p,
    this.skin,
    this.small,
    this.design,
    this.season,
    this.font,
  );
  final ReadingWidgetPalette p;
  final ReadingWidgetSkin skin;
  final bool small;
  final ReadingWidgetDesign design;
  final String season;
  final String? font;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = p.accent;
    if (skin == ReadingWidgetSkin.seasons) {
      for (var i = 0; i < 4; i++) {
        paint.color = ReadingWidgetPalette.seasons[i];
        canvas.drawRect(
          Rect.fromLTWH(size.width * i / 4, size.height - 5, size.width / 4, 5),
          paint,
        );
      }
      if (small) {
        final label = TextPainter(
          text: TextSpan(
            text: season,
            style: TextStyle(
              fontFamily: font,
              fontSize: 58,
              height: 1,
              fontWeight: FontWeight.w900,
              color: p.accent.withValues(alpha: .12),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(size.width - label.width - 10, 4));
      }
    } else if (skin == ReadingWidgetSkin.archive) {
      canvas.drawRect(Rect.fromLTWH(0, 0, 4, size.height), paint);
      if (small && design == ReadingWidgetDesign.focus) {
        paint.color = p.ink.withValues(alpha: .5);
        for (var x = size.width - 48; x < size.width - 14; x += 3) {
          canvas.drawRect(Rect.fromLTWH(x, size.height - 30, 1, 14), paint);
        }
      }
    } else if (skin == ReadingWidgetSkin.film) {
      paint.color = const Color(0xFF050505);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 11), paint);
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - 11, size.width, 11),
        paint,
      );
      paint.color = p.ink.withValues(alpha: .82);
      for (var x = 6.0; x < size.width; x += 18) {
        canvas.drawRect(Rect.fromLTWH(x, 3, 6, 5), paint);
        canvas.drawRect(Rect.fromLTWH(x, size.height - 8, 6, 5), paint);
      }
    } else if (skin == ReadingWidgetSkin.night && small) {
      canvas.drawCircle(Offset(size.width - 24, 24), 8, paint);
      paint.color = p.bg;
      canvas.drawCircle(Offset(size.width - 19, 21), 8, paint);
      paint.color = p.ink.withValues(alpha: .07);
      for (var i = 0; i < 8; i++) {
        canvas.drawRect(
          Rect.fromLTWH(
            i * size.width / 8,
            size.height - 10 - (i % 3) * 6,
            size.width / 11,
            24,
          ),
          paint,
        );
      }
    } else if (skin == ReadingWidgetSkin.paper) {
      paint.color = const Color(0xFFA9B3A6).withValues(alpha: .9);
      canvas.save();
      canvas.translate(size.width - 31, 2);
      canvas.rotate(.14);
      canvas.drawRect(const Rect.fromLTWH(-13, -10, 26, 20), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ReferenceDecoration old) =>
      old.skin != skin ||
      old.small != small ||
      old.design != design ||
      old.season != season ||
      old.font != font;
}
