import 'dart:ui' as ui;

/// Owned app captures and local illustration handles for one complete report.
class ReadingReportComponents {
  ReadingReportComponents({
    required this.monthly,
    required this.calendars,
    required this.progress,
    required this.ring,
    this.shelf,
    this.bookCovers = const [],
    this.serifFamily,
    this.art,
    this.artKey,
    this.illustrations = const {},
  });
  // Unselected components have no image or offscreen render tree to retain.
  final ui.Image? monthly, progress, ring;
  final List<ui.Image> calendars;
  final ui.Image? shelf;
  final ui.Image? art;
  final String? artKey;
  final Map<String, ui.Image> illustrations;
  ui.Image? illustration(String key) =>
      key == artKey ? art : illustrations[key];
  final List<ui.Image> bookCovers;

  /// An already registered, optional user serif. Null keeps platform fallback.
  final String? serifFamily;
  ui.Image? get featuredCover => bookCovers.firstOrNull;
  ReadingReportComponents clone() => ReadingReportComponents(
    monthly: monthly?.clone(),
    calendars: [for (final image in calendars) image.clone()],
    progress: progress?.clone(),
    ring: ring?.clone(),
    shelf: shelf?.clone(),
    bookCovers: [for (final image in bookCovers) image.clone()],
    serifFamily: serifFamily,
    art: art?.clone(),
    artKey: artKey,
    illustrations: {
      for (final entry in illustrations.entries) entry.key: entry.value.clone(),
    },
  );
  void dispose() {
    monthly?.dispose();
    progress?.dispose();
    ring?.dispose();
    art?.dispose();
    for (final image in illustrations.values) {
      image.dispose();
    }
    for (final image in calendars) {
      image.dispose();
    }
    shelf?.dispose();
    for (final image in bookCovers) {
      image.dispose();
    }
  }
}
