import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_declarations.dart';

Map<String, dynamic> engineFixture(String key) {
  final platform = switch (Uri.parse(key).host) {
    'n.novelia.cc' => ('novelia', 'Novelia', 'NV'),
    'www.lightnovel.fun' => ('qingguo', '轻之国度', 'LK'),
    'www.lightnovel.app' => ('lightnovel', '轻书架', 'LS'),
    'www.bilinovel.com' => ('bilinovel', '哔哩轻小说', 'BL'),
    _ => key == 'builtin:wenku8' ? ('wenku8', '轻小说文库', 'W8') : (key, key, 'JS'),
  };
  return {
    'version': 1,
    'platform': {'id': platform.$1, 'name': platform.$2, 'mark': platform.$3},
    if (platform.$1 == 'novelia') ...{
      'session': {
        'id': 'fixture-novelia-session',
        'members': [
          for (final variant in ['sakura', 'gpt', 'youdao', 'jp'])
            'https://n.novelia.cc#$variant',
        ],
      },
      'search': {'group': 'novelia'},
    },
    if (platform.$1 == 'lightnovel')
      'content': {'font': 'embedded', 'intro': 'html'},
  };
}

void registerSourceFixtures() => SourceDeclarations.register([
  for (final key in [
    'builtin:wenku8',
    'https://n.novelia.cc#sakura',
    'https://n.novelia.cc#gpt',
    'https://n.novelia.cc#youdao',
    'https://n.novelia.cc#jp',
    'https://www.lightnovel.fun',
    'https://www.lightnovel.app',
    'https://www.bilinovel.com',
  ])
    BookSource({
      'bookSourceName': key,
      'bookSourceUrl': key,
      'engine': engineFixture(key),
    }),
]);
