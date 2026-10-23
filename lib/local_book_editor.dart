import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'local_books.dart';
import 'local_library_preferences.dart';
import 'local_series_editor.dart';
import 'local_book_removal.dart';
import 'app_interactions.dart';
import 'book_documents.dart';
import 'local_text_recovery.dart';

enum LocalBookEditResult { saved, hidden, deleted, regrouped }

class LocalBookEditor extends StatefulWidget {
  const LocalBookEditor({
    super.key,
    required this.book,
    required this.books,
    required this.library,
    this.documents,
  });
  final Novel book;
  final LocalBookStore books;
  final LibraryState library;
  final BookDocuments? documents;
  @override
  State<LocalBookEditor> createState() => _LocalBookEditorState();
}

class _LocalBookEditorState extends State<LocalBookEditor> {
  late final _title = TextEditingController(text: widget.book.title),
      _author = TextEditingController(text: widget.book.author);
  LocalLibraryPreferences? _groups;
  String _group = LocalLibraryPreferences.unfiled;
  bool _busy = false;
  String? _error;
  bool _coverChanged = false;
  Future<void> _chooseCover() async {
    final volumes = widget.books.volumeCoverChoices(widget.book.id);
    if (volumes.isEmpty) return _cover();
    final choice = await showJellySheet<int>(
      context: context,
      reduceMotion: widget.library.reduceMotion,
      heightFactor: .72,
      builder: (sheet) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          const ArchiveSection(title: '更换封面', code: 'LOCAL / COVER'),
          const SizedBox(height: 16),
          GlassTextButton(
            key: const ValueKey('local-cover-pick-image'),
            onPressed: () => Navigator.pop(sheet, -1),
            child: const AppText('从图片选择'),
          ),
          const SizedBox(height: 16),
          const AppText('使用分卷封面'),
          const SizedBox(height: 12),
          for (final volume in volumes)
            GlassTextButton(
              key: ValueKey('local-cover-volume-${volume.id}'),
              onPressed: () => Navigator.pop(sheet, volume.id),
              child: Row(
                children: [
                  NovelCover(volume, width: 48, height: 68),
                  const SizedBox(width: 16),
                  Expanded(child: AppText(volume.title)),
                ],
              ),
            ),
        ],
      ),
    );
    if (mounted && choice != null) {
      await _cover(volume: choice == -1 ? null : choice);
    }
  }

  Future<void> _cover({bool restore = false, int? volume}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final documents = widget.documents ?? BookDocuments();
    try {
      if (restore) {
        await widget.books.restoreCover(widget.book.id);
      } else if (volume != null) {
        await widget.books.setVolumeCover(widget.book.id, volume);
      } else {
        final selected = await documents.pickImage();
        if (selected == null) return;
        try {
          await widget.books.setCover(widget.book.id, selected.path!);
        } finally {
          await documents.releaseBooks([selected]);
        }
      }
      _coverChanged = true;
      final book = widget.books.book(widget.book.id)!;
      await widget.library.setShelfMembership(
        book.id,
        widget.library.contains(book.id),
        novel: book,
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException ? e.message : '封面保存未完成，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (!mounted) return;
      final groups = widget.library.organization;
      setState(() {
        _groups = groups;
        _group = groups.groupOf(widget.book.id);
      });
    } catch (_) {
      if (mounted) setState(() => _error = '分类读取失败，请返回后重试');
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _chooseGroup() async {
    final groups = _groups!;
    final value = await showJellySheet<String>(
      context: context,
      reduceMotion: widget.library.reduceMotion,
      heightFactor: .6,
      builder: (sheet) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          const ArchiveSection(title: '选择分类', code: 'LOCAL / CATEGORY'),
          const SizedBox(height: 16),
          for (final e in {
            LocalLibraryPreferences.unfiled: '未分类',
            ...groups.groups,
          }.entries)
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, e.key),
              child: AppText(e.value),
            ),
        ],
      ),
    );
    if (mounted && value != null) setState(() => _group = value);
  }

  Future<void> _save() async {
    if (_busy || _groups == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final groups = _groups!;
      if (_group != LocalLibraryPreferences.unfiled &&
          !groups.groups.containsKey(_group)) {
        throw const FormatException('分类已变化，请重新选择分类');
      }
      final updated = await widget.books.updateMetadata(
        widget.book.id,
        title: _title.text,
        author: _author.text,
        summary: widget.book.summary,
      );
      await groups.assign(updated.id, _group);
      await widget.library.setShelfMembership(
        updated.id,
        widget.library.contains(updated.id),
        novel: updated,
      );
      if (mounted) Navigator.pop(context, LocalBookEditResult.saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is FormatException ? e.message : '书籍信息保存未完成，请重试';
        });
      }
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await chooseLocalBookRemoval(
        context,
        book: widget.book,
        books: widget.books,
        library: widget.library,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() => _busy = false);
        return;
      }
      Navigator.pop(
        context,
        result == LocalBookRemoval.files
            ? LocalBookEditResult.deleted
            : LocalBookEditResult.hidden,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '删除未完成，请重试';
        });
      }
    }
  }

  Future<void> _volumes() async {
    final result = await pushNovelPage<LocalSeriesEditResult>(
      context,
      LocalSeriesEditor(
        book: widget.books.book(widget.book.id) ?? widget.book,
        books: widget.books,
        library: widget.library,
      ),
      reduceMotion: widget.library.reduceMotion,
    );
    if (!mounted || result == null) return;
    Navigator.pop(
      context,
      result.dissolved || result.bookId != widget.book.id
          ? LocalBookEditResult.regrouped
          : LocalBookEditResult.saved,
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int lines = 1,
    required int limit,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppText(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 9),
        CupertinoTextField(
          key: ValueKey('local-edit-$label'),
          onTap: () => AppHaptics.play(context, HapticCue.selection),
          onSubmitted: (_) => AppHaptics.play(context, HapticCue.action),
          controller: controller,
          enabled: !_busy,
          maxLines: lines,
          maxLength: limit,
          padding: const EdgeInsets.all(15),
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: 16,
            height: 1.6,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: .045),
            borderRadius: BorderRadius.circular(ArchiveDesign.panelRadius),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope<LocalBookEditResult>(
    canPop: !_busy && !_coverChanged,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_busy) Navigator.pop(context, LocalBookEditResult.saved);
    },
    child: Scaffold(
      body: Atmosphere(
        child: GlassHeaderLayout(
          header: ArchiveHeaderBar(
            leading: GlassIconButton(
              icon: CupertinoIcons.back,
              label: '返回详情',
              onPressed: _busy
                  ? null
                  : () => Navigator.pop(
                      context,
                      _coverChanged ? LocalBookEditResult.saved : null,
                    ),
            ),
            title: const ArchiveRouteTitle(
              title: '书籍配置',
              code: 'LOCAL / BOOK PROFILE',
            ),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.paddingOf(context).top +
                  FrostedHeader.toolbarHeight +
                  20,
              24,
              MediaQuery.paddingOf(context).bottom + 32,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  NovelCover(
                    widget.books.book(widget.book.id) ?? widget.book,
                    width: 80,
                    height: 112,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GlassTextButton(
                          key: const ValueKey('local-edit-cover'),
                          onPressed: _busy ? null : _chooseCover,
                          child: const AppText('更换封面'),
                        ),
                        if (widget.books.hasCustomCover(widget.book.id))
                          GlassTextButton(
                            key: const ValueKey('local-restore-cover'),
                            onPressed: _busy
                                ? null
                                : () => _cover(restore: true),
                            child: const AppText(
                              '恢复原书封面',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              for (final original in widget.books.linkedOriginals(
                widget.book.id,
              )) ...[
                AppText(
                  '关联原文件 · ${original.title}',
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
                LocalTextRecovery(
                  books: widget.books,
                  bookId: original.id,
                  documents: widget.documents,
                  allowCopy: true,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 20),
              ],
              _field('书名', _title, limit: 160),
              _field('作者', _author, limit: 160),
              Row(
                children: [
                  const AppText(
                    '分类',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GlassTextButton(
                      key: const ValueKey('local-edit-category'),
                      onPressed: _busy || _groups == null ? null : _chooseGroup,
                      child: AppText(_groups?.nameOf(_group) ?? '正在读取分类'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              GlassTextButton(
                key: const ValueKey('local-edit-volumes'),
                onPressed: _busy ? null : _volumes,
                child: AppText(
                  widget.books.seriesFor(widget.book.id) == null
                      ? '合并分卷'
                      : '管理分卷',
                ),
              ),
              const SizedBox(height: 22),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AppText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              GlassPillButton(
                key: const ValueKey('local-edit-save'),
                icon: CupertinoIcons.checkmark,
                label: _busy ? '正在处理' : '保存修改',
                onPressed: _busy || _groups == null ? null : _save,
              ),
              const SizedBox(height: 28),
              GlassTextButton(
                key: const ValueKey('local-edit-delete'),
                onPressed: _busy ? null : _delete,
                child: AppText(
                  '移除书籍',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
