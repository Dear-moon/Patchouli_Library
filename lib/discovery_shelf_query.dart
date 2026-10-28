import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'novel_feed_controller.dart';
import 'publication_catalog.dart';
import 'tag_catalogue.dart';
import 'web_publication_catalog.dart' show PublicationConnectionRequired;

/// One remote discovery region owns one source and cursor. Ranking, tags and
/// publication requests use the existing feed contract and never combine APIs.
class DiscoveryShelfQuery {
  const DiscoveryShelfQuery.defaults()
    : sort = NovelSort.lastUpdate,
      tags = const [],
      publication = null;

  factory DiscoveryShelfQuery({
    NovelSort sort = NovelSort.lastUpdate,
    Iterable<String> tags = const [],
    PublicationLibrary? publication,
  }) => DiscoveryShelfQuery._(
    sort,
    publication == null
        ? List.unmodifiable(tagSearchTerms(tags.join(' ')))
        : const [],
    publication,
  );

  const DiscoveryShelfQuery._(this.sort, this.tags, this.publication);

  factory DiscoveryShelfQuery.fromFeed(NovelFeedController feed) =>
      DiscoveryShelfQuery(
        sort: feed.sort,
        tags: feed.tags,
        publication: feed.publication,
      );

  final NovelSort sort;
  final List<String> tags;
  final PublicationLibrary? publication;

  String get label =>
      publication?.name ?? (tags.isEmpty ? sort.label : tags.join(' · '));

  DiscoveryShelfQuery withSort(NovelSort value) =>
      DiscoveryShelfQuery(sort: value);

  DiscoveryShelfQuery withTags(Iterable<String> values) =>
      DiscoveryShelfQuery(sort: sort, tags: values);

  DiscoveryShelfQuery withPublication(PublicationLibrary value) =>
      DiscoveryShelfQuery(sort: sort, publication: value);

  Map<String, Object> toJson() => {
    'version': 1,
    'sort': sort.name,
    'tags': tags,
    if (publication case final value?)
      'publication': {'id': value.id, 'name': value.name},
  };

  String get record => jsonEncode(toJson());

  static DiscoveryShelfQuery? tryParse(Object? value) {
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return null;
      }
    }
    if (value is! Map || value['version'] != 1 || value['tags'] is! List) {
      return null;
    }
    final rawTags = value['tags'] as List;
    if (rawTags.any((tag) => tag is! String)) return null;
    final sortName = value['sort'];
    final sort = NovelSort.values
        .where((item) => item.name == sortName)
        .firstOrNull;
    if (sort == null) return null;
    PublicationLibrary? publication;
    final rawPublication = value['publication'];
    if (rawPublication != null) {
      if (rawPublication is! Map ||
          rawPublication['id'] is! int ||
          (rawPublication['id'] as int) <= 0 ||
          rawPublication['name'] is! String ||
          (rawPublication['name'] as String).trim().isEmpty ||
          rawTags.isNotEmpty) {
        return null;
      }
      publication = PublicationLibrary(
        rawPublication['id'] as int,
        (rawPublication['name'] as String).trim(),
      );
    }
    return DiscoveryShelfQuery(
      sort: sort,
      tags: rawTags.cast<String>(),
      publication: publication,
    );
  }

  static DiscoveryShelfQuery parseOrDefault(Object? value) =>
      tryParse(value) ?? const DiscoveryShelfQuery.defaults();

  /// Restoring the default ranking still needs an initial request: the feed's
  /// selectSort intentionally does nothing when that ranking is already selected.
  Future<void> applyTo(
    NovelFeedController feed, {
    PublicationCatalog? publications,
  }) async {
    if (publication case final value?) {
      if (publications == null) throw const PublicationConnectionRequired();
      await feed.selectPublication(value, catalog: publications);
    } else if (tags.isNotEmpty) {
      await feed.selectTags(tags);
    } else {
      await feed.selectSort(sort);
    }
    if (!feed.hasLoaded && !feed.loading && feed.error == null) {
      await feed.loadInitial();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DiscoveryShelfQuery &&
      sort == other.sort &&
      listEquals(tags, other.tags) &&
      publication?.id == other.publication?.id &&
      publication?.name == other.publication?.name;

  @override
  int get hashCode => Object.hash(
    sort,
    Object.hashAll(tags),
    publication?.id,
    publication?.name,
  );
}
