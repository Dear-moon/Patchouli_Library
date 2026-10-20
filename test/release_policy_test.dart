import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/updates/app_updates.dart';
import 'package:wenku8_flutter/updates/release_highlights.dart';

void main() {
  test('package and in-app version identifiers stay aligned', () {
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(version, '$currentAppVersion+$currentAppBuild');
  });

  test('current release upgrades the restored and earlier app versions', () {
    expect(currentAppVersion, '0.4.3');
    expect(currentAppBuild, greaterThan(144));
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

  test(
    'source policy remains first, prominent and repeated alongside current notes',
    () {
      expect(currentReleaseSummary.first, currentReleaseSourcePolicy);
      expect(currentReleaseSections.first.title, contains('重要说明'));
      expect(
        currentReleaseSections.first.items.first,
        currentReleaseSourcePolicy,
      );
      expect(
        currentReleaseSections.last.items.last,
        contains(currentReleaseSourcePolicy),
      );
      expect(currentReleaseNotes, contains(currentReleaseSourcePolicy));
      expect(currentReleaseNotes, isNot(contains('未加入其他功能调整或问题修复')));
    },
  );
}
