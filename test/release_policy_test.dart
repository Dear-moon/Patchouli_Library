import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/updates/app_updates.dart';
import 'package:wenku8_flutter/updates/release_highlights.dart';
import 'package:wenku8_flutter/updates/current_release_content.dart';

void main() {
  test('package and in-app version identifiers stay aligned', () {
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(version, '$currentAppVersion+$currentAppBuild');
  });

  test('current release upgrades the restored and earlier app versions', () {
    expect(currentAppVersion, '0.4.7');
    expect(currentAppBuild, 183);
    final release = AppRelease.fromGithub({
      'tag_name': 'v$currentAppVersion',
      'draft': false,
      'prerelease': false,
      'body': currentReleaseNotes,
      'assets': [
        for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64'])
          {
            'id': 100 + abi.length,
            'name': 'wenku8-$currentAppVersion-$abi.apk',
            'size': 57000000,
            'browser_download_url':
                'https://github.com/$officialUpdateRepository/releases/download/v$currentAppVersion/wenku8-$currentAppVersion-$abi.apk',
          },
      ],
    }, officialUpdateRepository)!;
    for (final old in [
      (version: '0.3.7', build: 63),
      (version: '0.4.0', build: 87),
      (version: '0.4.1', build: 88),
      (version: '0.4.2', build: 139),
      (version: '0.4.2', build: 144),
      (version: '0.4.3', build: 145),
      (version: '0.4.4', build: 153),
      (version: '0.4.4', build: 154),
      (version: '0.4.5', build: 155),
      (version: '0.4.5', build: 162),
      (version: '0.4.6', build: 163),
      (version: '0.4.6', build: 182),
    ]) {
      expect(
        release.isNewerThan(
          InstalledApp(
            version: old.version,
            build: old.build,
            abis: const ['arm64-v8a'],
          ),
        ),
        isTrue,
      );
    }
    for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
      expect(
        release.assetFor([abi])?.name,
        'wenku8-$currentAppVersion-$abi.apk',
      );
    }
  });

  test('public notes omit contacts while in-app notices retain them', () {
    const fixedOpening = r'''**交流群：1131397088**\
遇到问题或有功能建议，欢迎进群反馈。

### ⚠️ 免费开源，请勿付费

**本项目完全免费、开源，无任何赞助、打赏或付费渠道。**

不出售会员、激活码或功能解锁服务。任何以本项目或开发者名义收费、募捐、索要赞助的行为均与本项目无关，请勿付款。

请通过**项目仓库或 App 内更新**获取安装包。''';
    expect(currentReleaseNotes, startsWith(fixedOpening));
    expect(currentReleaseSummary.first, inAppCommunityNotice);
    expect(currentReleaseSummary[1], releaseFreeNotice);
    expect(currentReleaseSummary[2], releaseReadingNotice);
    expect(currentReleaseSummary[3], currentReleaseSourcePolicy);
    expect(currentReleaseSections.first.title, contains('重要说明'));
    expect(currentReleaseSections.first.items.last, currentReleaseSourcePolicy);
    expect(currentReleaseSections, hasLength(6));
    expect(currentReleaseSections[1].title, '阅读器与翻页');
    expect(currentReleaseSections[1].items, hasLength(8));
    expect(currentReleaseSections.last.title, '评论与联网阅读');
    expect(currentReleaseSections.last.items.last, contains('插图连接超时'));
    expect(currentReleaseNotes, contains('左右点按均为下一页'));
    expect(currentReleaseNotes, contains('强制竖屏'));
    expect(currentReleaseNotes, contains('每种语言单独配置音色'));
    for (final hidden in ['发布前待确认', '仍需补齐真机验收', '仅复制故障码', '加密', '故障排查']) {
      expect(currentReleaseNotes, isNot(contains(hidden)));
    }
    expect(currentReleaseNotes, contains(currentReleaseSourcePolicy));
    expect(currentReleaseNotes, isNot(contains('未加入其他功能调整或问题修复')));
    expect(currentReleaseNotes, contains(releaseReadingNotice));
    expect(currentReleaseSections.first.items.first, inAppCommunityNotice);
    expect(publicReleaseNotes, startsWith('### ⚠️ 免费开源，请勿付费'));
    expect(currentReleaseNotes, contains(inAppCommunityNotice));
    expect(publicReleaseNotes, isNot(contains('交流群')));
    expect(publicReleaseNotes, isNot(contains('1131397088')));
    expect(publicReleaseNotes, contains(releaseFreeNotice));
    expect(publicReleaseNotes, contains('因版权限制而停止开放'));
    expect(publicReleaseNotes, isNot(contains('MewX')));
    expect(publicReleaseNotes, isNot(contains('API')));
    expect(publicReleaseNotes, contains('免费开源，请勿付费'));
    final changelog = File('CHANGELOG.md').readAsStringSync();
    expect(changelog, isNot(contains('1131397088')));
    final readme = File('README.md').readAsStringSync();
    expect(readme, isNot(contains('1131397088')));
    final currentChangelog = changelog.split(
      RegExp(r'^## ', multiLine: true),
    )[1];
    final publishedNotes = currentChangelog
        .substring(currentChangelog.indexOf('\n') + 1)
        .trim();
    expect(publishedNotes, publicReleaseNotes.trim());
  });
}
