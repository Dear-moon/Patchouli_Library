import 'package:flutter/cupertino.dart';
import '../app_interactions.dart';
import '../app_ui.dart';
import '../catalog.dart';
import '../feature_pages.dart';
import '../library_state.dart';
import '../wenku_features.dart';
import 'source_account_card.dart';
import 'source_login_page.dart';
import 'source_platform_ui.dart';
import 'source_repository.dart';
import 'source_account.dart';
import 'source_declarations.dart';
import 'platform_account_identity.dart';

class PlatformAccountPage extends StatelessWidget {
  const PlatformAccountPage({
    super.key,
    required this.repository,
    required this.state,
  });
  final NovelRepository repository;
  final LibraryState state;

  Future<void> _openPlatform(
    BuildContext context,
    BookPlatform platform,
  ) async {
    final sources = sourceRepositoryOf(repository);
    final account = WenkuFeaturesScope.maybeOf(context)?.account;
    if (platform.isWenku) {
      if (account == null) return;
      await pushNovelPage<void>(
        context,
        WenkuAccountPage(
          account: account,
          state: state,
          repository: repository,
        ),
        reduceMotion: state.reduceMotion,
      );
    } else {
      await pushNovelPage<void>(
        context,
        SourceLoginPage(source: platform.sources.first, repository: sources!),
        reduceMotion: state.reduceMotion,
      );
    }
  }

  Future<void> _chooseOther(
    BuildContext context,
    List<BookPlatform> platforms,
  ) async {
    final sources = sourceRepositoryOf(repository);
    final account = WenkuFeaturesScope.maybeOf(context)?.account;
    final choice = await showGlassMenu<BookPlatform>(
      context: context,
      reduceMotion: state.reduceMotion,
      builder: (_) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, platform) in platforms.indexed)
              if (platform.isWenku)
                GlassMenuItem(
                  key: ValueKey('other-account-${platform.key}'),
                  order: index,
                  label:
                      '${platform.name} · ${account?.authenticated == true ? '已登录' : '未登录'}',
                  onPressed: () => Navigator.pop(context, platform),
                )
              else
                FutureBuilder<SourceAccountStatus>(
                  future: sources!.accountStatus(platform.sources.first),
                  builder: (menuContext, snapshot) => GlassMenuItem(
                    key: ValueKey('other-account-${platform.key}'),
                    order: index,
                    label:
                        '${platform.name} · ${snapshot.data?.label ?? '读取中'}',
                    onPressed: () => Navigator.pop(context, platform),
                  ),
                ),
          ],
        ),
      ),
    );
    if (choice != null && context.mounted) await _openPlatform(context, choice);
  }

  @override
  Widget build(BuildContext context) {
    final sources = sourceRepositoryOf(repository);
    final account = WenkuFeaturesScope.maybeOf(context)?.account;
    return ArchiveFeaturePage(
      title: '账号与登录',
      code: 'PLATFORMS / ACCOUNTS',
      child: AnimatedBuilder(
        animation: Listenable.merge([
          ?sources,
          ?account,
          ?sources?.accountChanges,
        ]),
        builder: (context, _) {
          final current = currentAccountPlatform(sources);
          final others = bookPlatforms(
            sources?.store.sources ?? [],
            includeWenku: true,
          ).where((platform) => platform.key != current.key).toList();
          return ListView(
            padding: featurePadding(context),
            children: [
              ContentPanel(
                key: ValueKey('platform-account-${current.key}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PlatformAccountIdentity(
                      key: ValueKey('identity-${current.key}'),
                      platform: current,
                      repository: sources,
                      wenku: account,
                    ),
                    const SizedBox(height: 14),
                    if (current.sources.isNotEmpty)
                      SourceAccountPanel(
                        source: current.sources.first,
                        repository: sources!,
                        library: state,
                      ),
                    GlassTextButton(
                      key: const ValueKey('primary-platform-login'),
                      compact: true,
                      onPressed: current.sources.isEmpty
                          ? null
                          : () => _openPlatform(context, current),
                      child: const AppText('登录／管理账号'),
                    ),
                    if (current.sources.isNotEmpty &&
                        SourceDeclarations.sessionKey(
                              current.sources.first.key,
                            ) !=
                            current.sources.first.key)
                      const AppText(
                        '所有译文版本共用此账号。',
                        style: TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 18),
                GlassMenuAnchor(
                  child: Builder(
                    builder: (anchor) => GlassTextButton(
                      key: const ValueKey('other-platform-accounts'),
                      onPressed: () => _chooseOther(anchor, others),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppText('其他平台账号'),
                          SizedBox(width: 10),
                          ArchiveIcon(CupertinoIcons.chevron_down, size: 14),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const AppText(
                '各平台账号独立管理。签到需手动操作。',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ],
          );
        },
      ),
    );
  }
}
