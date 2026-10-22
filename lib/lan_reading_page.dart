import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_ui.dart';
import 'app_interactions.dart';
import 'feature_pages.dart';
import 'lan_reading_sync.dart';
import 'library_sync_conflicts_page.dart';

class LanReadingPage extends StatefulWidget {
  const LanReadingPage({
    super.key,
    required this.sync,
    required this.reduceMotion,
  });
  final LanReadingSync sync;
  final bool reduceMotion;
  @override
  State<LanReadingPage> createState() => _LanReadingPageState();
}

class _LanReadingPageState extends State<LanReadingPage> {
  final _code = TextEditingController();
  final _scroll = ScrollController();
  String? _shownPairing;
  bool _busy = false, _manual = false;
  @override
  void initState() {
    super.initState();
    widget.sync.openPairing();
    widget.sync.addListener(_followPairing);
  }

  @override
  void didUpdateWidget(LanReadingPage old) {
    super.didUpdateWidget(old);
    if (old.sync != widget.sync) {
      old.sync.removeListener(_followPairing);
      old.sync.closePairing();
      widget.sync.openPairing();
      widget.sync.addListener(_followPairing);
    }
  }

  void _followPairing() {
    final pending = widget.sync.pendingPairing;
    if (pending == null) {
      _shownPairing = null;
      return;
    }
    if (_shownPairing == pending.digits) return;
    _shownPairing = pending.digits;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (widget.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(0);
      } else {
        _scroll.animateTo(
          0,
          duration: NovelMotion.enter,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        showNovelFeedback(
          context,
          error is FormatException ? error.message : '连接未完成，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    widget.sync.removeListener(_followPairing);
    widget.sync.closePairing();
    _code.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '局域网续读',
    code: 'READING / NEARBY SYNC',
    child: AnimatedBuilder(
      animation: widget.sync,
      builder: (context, _) {
        final sync = widget.sync;
        final known = {for (final peer in sync.peers) peer.deviceId};
        final nearby = sync.nearby
            .where((device) => !known.contains(device.id))
            .toList();
        final pairing = sync.pendingPairing;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              controller: _scroll,
              padding: featurePadding(context),
              children: [
                ContentPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: AppText(
                              '自动同步阅读记录',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          AppControls.toggle(
                            context,
                            value: sync.enabled,
                            onChanged: _busy
                                ? null
                                : (value) => _run(() => sync.setEnabled(value)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const AppText(
                        '两台设备连上同一 Wi-Fi 或手机热点，首次确认自己的设备，以后自动连接。进度、书签与分类自动增量同步，两端 App 需保持前台。',
                        style: TextStyle(fontSize: 13, height: 1.7),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (sync.librarySync case final library?
                    when library.conflicts.isNotEmpty) ...[
                  FeatureEntry(
                    key: const ValueKey('lan-library-conflicts'),
                    title: '同步冲突',
                    subtitle: '${library.conflicts.length} 条记录保留了不同版本，点此选择',
                    icon: CupertinoIcons.arrow_branch,
                    onTap: () => pushNovelPage<void>(
                      context,
                      LibrarySyncConflictsPage(sync: library),
                      reduceMotion: widget.reduceMotion,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if ((sync.librarySync?.pendingBooks ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: AppText(
                      '${sync.librarySync!.pendingBooks} 条书签等待两端使用一致的原书排版；现有记录保留。',
                      style: const TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ),
                AnimatedOptionSection(
                  expanded: sync.enabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedOptionSection(
                        expanded: pairing != null,
                        child: pairing == null
                            ? const SizedBox()
                            : ContentPanel(
                                key: const ValueKey('lan-confirm-card'),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    AppText(
                                      '连接 ${pairing.name}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    AppText(
                                      '${pairing.digits.substring(0, 3)}  ${pairing.digits.substring(3)}',
                                      key: const ValueKey(
                                        'lan-verification-digits',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 30,
                                        letterSpacing: 3,
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    AppText(
                                      pairing.accepted
                                          ? '已确认，等待另一台设备确认。'
                                          : '核对两台设备的数字；一致时，分别点一下确认。',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.7,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 8,
                                      children: [
                                        GlassPillButton(
                                          key: const ValueKey(
                                            'lan-confirm-pairing',
                                          ),
                                          icon: CupertinoIcons.check_mark,
                                          label: pairing.accepted
                                              ? '等待对方'
                                              : '确认连接',
                                          onPressed: _busy || pairing.accepted
                                              ? null
                                              : () => _run(sync.confirmPairing),
                                        ),
                                        GlassTextButton(
                                          onPressed: _busy
                                              ? null
                                              : sync.cancelPairing,
                                          child: const AppText('取消'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      if (pairing != null) const SizedBox(height: 22),
                      Row(
                        children: [
                          const Expanded(
                            child: ArchiveSection(
                              title: '附近的设备',
                              code: '01 / NEARBY',
                            ),
                          ),
                          GlassIconButton(
                            key: const ValueKey('lan-refresh-discovery'),
                            icon: CupertinoIcons.arrow_clockwise,
                            label: '重新发现',
                            onPressed: _busy
                                ? null
                                : () => _run(sync.refreshDiscovery),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (nearby.isEmpty)
                        AppText(
                          sync.automaticDiscovery
                              ? '还没有发现新设备。请让另一台设备开启局域网续读，并保持 App 在前台。'
                              : '自动发现暂不可用。请检查 Wi-Fi 与本地网络权限，或使用下方的手动连接。',
                          style: const TextStyle(fontSize: 13, height: 1.7),
                        ),
                      for (final device in nearby) ...[
                        FeatureEntry(
                          key: ValueKey('lan-nearby-${device.id}'),
                          title: device.name,
                          subtitle: '点一下连接，不需要输入地址',
                          icon: CupertinoIcons.device_phone_portrait,
                          onTap: _busy || pairing != null
                              ? null
                              : () => _run(() => sync.pairNearby(device)),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 24),
                      const ArchiveSection(
                        title: '已配对',
                        code: '02 / YOUR DEVICES',
                      ),
                      const SizedBox(height: 12),
                      if (sync.peers.isEmpty)
                        const AppText(
                          '还没有配对的设备。',
                          style: TextStyle(fontSize: 13),
                        ),
                      for (final peer in sync.peers) ...[
                        FeatureEntry(
                          title: peer.name ?? peer.host,
                          subtitle:
                              sync.nearby.any((d) => d.id == peer.deviceId)
                              ? '已发现 · 自动同步阅读位置'
                              : '已记住 · 两端打开 App 后自动连接',
                          icon: CupertinoIcons.link,
                          onTap: _busy ? null : () => _run(sync.sync),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (sync.lastSync case final time?)
                        AppText(
                          '最近同步 ${DateTime.fromMillisecondsSinceEpoch(time).hour.toString().padLeft(2, '0')}:${DateTime.fromMillisecondsSinceEpoch(time).minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 12, height: 1.7),
                        ),
                      FeatureError(sync.error),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          GlassTextButton(
                            onPressed: _busy ? null : () => _run(sync.sync),
                            child: const AppText('立即同步'),
                          ),
                          GlassTextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                    if (await confirmNovelAction(
                                      context,
                                      title: '解除所有局域网配对？',
                                      message: '阅读记录保留，旧配对与连接码失效。',
                                      confirmLabel: '解除配对',
                                      reduceMotion: widget.reduceMotion,
                                    )) {
                                      await sync.forget();
                                    }
                                  }),
                            child: const AppText('解除配对'),
                          ),
                          GlassTextButton(
                            key: const ValueKey('lan-manual-toggle'),
                            onPressed: () => setState(() => _manual = !_manual),
                            child: AppText(_manual ? '收起手动连接' : '手动连接'),
                          ),
                        ],
                      ),
                      AnimatedOptionSection(
                        expanded: _manual,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CupertinoTextField(
                                key: const ValueKey('lan-pair-code'),
                                controller: _code,
                                maxLines: 3,
                                autocorrect: false,
                                enableSuggestions: false,
                                placeholder: '粘贴另一台设备的连接码',
                                padding: const EdgeInsets.all(14),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 12),
                              GlassPillButton(
                                key: const ValueKey('lan-pair'),
                                icon: CupertinoIcons.link,
                                label: '连接并同步',
                                onPressed: _busy
                                    ? null
                                    : () => _run(() => sync.pair(_code.text)),
                              ),
                              for (final host in sync.hosts)
                                if (sync.codeFor(host) case final code?)
                                  GlassTextButton(
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: code),
                                      );
                                      if (context.mounted) {
                                        showNovelFeedback(
                                          context,
                                          '已复制连接码，仅发给自己的设备',
                                        );
                                      }
                                    },
                                    child: AppText('复制本机连接码 · $host'),
                                  ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      AppText(
                        sync.books == null
                            ? '自动同步两端已有书籍的较新位置，不打断当前阅读。App 退到后台会暂停同步。'
                            : '自动同步两端已有书籍的较新位置，不打断当前阅读。本地书可在「目录 → 章节进度」选择「在其他设备上续读」，对方缺书时一并传送。两台 App 需保持前台。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.7,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
