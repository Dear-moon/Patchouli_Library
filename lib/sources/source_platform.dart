import 'package:flutter/services.dart';
import 'book_source.dart';
import 'source_account.dart';
import 'wenku_catalog_driver.dart';

class SourcePlatform {
  const SourcePlatform({this.wenku});
  final WenkuCatalogDriver? wenku;
  static const channel = MethodChannel('org.mewx.wenku8/book_sources');
  static Map<String, dynamic> Function()? environmentProvider;
  static final _downloads = <String, void Function(int, int?)>{};
  static int _nextDownload = 0;
  static void reportDownloadProgress(Map<String, dynamic> data) =>
      _downloads[data['id']]?.call(
        (data['received'] as num).toInt(),
        (data['total'] as num?)?.toInt(),
      );
  Future<dynamic> run(
    BookSource source,
    String operation, {
    String? url,
    String key = '',
    int page = 1,
    Map<String, dynamic>? book,
    Map<String, dynamic>? chapter,
    String? requestId,
    bool background = false,
    void Function(int received, int? total)? onDownloadProgress,
  }) async {
    final id =
        requestId ??
        (onDownloadProgress == null
            ? null
            : 'source-download-${++_nextDownload}');
    if (onDownloadProgress != null) _downloads[id!] = onDownloadProgress;
    try {
      return await channel.invokeMethod<dynamic>('run', {
        'source': source.data,
        'operation': operation,
        'url': url,
        'key': key,
        'page': page,
        'book': book,
        'chapter': chapter,
        'requestId': id,
        if (background) 'background': true,
        if (environmentProvider != null) 'environment': environmentProvider!(),
      });
    } on PlatformException catch (error) {
      throw SourceFailure(error.message ?? '书源请求未完成');
    } finally {
      if (onDownloadProgress != null) _downloads.remove(id);
    }
  }

  Future<void> pauseConnections() async {
    try {
      await channel.invokeMethod<void>('pauseConnections');
    } on MissingPluginException {
      // Offline-only hosts have no native source connections.
    }
  }

  Future<void> cancel(String requestId) =>
      channel.invokeMethod('cancel', requestId);
  Future<BookSource> inspectScript(String text) async => BookSource(
    Map<String, dynamic>.from(
      await channel.invokeMapMethod<String, dynamic>('inspectScript', text) ??
          (throw const SourceFailure('JS 书源配置未返回')),
    ),
  );
  Future<String?> pick() => channel.invokeMethod<String>('pick');
  Future<bool> export(String text) async =>
      await channel.invokeMethod<bool>('export', text) ?? false;
  Future<String> fetchImport(String url) async =>
      (await channel.invokeMethod<String>('fetchImport', url))!;
  Future<Uint8List> image({
    required String url,
    BookSource? source,
    String? sourceKey,
    String? referrer,
    bool cachedOnly = false,
    bool isCover = false,
    Map<String, dynamic>? book,
  }) async {
    final bytes = await channel.invokeMethod<Uint8List>('image', {
      'url': url,
      'source': source?.data,
      'sourceKey': sourceKey ?? source?.key,
      'referrer': referrer,
      'cachedOnly': cachedOnly,
      'isCover': isCover,
      'book': book,
      if (environmentProvider != null) 'environment': environmentProvider!(),
    });
    if (bytes == null || bytes.isEmpty) throw const SourceFailure('图片未缓存或无法读取');
    return bytes;
  }

  Future<void> clearImages() => channel.invokeMethod('clearImages');
  Future<SourceAccountStatus> accountStatus(BookSource source) async {
    try {
      final result = await channel.invokeMapMethod<dynamic, dynamic>(
        'accountStatus',
        source.data,
      );
      if (result == null) throw const SourceFailure('书源账号状态未返回');
      return SourceAccountStatus.fromMap(result);
    } on PlatformException catch (error) {
      throw SourceFailure(error.message ?? '书源账号状态暂不可用');
    }
  }

  Future<void> openLogin(BookSource source, {required String requestId}) async {
    try {
      await channel.invokeMethod('openLogin', {
        'source': source.data,
        'requestId': requestId,
        if (environmentProvider != null) 'environment': environmentProvider!(),
      });
    } on PlatformException catch (error) {
      throw SourceFailure(error.message ?? '网页登录未完成');
    }
  }

  Future<void> clearSession(BookSource source) =>
      channel.invokeMethod('clearSession', source.key);
}
