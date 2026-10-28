import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'reading_report_options.dart';
import 'reading_report_components.dart';
import 'reading_statistics_data.dart';
import 'reading_report_insights.dart';
import 'reading_visual_theme.dart';
import 'reading_analysis_charts.dart';
import 'reading_report_reference_assets.dart';
import 'reading_export_theme.dart';

part 'reading_report_composition.dart';
part 'reading_report_plate.dart';
part 'reading_report_print.dart';
part 'reading_report_analysis_print.dart';
part 'reading_report_art_direction.dart';
part 'reading_report_reference.dart';
part 'reading_report_papercut_255.dart';
part 'reading_report_dossier_night_255.dart';
part 'reading_report_seasons_film_255.dart';
part 'reading_report_landscape_travel_255.dart';
part 'reading_report_dimension_print.dart';
part 'reading_report_calendar_257.dart';

class ReadingReportCaptureSpec {
  const ReadingReportCaptureSpec({
    required this.monthlySize,
    required this.progressSize,
    required this.calendarWidth,
    this.progressLabelSize = 13,
    this.invertProgress = false,
    this.ringSize = const Size(260, 260),
    this.coverSize = const Size(148, 208),
    this.captureMonthly = true,
    this.captureRing = true,
    this.captureCalendar = true,
    this.captureProgress = true,
    this.captureBookCovers = true,
  });
  final Size monthlySize, progressSize, ringSize, coverSize;
  final double calendarWidth, progressLabelSize;
  final bool invertProgress;
  final bool captureMonthly;
  final bool captureRing;
  final bool captureCalendar;
  final bool captureProgress;
  final bool captureBookCovers;
}

ReadingReportCaptureSpec readingReportCaptureSpec(
  ReadingReportOptions options,
) => ReadingReportCaptureSpec(
  monthlySize: const Size(536, 145),
  captureMonthly: false,
  calendarWidth: 536,
  progressSize: Size(switch (options.template) {
    ReadingReportTemplate.archive => 362,
    ReadingReportTemplate.ink => 460,
    ReadingReportTemplate.festival => 504,
    _ => 536,
  }, 146),
  coverSize: const Size(34, 48),
  captureRing: false,
  captureCalendar: false,
  captureProgress: const {
    ReadingReportTemplate.archive,
    ReadingReportTemplate.ink,
    ReadingReportTemplate.festival,
  }.contains(options.template),
  captureBookCovers: options.template == ReadingReportTemplate.archive,
);

class ReadingReportDuration {
  const ReadingReportDuration({
    required this.observed,
    required this.value,
    required this.unit,
    required this.shortUnit,
    this.remainder,
    this.remainderUnit,
  });
  final bool observed;
  final String value, unit, shortUnit;
  final String? remainder, remainderUnit;
  String get label => !observed
      ? '尚未记录'
      : '$value$unit${remainder == null ? '' : ' $remainder$remainderUnit'}';
  String get compact => observed ? '$value $shortUnit' : '—';
}

ReadingReportDuration readingReportDuration(
  int seconds, {
  required bool observed,
}) {
  if (!observed) {
    return const ReadingReportDuration(
      observed: false,
      value: '—',
      unit: '',
      shortUnit: '',
    );
  }
  if (seconds >= 3600) {
    return ReadingReportDuration(
      observed: true,
      value: '${seconds ~/ 3600}',
      unit: '小时',
      shortUnit: 'h',
      remainder: '${seconds ~/ 60 % 60}',
      remainderUnit: seconds % 60 == 0 ? '分钟' : '分钟 ${seconds % 60}秒',
    );
  }
  if (seconds >= 60) {
    return ReadingReportDuration(
      observed: true,
      value: '${seconds ~/ 60}',
      unit: '分钟',
      shortUnit: 'min',
      remainder: seconds % 60 == 0 ? null : '${seconds % 60}',
      remainderUnit: seconds % 60 == 0 ? null : '秒',
    );
  }
  return ReadingReportDuration(
    observed: true,
    value: '$seconds',
    unit: '秒',
    shortUnit: 's',
  );
}

