import 'dart:convert';
import 'package:flutter/painting.dart';
import 'package:characters/characters.dart';
import 'reader_coordinate_map.dart';
import 'reader_block_spacing.dart';
import 'reader_languages.dart';

class ReaderRuby {
  const ReaderRuby(this.start, this.end, this.text);
  final int start, end;
  final String text;
  Map<String, Object> toJson() => {'start': start, 'end': end, 'text': text};
}

class ReaderNoteReference {
  const ReaderNoteReference(this.start, this.end, this.id);
  final int start, end;
  final String id;
  Map<String, Object> toJson() => {'start': start, 'end': end, 'id': id};
}

class ReaderEmphasis {
  const ReaderEmphasis(this.start, this.end, this.mask);
  final int start, end, mask;
  Map<String, int> toJson() => {'start': start, 'end': end, 'mask': mask};
}

class ReaderRichParagraph {
  const ReaderRichParagraph({
    this.alignment = '',
    this.writing = '',
    this.rule = false,
    this.ruby = const [],
    this.references = const [],
    this.emphasis = const [],
    this.breakBefore = false,
    this.breakAfter = false,
    this.spacing = const ReaderBlockSpacing(),
    this.language = '',
    this.opacity = 1,
  });
  final String alignment, writing;
  final bool rule;
  final List<ReaderRuby> ruby;
  final List<ReaderNoteReference> references;
  final List<ReaderEmphasis> emphasis;
  final bool breakBefore, breakAfter;
  final ReaderBlockSpacing spacing;
  final String language;
  final double opacity;
  ReaderRichParagraph withReferences(List<ReaderNoteReference> value) =>
      ReaderRichParagraph(
        alignment: alignment,
        writing: writing,
        rule: rule,
        ruby: ruby,
        references: value,
        emphasis: emphasis,
        breakBefore: breakBefore,
        breakAfter: breakAfter,
        spacing: spacing,
        language: language,
        opacity: opacity,
      );
  ReaderRichParagraph withBreaks({bool before = false, bool after = false}) =>
      ReaderRichParagraph(
        alignment: alignment,
        writing: writing,
        rule: rule,
        ruby: ruby,
        references: references,
        emphasis: emphasis,
        breakBefore: breakBefore || before,
        breakAfter: breakAfter || after,
        spacing: spacing,
        language: language,
        opacity: opacity,
      );
  ReaderRichParagraph withSpacing(ReaderBlockSpacing value) =>
      ReaderRichParagraph(
        alignment: alignment,
        writing: writing,
        rule: rule,
        ruby: ruby,
        references: references,
        emphasis: emphasis,
        breakBefore: breakBefore,
        breakAfter: breakAfter,
        spacing: spacing.merge(value),
        language: language,
        opacity: opacity,
      );
  ReaderRichParagraph replaceSpacing(ReaderBlockSpacing value) =>
      ReaderRichParagraph(
        alignment: alignment,
        writing: writing,
        rule: rule,
        ruby: ruby,
        references: references,
        emphasis: emphasis,
        breakBefore: breakBefore,
        breakAfter: breakAfter,
        spacing: value,
        language: language,
        opacity: opacity,
      );
  ReaderRichParagraph withPublisherLanguage(ReaderRichParagraph value) =>
      ReaderRichParagraph(
        alignment: alignment,
        writing: writing,
        rule: rule,
        ruby: ruby,
        references: references,
        emphasis: emphasis,
        breakBefore: breakBefore,
        breakAfter: breakAfter,
        spacing: spacing,
        language: value.language,
        opacity: value.opacity,
      );
  ReaderRichParagraph get withoutSpacing =>
      spacing.empty ? this : replaceSpacing(const ReaderBlockSpacing());
  double gapBefore(
    ReaderRichParagraph? previous, {
    required double font,
    required double lineHeight,
    required double width,
    required double defaultGap,
  }) => spacing.gapBefore(
    previous?.spacing,
    font: font,
    lineHeight: lineHeight,
    width: width,
    defaultGap: defaultGap,
  );
  bool get allowsIndent =>
      !const {'center', 'right', 'end'}.contains(alignment);
  bool get empty =>
      alignment.isEmpty &&
      writing.isEmpty &&
      !rule &&
      ruby.isEmpty &&
      references.isEmpty &&
      emphasis.isEmpty &&
      !breakBefore &&
      !breakAfter &&
      spacing.empty &&
      language.isEmpty &&
      opacity == 1;
  int emphasisAt(int offset) {
    var mask = 0;
    for (final run in emphasis) {
      if (run.start <= offset && offset < run.end) mask |= run.mask;
    }
    return mask;
  }

