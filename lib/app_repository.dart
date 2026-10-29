import 'catalog.dart';
import 'local_books.dart';
import 'network_status.dart';
import 'offline_cache.dart';
import 'offline_repository.dart';

/// Persistence belongs to the app, not to the Android transport. Every host
/// opens the same library/position contracts; only remote I/O is platform-specific.
Future<OfflineNovelRepository> openApplicationLibrary({
  required NovelRepository remote,
  NetworkStatus? network,
}) async => OfflineNovelRepository(
  remote: remote,
  cache: await OfflineCacheStore.forApp(),
  local: await LocalBookStore.forApp(),
  network: network,
);
