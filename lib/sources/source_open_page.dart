import 'package:flutter/material.dart';
import '../app_ui.dart';
import '../catalog.dart';
import '../feature_pages.dart';
import '../library_state.dart';
import '../pages.dart' show openDetail;
import 'book_source.dart';
import 'source_fields.dart';
import 'source_repository.dart';

class SourceOpenPage extends StatefulWidget {
  const SourceOpenPage({
    super.key,
    required this.repository,
    required this.state,
    required this.books,
  });
  final SourceNovelRepository repository;
  final LibraryState state;
  final NovelRepository books;
  @override
  State<SourceOpenPage> createState() => _SourceOpenPageState();
}

class _SourceOpenPageState extends State<SourceOpenPage> {
  final _url = TextEditingController();
  late BookSource? _source =
      widget.repository.discoverySource ??
      widget.repository.enabled.firstOrNull;
  bool _busy = false;
  String? _error;
  Future<void> _open() async {
    final source = _source;
    if (source == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await widget.repository.platform.run(
                source,
                'search',
                key: _url.text.trim(),
                page: 1,
              )
              as Map;
      final rows = result['items'] as List;
      if (rows.isEmpty) throw const FormatException('未找到此链接对应的书籍');
      final book = widget.repository.store.remember(
        source,
        Map<String, dynamic>.from(rows.first),
      );
      await widget.repository.store.flush();
      final detail = await widget.repository.detail(book);
      await widget.repository.chapters(book.id);
      if (mounted) openDetail(context, detail, widget.state, widget.books);
    } catch (error) {
      if (mounted) setState(() => _error = sourceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '打开书籍',
    code: 'SOURCES / BOOK LINK',
    child: ListView(
      padding: featurePadding(context),
      children: [
        DropdownButtonFormField<BookSource>(
          initialValue: _source,
          decoration: const InputDecoration(labelText: '书源与版本'),
          items: [
            for (final source in widget.repository.enabled)
              DropdownMenuItem(value: source, child: AppText(source.name)),
          ],
          onChanged: _busy
              ? null
              : (source) => setState(() => _source = source),
        ),
        const SizedBox(height: 20),
        sourceField(context, '书籍网页链接', _url, lines: 2),
        const SizedBox(height: 12),
        const AppText('Novelia 支持 Sakura、GPT、有道与日文原文，请选择所需版本。链接中的翻译参数以此处选择为准。'),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: AppText(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 24),
        GlassTextButton(
          onPressed: _busy || _source == null ? null : _open,
          child: AppText(_busy ? '正在读取' : '打开书籍'),
        ),
      ],
    ),
  );
}
