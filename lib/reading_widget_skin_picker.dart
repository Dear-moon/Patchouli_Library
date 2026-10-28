import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'reading_widget_reference.dart';
import 'reading_widget_skin.dart';
import 'reading_widget_snapshot.dart';

/// Preview the production desktop face at the chosen size, with live data.
class ReadingWidgetSkinPicker extends StatelessWidget {
  const ReadingWidgetSkinPicker({
    super.key,
    required this.value,
    required this.snapshot,
    this.size = ReadingDesktopSize.small,
    this.onChanged,
    this.previewBuilder,
  });
  final ReadingWidgetSkin value;
  final ReadingWidgetSnapshot snapshot;
  final ReadingDesktopSize size;
  final ValueChanged<ReadingWidgetSkin>? onChanged;
  final Widget Function(ReadingWidgetSkin)? previewBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final width = size == ReadingDesktopSize.small
          ? (bounds.maxWidth - 12) / 2
          : bounds.maxWidth;
      final color = Theme.of(context).colorScheme.primary;
      return Wrap(
        spacing: 12,
        runSpacing: 18,
        children: [
          for (final skin in ReadingWidgetSkin.available)
            SizedBox(
              width: width,
              child: Semantics(
                selected: value == skin,
                button: true,
                label: skin.label,
                child: JellyTapSurface(
                  tapKey: ValueKey('reading-widget-skin-${skin.name}'),
                  onTap: onChanged == null ? null : () => onChanged!(skin),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        height: width * size.size.height / size.size.width,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: value == skin ? color : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: FittedBox(
                          child:
                              previewBuilder?.call(skin) ??
                              ReadingDesktopCard(
                                data: snapshot.styled(
                                  skin: skin,
                                  showBookDetails: snapshot.showBookDetails,
                                ),
                                size: size,
                              ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Row(
                          children: [
                            Expanded(
                              child: AppText(
                                skin.label,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            if (value == skin)
                              Icon(Icons.check_rounded, size: 16, color: color),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
