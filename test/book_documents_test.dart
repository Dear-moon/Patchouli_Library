import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/book_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  Object? result;
  setUp(() {
    calls.clear();
    result = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BookDocuments.channel, (call) async {
          calls.add(call);
          return result;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BookDocuments.channel, null),
  );
  test(
    'multi picker preserves individual errors and releases only copied sources',
    () async {
      result = [
        {'name': '一.epub', 'path': '/cache/import-1.source'},
        {'name': '二.epub', 'error': '云盘文件暂不可用'},
        {'name': '三.txt', 'path': '/cache/import-3.source'},
      ];
      final documents = BookDocuments();
      final books = await documents.pickBooks();
      expect(books.map((b) => b.name), ['一.epub', '二.epub', '三.txt']);
      expect(books[1].error, '云盘文件暂不可用');
      result = null;
      await documents.releaseBooks(books);
      expect(calls.map((c) => c.method), ['pickBooks', 'releaseBooks']);
      expect(calls.last.arguments, {
        'paths': ['/cache/import-1.source', '/cache/import-3.source'],
      });
    },
  );
  test(
    'cancelled multi picker returns empty; legacy picker keeps its map contract',
    () async {
      final documents = BookDocuments();
      expect(await documents.pickBooks(), isEmpty);
      result = {'name': '原书.epub', 'path': '/cache/import-source'};
      expect(await documents.pickBook(), (
        name: '原书.epub',
        path: '/cache/import-source',
      ));
      expect(calls.map((c) => c.method), ['pickBooks', 'pickBook']);
    },
  );
  test(
    'deferred selection stages one opaque reference and releases its lease',
    () async {
      final documents = BookDocuments();
      result = [
        {'name': '第一本.epub', 'token': 'one'},
        {'name': '第二本.epub', 'token': 'two'},
        {'name': '失败.epub', 'error': '授权失效'},
      ];
      final selected = await documents.pickForImport();
      expect(calls.single.arguments, {'deferred': true, 'linkOriginals': true});
      expect(selected.map((b) => b.path), [null, null, null]);
      result = {'name': '第一本.epub', 'path': '/private/import-1.source'};
      final staged = await documents.stageForImport(selected.first);
      expect(calls.last.method, 'stageImportBook');
      expect(calls.last.arguments, {'token': 'one'});
      expect(staged.path, '/private/import-1.source');
      expect(await documents.stageForImport(staged), same(staged));
      result = null;
      await documents.releaseBooks([...selected, staged]);
      expect(calls.last.arguments, {
        'paths': ['/private/import-1.source'],
        'tokens': ['one', 'two'],
      });
    },
  );
  test(
    'linked TXT selections never stage a copy or release durable grants as temporary files',
    () async {
      result = [
        {'name': '原书.txt', 'reference': 'opaque-document'},
      ];
      final documents = BookDocuments();
      final selected = (await documents.pickForImport()).single;
      expect(selected.reference, 'opaque-document');
      expect(await documents.stageForImport(selected), same(selected));
      expect(await documents.prepareBook(selected), [selected]);
      result = null;
      await documents.releaseBooks([selected]);
      expect(calls.map((c) => c.method), ['pickBooks', 'releaseBooks']);
      expect(calls.last.arguments, {'paths': <String>[]});
    },
  );
  test(
    'explicit copy picker retains the old deferred managed import',
    () async {
      await BookDocuments().pickCopiesForImport();
      expect(calls.single.arguments, {'deferred': true});
    },
  );
  test(
    'linked document conversion retains the origin and owns only its derived staging',
    () async {
      result = [
        {'name': '文档.epub', 'path': '/private/import-document.source'},
      ];
      final prepared = await BookDocuments().prepareBook(
        const BookDocumentSelection.linked(
          name: '文档.pdf',
          reference: 'opaque-pdf',
        ),
      );
      expect(calls.single.method, 'prepareLinkedDocument');
      expect(calls.single.arguments, {
        'name': '文档.pdf',
        'reference': 'opaque-pdf',
      });
      expect(prepared.single.originReference, 'opaque-pdf');
      expect(prepared.single.originName, '文档.pdf');
      expect(prepared.single.reference, isNull);
      expect(prepared.single.path, '/private/import-document.source');
    },
  );
}
