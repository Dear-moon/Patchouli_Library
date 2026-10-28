import 'dart:io';
import 'app_updates.dart';
import 'ios_update_platform.dart';

/// Same installed-version/project-link contract; Android assets never install
/// on HarmonyOS. Native version information comes from the HAP manifest.
class HarmonyUpdatePlatform extends IOSUpdatePlatform {
  HarmonyUpdatePlatform({super.open});
  @override
  Future<UpdatePackageInfo> inspect(
    File apk,
    String version, {
    int? build,
  }) async => throw UnsupportedError('HarmonyOS 不使用 APK 安装包');
  @override
  Future<String> install(File apk, String version, {int? build}) async =>
      throw UnsupportedError('HarmonyOS 不使用 APK 安装包');
  @override
  Future<void> allowInstalls() async =>
      throw UnsupportedError('HarmonyOS 不使用 Android 安装权限');
}
