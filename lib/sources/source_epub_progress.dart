import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../app_ui.dart';
import 'source_epub.dart';

class SourceEpubProgressPanel extends StatelessWidget {
  const SourceEpubProgressPanel({super.key, required this.progress});
  final ValueListenable<EpubLoadProgress> progress;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<EpubLoadProgress>(
    valueListenable: progress,
    builder: (context, value, _) {
      final title = switch (value.stage) {
        EpubLoadStage.preparing => '正在获取 EPUB 下载地址',
        EpubLoadStage.downloading => '正在下载 EPUB',
        EpubLoadStage.checking => '正在检查 EPUB 文件',
        EpubLoadStage.parsing => '正在读取目录、正文与插图',
        EpubLoadStage.ready => '卷册已准备完毕',
        EpubLoadStage.failed => '卷册加载失败，请重试',
      };
      final fraction = value.fraction;
      final amount = value.received / (1024 * 1024);
      final detail = switch (value.stage) {
        EpubLoadStage.downloading =>
          value.total == null
              ? '已下载 ${amount.toStringAsFixed(1)} MB'
              : '${amount.toStringAsFixed(1)} / ${(value.total! / (1024 * 1024)).toStringAsFixed(1)} MB'
                    '${fraction == null ? '' : ' · ${(fraction * 100).round()}%'}',
        EpubLoadStage.parsing when value.chapters > 0 =>
          '已处理 ${value.chapters} 章',
        EpubLoadStage.ready => '共 ${value.chapters} 章',
        _ => '首次打开需要准备卷册，缓存后可直接读取',
      };
      return ContentPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ArchiveCode('NOVELIA / EPUB'),
            const SizedBox(height: 12),
            AppText(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: fraction),
            const SizedBox(height: 12),
            AppText(
              detail,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    },
  );
}
