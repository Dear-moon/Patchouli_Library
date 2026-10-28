import 'package:flutter/foundation.dart' show Listenable;

abstract interface class LocalBookImportWarningAccess {
  List<LocalBookImportIssue> importIssues(int id);
  bool shouldShowImportWarning(int id);
  Future<void> setImportWarningHidden(int id, bool hidden);
  Listenable get importWarningChanges;
}

enum LocalBookImportIssueKind { chapter, image, resource }

class LocalBookImportIssue {
  const LocalBookImportIssue({
    required this.bookId,
    required this.path,
    required this.reason,
    required this.kind,
    this.chapterIds = const [],
    this.chapterTitles = const [],
  });

  final int bookId;
  final String path, reason;
  final LocalBookImportIssueKind kind;
  final List<int> chapterIds;
  final List<String> chapterTitles;
}
