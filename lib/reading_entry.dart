enum ReadingEntry {
  discovery('发现页'),
  shelf('书架页'),
  local('本地页');

  const ReadingEntry(this.label);
  final String label;

  static Set<ReadingEntry> decode(Object? value, {bool legacy = false}) =>
      value is List
      ? {
          for (final entry in values)
            if (value.contains(entry.name)) entry,
        }
      : legacy
      ? values.toSet()
      : {};
}
