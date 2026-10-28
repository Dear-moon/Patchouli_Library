import 'dart:io';
import 'package:flutter/services.dart';
import 'book_import_limits.dart';

class BookDocumentSelection {
  const BookDocumentSelection({
    required this.name,
    this.path,
    this.error,
    this.originReference,
    this.originName,
  }) : token = null,
       reference = null,
       assert((path == null) != (error == null));
  const BookDocumentSelection.pending({required this.name, required this.token})
    : path = null,
      reference = null,
      originReference = null,
      originName = null,
      error = null;
  const BookDocumentSelection.linked({
    required this.name,
    required this.reference,
  }) : path = null,
       token = null,
       originReference = null,
       originName = null,
       error = null;
  final String name;
  final String? path, error, token, reference;
  final String? originReference, originName;

  factory BookDocumentSelection.fromMap(Map<dynamic, dynamic> value) =>
      value['reference'] is String
      ? BookDocumentSelection.linked(
          name: value['name'] as String,
          reference: value['reference'] as String,
        )
      : value['token'] is String
      ? BookDocumentSelection.pending(
          name: value['name'] as String,
          token: value['token'] as String,
        )
      : BookDocumentSelection(
          name: value['name'] as String,
          path: value['path'] as String?,
          error: value['error'] as String?,
        );
}

class BookScanFolder {
  const BookScanFolder({
    required this.name,
    required this.automatic,
    required this.readable,
    this.allStorage = false,
  });
  factory BookScanFolder.fromMap(Map<dynamic, dynamic> value) => BookScanFolder(
    name: value['name'] as String,
    automatic: value['automatic'] == true,
    readable: value['readable'] == true,
    allStorage: value['all'] == true,
  );
  final String name;
  final bool automatic, readable;
  final bool allStorage;
}

class BookOpenRequest {
  const BookOpenRequest({
    required this.id,
    required this.name,
    required this.canLink,
    this.error,
  });
  factory BookOpenRequest.fromMap(Map<dynamic, dynamic> value) =>
      BookOpenRequest(
        id: value['id'] as String,
        name: value['name'] as String,
        canLink: value['canLink'] == true,
        error: value['error'] as String?,
      );
  final String id, name;
  final bool canLink;
  final String? error;
}

typedef BookScanEntry = ({String token, String name});

class BookScanSnapshot {
  const BookScanSnapshot({
    required this.books,
    this.total = 0,
    this.unchanged = 0,
    this.warnings = const [],
    this.details = const {},
  });
  final List<BookScanEntry> books;
  final int total, unchanged;
  final List<String> warnings;
  final Map<String, ({int? size, String folder})> details;
}

