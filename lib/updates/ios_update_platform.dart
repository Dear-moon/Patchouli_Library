import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_updates.dart';

/// Installed-version notices and project links do not require an APK installer.
/// iOS distribution stays with the signing/distribution mechanism, not Android
/// release assets published in the same repository.
class IOSUpdatePlatform implements UpdatePlatform {
  IOSUpdatePlatform({Future<bool> Function(Uri)? open})
    : _open =
          open ??
          ((page) => launchUrl(page, mode: LaunchMode.externalApplication));

  static const _channel = MethodChannel('org.mewx.wenku8/reader_controls');
  final Future<bool> Function(Uri) _open;

  @override
  Future<InstalledApp> installedApp() async {
    final info = await _channel.invokeMapMethod<String, Object?>(
      'installedApp',
    );
    final version = info?['appVersion'], build = info?['appBuild'];
    if (version is! String ||
        ReleaseVersion.parse(version) == null ||
        build is! int ||
        build <= 0) {
      throw const FormatException('无法读取当前版本');
    }
    return InstalledApp(version: version, build: build, abis: const []);
  }

  @override
  Future<void> openRelease(Uri page) async {
    if (page.scheme != 'https' ||
        page.host.isEmpty ||
        page.userInfo.isNotEmpty ||
        !await _open(page)) {
      throw const FormatException('暂时无法打开项目页面');
    }
  }

  @override
  Future<UpdatePackageInfo> inspect(
    File apk,
    String version, {
    int? build,
  }) async => throw UnsupportedError('iOS 不使用 APK 安装包');
  @override
  Future<String> install(File apk, String version, {int? build}) async =>
      throw UnsupportedError('iOS 不使用 APK 安装包');
  @override
  Future<void> allowInstalls() async =>
      throw UnsupportedError('iOS 不使用 Android 安装权限');
}
