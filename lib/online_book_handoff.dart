import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'book_identity.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'reader_content.dart';

/// An online handoff contains identities and a source coordinate, never a body,
/// image URL, login session or device-specific scroll geometry.
class OnlineBookHandoff {
  const OnlineBookHandoff._({
    required this.book,
    required this.chapterTitle,
    required this.position,
    required this.contentDigest,
  });

  final Novel book;
  final String chapterTitle;
  final ReadingPosition position;
  final String contentDigest;

  /// Uses the sender's repository only to establish the coordinate revision.
  /// The receiver must independently obtain the same chapter through its own
  /// repository before this position can be opened.
  static Future<OnlineBookHandoff> prepare({
    required Novel book,
    required ReadingPosition position,
    required NovelRepository repository,
  }) async {
    if (book.id <= 0 || isLocalBook(book.id) || position.chapterId <= 0) {
      throw const FormatException('这本书没有有效的在线续读标识');
    }
    final matches = book.chapters.where((c) => c.id == position.chapterId);
    if (matches.length != 1) {
      throw const FormatException('当前章节尚未准备好，请加载正文后再发送续读');
    }
    final chapter = matches.single;
    final content = await _content(repository, book.id, chapter);
    if (position.contentRevision != content.revision) {
      throw const FormatException('当前正文版本已变化，请重新打开本章后再发送续读');
    }
    final paragraph =
        position.paragraphIndex ??
        (position.fraction == 0 && position.offset == 0 ? 0 : null);
    if (paragraph == null) {
      throw const FormatException('当前阅读位置尚未准备好，请稍后再发送续读');
    }
    final normalized = ReadingPosition.fromJson({
      ...position.toJson(),
      'paragraphIndex': paragraph,
      'textOffset': position.textOffset ?? 0,
    });
    _validateAnchor(content, normalized);
    return OnlineBookHandoff.fromJson({
      'source': 'wenku8',
      'bookId': book.id,
      'title': book.title,
      'chapterTitle': chapter.title,
      'position': _coordinate(normalized),
      'contentDigest': await _digest(content),
    });
  }

  /// Reject malformed coordinates rather than letting ReadingPosition's legacy
  /// compatibility defaults turn them into a different valid-looking location.
  factory OnlineBookHandoff.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('在线续读信息格式有误');
    final id = raw['bookId'];
    final title = raw['title'];
    final chapterTitle = raw['chapterTitle'];
    final coordinate = raw['position'];
    final digest = raw['contentDigest'];
    if (raw['source'] != 'wenku8' ||
        id is! int ||
        id <= 0 ||
        isLocalBook(id) ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 2048 ||
        chapterTitle is! String ||
        chapterTitle.length > 2048 ||
        coordinate is! Map ||
        digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('在线续读信息缺少书籍或章节标识');
    }
    for (final key in [
      'chapter',
      'chapterId',
      'paragraphIndex',
      'textOffset',
      'updatedAt',
    ]) {
      final value = coordinate[key];
      if (value is! int || value < 0 || (key == 'chapterId' && value == 0)) {
        throw const FormatException('在线续读位置格式有误');
      }
    }
    for (final key in ['fraction', 'paragraphFraction']) {
      final value = coordinate[key];
      if (value is! num || !value.isFinite || value < 0 || value > 1) {
        throw const FormatException('在线续读位置格式有误');
      }
    }
    final revision = coordinate['contentRevision'];
    if (revision is! String ||
        revision.length > 256 ||
        coordinate['chapter'] > 100000 ||
        coordinate['updatedAt'] >
            DateTime.now().millisecondsSinceEpoch + 300000) {
      throw const FormatException('在线续读位置版本有误');
    }
    final position = ReadingPosition.fromJson({
      for (final key in [
        'chapter',
        'chapterId',
        'paragraphIndex',
        'textOffset',
        'updatedAt',
        'fraction',
        'paragraphFraction',
        'contentRevision',
      ])
        key: coordinate[key],
    });
    return OnlineBookHandoff._(
      book: Novel.fromSnapshot({'id': id, 'title': title}),
      chapterTitle: chapterTitle,
      position: position,
      contentDigest: digest,
    );
  }

  Map<String, Object> toJson() => {
    'source': 'wenku8',
    'bookId': book.id,
    'title': book.title,
    'chapterTitle': chapterTitle,
    'position': _coordinate(position),
    'contentDigest': contentDigest,
  };

  static Map<String, Object> _coordinate(ReadingPosition position) => {
    'chapter': position.chapter,
    'chapterId': position.chapterId,
    'paragraphIndex': position.paragraphIndex!,
    'textOffset': position.textOffset ?? 0,
    'updatedAt': position.updatedAt,
    'fraction': position.fraction,
    'paragraphFraction': position.paragraphFraction,
    'contentRevision': position.contentRevision,
  };

  /// Loads using the receiving device's access, validates exact source identity,
  /// and leaves local progress untouched on every failure path.
  Future<({Novel book, ReadingPosition position})> resolve(
    NovelRepository repository,
  ) async {
    final Novel? found;
    final Novel detailed;
    try {
      found = await repository.find(book.id);
      if (found == null || found.id != book.id) {
        throw const FormatException('接收设备找不到这本在线书，未更改阅读位置');
      }
      detailed = await repository.detail(found);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('接收设备无法加载在线书，请检查本机的官网登录状态与网络后重试');
    }
    if (detailed.id != book.id) {
      throw const FormatException('两端书籍标识不一致，未更改阅读位置');
    }
    final matches = [
      for (final (index, chapter) in detailed.chapters.indexed)
        if (chapter.id == position.chapterId) (index, chapter),
    ];
    if (matches.length != 1) {
      throw const FormatException('接收设备的目录找不到目标章节，请更新目录后重试；未跳转到其他章节');
    }
    final (index, chapter) = matches.single;
    final content = await _content(repository, book.id, chapter);
    if (content.revision != position.contentRevision ||
        await _digest(content) != contentDigest) {
      throw const FormatException('两台设备的章节正文版本不一致，请更新本章后重新发送续读；未更改阅读位置');
    }
    _validateAnchor(content, position);
    return (
      book: detailed,
      position: ReadingPosition.fromJson({
        ...position.toJson(),
        'chapter': index,
        'offset': 0,
        'width': 0,
        'layout': '',
      }),
    );
  }

  static Future<ReaderContent> _content(
    NovelRepository repository,
    int bookId,
    NovelChapter chapter,
  ) async {
    final String body;
    try {
      body = await repository.chapterContent(bookId, chapter);
    } catch (_) {
      throw const FormatException('本机无法读取目标章节，请检查官网登录状态与网络后重试；已有缓存的章节可离线续读');
    }
    return ReaderContent.parse(body);
  }

  static void _validateAnchor(ReaderContent content, ReadingPosition position) {
    final paragraph = position.paragraphIndex;
    if (paragraph == null ||
        paragraph < 0 ||
        paragraph >= content.paragraphs.length ||
        (position.textOffset ?? 0) > content.paragraphs[paragraph].length) {
      throw const FormatException('目标段落位置已变化，请重新发送续读；未更改阅读位置');
    }
  }

  static Future<String> _digest(ReaderContent content) async {
    // This digest enforces cross-device coordinate integrity, not file identity.
    // Mirror image hosts may differ without changing paragraph coordinates.
    final bytes = utf8.encode(
      jsonEncode([
        for (final text in content.paragraphs)
          readerIllustrationUrl(text) == null ? text : '[插图]',
      ]),
    );
    final hash = await Sha256().hash(bytes);
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
