import 'package:flutter/foundation.dart';
import 'library_state.dart';
import 'online_component.dart';
import 'wenku_shelf_sync.dart' show CloudShelfPlan;

class WenkuProfile {
  const WenkuProfile({
    required this.id,
    required this.username,
    required this.nickname,
    required this.score,
    required this.experience,
    required this.rank,
  });
  final int id, score, experience;
  final String username, nickname, rank;
  String get displayName => nickname.isEmpty ? username : nickname;
}

class CloudBook {
  const CloudBook({
    required this.id,
    this.title = '',
    this.updated = '',
    this.latestChapterId = 0,
    this.latestChapter = '',
  });
  final int id, latestChapterId;
  final String title, updated, latestChapter;
}

class CloudUploadResult {
  const CloudUploadResult(this.uploaded, this.remaining, this.error);
  final List<int> uploaded, remaining;
  final Object? error;
}

/// Domain-facing account state for presentation and local-library integration.
/// No requests, response parsers, service status codes or session material live here.
class WenkuAccount extends ChangeNotifier {
  WenkuAccount();
  Uint8List? avatar;
  bool authenticated = false, busy = false, signedToday = false;
  String? operation, error;
  WenkuProfile? profile;
  List<CloudBook>? cloudBooks;
  int? syncedAt;
  int get sessionRevision => 0;
  int get publicationRevision => 0;
  static String describeError(Object error) =>
      error is OnlineComponentUnavailable ||
          error is OnlineAuthenticationRequired
      ? error.toString()
      : error is FormatException
      ? error.message.toString()
      : '网络或本地存储暂时异常，请重试';
  Future<void> initialize() async {}
  Future<T> _unavailable<T>() async {
    error = OnlineComponentUnavailable.message;
    notifyListeners();
    throw const OnlineComponentUnavailable();
  }

  Future<void> login(String username, String password) => _unavailable();
  Future<void> connectPublications(String password) => _unavailable();
  Future<void> refreshProfile() => _unavailable();
  Future<void> signIn() => _unavailable();
  Future<List<CloudBook>> refreshCloud() => _unavailable();
  Future<CloudShelfPlan> exchangeShelf({
    required Set<int> local,
    Set<int>? lastLocal,
    Set<int>? lastCloud,
  }) => _unavailable();
  Future<CloudUploadResult> uploadMissing(Set<int> localIds) => _unavailable();
  Future<void> addCloud(int id) => _unavailable();
  Future<void> removeCloud(int id) => _unavailable();
  Future<void> recommend(int id) => _unavailable();
  Future<void> postReview({
    required int bookId,
    required String title,
    required String content,
  }) => _unavailable();
  Future<void> replyReview({required int threadId, required String content}) =>
      _unavailable();
  Future<int> mergeCloudToLocal(LibraryState state) => _unavailable();
  Future<void> logout() async {
    authenticated = false;
    profile = null;
    avatar = null;
    cloudBooks = null;
    signedToday = false;
    error = null;
    notifyListeners();
  }
}
