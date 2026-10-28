import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'book_collection_layout.dart';
import 'book_source_badge.dart';
import 'catalog.dart';
import 'local_library_preferences.dart';
import 'book_grid_density.dart';

/// The cover is an uninterrupted reading target; actions live below the title.
/// Height follows readable text instead of clipping larger accessibility text.
class BookGridTile extends StatelessWidget {
  const BookGridTile({
    super.key,
    required this.book,
    required this.onTap,
    required this.trailing,
    this.coverHeroTag,
    this.sourceLabel,
    this.progress,
  });

  final Novel book;
  final VoidCallback onTap;
  final Widget trailing;
  final Object? coverHeroTag;
  final String? sourceLabel, progress;

  Widget _cover(double width, double height) => SizedBox(
    height: height,
    child: Center(
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Semantics(
              label: book.title,
              image: true,
              child: NovelCover(
                book,
                width: width,
                height: height,
                heroTag: coverHeroTag,
              ),
            ),
            if (sourceLabel != null)
              Positioned(
                top: 4,
                right: 4,
                child: BookSourceBadge(sourceLabel!),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _metadata(BuildContext context, {double? height}) => SizedBox(
    key: ValueKey('grid-metadata-${book.id}'),
    height: height,
    child: Row(
      children: [
        Expanded(
          child: JellyTapSurface(
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppText(
                    LocalLibraryPreferences.authorName(book.author),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 4),
                    AppText(
                      progress!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // This sibling is never inside the cover's open-book gesture target.
        trailing,
      ],
    ),
  );

  Widget _tile(
    BuildContext context, {
    required double coverWidth,
    required double coverHeight,
    BookGridGeometry? geometry,
  }) => SizedBox(
    height: geometry?.rowHeight,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        JellyTapSurface(
          key: ValueKey('grid-open-${book.id}'),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _cover(coverWidth, coverHeight),
              const SizedBox(height: 10),
              SizedBox(
                height: geometry?.viewport.titleHeight,
                child: AppText(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _metadata(context, height: geometry?.viewport.footerHeight),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final geometry = BookGridScope.of(context);
    if (geometry?.fixed == true) {
      return _tile(
        context,
        coverWidth: geometry!.coverWidth,
        coverHeight: geometry.coverHeight,
        geometry: geometry,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => _tile(
        context,
        coverWidth: constraints.maxWidth,
        coverHeight:
            constraints.maxWidth / BookCollectionLayout.gridCoverAspectRatio,
      ),
    );
  }
}

/// Metadata recovery keeps a cover-sized retry target and a separate menu.
class BookGridFailure extends StatelessWidget {
  const BookGridFailure({
    super.key,
    required this.id,
    required this.onRetry,
    required this.trailing,
  });
  final int id;
  final VoidCallback onRetry;
  final Widget trailing;

  Widget _cover(BuildContext context, double width, double height) => Center(
    child: SizedBox(
      width: width,
      height: height,
      child: Semantics(
        button: true,
        label: '重新载入书籍 $id',
        child: JellyTapSurface(
          onTap: onRetry,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: .04),
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(ArchiveDesign.coverRadius),
            ),
            child: const Center(
              child: AppText(
                '重试',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _tile(
    BuildContext context, {
    required double coverWidth,
    required double coverHeight,
    BookGridGeometry? geometry,
  }) => SizedBox(
    height: geometry?.rowHeight,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _cover(context, coverWidth, coverHeight),
        const SizedBox(height: 10),
        SizedBox(
          height: geometry?.viewport.titleHeight,
          child: AppText(
            '书籍 $id 暂未载入',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: geometry?.viewport.footerHeight,
          child: Align(alignment: Alignment.centerRight, child: trailing),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final geometry = BookGridScope.of(context);
    if (geometry?.fixed == true) {
      return _tile(
        context,
        coverWidth: geometry!.coverWidth,
        coverHeight: geometry.coverHeight,
        geometry: geometry,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => _tile(
        context,
        coverWidth: constraints.maxWidth,
        coverHeight:
            constraints.maxWidth / BookCollectionLayout.gridCoverAspectRatio,
      ),
    );
  }
}
