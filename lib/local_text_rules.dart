import 'dart:async';
import 'dart:isolate';
import 'local_import_options.dart';

const localHeadingNone = 0, localHeadingVolume = 1, localHeadingChapter = 2;

final _decoratedDefaultHeading = RegExp(r'^(={2,})\s*(.*?)\s*\1$');

/// Some TXT exports surround directory lines with matching `===` markers.
/// Use this candidate only for default heading recognition; unmatched prose and
/// custom expressions retain their exact text and original source coordinates.
String defaultLocalHeadingCandidate(String line) {
  final candidate = _decoratedDefaultHeading.firstMatch(line)?.group(2)?.trim();
  if (candidate == null ||
      candidate.startsWith('=') ||
      candidate.endsWith('=')) {
    return line;
  }
  return candidate;
}

/// A custom expression runs in one small, persistent rule worker per import.
/// Only matching is timed: slow file I/O never looks like a stuck expression,
/// and a bad rule cannot freeze the UI or strand the book-import worker.
class LocalTextRuleMatcher {
  LocalTextRuleMatcher._(this.options, this.timeout);
  final LocalImportOptions options;
  final Duration timeout;
  Isolate? _worker;
  final _events = ReceivePort(), _errors = ReceivePort(), _exit = ReceivePort();
  final _ready = Completer<SendPort>();
  final _stopped = Completer<void>();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Completer<List<int>>? _pending;
  SendPort? _requests;
  bool _closed = false;

  static Future<LocalTextRuleMatcher> start(
    LocalImportOptions options, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final matcher = LocalTextRuleMatcher._(options.effective, timeout);
    matcher._subscriptions.addAll([
      matcher._events.listen((message) {
        if (matcher._closed) return;
        if (message is SendPort) {
          if (!matcher._ready.isCompleted) matcher._ready.complete(message);
        } else if (message is List<int>) {
          matcher._pending?.complete(message);
        } else {
          matcher._fail(const FormatException('目录表达式格式有误，请检查后重试'));
        }
      }),
      matcher._errors.listen(
        (_) => matcher._fail(const FormatException('目录规则处理失败，请检查表达式')),
      ),
      matcher._exit.listen((_) {
        if (!matcher._stopped.isCompleted) matcher._stopped.complete();
        matcher._fail(const FormatException('目录规则处理已中断，请重试'));
      }),
    ]);
    try {
      matcher._worker = await Isolate.spawn(
        _ruleWorker,
        (matcher._events.sendPort, matcher.options.toJson()),
        onError: matcher._errors.sendPort,
        onExit: matcher._exit.sendPort,
      );
      matcher._requests = await matcher._ready.future.timeout(
        timeout,
        onTimeout: () => throw const FormatException('目录规则处理过慢，请简化表达式后重试'),
      );
      return matcher;
    } catch (_) {
      await matcher.close();
      rethrow;
    }
  }

  void _fail(FormatException error) {
    if (_closed) return;
    if (!_ready.isCompleted) _ready.completeError(error);
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  Future<List<int>> classify(List<String> lines) async {
    if (_closed || _pending != null) {
      throw StateError('Directory matcher is unavailable');
    }
    final result = Completer<List<int>>();
    _pending = result;
    _requests!.send(lines);
    try {
      return await result.future.timeout(
        timeout,
        onTimeout: () {
          _worker?.kill(priority: Isolate.immediate);
          throw const FormatException('目录规则处理过慢，请简化表达式后重试');
        },
      );
    } finally {
      _pending = null;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _worker?.kill(priority: Isolate.immediate);
    try {
      if (_worker != null) {
        await _stopped.future.timeout(const Duration(seconds: 2));
      }
    } finally {
      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      _events.close();
      _errors.close();
      _exit.close();
    }
  }
}

void _ruleWorker((SendPort, Map<String, Object>) job) {
  final (reply, raw) = job;
  final options = LocalImportOptions.fromJson(raw);
  final chapter = RegExp(
    options.customToc ? options.chapterRule : defaultLocalChapterRule,
    caseSensitive: false,
  );
  final volumeText = options.customToc
      ? options.volumeRule
      : defaultLocalVolumeRule;
  final volume = volumeText.isEmpty
      ? null
      : RegExp(volumeText, caseSensitive: false);
  int classify(String line) {
    if (line.isEmpty || line.length > 90) return localHeadingNone;
    final candidate = options.customToc
        ? line
        : defaultLocalHeadingCandidate(line);
    return volume?.hasMatch(candidate) == true
        ? localHeadingVolume
        : chapter.hasMatch(candidate)
        ? localHeadingChapter
        : localHeadingNone;
  }

  final requests = ReceivePort();
  requests.listen((message) {
    final lines = message as List<String>;
    reply.send(<int>[for (final line in lines) classify(line)]);
  });
  reply.send(requests.sendPort);
}

Future<List<({String title, bool volume})>> previewLocalDirectory(
  LocalImportOptions options,
  String sample, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (sample.length > 20000) throw const FormatException('预览文字最多 20000 个字符');
  final lines = sample
      .split(RegExp(r'\r\n?|\n'))
      .map((line) => line.trim())
      .toList();
  final matcher = await LocalTextRuleMatcher.start(options, timeout: timeout);
  try {
    final matches = await matcher.classify(lines);
    return [
      for (var i = 0; i < matches.length; i++)
        if (matches[i] != localHeadingNone)
          (
            title: options.customToc
                ? lines[i]
                : defaultLocalHeadingCandidate(lines[i]),
            volume: matches[i] == localHeadingVolume,
          ),
    ];
  } finally {
    await matcher.close();
  }
}