class BookDocuments {
  static const channel = MethodChannel('org.mewx.wenku8/book_documents');
  Future<BookOpenRequest?> pendingOpen() async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'pendingBookOpen',
    );
    return value == null ? null : BookOpenRequest.fromMap(value);
  }

  Future<BookDocumentSelection> resolveOpen(
    String id, {
    bool copy = false,
  }) async => BookDocumentSelection.fromMap(
    (await channel.invokeMapMethod<String, dynamic>('resolveBookOpen', {
      'id': id,
      'copy': copy,
    }))!,
  );

  Future<BookDocumentSelection?> authorizeOpen(String id) async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'pickBookOpenReference',
      {'id': id},
    );
    return value == null ? null : BookDocumentSelection.fromMap(value);
  }

  Future<void> finishOpen(String id) =>
      channel.invokeMethod<void>('finishBookOpen', {'id': id});

  Future<BookDocumentSelection?> pickImage() async {
    final value = await channel.invokeMapMethod<String, dynamic>('pickImage');
    return value == null
        ? null
        : BookDocumentSelection(
            name: value['name'] as String,
            path: value['path'] as String,
          );
  }

  Future<BookDocumentSelection?> pickFont() async {
    final value = await channel.invokeMapMethod<String, dynamic>('pickFont');
    return value == null
        ? null
        : BookDocumentSelection(
            name: value['name'] as String,
            path: value['path'] as String,
          );
  }

  Future<BookScanFolder?> scanFolderInfo() async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'scanFolderInfo',
    );
    return value == null ? null : BookScanFolder.fromMap(value);
  }

  Future<BookScanFolder?> selectScanFolder() async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'selectScanFolder',
    );
    return value == null ? null : BookScanFolder.fromMap(value);
  }

  Future<void> setScanAutomatic(bool value) =>
      channel.invokeMethod<void>('setScanAutomatic', {'value': value});
  Future<BookScanFolder?> selectAllScan() async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'selectAllScan',
    );
    return value == null ? null : BookScanFolder.fromMap(value);
  }

  Future<void> disconnectScanFolder() =>
      channel.invokeMethod<void>('disconnectScanFolder');
  Future<Set<String>> scanFormats() async {
    final extensions = await channel.invokeListMethod<String>('scanFormats');
    return extensions == null
        ? bookFormatLabels.keys.toSet()
        : extensions.map((e) => bookFormatKey('book.$e')).toSet();
  }

  Future<void> setScanFormats(Set<String> formats) =>
      channel.invokeMethod<void>('setScanFormats', {
        'extensions': bookFormatExtensions(formats).toList(),
      });
  Future<BookScanSnapshot> scanBooks() async {
    final value = (await channel.invokeMapMethod<String, dynamic>(
      'scanBooks',
    ))!;
    return BookScanSnapshot(
      books: [
        for (final book in value['books'] as List)
          (token: book['token'] as String, name: book['name'] as String),
      ],
      total: value['total'] as int,
      unchanged: value['unchanged'] as int,
      warnings: (value['warnings'] as List).cast<String>(),
      details: {
        for (final book in value['books'] as List)
          book['token'] as String: (
            size: book['size'] as int?,
            folder: book['folder'] as String? ?? '',
          ),
      },
    );
  }

  Future<BookDocumentSelection> stageScanBook(String token) async {
    final value = (await channel.invokeMapMethod<String, dynamic>(
      'stageScanBook',
      {'token': token},
    ))!;
    return BookDocumentSelection(
      name: value['name'] as String,
      path: value['path'] as String,
    );
  }

  Future<BookDocumentSelection> linkScanBook(String token) async =>
      BookDocumentSelection.fromMap(
        (await channel.invokeMapMethod<String, dynamic>('linkScanBook', {
          'token': token,
        }))!,
      );

  Future<BookDocumentSelection?> pickTextReference() async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'pickTextReference',
    );
    return value == null ? null : BookDocumentSelection.fromMap(value);
  }

  Future<BookDocumentSelection?> pickOriginalReference() async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'pickOriginalReference',
    );
    return value == null ? null : BookDocumentSelection.fromMap(value);
  }

  Future<String> stagedTextReference(String path) async => (await channel
      .invokeMethod<String>('stagedTextReference', {'path': path}))!;

  Future<void> markScanBook(String token) =>
      channel.invokeMethod<void>('markScanBook', {'token': token});
  Future<void> finishBookScan() => channel.invokeMethod<void>('finishBookScan');
  Future<({String name, String path})?> pickBook() async {
    final value = await channel.invokeMapMethod<String, dynamic>('pickBook');
    return value == null
        ? null
        : (name: value['name'] as String, path: value['path'] as String);
  }

  Future<List<BookDocumentSelection>> pickBooks() async {
    final values = await channel.invokeListMethod<dynamic>('pickBooks');
    return [
      for (final value in values ?? const [])
        BookDocumentSelection(
          name: value['name'] as String,
          path: value['path'] as String?,
          error: value['error'] as String?,
        ),
    ];
  }

  /// Select references, not copies of an entire library. Existing pickBooks
  /// callers retain their ready-to-read path contract.
  Future<List<BookDocumentSelection>> pickForImport() async {
    final values = await channel.invokeListMethod<dynamic>('pickBooks', {
      'deferred': true,
      'linkOriginals': true,
    });
    return [
      for (final value in values ?? const [])
        BookDocumentSelection.fromMap(value),
    ];
  }

  Future<List<BookDocumentSelection>> pickCopiesForImport() async {
    final values = await channel.invokeListMethod<dynamic>('pickBooks', {
      'deferred': true,
    });
    return [
      for (final value in values ?? const [])
        BookDocumentSelection.fromMap(value),
    ];
  }

  Future<BookDocumentSelection> stageForImport(
    BookDocumentSelection book,
  ) async {
    if (book.token == null) return book;
    final value = (await channel.invokeMapMethod<String, dynamic>(
      'stageImportBook',
      {'token': book.token},
    ))!;
    return BookDocumentSelection.fromMap(value);
  }

  Future<void> releaseBooks(Iterable<BookDocumentSelection> books) =>
      channel.invokeMethod<void>('releaseBooks', {
        'paths': books
            .map((book) => book.path)
            .whereType<String>()
            .toSet()
            .toList(),
        if (books.any((book) => book.token != null))
          'tokens': books
              .map((book) => book.token)
              .whereType<String>()
              .toSet()
              .toList(),
      });

  /// Existing TXT/EPUB callers keep their original, platform-independent path.
  /// MOBI is reconstructed as EPUB and ZIP yields a batch of staged originals.
  Future<List<BookDocumentSelection>> prepareBook(
    BookDocumentSelection book,
  ) async {
    if (book.error != null ||
        book.path == null && book.reference == null ||
        RegExp(r'\.(txt|epub)$', caseSensitive: false).hasMatch(book.name)) {
      return [book];
    }
    try {
      final values = await channel.invokeListMethod<dynamic>(
        book.reference == null ? 'prepareBook' : 'prepareLinkedDocument',
        {
          'name': book.name,
          if (book.reference == null)
            'path': book.path
          else
            'reference': book.reference,
        },
      );
      return [
        for (final value in values ?? const [])
          BookDocumentSelection(
            name: value['name'] as String,
            path: value['path'] as String?,
            error: value['error'] as String?,
            originReference: book.reference,
            originName: book.reference == null ? null : book.name,
          ),
      ];
    } on PlatformException catch (failure) {
      return [
        BookDocumentSelection(
          name: book.name,
          error: failure.message ?? '无法解析这本书',
        ),
      ];
    }
  }

  Future<String> decodeText(String path, {String encoding = 'auto'}) async =>
      (await channel.invokeMethod<String>('decodeText', {
        'path': path,
        'encoding': encoding,
      }))!;
  Future<String> decodeTextFile(
    String path, {
    String encoding = 'auto',
  }) async => (await channel.invokeMethod<String>('decodeTextFile', {
    'path': path,
    'encoding': encoding,
  }))!;
  Future<Map<String, dynamic>?> connect({required bool create}) => channel
      .invokeMapMethod<String, dynamic>(create ? 'createSync' : 'openSync');
  Future<Map<String, dynamic>?> info() =>
      channel.invokeMapMethod<String, dynamic>('syncInfo');
  Future<({File before, File output})> read() async {
    final value = await channel.invokeMapMethod<String, dynamic>('readSync');
    if (value == null) throw const FormatException('无法读取云同步文件');
    return (before: File(value['path']), output: File(value['outputPath']));
  }

  Future<void> write(File before, File next) => channel.invokeMethod<void>(
    'writeSync',
    {'path': next.path, 'expectedPath': before.path},
  );
  Future<void> disconnect() => channel.invokeMethod<void>('disconnectSync');
  Future<File?> recovery(String which) async {
    final path = await channel.invokeMethod<String>('recoverSync', {
      'which': which,
    });
    return path == null ? null : File(path);
  }
}
