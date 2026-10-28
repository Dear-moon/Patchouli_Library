import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_interactions.dart';
import 'app_ui.dart';
import 'glass_choices.dart';
import 'library_state.dart';
import 'local_import_settings_page.dart';

/// One entry point for existing local pickers, folder scanning and cloud sources.
class LocalImportPage extends StatefulWidget {
  const LocalImportPage({
    super.key,
    required this.library,
    required this.changes,
    required this.isBusy,
    required this.progress,
    required this.failure,
    required this.onScan,
    required this.onManual,
    required this.onCloud,
    required this.onSyncSettings,
  });
  final LibraryState library;
  final Listenable changes;
  final bool Function() isBusy;
  final (int, int)? Function() progress;
  final String? Function() failure;
  final Future<void> Function(BuildContext) onScan, onManual, onCloud;
  final Future<void> Function(BuildContext) onSyncSettings;

  @override
  State<LocalImportPage> createState() => _LocalImportPageState();
}

class _LocalImportPageState extends State<LocalImportPage> {
  bool _saving = false;
  String? _error;

  Future<void> _storage(bool linked) async {
    if (_saving || widget.isBusy()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.library.organization.setLinkLocalBooks(linked);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : '保存方式设置未保存，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _settings(BuildContext anchor) async {
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: widget.library.reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassMenuItem(
            key: const ValueKey('local-sync-settings'),
            label: '跨设备同步设置',
            onPressed: () => Navigator.pop(menu, 'sync'),
          ),
          GlassMenuItem(
            key: const ValueKey('local-import-settings'),
            order: 1,
            label: '导入与目录设置',
            onPressed: () => Navigator.pop(menu, 'import'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'sync':
        await widget.onSyncSettings(context);
      case 'import':
        final saved = await pushNovelPage<bool>(
          context,
          LocalImportSettingsPage(library: widget.library),
          reduceMotion: widget.library.reduceMotion,
        );
        if (mounted && saved == true) {
          showNovelFeedback(context, '导入目录设置已保存');
        }
    }
  }

  Widget _entry({
    required String id,
    required String title,
    required String detail,
    required IconData icon,
    required bool enabled,
    required Future<void> Function(BuildContext) onPressed,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: GlassTextButton(
      key: ValueKey('import-hub-$id'),
      onPressed: enabled ? () => onPressed(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ArchiveIcon(icon, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  AppText(
                    detail,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const ArchiveIcon(CupertinoIcons.chevron_right, size: 15),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.changes, widget.library.organization]),
    builder: (context, _) {
      final busy = _saving || widget.isBusy();
      final linked = widget.library.organization.linkLocalBooks;
      final progress = widget.progress();
      final error = _error ?? widget.failure();
      return Scaffold(
        key: const ValueKey('local-import-page'),
        body: Atmosphere(
          child: GlassHeaderLayout(
            header: ArchiveHeaderBar(
              leading: GlassIconButton(
                icon: CupertinoIcons.back,
                label: '返回',
                onPressed: () => Navigator.pop(context),
              ),
              title: const ArchiveRouteTitle(
                title: '导入书籍',
                code: 'LOCAL / IMPORT',
              ),
              actions: [
                GlassMenuAnchor(
                  child: Builder(
                    builder: (anchor) => GlassIconButton(
                      key: const ValueKey('import-hub-settings'),
                      icon: CupertinoIcons.settings,
                      label: '导入设置',
                      onPressed: busy ? null : () => _settings(anchor),
                    ),
                  ),
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
                    MediaQuery.paddingOf(context).bottom + 32,
                  ),
                  children: [
                    GlassChoiceGroup<bool>(
                      name: 'import-storage',
                      label: '本地书籍保存方式',
                      value: linked,
                      options: const {true: '关联到 App', false: '复制到 App'},
                      leading: (value) => ArchiveIcon(
                        value ? CupertinoIcons.link : CupertinoIcons.doc_on_doc,
                        size: 18,
                      ),
                      enabled: !busy,
                      onChanged: _storage,
                    ),
                    AppText(
                      linked
                          ? '保留原文件，不重复保存原书；移动文件或撤销授权后可重新关联。'
                          : '将原书另存到 App，原文件不变。已有书籍不会自动转换。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.65,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _entry(
                      id: 'scan',
                      title: '扫描本地文件夹',
                      detail: '关联目录，选择格式并扫描书籍。',
                      icon: CupertinoIcons.folder_open,
                      enabled: !busy,
                      onPressed: widget.onScan,
                    ),
                    _entry(
                      id: 'manual',
                      title: '手动导入',
                      detail: '从系统文件选择器添加书籍。',
                      icon: CupertinoIcons.arrow_down_doc,
                      enabled: !busy,
                      onPressed: widget.onManual,
                    ),
                    _entry(
                      id: 'cloud',
                      title: '从网盘、NAS、S3 同步',
                      detail: '连接已有云端来源；原书下载到本机，不改动云端文件。',
                      icon: CupertinoIcons.cloud,
                      enabled: !busy,
                      onPressed: widget.onCloud,
                    ),
                    if (widget.isBusy()) ...[
                      const SizedBox(height: 12),
                      RefreshProgress(
                        label: progress == null
                            ? '正在导入书籍'
                            : '正在导入 ${progress.$1} / ${progress.$2} 本',
                      ),
                    ],
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: AppText(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
