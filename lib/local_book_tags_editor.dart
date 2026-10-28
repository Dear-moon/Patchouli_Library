import 'package:flutter/material.dart';

import 'app_search_field.dart';
import 'app_ui.dart';
import 'book_tag_catalog.dart';
import 'local_book_edit_widgets.dart';

/// Edits a caller-owned draft. Only the book editor's Save persists these tags.
class LocalBookTagsEditor extends StatefulWidget {
  const LocalBookTagsEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.availableTags = const [],
    this.enabled = true,
    this.reduceMotion = false,
  });

  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final Iterable<String> availableTags;
  final bool enabled, reduceMotion;

  @override
  State<LocalBookTagsEditor> createState() => _LocalBookTagsEditorState();
}

class _LocalBookTagsEditorState extends State<LocalBookTagsEditor> {
  final _custom = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _change(Iterable<String> value) {
    try {
      final tags = decodeBookTags(normalizeBookTags(value));
      widget.onChanged(tags);
      setState(() => _error = null);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  void _add() {
    _change([...widget.value, _custom.text]);
    if (_error == null) _custom.clear();
  }

  Future<void> _more() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final tags = await showJellySheet<List<String>>(
      context: context,
      reduceMotion: widget.reduceMotion,
      heightFactor: .82,
      builder: (_) => _TagChoices(
        selected: widget.value,
        candidates: normalizeBookTags([
          ...BookTagCatalog.shared.suggestions,
          ...widget.availableTags,
          ...widget.value,
        ]),
      ),
    );
    if (mounted && tags != null) _change(tags);
  }

  @override
  Widget build(BuildContext context) {
    final chosen = widget.value.map(bookTagKey).toSet();
    final quick = normalizeBookTags([
      ...widget.value,
      ...BookTagCatalog.quickTags,
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppText(
                widget.value.isEmpty ? '标签' : '标签 · ${widget.value.length}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            GlassTextButton(
              key: const ValueKey('local-tags-more'),
              compact: true,
              onPressed: widget.enabled ? _more : null,
              child: const AppText('更多标签'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final tag in quick)
              GlassTextButton(
                key: ValueKey('local-tag-$tag'),
                compact: true,
                selected: chosen.contains(bookTagKey(tag)),
                onPressed: !widget.enabled
                    ? null
                    : () => _change(
                        chosen.contains(bookTagKey(tag))
                            ? widget.value.where(
                                (value) => bookTagKey(value) != bookTagKey(tag),
                              )
                            : [...widget.value, tag],
                      ),
                child: AppText(tag, style: const TextStyle(fontSize: 14)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: LocalBookEditField(
                label: '自定义标签',
                placeholder: '输入标签，多个用逗号分隔',
                controller: _custom,
                inputKey: const ValueKey('local-tag-custom'),
                enabled: widget.enabled,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 10),
            GlassTextButton(
              key: const ValueKey('local-tag-add'),
              compact: true,
              onPressed: !widget.enabled || _custom.text.trim().isEmpty
                  ? null
                  : _add,
              child: const AppText('添加'),
            ),
          ],
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 8),
          AppText(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _TagChoices extends StatefulWidget {
  const _TagChoices({required this.selected, required this.candidates});
  final List<String> selected, candidates;

  @override
  State<_TagChoices> createState() => _TagChoicesState();
}

class _TagChoicesState extends State<_TagChoices> {
  late final _selected = [...widget.selected];
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = bookTagKey(_query.text);
    final chosen = _selected.map(bookTagKey).toSet();
    final tags = widget.candidates
        .where((tag) => bookTagKey(tag).contains(query))
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ArchiveSection(title: '选择标签', code: 'LOCAL / TAGS'),
          const SizedBox(height: 12),
          const AppText('常用标签与在线已知标签', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 16),
          AppSearchField(
            inputKey: const ValueKey('local-tags-search'),
            controller: _query,
            hint: '搜索标签',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: tags.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: AppText('没有匹配标签，可返回添加自定义标签'),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in tags)
                          GlassTextButton(
                            key: ValueKey('local-tag-choice-$tag'),
                            compact: true,
                            selected: chosen.contains(bookTagKey(tag)),
                            onPressed: () => setState(() {
                              if (chosen.contains(bookTagKey(tag))) {
                                _selected.removeWhere(
                                  (value) =>
                                      bookTagKey(value) == bookTagKey(tag),
                                );
                              } else {
                                _selected.add(tag);
                              }
                            }),
                            child: AppText(
                              tag,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              GlassTextButton(
                key: const ValueKey('local-tags-clear'),
                onPressed: _selected.isEmpty
                    ? null
                    : () => setState(() => _selected.clear()),
                child: const AppText('清空'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassTextButton(
                  key: const ValueKey('local-tags-done'),
                  selected: true,
                  onPressed: () => Navigator.pop(context, _selected),
                  child: AppText('完成 · ${_selected.length}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
