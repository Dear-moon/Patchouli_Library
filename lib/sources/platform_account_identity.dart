import 'dart:async';
import 'package:flutter/material.dart';
import '../app_ui.dart';
import '../wenku_account.dart';
import 'book_source.dart';
import 'source_account.dart';
import 'source_platform_ui.dart';
import 'source_repository.dart';

BookPlatform currentAccountPlatform(SourceNovelRepository? repository) {
  final platforms = bookPlatforms(
    repository?.store.sources ?? [],
    includeWenku: true,
  );
  final key = repository == null || repository.legacySelected
      ? wenkuPlatformKey
      : bookPlatformKey(repository.discoverySource?.key);
  return platforms.where((platform) => platform.key == key).firstOrNull ??
      platforms.firstOrNull ??
      BookPlatform('local', '本地书库', 'LOCAL', []);
}

class PlatformAccountIdentity extends StatefulWidget {
  const PlatformAccountIdentity({
    super.key,
    required this.platform,
    required this.repository,
    required this.wenku,
  });
  final BookPlatform platform;
  final SourceNovelRepository? repository;
  final WenkuAccount? wenku;
  @override
  State<PlatformAccountIdentity> createState() =>
      _PlatformAccountIdentityState();
}

class _PlatformAccountIdentityState extends State<PlatformAccountIdentity>
    with WidgetsBindingObserver {
  Future<SourceAccountStatus>? _status;
  BookSource get _source => widget.platform.sources.first;

  @override
  void initState() {
    super.initState();
    widget.repository?.accountChanges.addListener(_changed);
    widget.wenku?.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  void _load() {
    if (widget.platform.sources.isEmpty) return;
    if (widget.platform.isWenku) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(widget.wenku?.initialize());
      });
    } else {
      _status = widget.repository!.ensureAccount(_source);
    }
  }

  void _changed() {
    if (!mounted || widget.platform.sources.isEmpty) return;
    setState(() {
      if (!widget.platform.isWenku) {
        _status = widget.repository!.accountStatus(_source);
      }
    });
  }

  @override
  void didUpdateWidget(PlatformAccountIdentity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.wenku != widget.wenku) {
      oldWidget.repository?.accountChanges.removeListener(_changed);
      oldWidget.wenku?.removeListener(_changed);
      widget.repository?.accountChanges.addListener(_changed);
      widget.wenku?.addListener(_changed);
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(_load);
    }
  }

  @override
  void dispose() {
    widget.repository?.accountChanges.removeListener(_changed);
    widget.wenku?.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _identity(
    BuildContext context,
    String name,
    String status,
    String avatar,
  ) {
    final fallback = Center(child: BookPlatformMark(widget.platform.mark));
    Widget image = fallback;
    if (widget.platform.isWenku && widget.wenku?.avatar != null) {
      image = Image.memory(
        widget.wenku!.avatar!,
        fit: BoxFit.cover,
        cacheWidth: 168,
        errorBuilder: (_, _, _) => fallback,
      );
    } else if (avatar.isNotEmpty) {
      final url = Uri.tryParse(avatar);
      if (url != null &&
          ['https', 'http'].contains(url.scheme) &&
          url.userInfo.isEmpty) {
        image = Image.network(
          avatar,
          fit: BoxFit.cover,
          cacheWidth: 168,
          errorBuilder: (_, _, _) => fallback,
        );
      }
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(width: 56, height: 56, child: image),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                name.isEmpty ? widget.platform.name : name,
                key: const ValueKey('platform-account-display-name'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              AppText(
                '${widget.platform.name} · $status',
                key: const ValueKey('platform-account-summary-status'),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.platform.isWenku) {
      final account = widget.wenku;
      return _identity(
        context,
        account?.profile?.displayName ?? '',
        account?.busy == true
            ? '正在验证登录'
            : account?.error != null
            ? '暂时无法验证登录'
            : account?.authenticated == true
            ? '已登录'
            : '未登录',
        '',
      );
    }
    if (widget.platform.sources.isEmpty) {
      return _identity(context, '本地书库', '请先导入书源', '');
    }
    return FutureBuilder<SourceAccountStatus>(
      future: _status,
      builder: (context, snapshot) {
        final status = snapshot.data;
        return _identity(
          context,
          status?.displayName ?? '',
          snapshot.hasError
              ? '登录信息读取失败，请重试'
              : widget.repository!.accountVerifying(_source)
              ? '正在验证登录'
              : status?.label ?? '正在读取登录信息',
          status?.avatarUrl ?? '',
        );
      },
    );
  }
}