  static TextStyle emphasized(TextStyle base, int mask) => mask == 0
      ? base
      : base.copyWith(
          fontWeight: mask & 1 != 0 ? FontWeight.w700 : base.fontWeight,
          fontStyle: mask & 2 != 0 ? FontStyle.italic : base.fontStyle,
          decoration: mask & 4 != 0
              ? TextDecoration.underline
              : base.decoration,
        );
  List<InlineSpan> spans(String text) {
    if (emphasis.isEmpty) return [TextSpan(text: text)];
    final boundaries = <int>{
      0,
      text.length,
      for (final run in emphasis) ...[
        run.start.clamp(0, text.length),
        run.end.clamp(0, text.length),
      ],
    }.toList()..sort();
    return [
      for (var i = 0; i < boundaries.length - 1; i++)
        TextSpan(
          text: text.substring(boundaries[i], boundaries[i + 1]),
          style: emphasized(const TextStyle(), emphasisAt(boundaries[i])),
        ),
    ];
  }

  TextAlign textAlign(TextAlign fallback) => switch (alignment) {
    'right' || 'end' => TextAlign.end,
    'center' => TextAlign.center,
    'left' || 'start' => TextAlign.start,
    'justify' => TextAlign.justify,
    _ => fallback,
  };
  TextStyle textStyle(TextStyle original) {
    final ink = opacity == 1 || original.color == null
        ? original
        : original.copyWith(
            color: original.color!.withValues(
              alpha: original.color!.a * opacity,
            ),
          );
    return ruby.isEmpty
        ? ink
        : ink.copyWith(
            // CJK fonts can have taller ink than their nominal font size. Ruby
            // needs real leading above the base, shared by paint and pagination.
            height: (original.height ?? 1.72) < 2.5 ? 2.5 : original.height,
            leadingDistribution: TextLeadingDistribution.proportional,
          );
  }

  Map<String, Object> toJson() => {
    if (language.isNotEmpty) 'lang': language,
    if (opacity != 1) 'opacity': opacity,
    if (alignment.isNotEmpty) 'align': alignment,
    if (writing.isNotEmpty) 'writing': writing,
    if (rule) 'rule': true,
    if (breakBefore) 'breakBefore': true,
    if (breakAfter) 'breakAfter': true,
    if (!spacing.empty) 'spacing': spacing.toJson(),
    if (emphasis.isNotEmpty)
      'emphasis': emphasis.map((r) => r.toJson()).toList(),
    if (ruby.isNotEmpty) 'ruby': ruby.map((r) => r.toJson()).toList(),
    if (references.isNotEmpty)
      'refs': references.map((r) => r.toJson()).toList(),
  };
  ReaderRichParagraph slice(int start, int end) => ReaderRichParagraph(
    alignment: alignment,
    writing: writing,
    language: language,
    opacity: opacity,
    rule: rule,
    breakBefore: breakBefore && start == 0,
    breakAfter: breakAfter,
    spacing: ReaderBlockSpacing(
      before: start == 0 ? spacing.before : const [],
      leading: start == 0 ? spacing.leading : const [],
      after: spacing.after,
      trailing: spacing.trailing,
    ),
    emphasis: [
      for (final r in emphasis)
        if (r.start < end && r.end > start)
          ReaderEmphasis(
            (r.start - start).clamp(0, end - start),
            (r.end - start).clamp(0, end - start),
            r.mask,
          ),
    ],
    ruby: [
      for (final r in ruby)
        if (r.start < end && r.end > start)
          ReaderRuby(
            (r.start - start).clamp(0, end - start),
            (r.end - start).clamp(0, end - start),
            rubyPart(r, start, end),
          ),
    ],
    references: [
      for (final r in references)
        if (r.start < end && r.end > start)
          ReaderNoteReference(
            (r.start - start).clamp(0, end - start),
            (r.end - start).clamp(0, end - start),
            r.id,
          ),
    ],
  );
  static String rubyPart(ReaderRuby ruby, int start, int end) {
    final letters = ruby.text.characters.toList();
    final a =
        (((start - ruby.start).clamp(0, ruby.end - ruby.start)) /
                (ruby.end - ruby.start) *
                letters.length)
            .floor();
    final b =
        (((end - ruby.start).clamp(0, ruby.end - ruby.start)) /
                (ruby.end - ruby.start) *
                letters.length)
            .floor();
    return letters.sublist(a, b).join();
  }

