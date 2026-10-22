import 'dart:async';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'library_state.dart';

class _ReaderTarget {
  const _ReaderTarget(this.bookId, this.resume);
  final int bookId;
  final void Function(ReadingPosition) resume;
}

/// Explicit handoff reuses the open reader for the same book and replaces it
/// for another book. Its lifetime is not locked until a pushed route is closed.
class ReaderHandoffNavigation extends NavigatorObserver with ChangeNotifier {
  final _routes = <Route<dynamic>>[];
  final _targets = <Route<dynamic>, _ReaderTarget>{};
  bool _disposed = false, _queued = false;
  int? get currentBookId {
    final page = _routes.reversed.whereType<PageRoute<dynamic>>().firstOrNull;
    return _targets[page]?.bookId;
  }

  void _changed() {
    if (_queued || _disposed) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!_disposed) notifyListeners();
    });
  }

  VoidCallback register(
    BuildContext context,
    int bookId,
    void Function(ReadingPosition) resume,
  ) {
    final route = ModalRoute.of(context);
    if (route == null) return () {};
    final target = _ReaderTarget(bookId, resume);
    _targets[route] = target;
    _changed();
    return () {
      if (identical(_targets[route], target)) {
        _targets.remove(route);
        _changed();
      }
    };
  }

  Future<void> open({
    required int bookId,
    required ReadingPosition position,
    required Widget page,
    required bool reduceMotion,
  }) async {
    final nav = navigator;
    if (nav == null || !nav.mounted) {
      throw const FormatException('阅读器暂未准备好，请重试');
    }
    final old = _routes.reversed
        .where((r) => r.isActive && _targets.containsKey(r))
        .firstOrNull;
    if (old != null) {
      final overlays = _routes
          .skipWhile((r) => !identical(r, old))
          .skip(1)
          .toList();
      final target = _targets[old]!;
      nav.popUntil((r) => identical(r, old));
      await Future.wait(
        overlays.whereType<TransitionRoute<dynamic>>().map((r) => r.completed),
      );
      if (!nav.mounted || !old.isActive || !identical(_targets[old], target)) {
        throw const FormatException('书页已关闭，请再点一次继续阅读');
      }
      if (target.bookId == bookId) {
        target.resume(position);
        return;
      }
      if (old.isFirst) {
        // An embedded/root reader must not remove the app's home route.
        unawaited(
          nav.push<void>(softRoute<void>(page, reduceMotion: reduceMotion)),
        );
      } else {
        unawaited(
          nav.pushReplacement<void, void>(
            softRoute<void>(page, reduceMotion: reduceMotion),
          ),
        );
      }
    } else {
      unawaited(
        nav.push<void>(softRoute<void>(page, reduceMotion: reduceMotion)),
      );
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _targets.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index < 0) {
      if (newRoute != null) _routes.add(newRoute);
    } else if (newRoute == null) {
      _routes.removeAt(index);
    } else {
      _routes[index] = newRoute;
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _targets.clear();
    _routes.clear();
    super.dispose();
  }
}

class ReaderHandoffScope extends InheritedWidget {
  const ReaderHandoffScope({
    super.key,
    required this.navigation,
    required super.child,
  });
  final ReaderHandoffNavigation navigation;
  static ReaderHandoffNavigation? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ReaderHandoffScope>()
      ?.navigation;
  @override
  bool updateShouldNotify(ReaderHandoffScope oldWidget) =>
      navigation != oldWidget.navigation;
}