class ReadingReportColors {
  ReadingReportColors.surface({
    required this.background,
    required this.ink,
    required this.muted,
    required this.accent,
  });

  ReadingReportColors(ReadingReportOptions options) {
    final base = readingExportTheme(options.template.theme);
    background = base.background;
    ink = base.foreground;
    muted = base.muted;
    final night = isDark;
    accent = switch (options.palette) {
      ReadingReportPalette.pine => base.accent,
      ReadingReportPalette.vermilion =>
        night ? const Color(0xffe7b4a4) : const Color(0xffa94d38),
      ReadingReportPalette.blue =>
        night ? const Color(0xffb8cce6) : const Color(0xff456b94),
      ReadingReportPalette.plum =>
        night ? const Color(0xffdac5df) : const Color(0xff896489),
    };
  }
  late final Color background, ink, muted, accent;
  bool get isDark => background.computeLuminance() < .15;
}

({int width, int height}) readingReportPixelSize(
  double height, {
  int preferredWidth = 1080,
}) {
  final scale = [
    preferredWidth / ReadingReportLayout.width,
    4096 / ReadingReportLayout.width,
    8192 / height,
    math.sqrt(12000000 / (ReadingReportLayout.width * height)),
  ].reduce(math.min);
  return (
    width: math.max(1, (ReadingReportLayout.width * scale).floor()),
    height: math.max(1, (height * scale).floor()),
  );
}

/// One complete drawing powers the editor, zoom preview and bounded PNG.
class ReadingReportLayout {
  ReadingReportLayout._({
    required this.picture,
    required this.height,
    required this.colors,
    required this.options,
    required this.labels,
    required this.sections,
    Map<ReadingReportModule, List<Rect>>? sectionFragments,
    Set<ReadingReportModule>? visibleModules,
    this.components,
  }) : visibleModules = Set.unmodifiable(visibleModules ?? options.modules),
       sectionFragments = Map.unmodifiable({
         for (final entry
             in (sectionFragments ??
                     {
                       for (final entry in sections.entries)
                         entry.key: [entry.value],
                     })
                 .entries)
           entry.key: List<Rect>.unmodifiable(entry.value),
       });
  static const width = 600.0;
  final ui.Picture picture;
  final double height;
  final ReadingReportColors colors;
  final ReadingReportOptions options;
  final List<String> labels;
  final Map<ReadingReportModule, Rect> sections;

  /// Real painted fragments; [sections] remains each class's first location.
  final Map<ReadingReportModule, List<Rect>> sectionFragments;
  final Set<ReadingReportModule> visibleModules;
  final ReadingReportComponents? components;
  // A layout is one rendered snapshot. Save followed by share must not rasterize
  // and encode its same multi-megapixel picture again. Only a successful bounded
  // PNG is retained, and callers receive independent mutable byte buffers.
  Future<Uint8List>? _pngEncoding;
  List<({ReadingReportModule module, String title, Rect bounds})> get contents {
    final ordered = sections.entries.toList()
      ..sort((a, b) {
        final row = a.value.top.compareTo(b.value.top);
        return row == 0 ? a.value.left.compareTo(b.value.left) : row;
      });
    return [
      for (final entry in ordered)
        (module: entry.key, title: entry.key.label, bounds: entry.value),
    ];
  }

