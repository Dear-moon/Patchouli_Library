import 'package:flutter/cupertino.dart';
import '../app_ui.dart';
import '../app_search_field.dart';
import '../glass_choices.dart';
import 'book_source.dart';

class SourceDiscoveryFilters extends StatefulWidget {
  const SourceDiscoveryFilters({
    super.key,
    required this.current,
    required this.config,
  });
  final String current;
  final Map<String, dynamic> config;
  @override
  State<SourceDiscoveryFilters> createState() => _SourceDiscoveryFiltersState();
}

class _SourceDiscoveryFiltersState extends State<SourceDiscoveryFilters> {
  late final params = Map<String, String>.from(
    Uri.parse(widget.current).queryParameters,
  );
  late final queryKey = widget.config['queryKey'] as String;
  late final query = TextEditingController(text: params[queryKey] ?? '');
  List<Map<String, dynamic>> get choices => (widget.config['choices'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  void apply() {
    params[queryKey] = query.text.trim();
    for (final field in choices) {
      params.putIfAbsent(
        field['key'] as String,
        () => (field['options'] as Map).keys.first as String,
      );
    }
    Navigator.pop(
      context,
      SourceExplore(
        title: widget.config['title'] as String,
        url: Uri(
          path: widget.config['path'] as String,
          queryParameters: params,
        ).toString(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ArchiveSection(
          title: widget.config['title'] as String,
          code: 'SOURCES / FILTER',
        ),
        const SizedBox(height: 16),
        AppSearchField(
          controller: query,
          hint: '搜索书名、作者或关键词',
          onSubmitted: (_) => apply(),
        ),
        const SizedBox(height: 16),
        for (final field in choices)
          GlassChoiceGroup<String>(
            name: field['key'] as String,
            label: field['label'] as String,
            value:
                params[field['key']] ??
                (field['options'] as Map).keys.first as String,
            options: Map<String, String>.from(field['options'] as Map),
            optionName: (value) => value,
            onChanged: (value) =>
                setState(() => params[field['key'] as String] = value),
          ),
        const SizedBox(height: 20),
        Row(
          children: [
            GlassTextButton(
              onPressed: () => setState(() {
                query.clear();
                params.clear();
              }),
              child: const AppText('重置'),
            ),
            const Spacer(),
            GlassTextButton(onPressed: apply, child: const AppText('应用筛选')),
          ],
        ),
      ],
    ),
  );
}
