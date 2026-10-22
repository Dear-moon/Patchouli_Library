import 'dart:convert';
import 'dart:io';
import 'catalog.dart';
import 'local_import_options.dart';
import 'local_text_rules.dart';

final localTextChapterPattern = RegExp(
  defaultLocalChapterRule,
  caseSensitive: false,
);
final localTextVolumePattern = RegExp(
  defaultLocalVolumeRule,
  caseSensitive: false,
);

/// Even a book with no newline keeps only a bounded physical-line fragment.
/// Decoder preserves UTF-8 sequences; fragment boundaries preserve surrogates.
typedef LocalTextLine = ({String text, bool heading, int start, int end});

Stream<LocalTextLine> localTextLines(
  Stream<String> chunks, {
  int offset = 0,
  bool removeBom = true,
}) async* {
  var tail = '', split = false, first = true;
  var position = offset, tailStart = offset;
  await for (var chunk in chunks) {
    if (first) {
      if (chunk.isEmpty) continue;
      if (removeBom && chunk.startsWith('\uFEFF')) {
        chunk = chunk.substring(1);
        position++;
        tailStart++;
      }
      first = false;
    }
    var start = 0;
    for (final end in [
      ...RegExp(r'[\r\n]').allMatches(chunk).map((m) => m.start),
      chunk.length,
    ]) {
      final value = tail + chunk.substring(start, end);
      final valueStart = tail.isEmpty ? position + start : tailStart;
      var at = 0;
      while (value.length - at > 4000) {
        var next = at + 4000;
        final last = value.codeUnitAt(next - 1);
        if (last >= 0xd800 && last <= 0xdbff) next--;
        yield (
          text: value.substring(at, next),
          heading: false,
          start: valueStart + at,
          end: valueStart + next,
        );
        at = next;
        split = true;
      }
      tail = value.substring(at);
      tailStart = valueStart + at;
      if (end < chunk.length) {
        yield (
          text: tail,
          heading: !split,
          start: tailStart,
          end: position + end,
        );
        tail = '';
        split = false;
      }
      start = end + 1;
    }
    position += chunk.length;
  }
  if (tail.isNotEmpty) {
    yield (text: tail, heading: !split, start: tailStart, end: position);
  }
}

Stream<({String text, int heading, int start, int end})> _classified(
  Stream<String> chunks,
  LocalImportOptions options,
) async* {
  if (!options.customToc) {
    await for (final line in localTextLines(chunks)) {
      final text = line.text.trim();
      if (text.isEmpty) continue;
      final eligible = line.heading && text.length <= 90;
      yield (
        text: text,
        start: line.start,
        end: line.end,
        heading: !eligible
            ? localHeadingNone
            : localTextVolumePattern.hasMatch(text)
            ? localHeadingVolume
            : localTextChapterPattern.hasMatch(text)
            ? localHeadingChapter
            : localHeadingNone,
      );
    }
    return;
  }
  final matcher = await LocalTextRuleMatcher.start(options);
  final batch = <LocalTextLine>[];
  Future<List<({String text, int heading, int start, int end})>> match() async {
    final matches = await matcher.classify([
      for (final line in batch)
        line.heading && line.text.length <= 90 ? line.text : '',
    ]);
    return [
      for (var i = 0; i < batch.length; i++)
        (
          text: batch[i].text,
          heading: matches[i],
          start: batch[i].start,
          end: batch[i].end,
        ),
    ];
  }

  try {
    await for (final line in localTextLines(chunks)) {
      final text = line.text.trim();
      if (text.isEmpty) continue;
      batch.add((
        text: text,
        heading: line.heading,
        start: line.start,
        end: line.end,
      ));
      if (batch.length == 128) {
        for (final result in await match()) {
          yield result;
        }
        batch.clear();
      }
    }
    if (batch.isNotEmpty) {
      for (final result in await match()) {
        yield result;
      }
    }
  } finally {
    await matcher.close();
  }
}

/// Called inside the import worker; emits each chapter straight to staging.
Future<List<NovelChapter>> importTextChapters(
  File file,
  String name,
  void Function(int index, String body) save, {
  LocalImportOptions options = const LocalImportOptions(),
}) async => (await indexTextChapters(
  file.openRead().transform(utf8.decoder),
  name,
  options: options,
  save: save,
)).chapters;

/// Linked TXT stores only ranges into the unchanged decoded source. Both modes
/// share directory parsing so chapter IDs and paragraph coordinates agree.
Future<({List<NovelChapter> chapters, List<List<int>> ranges})>
indexTextChapters(
  Stream<String> chunks,
  String name, {
  LocalImportOptions options = const LocalImportOptions(),
  void Function(int index, String body)? save,
}) async {
  final chapters = <NovelChapter>[];
  final ranges = <List<int>>[];
  final paragraphs = <String>[];
  var length = 0, volume = '', volumeId = 0, part = 0;
  var rangeStart = 0, rangeEnd = 0;
  var hasTitle = false;
  var title = name
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceFirst(RegExp(r'\.txt$', caseSensitive: false), '');
  if (title.length > 2048) title = title.substring(0, 2048);
  void flush() {
    if (length == 0) return;
    if (chapters.length >= 10000) {
      throw const FormatException('TXT 章节超过 10000 个，请拆分原书后导入');
    }
    final displayTitle = hasTitle || options.autoTitles ? title : '正文';
    chapters.add(
      NovelChapter(
        part == 0 ? displayTitle : '$displayTitle · 片段 ${part + 1}',
        '',
        id: chapters.length + 1,
        volumeTitle: volume,
        volumeId: volumeId,
      ),
    );
    ranges.add([rangeStart, rangeEnd]);
    save?.call(chapters.length, paragraphs.join('\n\n'));
    part++;
    length = 0;
    paragraphs.clear();
  }

  await for (final line in _classified(chunks, options)) {
    final value = line.text;
    if (line.heading == localHeadingVolume) {
      flush();
      volume = value;
      volumeId++;
      title = value;
      hasTitle = true;
      part = 0;
    } else if (line.heading == localHeadingChapter) {
      flush();
      title = value;
      hasTitle = true;
      part = 0;
    } else {
      if (length == 0) rangeStart = line.start;
      rangeEnd = line.end;
      if (save != null) paragraphs.add(value);
      length += value.length + 2;
      if (length >= 100000) flush();
    }
  }
  flush();
  if (chapters.isEmpty) throw const FormatException('文件中没有可阅读的正文');
  return (chapters: chapters, ranges: ranges);
}
