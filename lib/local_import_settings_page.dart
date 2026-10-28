import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_ui.dart';
import 'book_text_encoding.dart';
import 'glass_choices.dart';
import 'library_state.dart';
import 'local_import_options.dart';
import 'local_text_rules.dart';

class LocalImportSettingsPage extends StatefulWidget {
  const LocalImportSettingsPage({super.key, required this.library});
  final LibraryState library;
  @override
  State<LocalImportSettingsPage> createState() =>
      _LocalImportSettingsPageState();
}

class _LocalImportSettingsPageState extends State<LocalImportSettingsPage> {
  late final organization = widget.library.organization;
  late final initial = organization.importOptions;
  late final chapter = TextEditingController(text: initial.chapterRule);
  late final volume = TextEditingController(text: initial.volumeRule);
  final sample = TextEditingController(
    text: '序言\n这是前言。\n第一卷 春日\n第一章 海岸\n这是正文。\n【归途】\n完整的结尾。\nChapter 3 Night',
  );
  late bool custom = initial.customToc, autoTitles = initial.autoTitles;
  bool busy = false, dirty = false, previewCurrent = false;
  String? error;
  List<({String title, bool volume})>? preview;

  LocalImportOptions get draft => LocalImportOptions(
    customToc: custom,
    chapterRule: chapter.text,
    volumeRule: volume.text,
    autoTitles: autoTitles,
  );
  void changed(VoidCallback change) => setState(() {
    change();
    dirty = true;
    previewCurrent = false;
    error = null;
  });
  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is FormatException
              ? failure.message
              : '设置处理未完成，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() => perform(() async {
    await organization.setImportOptions(draft);
    if (mounted) Navigator.pop(context, true);
  });
  Future<void> inspect() => perform(() async {
    final result = await previewLocalDirectory(draft, sample.text);
    if (mounted) {
      setState(() {
        preview = result;
        previewCurrent = true;
      });
    }
  });
  void preset(String kind) => changed(() {
    custom = true;
    chapter.text = switch (kind) {
      'brackets' => r'^【.+】$',
      'english' => r'^chapter\s+\d+',
      _ => defaultLocalChapterRule,
    };
    volume.text = kind == 'english' ? r'^volume\s+\d+' : defaultLocalVolumeRule;
  });
  Widget ruleField(
    String label,
    TextEditingController controller,
    String key, {
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: TextField(
      key: ValueKey(key),
      onTap: () => AppHaptics.play(context, HapticCue.selection),
      onTapAlwaysCalled: true,
      controller: controller,
      enabled: !busy,
      minLines: 1,
      maxLines: 3,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontSize: 14, height: 1.5),
      inputFormatters: [LengthLimitingTextInputFormatter(1024)],
      decoration: InputDecoration(labelText: label, hintText: hint),
      onChanged: (_) => changed(() {}),
    ),
  );
  @override
  void dispose() {
    chapter.dispose();
    volume.dispose();
    sample.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([organization, widget.library.settingsChanges]),
    builder: (context, _) => Scaffold(
      body: Atmosphere(
        child: GlassHeaderLayout(
          header: ArchiveHeaderBar(
            leading: GlassIconButton(
              icon: CupertinoIcons.back,
              label: '返回',
              onPressed: () => Navigator.pop(context),
            ),
            title: const ArchiveRouteTitle(
              title: '导入与目录',
              code: 'IMPORT / CONTENTS',
            ),
            actions: [
              GlassTextButton(
                key: const ValueKey('import-options-save'),
                compact: true,
                onPressed: busy || !dirty ? null : save,
                child: AppText(busy ? '检查中' : '保存'),
              ),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  MediaQuery.paddingOf(context).top +
                      FrostedHeader.toolbarHeight +
                      20,
                  24,
                  MediaQuery.paddingOf(context).bottom + 36,
                ),
                children: [
                  GlassChoiceGroup<bool>(
                    name: 'local-book-storage',
                    label: '本地书籍保存方式',
                    value: organization.linkLocalBooks,
                    options: const {true: '关联原文件', false: '复制到应用'},
                    enabled: !busy,
                    onChanged: (value) =>
                        perform(() => organization.setLinkLocalBooks(value)),
                  ),
                  const AppText(
                    '关联模式不重复保存原书，请保留原文件；移动或撤销授权后可重新定位。文档转换、解压和排版会生成必要的阅读缓存。已有副本不自动转换，网盘下载仍保存到本机。',
                    style: TextStyle(fontSize: 13, height: 1.6),
                  ),
                  const SizedBox(height: 18),
                  const AppText(
                    '从文件管理器打开',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const AppText(
                    '在文件管理器点开书籍，选择「帕秋莉图书馆」。如系统显示「始终」，选中后即可作为这类文件的默认阅读器；不同文件格式需分别选择。',
                    style: TextStyle(fontSize: 13, height: 1.6),
                  ),
                  const SizedBox(height: 18),
                  GlassChoiceGroup<String>(
                    name: 'local-txt-encoding',
                    label: 'TXT 编码',
                    value: organization.encoding,
                    options: localTextEncodingOptions,
                    enabled: !busy,
                    onChanged: (value) =>
                        perform(() => organization.setEncoding(value)),
                  ),
                  const SizedBox(height: 18),
                  GlassChoiceGroup<bool>(
                    name: 'import-toc-mode',
                    label: 'TXT 目录识别',
                    value: custom,
                    options: const {false: '自动识别', true: '自定义规则'},
                    enabled: !busy,
                    onChanged: (value) => changed(() => custom = value),
                  ),
                  if (error case final message?)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AppText(
                        message,
                        key: const ValueKey('import-options-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          height: 1.6,
                        ),
                      ),
                    ),
                  AnimatedOptionSection(
                    expanded: custom,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ruleField('章节表达式', chapter, 'import-chapter-rule'),
                        ruleField(
                          '分卷表达式',
                          volume,
                          'import-volume-rule',
                          hint: '留空则不识别分卷',
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final entry in const {
                              'chinese': '常见中文',
                              'english': 'Chapter',
                              'brackets': '【标题】',
                            }.entries)
                              GlassTextButton(
                                compact: true,
                                onPressed: busy
                                    ? null
                                    : () => preset(entry.key),
                                child: AppText(
                                  entry.value,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                          ],
                        ),
                        const AppText(
                          '逐行匹配，匹配行保留为完整标题；分卷规则优先。',
                          style: TextStyle(fontSize: 12, height: 1.6),
                        ),
                      ],
                    ),
                  ),
                  GlassChoiceGroup<bool>(
                    name: 'import-auto-titles',
                    label: '原书未提供标题时',
                    value: autoTitles,
                    options: const {true: '补齐章名', false: '标为正文片段'},
                    enabled: !busy,
                    onChanged: (value) => changed(() => autoTitles = value),
                  ),
                  const SizedBox(height: 14),
                  const AppText(
                    '目录设置只用于之后导入的书籍，已有目录、阅读位置与书签不会重写。TXT 编码点选后立即保存。',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                  const SizedBox(height: 24),
                  const ArchiveSection(title: '预览目录', code: 'TXT / PREVIEW'),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('import-toc-sample'),
                    onTap: () => AppHaptics.play(context, HapticCue.selection),
                    onTapAlwaysCalled: true,
                    controller: sample,
                    enabled: !busy,
                    minLines: 4,
                    maxLines: 8,
                    style: const TextStyle(fontSize: 14, height: 1.6),
                    inputFormatters: [LengthLimitingTextInputFormatter(20000)],
                    decoration: const InputDecoration(
                      labelText: '粘贴几段原文，查看识别结果',
                    ),
                    onChanged: (_) => setState(() => previewCurrent = false),
                  ),
                  const SizedBox(height: 12),
                  GlassPillButton(
                    key: const ValueKey('preview-import-toc'),
                    icon: CupertinoIcons.list_bullet,
                    label: busy ? '正在检查规则' : '预览目录',
                    onPressed: busy ? null : inspect,
                  ),
                  AnimatedOptionSection(
                    expanded: preview != null,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppText(
                            previewCurrent
                                ? '识别到 ${preview?.length ?? 0} 个卷名与章名'
                                : '上次预览 · 修改后请重新预览',
                            style: const TextStyle(fontSize: 12, height: 1.6),
                          ),
                          for (final item
                              in preview?.take(60) ??
                                  const <({String title, bool volume})>[])
                            Padding(
                              padding: const EdgeInsets.only(top: 10, left: 0),
                              child: AppText(
                                '${item.volume ? '卷' : '章'} · ${item.title}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: item.volume
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          if (preview?.isEmpty == true)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: AppText(
                                '没有匹配的标题，请检查表达式或换一段原文。',
                                style: TextStyle(fontSize: 13, height: 1.6),
                              ),
                            ),
                          if ((preview?.length ?? 0) > 60)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: AppText(
                                '预览只展示前 60 条，完整导入不受此预览数量限制。',
                                style: TextStyle(fontSize: 12, height: 1.6),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
