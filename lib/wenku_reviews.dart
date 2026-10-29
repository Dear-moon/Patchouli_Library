import 'package:flutter/foundation.dart';
import 'online_component.dart';

class WenkuReview {
  const WenkuReview({
    required this.id,
    required this.user,
    required this.userId,
    required this.title,
    required this.content,
    required this.timestamp,
    required this.replies,
  });
  final int id, userId, replies;
  final String user, title, content, timestamp;
  String get identity => id > 0 ? '$id' : '$userId/$timestamp/$content';
  String get date => RegExp(r'^\d{14}$').hasMatch(timestamp)
      ? '${timestamp.substring(0, 4)}-${timestamp.substring(4, 6)}-${timestamp.substring(6, 8)} ${timestamp.substring(8, 10)}:${timestamp.substring(10, 12)}'
      : timestamp;
}

class WenkuReviewPage {
  const WenkuReviewPage(this.items, this.totalPages);
  final List<WenkuReview> items;
  final int totalPages;
}

typedef ReviewPageReader =
    Future<WenkuReviewPage> Function(int id, int page, bool replies);

class WenkuReviewFeed extends ChangeNotifier {
  WenkuReviewFeed({
    required this.id,
    this.replies = false,
    ReviewPageReader? read,
  }) : _read = read ?? ((_, _, _) => unavailableOnline());
  final int id;
  final bool replies;
  final ReviewPageReader _read;
  final _identities = <String>{};
  List<WenkuReview> items = const [];
  int page = 0, totalPages = 0, revision = 0, firstIndex = 0;
  bool loading = false, hasMore = true, requiresLogin = false;
  String? error;
  int _generation = 0;
  bool _disposed = false, _failedRefresh = false;
  Future<void> load({bool refresh = false}) async {
    refresh = refresh || _failedRefresh;
    if (_disposed || (loading && !refresh) || (!refresh && !hasMore)) return;
    final generation = ++_generation;
    final next = refresh ? 1 : page + 1;
    loading = true;
    error = null;
    requiresLogin = false;
    notifyListeners();
    try {
      final result = await _read(id, next, replies);
      if (_disposed || generation != _generation) return;
      final old = refresh ? <WenkuReview>[] : items;
      if (refresh) _identities.clear();
      final added = result.items
          .where((item) => _identities.add(item.identity))
          .toList();
      firstIndex = old.length;
      items = List.unmodifiable([...old, ...added]);
      page = next;
      totalPages = result.totalPages;
      _failedRefresh = false;
      revision++;
      hasMore = next < result.totalPages;
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = failure is OnlineComponentUnavailable
          ? failure.toString()
          : '暂时无法读取书评，请稍后重试';
      requiresLogin = failure is OnlineAuthenticationRequired;
      _failedRefresh = refresh;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
