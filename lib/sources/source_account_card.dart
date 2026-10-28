import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../app_ui.dart';
import '../app_interactions.dart';
import '../library_state.dart';
import '../feature_pages.dart' show confirmNovelAction;
import 'book_source.dart';
import 'source_account.dart';
import 'source_repository.dart';

/// A compact account row inside the existing source card, not another card.
class SourceAccountPanel extends StatefulWidget {
  const SourceAccountPanel({
    super.key,
    required this.source,
    required this.repository,
    this.library,
    this.enabled = true,
  });
  final BookSource source;
  final SourceNovelRepository repository;
  final LibraryState? library;
  final bool enabled;
  @override
  State<SourceAccountPanel> createState() => _SourceAccountPanelState();
}

class _SourceAccountPanelState extends State<SourceAccountPanel>
    with WidgetsBindingObserver {
  static int _next = 0;
  late Future<SourceAccountStatus> _status;
  String? _busy, _error, _request;
  bool _cancelled = false;
  @override
  void initState() {
    super.initState();
    _status = widget.repository.ensureAccount(widget.source);
    widget.repository.accountChanges.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  void _changed() {
    if (mounted) {
      setState(() {
        _status = widget.repository.accountStatus(widget.source);
      });
    }
  }

  void _refresh() {
    widget.repository.refreshAccount(widget.source.key);
    setState(
      () =>
          _status = widget.repository.ensureAccount(widget.source, force: true),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void didUpdateWidget(SourceAccountPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.accountChanges.removeListener(_changed);
      widget.repository.accountChanges.addListener(_changed);
    }
    if (oldWidget.source != widget.source ||
        oldWidget.repository != widget.repository) {
      _status = widget.repository.ensureAccount(widget.source);
    }
  }

  Future<void> _run(String action) async {
    if (_busy != null || !widget.enabled || !widget.source.enabled) return;
    setState(() {
      _busy = action;
      _error = null;
      _cancelled = false;
    });
    final id = _request = 'source-account-${++_next}';
    try {
      if (action == 'verify') {
        await widget.repository.verifyAccount(widget.source, requestId: id);
      } else if (action == 'checkIn') {
        final receipt = await widget.repository.checkIn(
          widget.source,
          requestId: id,
        );
        if (mounted) showNovelFeedback(context, receipt.label);
      } else {
        if (!await confirmNovelAction(
          context,
          title: '合并此源的云书架？',
          message: '将云端书目加入本机书架。不删除现有书籍，不覆盖阅读进度与书签，也不改动云端书架。',
          confirmLabel: '合并书架',
        )) {
          return;
        }
        if (!mounted || _cancelled) return;
        final added = await widget.repository.syncSourceShelf(
          widget.source,
          widget.library!,
          requestId: id,
        );
        if (mounted && !_cancelled) {
          showNovelFeedback(
            context,
            added == 0 ? '书架已同步，没有新增书籍' : '已加入 $added 本书',
          );
        }
      }
    } catch (error) {
      if (mounted && !_cancelled) {
        setState(() => _error = sourceErrorMessage(error));
      }
    } finally {
      if (_request == id) _request = null;
      if (mounted) setState(() => _busy = null);
    }
  }

  void _cancel() {
    _cancelled = true;
    if (_request case final id?) {
      unawaited(widget.repository.cancelAccountRequest(id));
    }
  }

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.repository.accountChanges.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SourceAccountStatus>(
    future: _status,
    builder: (context, snapshot) {
      final status = snapshot.data;
      final verifying = widget.repository.accountVerifying(widget.source);
      final enabled =
          widget.enabled &&
          widget.source.enabled &&
          _busy == null &&
          !verifying;
      final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ArchiveIcon(
                  status?.status == 'verified'
                      ? CupertinoIcons.checkmark_circle
                      : CupertinoIcons.person_crop_circle,
                  size: 17,
                  color: secondary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: AppText(
                    snapshot.hasError
                        ? '账号状态暂不可用'
                        : verifying
                        ? '正在验证登录'
                        : status?.label ?? '正在读取账号状态',
                    key: ValueKey('source-account-status-${widget.source.key}'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (snapshot.hasError)
                  GlassTextButton(
                    compact: true,
                    onPressed: _busy == null ? _refresh : null,
                    child: const AppText('重试'),
                  ),
              ],
            ),
            if (status?.explanation case final text?)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: AppText(
                  text,
                  style: TextStyle(fontSize: 12, height: 1.5, color: secondary),
                ),
              ),
            if (status != null &&
                (status.canVerify ||
                    status.canSync && widget.library != null ||
                    status.canCheckIn))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (status.canVerify)
                      GlassTextButton(
                        key: ValueKey(
                          'source-account-verify-${widget.source.key}',
                        ),
                        compact: true,
                        onPressed: enabled && status.hasSession
                            ? () => _run('verify')
                            : null,
                        child: const AppText('验证登录'),
                      ),
                    if (status.canSync && widget.library != null)
                      GlassTextButton(
                        key: ValueKey(
                          'source-account-shelf-${widget.source.key}',
                        ),
                        compact: true,
                        onPressed: enabled ? () => _run('sync') : null,
                        child: const AppText('合并云书架'),
                      ),
                    if (status.canCheckIn)
                      GlassTextButton(
                        key: ValueKey(
                          'source-account-checkin-${widget.source.key}',
                        ),
                        compact: true,
                        onPressed:
                            enabled &&
                                status.status == 'verified' &&
                                !status.checkedInToday
                            ? () => _run('checkIn')
                            : null,
                        child: AppText(
                          status.checkedInToday
                              ? '今日已签到'
                              : status.checkInSteps.any(
                                  (step) => !step.complete,
                                )
                              ? '重试未完成项目'
                              : '签到',
                        ),
                      ),
                  ],
                ),
              ),
            for (final step
                in status?.checkInSteps ?? const <SourceCheckInStep>[]) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AppText(
                      step.label,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  AppText(
                    step.complete ? '已完成' : '未完成',
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                ],
              ),
              if (step.message.isNotEmpty)
                AppText(
                  step.message,
                  style: TextStyle(fontSize: 12, height: 1.5, color: secondary),
                ),
            ],
            if (_busy != null) ...[
              InlineSkeleton(
                label: switch (_busy) {
                  'verify' => '正在验证账号',
                  'checkIn' => '正在签到',
                  _ => '正在合并云书架',
                },
              ),
              if (_busy == 'sync')
                GlassTextButton(
                  compact: true,
                  onPressed: _cancel,
                  child: const AppText('取消同步'),
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: AppText(
                  _error!,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
          ],
        ),
      );
    },
  );
}
