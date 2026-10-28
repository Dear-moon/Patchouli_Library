import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'app_interactions.dart';
import 'archive_progress.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'lan_reading_page.dart';
import 'lan_reading_sync.dart';

class LanSendBookSheet extends StatefulWidget {
  const LanSendBookSheet({
    super.key,
    required this.sync,
    required this.book,
    required this.position,
    required this.reduceMotion,
  });
  final LanReadingSync sync;
  final Novel book;
  final ReadingPosition position;
  final bool reduceMotion;
  @override
  State<LanSendBookSheet> createState() => _LanSendBookSheetState();
}

class _LanSendBookSheetState extends State<LanSendBookSheet> {
  String? _chosen, _failure;
  bool _complete = false;
  Future<void> _send(LanPeer peer) async {
    setState(() {
      _chosen = peer.deviceId ?? peer.addressKey;
      _complete = false;
      _failure = null;
    });
    try {
      await widget.sync.handoff.send(
        peer: peer,
        bookId: widget.book.id,
        position: widget.position,
      );
      if (mounted) setState(() => _complete = true);
    } catch (failure) {
      if (mounted) {
        setState(
          () => _failure =
              widget.sync.handoff.error ??
              (failure is FormatException
                  ? failure.message.toString()
                  : '续读未完成，请重试'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .56,
    child: AnimatedBuilder(
      animation: Listenable.merge([widget.sync, widget.sync.handoff]),
      builder: (context, _) {
        final sync = widget.sync, handoff = sync.handoff;
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
          children: [
            Row(
              children: [
                const Expanded(
                  child: ArchiveSection(
                    title: '在其他设备上续读',
                    code: 'READING / HANDOFF',
                  ),
                ),
                GlassIconButton(
                  icon: CupertinoIcons.xmark,
                  label: '关闭设备选择',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AppText(
              widget.book.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 7),
            const AppText(
              '选择自己的设备；对方缺少这本书时会一并传送。请保持两台 App 在前台。',
              style: TextStyle(fontSize: 13, height: 1.7),
            ),
            const SizedBox(height: 16),
            if (_failure != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppText(
                  _failure!,
                  style: const TextStyle(fontSize: 13, height: 1.6),
                ),
              ),
            if (!sync.enabled)
              GlassPillButton(
                icon: CupertinoIcons.wifi,
                label: '开启局域网续读',
                onPressed: () async {
                  try {
                    await sync.setEnabled(true);
                  } catch (_) {
                    if (mounted) setState(() => _failure = '局域网续读未能开启，请重试');
                  }
                },
              )
            else if (sync.peers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: AppText('还没有配对设备', style: TextStyle(fontSize: 14)),
              ),
            for (final peer in sync.peers) ...[
              Builder(
                builder: (context) {
                  final selected =
                      _chosen == (peer.deviceId ?? peer.addressKey);
                  final working =
                      selected && handoff.transfer?.incoming == false;
                  final found = sync.nearby.any(
                    (device) =>
                        device.id == peer.deviceId ||
                        device.host == peer.host && device.port == peer.port,
                  );
                  return ContentPanel(
                    // The enclosing reader sheet already owns the glass tint.
                    // Do not cover it with an opaque app-coloured white card.
                    backgroundColor: Colors.transparent,
                    key: ValueKey(
                      'handoff-device-${peer.deviceId ?? peer.addressKey}',
                    ),
                    child: Row(
                      children: [
                        const ArchiveIcon(
                          CupertinoIcons.device_laptop,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText(
                                peer.name ?? '已配对设备',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 5),
                              AppText(
                                working
                                    ? handoff.transfer!.phase
                                    : selected && _complete
                                    ? '已准备好，在对方点「继续阅读」'
                                    : found
                                    ? '已发现 · 同一局域网'
                                    : '已配对 · 请保持对方 App 在前台',
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ArchiveTransferButton(
                          icon: selected && _complete
                              ? CupertinoIcons.check_mark
                              : CupertinoIcons.arrow_right,
                          label: working
                              ? handoff.transfer!.cancellable
                                    ? '停止传书'
                                    : '正在完成续读'
                              : selected && _complete
                              ? '再次发送续读位置'
                              : '在此设备上续读',
                          working: working,
                          completed: selected && _complete,
                          value: working ? handoff.transfer?.progress : null,
                          status: working ? handoff.transfer?.phase : null,
                          reduceMotion: widget.reduceMotion,
                          onPressed: working
                              ? handoff.transfer!.cancellable
                                    ? handoff.cancel
                                    : null
                              : handoff.busy
                              ? null
                              : () => _send(peer),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            GlassTextButton(
              onPressed: handoff.busy
                  ? null
                  : () => pushNovelPage<void>(
                      context,
                      LanReadingPage(
                        sync: sync,
                        reduceMotion: widget.reduceMotion,
                      ),
                      reduceMotion: widget.reduceMotion,
                    ),
              child: const AppText('连接其他设备'),
            ),
          ],
        );
      },
    ),
  );
}

/// Transfer feedback floats above the navigator, including a currently open
/// reader, without pushing a page or switching the receiving device's book.
class LanHandoffMonitor extends StatefulWidget {
  const LanHandoffMonitor({
    super.key,
    required this.handoff,
    required this.child,
    required this.onContinue,
    required this.reduceMotion,
    this.noticeWrapper,
  });
  final LanBookHandoff? handoff;
  final Widget child;
  final Future<void> Function(LanHandoffReceipt) onContinue;
  final bool reduceMotion;
  final Widget Function(Widget)? noticeWrapper;
  @override
  State<LanHandoffMonitor> createState() => _LanHandoffMonitorState();
}

class _LanHandoffMonitorState extends State<LanHandoffMonitor> {
  bool _opening = false;
  Future<void> _continue(
    LanHandoffReceipt receipt,
    BuildContext noticeContext,
  ) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onContinue(receipt);
    } catch (failure) {
      if (noticeContext.mounted) {
        showNovelFeedback(
          noticeContext,
          failure is FormatException
              ? failure.message.toString()
              : '暂未打开阅读器，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Overlay.wrap(
    child: AnimatedBuilder(
      animation: widget.handoff ?? const AlwaysStoppedAnimation<double>(0),
      child: widget.child,
      builder: (context, child) {
        final active = widget.handoff?.transfer;
        // The sender already has its action-ring in the device picker.
        final transfer = active?.incoming == true ? active : null,
            receipt = widget.handoff?.received;
        final failure = widget.handoff?.incomingError;
        Widget notice = const SizedBox.shrink();
        if (transfer != null || failure != null || receipt != null) {
          notice = Material(
            key: ValueKey(
              transfer != null
                  ? 'handoff-transferring'
                  : failure != null
                  ? 'handoff-failed'
                  : 'handoff-received',
            ),
            color: Colors.transparent,
            child: ContentPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const ArchiveIcon(CupertinoIcons.device_laptop, size: 19),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppText(
                          transfer?.title ??
                              (failure != null ? '续读未完成' : receipt!.book.title),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (transfer != null)
                        ArchiveTransferButton(
                          icon: CupertinoIcons.arrow_right,
                          label: transfer.cancellable ? '停止传书' : '正在准备续读',
                          working: true,
                          value: transfer.progress,
                          status: transfer.phase,
                          reduceMotion: widget.reduceMotion,
                          onPressed: transfer.cancellable
                              ? widget.handoff!.cancel
                              : null,
                        )
                      else
                        GlassIconButton(
                          icon: CupertinoIcons.xmark,
                          label: '收起续读提醒',
                          onPressed: failure != null
                              ? widget.handoff!.dismissError
                              : widget.handoff!.dismissReceipt,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  AppText(
                    transfer != null
                        ? '${transfer.phase} · ${transfer.device}'
                        : failure ?? '来自 ${receipt!.device} · 已准备好阅读位置',
                    style: const TextStyle(fontSize: 12, height: 1.6),
                  ),
                  if (transfer == null && failure == null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Builder(
                        builder: (noticeContext) => GlassPillButton(
                          key: const ValueKey('handoff-continue-reading'),
                          icon: CupertinoIcons.book,
                          label: '继续阅读',
                          onPressed: _opening
                              ? null
                              : () => _continue(receipt!, noticeContext),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        if (widget.noticeWrapper case final wrapper?) {
          notice = KeyedSubtree(key: notice.key, child: wrapper(notice));
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            child!,
            Positioned(
              top: MediaQuery.paddingOf(context).top + 10,
              left: 16,
              right: 16,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: AnimatedSwitcher(
                    duration:
                        widget.reduceMotion ||
                            MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : NovelMotion.enter,
                    switchInCurve: NovelMotion.ease,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, -.06),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: notice,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
