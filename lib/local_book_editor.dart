import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'app_interactions.dart' show pushNovelPage, showNovelFeedback;
import 'catalog.dart';
import 'library_state.dart';
import 'local_books.dart';
import 'local_library_preferences.dart';
import 'local_series_editor.dart';
import 'local_book_removal.dart';
import 'book_documents.dart';
import 'local_text_recovery.dart';
import 'local_book_edit_widgets.dart';
import 'local_book_tags_editor.dart';
import 'book_tag_catalog.dart';
import 'local_book_import_warning.dart';
import 'feature_pages.dart' show FeatureEntry, FeatureError, featurePadding;

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
  late List<String> _tags = normalizeBookTags(widget.book.tags);
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
        final message = e is FormatException ? e.message : '封面保存未完成，请重试';
        setState(() => _error = message);
        showNovelFeedback(context, message);
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
        tags: _tags,
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
        final message = e is FormatException ? e.message : '书籍信息保存未完成，请重试';
        setState(() {
          _busy = false;
          _error = message;
        });
        showNovelFeedback(context, message);
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
        showNovelFeedback(context, _error!);
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

  void _back() =>
      Navigator.pop(context, _coverChanged ? LocalBookEditResult.saved : null);

  Future<void> _originalFiles() async {
    await showJellySheet<void>(
      context: context,
      reduceMotion: widget.library.reduceMotion,
      heightFactor: .72,
      builder: (_) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          const ArchiveSection(title: '关联原文件', code: 'LOCAL / ORIGINALS'),
          const SizedBox(height: 20),
          for (final original in widget.books.linkedOriginals(widget.book.id))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ContentPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppText(
                      original.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    LocalTextRecovery(
                      books: widget.books,
                      bookId: original.id,
                      documents: widget.documents,
                      allowCopy: true,
                      onChanged: () {
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _importIssues() async {
    await showLocalBookImportIssues(
      context,
      book: widget.books.book(widget.book.id) ?? widget.book,
      books: widget.books,
      reduceMotion: widget.library.reduceMotion,
    );
    if (mounted) setState(() {});
  }

  Widget _identity() {
    final book = widget.books.book(widget.book.id) ?? widget.book;
    final series = widget.books.seriesFor(book.id);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        NovelCover(book, width: 88, height: 124),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 7),
              AppText(
                '${series == null ? '本地书籍' : '${series.volumes.length} 卷合订本'} · ${book.chapters.length} 章',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  GlassTextButton(
                    key: const ValueKey('local-edit-cover'),
                    compact: true,
                    onPressed: _busy ? null : _chooseCover,
                    child: const AppText('更换封面'),
                  ),
                  if (widget.books.hasCustomCover(widget.book.id))
                    GlassTextButton(
                      key: const ValueKey('local-restore-cover'),
                      compact: true,
                      onPressed: _busy ? null : () => _cover(restore: true),
                      child: const AppText('恢复封面'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _content() {
    final series = widget.books.seriesFor(widget.book.id);
    final linked = widget.books.linkedOriginals(widget.book.id);
    final issues = widget.books.importIssues(widget.book.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _identity(),
        const SizedBox(height: 30),
        const ArchiveSection(title: '书籍信息', code: '01 / PROFILE'),
        const SizedBox(height: 18),
        LocalBookEditField(
          label: '书名',
          controller: _title,
          inputKey: const ValueKey('local-edit-书名'),
          enabled: !_busy,
        ),
        const SizedBox(height: 20),
        LocalBookEditField(
          label: '作者',
          controller: _author,
          inputKey: const ValueKey('local-edit-作者'),
          enabled: !_busy,
        ),
        const SizedBox(height: 20),
        LocalBookTagsEditor(
          value: _tags,
          availableTags: [
            for (final id in {
              ...widget.library.shelf,
              ...widget.library.readingPositions.keys,
            })
              ...?widget.library.cachedNovel(id)?.tags,
            for (final book in widget.books.books) ...book.tags,
          ],
          enabled: !_busy,
          reduceMotion: widget.library.reduceMotion,
          onChanged: (tags) => setState(() => _tags = tags),
        ),
        const SizedBox(height: 24),
        FeatureEntry(
          key: const ValueKey('local-edit-category'),
          title: '书籍分类',
          subtitle: _groups?.nameOf(_group) ?? '正在读取分类',
          icon: CupertinoIcons.folder,
          onTap: _busy || _groups == null ? null : _chooseGroup,
        ),
        const SizedBox(height: 30),
        const ArchiveSection(title: '本地管理', code: '02 / LIBRARY'),
        const SizedBox(height: 18),
        if (issues.isNotEmpty) ...[
          FeatureEntry(
            key: const ValueKey('local-edit-import-issues'),
            title: '导入问题',
            subtitle:
                '${issues.length} 项 · ${widget.books.shouldShowImportWarning(widget.book.id) ? '查看已发现的问题' : '封面警告已隐藏'}',
            icon: CupertinoIcons.exclamationmark_triangle,
            onTap: _busy ? null : _importIssues,
          ),
          const SizedBox(height: 12),
        ],
        FeatureEntry(
          key: const ValueKey('local-edit-volumes'),
          title: series == null ? '合并分卷' : '管理分卷',
          subtitle: series == null
              ? '将同一作品的多本书合为一本'
              : '${series.volumes.length} 卷 · 排序、改名与移出',
          icon: CupertinoIcons.square_stack,
          onTap: _busy ? null : _volumes,
        ),
        if (linked.isNotEmpty) ...[
          const SizedBox(height: 12),
          FeatureEntry(
            key: const ValueKey('local-edit-originals'),
            title: '关联原文件',
            subtitle: '${linked.length} 个文件 · 重新关联或保存副本',
            icon: CupertinoIcons.link,
            onTap: _busy ? null : _originalFiles,
          ),
        ],
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: GlassTextButton(
            key: const ValueKey('local-edit-delete'),
            compact: true,
            onPressed: _busy ? null : _delete,
            child: AppText(
              '移除书籍',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
        FeatureError(_error),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope<LocalBookEditResult>(
    canPop: !_busy && !_coverChanged,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_busy) Navigator.pop(context, LocalBookEditResult.saved);
    },
    child: LocalBookEditLayout(
      title: '书籍配置',
      code: 'LOCAL / BOOK PROFILE',
      onBack: _busy ? null : _back,
      primaryKey: const ValueKey('local-edit-save'),
      primaryLabel: _busy ? '正在处理' : '保存修改',
      primaryIcon: CupertinoIcons.checkmark,
      onPrimary: _busy || _groups == null ? null : _save,
      secondaryLabel: '取消',
      secondaryIcon: CupertinoIcons.xmark,
      onSecondary: _busy ? null : _back,
      slivers: [
        SliverPadding(
          padding: featurePadding(context).copyWith(bottom: 12),
          sliver: SliverToBoxAdapter(child: _content()),
        ),
      ],
    ),
  );
}
