import 'package:flutter/services.dart';

/// The same v1.30 POST bridge. Account cookies never cross into Dart or backups.
abstract final class LegacyTransport {
  static Future<dynamic> _source(
    String method, [
    Map<String, dynamic> arguments = const {},
  ]) => Future.error(UnsupportedError('旧版内置接口已移除，请导入新版书源规则'));
  static Future<Uint8List> cover(int id) async =>
      (await _source('cover', {'aid': id})) as Uint8List;

  static Future<void> setUpdatePriority(bool enabled) async {
    try {
      await _source('updatePriority', {'enabled': enabled});
    } on MissingPluginException {
      // Non-Android clients keep the original transport.
    }
  }

  static Future<String> request(String action) => _text('request', action);
  static Future<String> accountRequest(String action) =>
      _text('accountRequest', action);

  /// Read-only routes which the service may gate behind a signed-in session.
  /// Public discovery/search remain independent from account cookies.
  static Future<String> sessionRead(String action) async =>
      await hasSession() ? accountRequest(action) : request(action);
  static Future<String> login(String action) => _text('login', action);
  static Future<Uint8List> accountAvatar() async {
    final bytes = await _source('accountAvatar') as Uint8List?;
    if (bytes == null || bytes.isEmpty) throw const FormatException('账号暂无头像');
    return bytes;
  }

  static Future<String> _text(String method, String action) async {
    final text = await _source(method, {'action': action}) as String?;
    if (text == null || text.trim().isEmpty) {
      throw const FormatException('接口返回空内容');
    }
    return text;
  }

  static Future<bool> hasSession() async => await _source('hasSession') == true;
  static Future<void> clearSession() =>
      Future.error(UnsupportedError('请在书源账号页清除登录信息'));
  static Future<void> connectPublications(
    String username,
    String password,
  ) async {
    try {
      await _source('webLogin', {'username': username, 'password': password});
    } on PlatformException catch (failure) {
      if (failure.code.startsWith('WEB_')) {
        throw FormatException(failure.message ?? '分类连接未成功');
      }
      rethrow;
    }
  }

  static Future<String> publicationPage(int library, int page) async =>
      (await _source('publicationPage', {'library': library, 'page': page}))
          as String? ??
      '';
  static Future<Uint8List> Function(String) illustrationReader =
      _readIllustration;
  static Future<Uint8List> illustration(
    String url, {
    bool cacheForViewing = true,
  }) => illustrationReader(url);

  static Future<Uint8List> _readIllustration(String url) async {
    final bytes = await _source('illustration', {'url': url}) as Uint8List?;
    if (bytes == null || bytes.isEmpty) throw const FormatException('插图内容为空');
    return bytes;
  }

  static Future<void> clearIllustrations() =>
      _source('clearIllustrations').then((_) {});
  static Future<String> encodeReview(String text) async {
    try {
      final encoded = await _source('encodeReview', {'text': text}) as String?;
      if (encoded == null || encoded.isEmpty) {
        throw const FormatException('书评编码返回空内容');
      }
      return encoded;
    } on PlatformException catch (error) {
      if (error.code == 'REVIEW_ENCODING') {
        throw const FormatException('原版书评接口使用 GBK，请移除表情或特殊字符后重试；草稿仍保留');
      }
      rethrow;
    }
  }
}
