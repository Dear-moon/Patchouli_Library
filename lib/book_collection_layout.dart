import 'package:flutter/material.dart';
import 'library_reflow.dart';
import 'native_effects.dart';
import 'book_grid_density.dart';

/// Keep a book's cover, metadata and actions together. Wider panes add columns,
/// not wider covers or fixed-height tiles that clip larger text.
abstract final class BookCollectionLayout {
  static const gap = 24.0;
  static const gridGap = 16.0;
  static const gridCoverAspectRatio = 30 / 41;
  // Experimental: pixel parity passed, but matched device runs have not shown
  // a repeatable frame-time benefit. Keep ordinary builds on independent inputs.
  static const rowGlassSharingEnabled = bool.fromEnvironment('GLASS_ROW_BATCH');
  static int columnsFor(double width) =>
      ((width + gap) / (272 + gap)).floor().clamp(1, 3);
  static int gridColumnsFor(double width) =>
      ((width + gridGap) / (100 + gridGap)).floor().clamp(1, 6);
  // Preserve visible books and network prefetch. A wider list must not also
  // multiply its speculative offscreen widget/image work by its column count.
  static double cacheExtentFor(
    double width, {
    double base = 500,
    bool grid = false,
  }) => (base / (grid ? gridColumnsFor(width) : columnsFor(width))).clamp(
    grid ? 64.0 : 128.0,
    base,
  );
}

class BookCollectionSliver extends StatefulWidget {
  const BookCollectionSliver({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.shareRowGlass = false,
    this.grid = false,
    this.gridDensity = const BookGridDensity.auto(),
    this.gridBottomInset = 0,
    this.onGridViewport,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool grid;
  final BookGridDensity gridDensity;
  final double gridBottomInset;
  final ValueChanged<BookGridViewport>? onGridViewport;

  /// Opt in only for clear controls in empty, separated row trailing lanes.
  /// Headings/featured content belong outside this input-sharing scope.
  final bool shareRowGlass;

  @override
  State<BookCollectionSliver> createState() => _BookCollectionSliverState();
}

class _BookCollectionSliverState extends State<BookCollectionSliver> {
  Widget? _rows;
  int? _columns;
  Object? _gridLayoutKey, _viewportKey;
  BookGridGeometry? _geometry;

  @override
  void didUpdateWidget(BookCollectionSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rows = null;
  }

  Widget _item(BuildContext context, int index) {
    final item = widget.itemBuilder(context, index);
    final part = LibraryReflowPart(relocate: false, order: index, child: item);
    return widget.grid
        ? Padding(
            padding: EdgeInsets.only(
              bottom: _geometry?.fixed == true
                  ? BookCollectionLayout.gridGap
                  : BookCollectionLayout.gap,
            ),
            child: part,
          )
        : part;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();
    if (!widget.shareRowGlass || !BookCollectionLayout.rowGlassSharingEnabled) {
      return rows;
    }
    return NativeGlassGroup(
      inherit: false,
      preserveMemberClip: true,
      // Reflow can move a trailing lane across another row's painted content.
      // Read each current backdrop independently until the lanes settle again.
      enabled: LibraryReflowScope.of(context)?.active != true,
      child: rows,
    );
  }

  Widget _buildRows() => SliverLayoutBuilder(
    builder: (context, constraints) {
      if (widget.grid) {
        final viewport = BookGridViewport(
          width: constraints.crossAxisExtent,
          height:
              (constraints.viewportMainAxisExtent -
                      constraints.precedingScrollExtent -
                      widget.gridBottomInset)
                  .clamp(0.0, double.infinity),
          textScaler: MediaQuery.textScalerOf(context),
        );
        _geometry = viewport.resolve(widget.gridDensity);
        if (_viewportKey != viewport.layoutKey) {
          _viewportKey = viewport.layoutKey;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onGridViewport?.call(viewport);
          });
        }
      } else {
        _geometry = null;
      }
      final columns = widget.grid
          ? _geometry?.columns ??
                BookCollectionLayout.gridColumnsFor(constraints.crossAxisExtent)
          : BookCollectionLayout.columnsFor(constraints.crossAxisExtent);
      final gap = widget.grid
          ? BookCollectionLayout.gridGap
          : BookCollectionLayout.gap;
      // SliverConstraints include scrollOffset, so this builder is called on
      // every fling frame. Replacing the delegate here rebuilds all mounted
      // book rows, including covers and glass. Only a new data builder or a
      // column-count or density-geometry change needs a new delegate.
      final gridLayoutKey = _geometry?.layoutKey;
      if (_rows != null &&
          _columns == columns &&
          _gridLayoutKey == gridLayoutKey) {
        return _rows!;
      }
      _columns = columns;
      _gridLayoutKey = gridLayoutKey;
      final Widget rows;
      if (columns == 1) {
        rows = SliverList.builder(
          itemCount: widget.itemCount,
          itemBuilder: _item,
        );
      } else {
        rows = SliverList.builder(
          itemCount: (widget.itemCount / columns).ceil(),
          itemBuilder: (context, row) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column != 0) SizedBox(width: gap),
                Expanded(
                  child: row * columns + column < widget.itemCount
                      ? _item(context, row * columns + column)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        );
      }
      if (widget.grid && !widget.gridDensity.automatic) {
        return _rows = BookGridScope(
          geometry: _geometry!,
          child: widget.gridDensity.size != null
              ? rows
              : SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: _geometry!.viewport.statusHeight,
                        child: Text(
                          _geometry!.status,
                          key: const ValueKey('grid-density-status'),
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    rows,
                  ],
                ),
        );
      }
      return _rows = rows;
    },
  );
}

/// Full-width headings/featured books, followed by a lazy responsive collection.
class BookCollectionView extends StatelessWidget {
  const BookCollectionView.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.leadingCount = 0,
    this.trailingCount = 0,
    this.padding = EdgeInsets.zero,
    this.physics,
    this.shareRowGlass = false,
    this.grid = false,
    this.gridDensity = const BookGridDensity.auto(),
    this.onGridViewport,
  }) : assert(itemCount >= leadingCount + trailingCount);
  final int itemCount, leadingCount, trailingCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsets padding;
  final ScrollPhysics? physics;
  final bool grid;
  final BookGridDensity gridDensity;
  final ValueChanged<BookGridViewport>? onGridViewport;

  /// Share backdrop input only across the ordinary collection's row controls.
  final bool shareRowGlass;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => CustomScrollView(
      physics: physics,
      clipBehavior: LibraryReflowScope.clipOf(context),
      cacheExtent: BookCollectionLayout.cacheExtentFor(
        constraints.maxWidth - padding.horizontal,
        base: 250,
        grid: grid,
      ),
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: SliverMainAxisGroup(
            slivers: [
              if (leadingCount > 0)
                SliverList.builder(
                  itemCount: leadingCount,
                  itemBuilder: itemBuilder,
                ),
              BookCollectionSliver(
                shareRowGlass: shareRowGlass,
                grid: grid,
                gridDensity: gridDensity,
                gridBottomInset: padding.bottom,
                onGridViewport: onGridViewport,
                itemCount: itemCount - leadingCount - trailingCount,
                itemBuilder: (context, index) =>
                    itemBuilder(context, index + leadingCount),
              ),
              if (trailingCount > 0)
                SliverList.builder(
                  itemCount: trailingCount,
                  itemBuilder: (context, index) =>
                      itemBuilder(context, itemCount - trailingCount + index),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