  bool get hasCompleteContents {
    if (sections.length != visibleModules.length) return false;
    if (sectionFragments.length != visibleModules.length) return false;
    if (!visibleModules.every((module) {
      final bounds = sections[module];
      final pieces = sectionFragments[module];
      return bounds != null &&
          pieces != null &&
          pieces.isNotEmpty &&
          bounds == pieces.first &&
          pieces.every(
            (bounds) =>
                !bounds.isEmpty &&
                bounds.top >= 0 &&
                bounds.bottom <= height &&
                bounds.left >= 0 &&
                bounds.right <= width,
          );
    })) {
      return false;
    }
    final rectangles = sectionFragments.values
        .expand((pieces) => pieces)
        .toList();
    for (var i = 0; i < rectangles.length; i++) {
      for (var j = i + 1; j < rectangles.length; j++) {
        if (rectangles[i].overlaps(rectangles[j])) return false;
      }
    }
    return true;
  }

  ({int width, int height}) get pixelSize => readingReportPixelSize(height);
  factory ReadingReportLayout.prepare(
    ReadingStatisticsData data,
    ReadingReportOptions options, {
    String Function(String)? translate,
    ReadingReportComponents? components,
    ReadingReportInsights? insights,
  }) {
    final text = translate ?? (String value) => value;
    final composer = switch (options.template) {
      ReadingReportTemplate.archive => _ArchivePosterComposer(
        data,
        options,
        text,
        components,
      ),
      ReadingReportTemplate.constellation => _NightPosterComposer(
        data,
        options,
        text,
        components,
      ),
      ReadingReportTemplate.editorial => _SeasonPosterComposer(
        data,
        options,
        text,
        components,
      ),
      ReadingReportTemplate.score => _FilmPosterComposer(
        data,
        options,
        text,
        components,
      ),
      ReadingReportTemplate.signal => _PaperCutPosterComposer(
        data,
        options,
        text,
        components,
      ),
      ReadingReportTemplate.shelf => _HarborPosterComposer(
        data,
        options,
        text,
        components,
      ),
      ReadingReportTemplate.ink => _MountainPosterComposer(
        data,
        options,
        text,
        components,
      ),
      ReadingReportTemplate.festival => _TravelPosterComposer(
        data,
        options,
        text,
        components,
      ),
    };
    composer.insights = insights ?? ReadingReportInsights.from(data);
    return composer.compose();
  }
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / width, size.height / height);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = colors.background,
    );
    canvas.drawPicture(picture);
    canvas.restore();
  }

  Future<Uint8List> png() async {
    if (components == null) throw const FormatException('报告组件尚未准备完成，请重新打开预览');
    if (components!.art == null) {
      throw const FormatException('主题插画尚未准备完成，请重新打开预览');
    }
    if (!hasCompleteContents) {
      throw const FormatException('所选报告内容未完整生成，请重新预览后保存');
    }
    final pending = _pngEncoding ??= _encodePng();
    try {
      return Uint8List.fromList(await pending);
    } catch (_) {
      if (identical(_pngEncoding, pending)) _pngEncoding = null;
      rethrow;
    }
  }

  Future<Uint8List> _encodePng() async {
    final pixels = pixelSize;
    final recorder = ui.PictureRecorder();
    paint(
      Canvas(recorder),
      Size(pixels.width.toDouble(), pixels.height.toDouble()),
    );
    final drawing = recorder.endRecording();
    late ui.Image image;
    try {
      image = await drawing.toImage(pixels.width, pixels.height);
    } finally {
      drawing.dispose();
    }
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw const FormatException('图片生成失败，请重试');
      final result = bytes.buffer.asUint8List();
      if (result.length > 12 * 1024 * 1024) {
        throw const FormatException('图片超过保存上限，请减少报告模块后重试');
      }
      return result;
    } finally {
      image.dispose();
    }
  }

  void dispose() {
    _pngEncoding = null;
    picture.dispose();
    components?.dispose();
  }
}

class ReadingReportPainter extends CustomPainter {
  const ReadingReportPainter(this.layout);
  final ReadingReportLayout layout;
  @override
  void paint(Canvas canvas, Size size) => layout.paint(canvas, size);
  @override
  bool shouldRepaint(ReadingReportPainter oldDelegate) =>
      layout != oldDelegate.layout;
}