  factory ReaderRichParagraph.fromJson(Map value, int length) {
    bool range(Map r) =>
        r['start'] is int &&
        r['end'] is int &&
        r['start'] >= 0 &&
        r['end'] > r['start'] &&
        r['end'] <= length;
    return ReaderRichParagraph(
      alignment: '${value['align'] ?? ''}',
      writing: '${value['writing'] ?? ''}',
      language: readerLanguageCode('${value['lang'] ?? ''}'),
      opacity:
          value['opacity'] is num &&
              (value['opacity'] as num).isFinite &&
              value['opacity'] >= 0 &&
              value['opacity'] <= 1
          ? (value['opacity'] as num).toDouble()
          : 1,
      rule: value['rule'] == true,
      breakBefore: value['breakBefore'] == true,
      breakAfter: value['breakAfter'] == true,
      spacing: ReaderBlockSpacing.fromJson(value['spacing']),
      emphasis: [
        for (final r
            in value['emphasis'] is List ? value['emphasis'] as List : const [])
          if (r is Map &&
              range(r) &&
              r['mask'] is int &&
              r['mask'] >= 0 &&
              r['mask'] <= 7)
            ReaderEmphasis(r['start'], r['end'], r['mask']),
      ],
      ruby: [
        for (final r
            in value['ruby'] is List ? value['ruby'] as List : const [])
          if (r is Map &&
              range(r) &&
              r['text'] is String &&
              r['text'].length <= 2000)
            ReaderRuby(r['start'], r['end'], r['text']),
      ],
      references: [
        for (final r
            in value['refs'] is List ? value['refs'] as List : const [])
          if (r is Map && range(r) && r['id'] is String)
            ReaderNoteReference(r['start'], r['end'], r['id']),
      ],
    );
  }
}

/// Optional local EPUB metadata. Body coordinates are always plain UTF-16 text;
/// annotations never become copied text, speech, or an extra paragraph.
class ReaderRichBody {
  const ReaderRichBody(
    this.paragraphs, {
    this.formats = const {},
    this.notes = const {},
    this.revision = '',
    this.coordinateMap,
  });
  static const prefix = '<!--reader-rich-v1:';
  final List<String> paragraphs;
  final Map<int, ReaderRichParagraph> formats;
  final Map<String, String> notes;
  final String revision;
  final ReaderCoordinateMap? coordinateMap;
  String encode() {
    if (paragraphs.isEmpty) return '';
    final body = paragraphs.join('\n\n');
    if (formats.isEmpty &&
        notes.isEmpty &&
        revision.isEmpty &&
        coordinateMap == null) {
      return body;
    }
    final meta = jsonEncode({
      'count': paragraphs.length,
      'blocks': {for (final e in formats.entries) '${e.key}': e.value.toJson()},
      'notes': notes,
      if (revision.isNotEmpty) 'revision': revision,
      if (coordinateMap != null) 'coordinates': coordinateMap!.toJson(),
    });
    return '$body\n\n$prefix${base64Url.encode(utf8.encode(meta))}-->';
  }

  static ReaderRichBody decode(String source) {
    if (!source.contains(prefix)) return ReaderRichBody(source.split('\n\n'));
    final paragraphs = <String>[],
        formats = <int, ReaderRichParagraph>{},
        notes = <String, String>{};
    var revision = '';
    ReaderCoordinateMap? coordinates;
    for (final part in source.split('\n\n')) {
      if (!part.startsWith(prefix) || !part.endsWith('-->')) {
        paragraphs.add(part);
        continue;
      }
      final value = jsonDecode(
        utf8.decode(
          base64Url.decode(part.substring(prefix.length, part.length - 3)),
        ),
      );
      if (value is! Map ||
          value['count'] is! int ||
          value['count'] > paragraphs.length ||
          value['count'] < 0 ||
          value['blocks'] is! Map ||
          value['notes'] is! Map) {
        throw const FormatException('原书排版数据格式有误');
      }
      final base = paragraphs.length - (value['count'] as int);
      revision = value['revision'] is String
          ? value['revision']
          : 'epub-rich-v1';
      if (value['coordinates'] != null) {
        coordinates = ReaderCoordinateMap.fromJson(
          value['coordinates'],
          paragraphs.join('\n\n').length,
        );
      }
      for (final e in (value['blocks'] as Map).entries) {
        final index = int.tryParse('${e.key}');
        if (index != null &&
            index >= 0 &&
            base + index < paragraphs.length &&
            e.value is Map) {
          formats[base + index] = ReaderRichParagraph.fromJson(
            e.value,
            paragraphs[base + index].length,
          );
        }
      }
      for (final e in (value['notes'] as Map).entries) {
        if (e.key is String && e.value is String && e.value.length <= 32000) {
          notes[e.key] = e.value;
        }
      }
    }
    return ReaderRichBody(
      paragraphs,
      formats: formats,
      notes: notes,
      revision: revision,
      coordinateMap: coordinates,
    );
  }
}
