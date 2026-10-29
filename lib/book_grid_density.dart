import 'dart:math' as math;

import 'package:flutter/widgets.dart';

enum BookGridSize { small, medium, large }

/// A single atomic preference. Rows describe a viewport target, not pagination.
@immutable
class BookGridDensity {
  const BookGridDensity.auto() : columns = 0, rows = 0, size = null;
  const BookGridDensity.sized(this.size) : columns = 0, rows = 0;
  const BookGridDensity(this.columns, this.rows)
    : size = null,
      assert(columns >= 1 && columns <= 8),
      assert(rows >= 1 && rows <= 10);

  final int columns, rows;
  final BookGridSize? size;
  bool get automatic => columns == 0 && size == null;
  String get value => size?.name ?? (automatic ? 'auto' : '${columns}x$rows');
  String get label => switch (size) {
    BookGridSize.small => '小',
    BookGridSize.medium => '中',
    BookGridSize.large => '大',
    null => automatic ? '自动' : '$columns × $rows',
  };

  static BookGridDensity? tryParse(Object? value) {
    if (value == 'auto') return const BookGridDensity.auto();
    for (final size in BookGridSize.values) {
      if (value == size.name) return BookGridDensity.sized(size);
    }
    if (value is! String) return null;
    final match = RegExp(r'^([1-8])x([1-9]|10)$').firstMatch(value);
    return match == null
        ? null
        : BookGridDensity(int.parse(match[1]!), int.parse(match[2]!));
  }

  static BookGridDensity parseOrAuto(Object? value) {
    final parsed = tryParse(value) ?? const BookGridDensity.auto();
    if (parsed.automatic || parsed.size != null) return parsed;
    return BookGridDensity.sized(
      parsed.columns >= 4
          ? BookGridSize.small
          : parsed.columns == 3
          ? BookGridSize.medium
          : BookGridSize.large,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookGridDensity && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// Stable scrollport geometry: excludes leading controls and protected dock.
/// Text is budgeted at its actual scaled size; it is never shrunk to fit a grid.
@immutable
class BookGridViewport {
  BookGridViewport({
    required this.width,
    required this.height,
    required TextScaler textScaler,
  }) : titleHeight = textScaler.scale(14) * 1.4 * 2,
       authorHeight = textScaler.scale(12) * 1.4,
       progressHeight = textScaler.scale(12) * 1.4,
       minimumCellWidth = math.max(56.0, textScaler.scale(14) * 4),
       retryHeight = math.max(48.0, textScaler.scale(12) * 1.4 + 16),
       statusHeight = textScaler.scale(12) * 1.4 * 2 + 8;

  static const gap = 16.0, coverAspectRatio = 30 / 41;
  // Cover artwork and the metadata action lane have separate hit areas.
  static const minimumCoverWidth = 48.0;
  final double width, height;
  final double titleHeight, authorHeight, progressHeight, minimumCellWidth;
  final double retryHeight, statusHeight;
  double get footerHeight => math.max(48.0, authorHeight + 4 + progressHeight);
  double get metadataHeight => math.max(
    10 + titleHeight + 4 + footerHeight,
    10 + titleHeight + 4 + retryHeight,
  );
  double get minimumRowHeight =>
      metadataHeight + minimumCoverWidth / coverAspectRatio;
  int get maximumColumns => math
      .max(0, ((width + gap) / (minimumCellWidth + gap)).floor())
      .clamp(0, 8);
  int get maximumRows => math
      .max(
        0,
        ((height - statusHeight + gap) / (minimumRowHeight + gap)).floor(),
      )
      .clamp(0, 10);
  bool canFit(BookGridDensity density) =>
      density.automatic ||
      density.size != null ||
      (density.columns <= maximumColumns && density.rows <= maximumRows);

  BookGridGeometry resolve(BookGridDensity requested) {
    if (requested.size case final size?) {
      final target = switch (size) {
        BookGridSize.small => 92.0,
        BookGridSize.medium => 140.0,
        BookGridSize.large => 196.0,
      };
      final maximum = ((width + gap) / (minimumCellWidth + gap)).floor().clamp(
        1,
        12,
      );
      // Compact phones can have less than 308dp after page padding. Small
      // still means three columns there; wider panes keep adding columns.
      // Large text retains the readable-width limit rather than shrinking.
      final columns = math
          .max(
            size == BookGridSize.small ? 3 : 1,
            ((width + gap) / (target + gap)).floor(),
          )
          .clamp(1, maximum);
      return BookGridGeometry._(this, requested, null, columns);
    }
    if (requested.automatic || maximumColumns == 0 || maximumRows == 0) {
      return BookGridGeometry._(this, requested, null);
    }
    return BookGridGeometry._(
      this,
      requested,
      BookGridDensity(
        math.min(requested.columns, maximumColumns),
        math.min(requested.rows, maximumRows),
      ),
    );
  }

  Object get layoutKey =>
      (width, height, titleHeight, authorHeight, retryHeight);
}

@immutable
class BookGridGeometry {
  const BookGridGeometry._(
    this.viewport,
    this.requested,
    this.effective, [
    this.responsiveColumns,
  ]);
  final BookGridViewport viewport;
  final BookGridDensity requested;
  final BookGridDensity? effective;
  final int? responsiveColumns;
  int? get columns => responsiveColumns ?? effective?.columns;
  bool get fixed => effective != null || responsiveColumns != null;
  bool get adjusted =>
      requested.size == null && !requested.automatic && requested != effective;
  double get cellWidth =>
      (viewport.width - (columns! - 1) * BookGridViewport.gap) / columns!;
  double get rowHeight => responsiveColumns != null
      ? viewport.metadataHeight + cellWidth / BookGridViewport.coverAspectRatio
      : (viewport.height -
                viewport.statusHeight -
                (effective!.rows - 1) * BookGridViewport.gap) /
            effective!.rows;
  double get coverWidth => math.min(
    cellWidth,
    (rowHeight - viewport.metadataHeight) * BookGridViewport.coverAspectRatio,
  );
  double get coverHeight => coverWidth / BookGridViewport.coverAspectRatio;
  Object get layoutKey => (
    viewport.layoutKey,
    requested.value,
    effective?.value,
    responsiveColumns,
  );
  String get status => requested.size != null
      ? '${requested.label}封面'
      : adjusted
      ? effective == null
            ? '已设 ${requested.label}；当前自动布局（窗口或字号限制）'
            : '已设 ${requested.label}；当前 ${effective!.label}（窗口或字号限制）'
      : '每屏 ${effective!.columns} 列 × ${effective!.rows} 行';
}

class BookGridScope extends InheritedWidget {
  const BookGridScope({
    super.key,
    required this.geometry,
    required super.child,
  });
  final BookGridGeometry geometry;
  static BookGridGeometry? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BookGridScope>()?.geometry;
  @override
  bool updateShouldNotify(BookGridScope oldWidget) =>
      geometry.layoutKey != oldWidget.geometry.layoutKey;
}
