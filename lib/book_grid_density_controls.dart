import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'book_grid_density.dart';

class BookGridDensityOptions extends StatelessWidget {
  const BookGridDensityOptions({
    super.key,
    required this.value,
    required this.viewport,
    required this.onChanged,
  });
  final BookGridDensity value;
  final BookGridViewport? viewport;
  final ValueChanged<BookGridDensity> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 14, bottom: 4),
        child: AppText(
          '封面大小',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final preset in const [
            BookGridDensity.auto(),
            BookGridDensity.sized(BookGridSize.small),
            BookGridDensity.sized(BookGridSize.medium),
            BookGridDensity.sized(BookGridSize.large),
          ])
            Semantics(
              selected: value == preset,
              inMutuallyExclusiveGroup: true,
              child: GlassTextButton(
                key: ValueKey('grid-density-${preset.value}'),
                compact: true,
                selected: value == preset,
                onPressed: () => onChanged(preset),
                child: AppText(
                  preset.label,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    ],
  );
}
