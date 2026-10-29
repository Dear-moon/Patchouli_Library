import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_ui.dart';
import '../app_interactions.dart';
import 'app_updates.dart';
import 'release_markdown.dart';
import 'release_notices.dart';
import 'current_release_content.dart';

export 'release_notices.dart' show currentReleaseSourcePolicy;
export 'current_release_content.dart'
    show ReleaseSection, currentReleaseSummary, currentReleaseSections;

class CurrentReleaseCard extends StatelessWidget {
  const CurrentReleaseCard({super.key, this.updates});
  final AppUpdates? updates;
  @override
  Widget build(BuildContext context) {
    final service = updates;
    Widget card() => ContentPanel(
      key: const ValueKey('current-release-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArchiveSection(
            title: '本版更新',
            code:
                'RELEASE / ${service?.installed?.version ?? currentAppVersion}',
          ),
          const SizedBox(height: 12),
          for (final item in currentReleaseSummary)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ReleaseNotes(
                item == currentReleaseSourcePolicy ? '**$item**' : '- $item',
                style: TextStyle(
                  fontSize: item == currentReleaseSourcePolicy ? 16 : 13,
                  fontWeight: item == currentReleaseSourcePolicy
                      ? FontWeight.w700
                      : FontWeight.normal,
                  height: 1.6,
                ),
              ),
            ),
          const SizedBox(height: 6),
          GlassTextButton(
            key: const ValueKey('view-current-release-details'),
            onPressed: () =>
                showInstalledReleaseNotes(context, updates: service),
            child: const AppText('查看详细更新说明'),
          ),
        ],
      ),
    );
    return service == null
        ? card()
        : AnimatedBuilder(animation: service, builder: (_, _) => card());
  }
}

Future<bool> showInstalledReleaseNotes(
  BuildContext context, {
  AppUpdates? updates,
  bool automatic = false,
}) async {
  if (updates != null && updates.installed == null) {
    try {
      await updates.loadInstalled();
    } catch (_) {
      // Manual viewing remains available when platform metadata is unavailable.
    }
    if (!context.mounted) return false;
  }
  final installed = updates?.installed;
  final appearance = GlassAppearance.of(context);
  final reduced = MediaQuery.disableAnimationsOf(context);
  final completed =
      await Navigator.of(context, rootNavigator: true).push<bool>(
        _ReleaseDetailsRoute(
          barrierDismissible: !automatic,
          barrierLabel: '关闭更新说明',
          barrierColor: Colors.black.withValues(alpha: .16),
          transitionDuration: reduced ? Duration.zero : NovelMotion.enter,
          transitionBuilder: (context, animation, secondary, child) =>
              GlassOverlayTransition(
                animation: animation,
                kind: GlassOverlayKind.sheet,
                reduceMotion: reduced,
                child: child,
              ),
          pageBuilder: (context, _, _) => GlassAppearance(
            blur: appearance.blur,
            opacity: appearance.opacity,
            child: PopScope(
              canPop: !automatic,
              child: _ReleaseDetails(
                version: installed?.version ?? currentAppVersion,
                build: installed?.build ?? currentAppBuild,
              ),
            ),
          ),
        ),
      ) ==
      true;
  if (completed && installed != null && updates != null) {
    try {
      await updates.rememberReleaseNotes(installed);
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '阅读状态未保存，下次打开可能再次显示');
    }
  }
  return completed;
}

class _ReleaseDetailsRoute extends RawDialogRoute<bool>
    with AppHapticModalBarrier<bool> {
  _ReleaseDetailsRoute({
    required super.pageBuilder,
    required super.barrierDismissible,
    required super.barrierLabel,
    required super.barrierColor,
    required super.transitionDuration,
    required super.transitionBuilder,
  });
}

class _ReleaseDetails extends StatefulWidget {
  const _ReleaseDetails({required this.version, required this.build});
  final String version;
  final int build;
  @override
  State<_ReleaseDetails> createState() => _ReleaseDetailsState();
}

class _ReleaseDetailsState extends State<_ReleaseDetails> {
  final _pages = PageController();
  final _sections = currentReleaseSections
      .where((s) => s.items.isNotEmpty)
      .toList(growable: false);
  int _page = 0;
  bool _moving = false;
  bool _userPaging = false;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _move(int page) async {
    if (_moving) return;
    _userPaging = false;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      setState(() => _moving = true);
      await _pages.animateToPage(
        page,
        duration: NovelMotion.enter,
        curve: NovelMotion.ease,
      );
      if (mounted) setState(() => _moving = false);
    }
  }

  Widget _navigation(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final previous = GlassTextButton(
        key: const ValueKey('release-details-previous'),
        onPressed: _page == 0 || _moving ? null : () => _move(_page - 1),
        child: const AppText('上一页'),
      );
      final next = GlassPillButton(
        key: const ValueKey('release-details-next'),
        label: _page == _sections.length - 1 ? '完成' : '下一页',
        icon: _page == _sections.length - 1
            ? CupertinoIcons.checkmark
            : CupertinoIcons.arrow_right,
        onPressed: _moving
            ? null
            : () {
                if (_page == _sections.length - 1) {
                  Navigator.pop(context, true);
                } else {
                  _move(_page + 1);
                }
              },
      );
      if (constraints.maxWidth <
          MediaQuery.textScalerOf(context).scale(14) * 8 + 120) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [previous, const SizedBox(height: 6), next],
        );
      }
      return Row(
        children: [
          Expanded(child: previous),
          const SizedBox(width: 12),
          Expanded(child: next),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
            child: GlassOverlaySurface(
              key: const ValueKey('installed-release-details'),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ArchiveCode(
                      'RELEASE / ${widget.version} · ${widget.build}',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: AppText(
                            '本版更新',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        AppText(
                          '${_page + 1}/${_sections.length}',
                          key: const ValueKey('release-details-progress'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification.depth != 0) return false;
                          if (notification is ScrollStartNotification) {
                            _userPaging = notification.dragDetails != null;
                          } else if (notification is ScrollEndNotification) {
                            _userPaging = false;
                          }
                          return false;
                        },
                        child: PageView.builder(
                          key: const ValueKey('release-details-pages'),
                          controller: _pages,
                          itemCount: _sections.length,
                          onPageChanged: (page) {
                            if (_userPaging && page != _page) {
                              AppHaptics.play(context, HapticCue.pageTurn);
                            }
                            setState(() => _page = page);
                          },
                          itemBuilder: (context, index) =>
                              SingleChildScrollView(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    AppText(
                                      _sections[index].title,
                                      key: ValueKey('release-section-$index'),
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    for (final item in _sections[index].items)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        child: ReleaseNotes(
                                          item == currentReleaseSourcePolicy
                                              ? '> **$item**'
                                              : index == 0
                                              ? item
                                              : '- $item',
                                          style: TextStyle(
                                            fontSize:
                                                item ==
                                                    currentReleaseSourcePolicy
                                                ? 16
                                                : 14,
                                            fontWeight:
                                                item ==
                                                    currentReleaseSourcePolicy
                                                ? FontWeight.w700
                                                : FontWeight.normal,
                                            height: 1.75,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _navigation(context),
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
