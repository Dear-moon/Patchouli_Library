import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'catalog.dart';
import 'reader_tools.dart';

({int chapter, double fraction}) readerBookTarget(double value, int chapters) {
  if (chapters <= 0) return (chapter: 0, fraction: 0);
  final scaled = value.clamp(0.0, 1.0) * chapters;
  final chapter = scaled.floor().clamp(0, chapters - 1);
  return (chapter: chapter, fraction: (scaled - chapter).clamp(0.0, 1.0));
}

class ReaderBookProgress extends StatefulWidget {
  const ReaderBookProgress({
    super.key,
    required this.novel,
    required this.chapter,
    required this.fraction,
  });
  final Novel novel;
  final int chapter;
  final double fraction;
  @override
  State<ReaderBookProgress> createState() => _ReaderBookProgressState();
}

class _ReaderBookProgressState extends State<ReaderBookProgress> {
  late double _value =
      (widget.chapter + widget.fraction) / widget.novel.chapters.length;
  @override
  Widget build(BuildContext context) {
    final target = readerBookTarget(_value, widget.novel.chapters.length);
    final chapter = widget.novel.chapters[target.chapter];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReaderValueSlider(
          sliderKey: const ValueKey('reader-book-progress-slider'),
          label: '整书进度',
          value: _value,
          min: 0,
          max: 1,
          divisions: 10000,
          hapticSteps: widget.novel.chapters.length.clamp(1, 100),
          format: (v) => '${(v * 100).toStringAsFixed(1)}%',
          onPreview: (v) => setState(() => _value = v),
          onCommitted: (v) => setState(() => _value = v),
        ),
        AppText(chapter.volumeTitle, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        AppText(
          '第 ${target.chapter + 1}/${widget.novel.chapters.length} 章 · ${chapter.title}',
          style: const TextStyle(fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 8),
        AppText(
          '章内 ${(target.fraction * 100).round()}% · 整书比例按章节计算',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        GlassPillButton(
          key: const ValueKey('reader-book-progress-go'),
          icon: CupertinoIcons.arrow_right,
          label: '前往这里',
          onPressed: () => Navigator.pop(
            context,
            ReaderSeekBookProgress(target.chapter, target.fraction),
          ),
        ),
      ],
    );
  }
}
