import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/local_books.dart';
import 'package:wenku8_flutter/local_library_preferences.dart';

class _GroupReadCounter extends LocalLibraryPreferences {
  _GroupReadCounter(super.preferences);
  int groupCopies = 0;
  @override
  Map<String, String> get groups {
    groupCopies++;
    return super.groups;
  }
}

Novel book(String title) => parseLocalBook(
  LocalBookInput(
    '$title.txt',
    Uint8List.fromList(utf8.encode('$title\n正文内容。')),
    text: '$title\n正文内容。',
  ),
).novel;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'filtering does not copy every category for each visible book',
    () async {
      SharedPreferences.setMockInitialValues({});
      final view = _GroupReadCounter(await SharedPreferences.getInstance());
      addTearDown(view.dispose);
      await view.mergeOrganization({
        'version': 1,
        'groups': {
          'fantasy': {'name': '幻想', 'at': 1, 'deleted': false},
          'deleted': {'name': '旧分类', 'at': 2, 'deleted': true},
        },
        'assignments': {
          '1': {'group': 'fantasy', 'at': 1},
          '2': {'group': 'deleted', 'at': 1},
        },
      });
      final originals = [
        for (var i = 1; i <= 3; i++)
          Novel(
            id: i,
            title: '$i',
            author: '',
            genre: '',
            summary: '',
            colors: const [],
          ),
      ];
      view.groupCopies = 0;
      expect(view.filter(originals).map((b) => b.id), [1, 2, 3]);
      expect(view.filter(originals, query: '#幻想').map((b) => b.id), [1]);
      expect(view.filter(originals, query: '#未分类').map((b) => b.id), [2, 3]);
      expect(view.filter(originals, query: '#旧分类'), isEmpty);
      expect(view.nameOf('deleted'), '全部书籍');
      expect(view.groupCopies, 0);
    },
  );
  test(
    'shelf threshold, list preference, categories and deletion survive reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final view = LocalLibraryPreferences(prefs);
      addTearDown(view.dispose);
      expect(view.showsShelf(9), false);
      expect(view.showsShelf(10), true);
      expect(view.showsShelf(11), true);
      await view.setView(LocalLibraryView.list);
      expect(view.showsShelf(20), false);
      final group = await view.addGroup('科幻');
      final a = book('甲');
      await view.assign(a.id, group);
      await view.select(group);
      expect(view.filter([a]).single, a);
      await view.renameGroup(group, '幻想');
      expect(view.nameOf(group), '幻想');
      final reloaded = LocalLibraryPreferences(prefs)..load();
      addTearDown(reloaded.dispose);
      expect(reloaded.selected, group);
      expect(reloaded.groupOf(a.id), group);
      expect(reloaded.view, LocalLibraryView.list);
      final stale = view.exportOrganization();
      await reloaded.removeGroup(group);
      expect(reloaded.groupOf(a.id), LocalLibraryPreferences.unfiled);
      await reloaded.mergeOrganization(stale);
      expect(reloaded.groups, isEmpty);
      expect(reloaded.selected, LocalLibraryPreferences.all);
    },
  );
  test(
    'search and sorting preserve local book identities; invalid metadata rejected',
    () async {
      SharedPreferences.setMockInitialValues({});
      final view = LocalLibraryPreferences(
        await SharedPreferences.getInstance(),
      );
      addTearDown(view.dispose);
      final a = book('Alpha'), b = book('Beta');
      expect(view.filter([b, a], query: 'ALP').single.id, a.id);
      await view.setSort(LocalLibrarySort.recentRead);
      expect(
        view.filter([a, b], readAt: (id) => id == b.id ? 20 : 0).first.id,
        b.id,
      );
      expect(
        () => LocalLibraryPreferences.validateOrganization({
          'version': 1,
          'groups': {},
          'assignments': {
            '0': {'group': 'x', 'at': 1},
          },
        }),
        throwsFormatException,
      );
      expect(
        () => view.assign(0, LocalLibraryPreferences.unfiled),
        throwsFormatException,
      );
      await view.addGroup('分类');
      await expectLater(view.addGroup('分类'), throwsFormatException);
    },
  );
}
