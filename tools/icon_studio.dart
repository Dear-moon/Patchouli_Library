import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/glass_dock.dart';

/// An isolated, offline entry point; it never opens the production library or
/// connects to a book source. Run: flutter run -t tools/icon_studio.dart
void main() => runApp(const IconStudioApp());

class IconStudioApp extends StatefulWidget {
  const IconStudioApp({super.key});
  @override
  State<IconStudioApp> createState() => _IconStudioAppState();
}

class _IconStudioAppState extends State<IconStudioApp> {
  bool _dark = false, _still = false;
  int _replay = 0;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: novelTheme(_dark ? Brightness.dark : Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: _still),
      child: child!,
    ),
    home: Scaffold(
      body: Atmosphere(
        child: SafeArea(
          child: SingleChildScrollView(
            child: Center(
              child: IconStudioSheet(
                replay: _replay,
                controls: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlassIconButton(
                      icon: CupertinoIcons.play_fill,
                      label: '播放一轮图标动效',
                      onPressed: _still
                          ? null
                          : () => setState(() => _replay++),
                    ),
                    const SizedBox(width: 12),
                    GlassIconButton(
                      icon: CupertinoIcons.moon_stars,
                      label: '切换深浅主题',
                      onPressed: () => setState(() => _dark = !_dark),
                    ),
                    const SizedBox(width: 12),
                    GlassTextButton(
                      onPressed: () => setState(() => _still = !_still),
                      child: Text(_still ? '动效已关闭' : '动效已开启'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class IconStudioSheet extends StatelessWidget {
  const IconStudioSheet({super.key, this.controls, this.replay = 0});
  final Widget? controls;
  final int replay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = ArchiveSymbol.values.map((s) => s.group).toSet().toList();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1080),
      child: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 20 : 36,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 24,
                runSpacing: 12,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const ArchiveCode('WENKU8 / ICONOGRAPHY 02'),
                  ?controls,
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              '折页墨线',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '纸页与档案 · ${ArchiveSymbol.values.length} 枚动态图标 · 第二版',
              style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            IconStudioFeatured(replay: replay),
            const SizedBox(height: 24),
            const IconStudioActions(),
            const SizedBox(height: 34),
            for (final (index, group) in groups.indexed) ...[
              Row(
                children: [
                  ArchiveCode(
                    '0${index + 1} / ${switch (group) {
                      '导航' => 'NAVIGATION',
                      '阅读' => 'READING',
                      '听书' => 'LISTENING',
                      '操作' => 'ACTIONS',
                      '文件' => 'FILES',
                      _ => 'SYSTEM',
                    }}',
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Divider(color: Theme.of(context).dividerColor),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    group,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, box) {
                  final columns = (box.maxWidth / 108).floor().clamp(2, 9);
                  return Wrap(
                    children: [
                      for (final symbol in ArchiveSymbol.values.where(
                        (s) => s.group == group,
                      ))
                        SizedBox(
                          width: box.maxWidth / columns,
                          child: _IconTile(symbol, replay: replay),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 26),
            ],
            const Divider(),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: ArchiveCode('FOLDED PAPER / INK / 640ms'),
                ),
                Text(
                  '轻触图标，查看动态',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Uses the production dock, action buttons and stateful glyphs.
class IconStudioActions extends StatefulWidget {
  const IconStudioActions({super.key});
  @override
  State<IconStudioActions> createState() => _IconStudioActionsState();
}

class _IconStudioActionsState extends State<IconStudioActions> {
  int _tab = 0;
  bool _playing = false, _saved = false;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(
      horizontal: MediaQuery.sizeOf(context).width < 600 ? 10 : 20,
      vertical: 18,
    ),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .6),
      border: Border.all(color: Theme.of(context).dividerColor, width: .7),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 18,
      spacing: 24,
      children: [
        GlassDock(
          selectedIndex: _tab,
          onSelected: (value) => setState(() => _tab = value),
          items: const [
            GlassDockItem(CupertinoIcons.house, '发现'),
            GlassDockItem(
              CupertinoIcons.book,
              '书架',
              symbol: ArchiveSymbol.shelf,
            ),
            GlassDockItem(CupertinoIcons.folder, '本地'),
            GlassDockItem(CupertinoIcons.person_crop_circle, '我的'),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassIconButton(
              icon: CupertinoIcons.search,
              label: '搜索演示',
              onPressed: () {},
            ),
            const SizedBox(width: 8),
            GlassIconButton(
              key: const ValueKey('studio-play'),
              icon: _playing
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_fill,
              label: _playing ? '暂停演示' : '播放演示',
              onPressed: () => setState(() => _playing = !_playing),
            ),
            const SizedBox(width: 8),
            GlassIconButton(
              key: const ValueKey('studio-bookmark'),
              icon: _saved
                  ? CupertinoIcons.bookmark_fill
                  : CupertinoIcons.bookmark,
              label: _saved ? '取消收藏演示' : '收藏演示',
              onPressed: () => setState(() => _saved = !_saved),
            ),
            const SizedBox(width: 8),
            GlassIconButton(
              icon: CupertinoIcons.slider_horizontal_3,
              label: '设置演示',
              onPressed: () {},
            ),
          ],
        ),
      ],
    ),
  );
}

class IconStudioFeatured extends StatelessWidget {
  const IconStudioFeatured({super.key, this.replay = 0});
  final int replay;
  static const specimens = [
    (ArchiveSymbol.discover, '拨开书页'),
    (ArchiveSymbol.shelf, '抽卷回落'),
    (ArchiveSymbol.folder, '纸页探出'),
    (ArchiveSymbol.bookmark, '折页回弹'),
    (ArchiveSymbol.play, '双页变形'),
    (ArchiveSymbol.sliders, '错峰滑动'),
  ];
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.symmetric(
        horizontal: BorderSide(
          color: Theme.of(context).dividerColor,
          width: .7,
        ),
      ),
    ),
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth < 600 ? 3 : 6;
        return Wrap(
          children: [
            for (final (symbol, note) in specimens)
              SizedBox(
                width: box.maxWidth / columns,
                child: _IconTile(symbol, replay: replay, size: 48, note: note),
              ),
          ],
        );
      },
    ),
  );
}

class _IconTile extends StatefulWidget {
  const _IconTile(this.symbol, {this.replay = 0, this.size = 28, this.note});
  final ArchiveSymbol symbol;
  final int replay;
  final double size;
  final String? note;
  @override
  State<_IconTile> createState() => _IconTileState();
}

class _IconTileState extends State<_IconTile> {
  bool _active = false;
  int _hover = 0;
  @override
  Widget build(BuildContext context) {
    final symbol = _active
        ? switch (widget.symbol) {
            ArchiveSymbol.play => ArchiveSymbol.pause,
            ArchiveSymbol.pause => ArchiveSymbol.play,
            ArchiveSymbol.bookmark => ArchiveSymbol.bookmarked,
            ArchiveSymbol.bookmarked => ArchiveSymbol.bookmark,
            ArchiveSymbol.forward => ArchiveSymbol.down,
            ArchiveSymbol.eye => ArchiveSymbol.eyeOff,
            ArchiveSymbol.eyeOff => ArchiveSymbol.eye,
            ArchiveSymbol.circle => ArchiveSymbol.selected,
            _ => widget.symbol,
          }
        : widget.symbol;
    return Semantics(
      button: true,
      label: widget.symbol.label,
      child: ArchiveIconResponse(
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover++),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _active = !_active),
            child: SizedBox(
              height: widget.note == null ? 88 : 136,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ArchiveIcon.symbol(
                    symbol,
                    size: widget.size,
                    active: _active,
                    trigger: (widget.replay, _hover),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.symbol.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (widget.note case final note?) ...[
                    const SizedBox(height: 6),
                    Text(
                      note,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
