import 'package:flutter/material.dart';
import 'app_ui.dart';

class GlassChoiceRail<T> extends StatefulWidget {
  const GlassChoiceRail({
    super.key,
    required this.name,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.enabled = true,
  });
  final String name;
  final String? label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  State<GlassChoiceRail<T>> createState() => _GlassChoiceRailState<T>();
}

class _GlassChoiceRailState<T> extends State<GlassChoiceRail<T>> {
  final _selected = GlobalKey();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _revealSelection();
  }

  @override
  void didUpdateWidget(GlassChoiceRail<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _revealSelection();
  }

  void _revealSelection() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    if (widget.options.keys.firstOrNull == widget.value && _scroll.hasClients) {
      _scroll.jumpTo(0);
      return;
    }
    final chip = _selected.currentContext;
    final target = chip?.findRenderObject();
    if (chip == null || target == null || !target.attached) return;
    // Only move this horizontal rail, not an enclosing page/sheet.
    Scrollable.of(chip).position.ensureVisible(target, alignment: .35);
  });

  @override
  Widget build(BuildContext context) {
    final entries = widget.options.entries.toList(growable: false);
    return Row(
      children: [
        if (widget.label case final label?) ...[
          AppText(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: SizedBox(
            height: (MediaQuery.textScalerOf(context).scale(13) * 1.4 + 28)
                .clamp(56.0, double.infinity),
            child: ListView.builder(
              key: ValueKey('${widget.name}-rail'),
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              primary: false,
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Padding(
                  key: entry.key == widget.value ? _selected : null,
                  padding: const EdgeInsets.only(right: 8),
                  child: Semantics(
                    selected: entry.key == widget.value,
                    inMutuallyExclusiveGroup: true,
                    child: Tooltip(
                      message: entry.value,
                      child: GlassTextButton(
                        key: ValueKey('${widget.name}-${entry.key}'),
                        compact: true,
                        selected: entry.key == widget.value,
                        onPressed: widget.enabled
                            ? () => widget.onChanged(entry.key)
                            : null,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: AppText(
                            entry.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Small, visible sets of choices share the app's glass button and hit area.
class GlassChoiceGroup<T> extends StatelessWidget {
  const GlassChoiceGroup({
    super.key,
    required this.name,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.leading,
    this.optionName,
    this.labelSize = 14,
    this.optionSize = 13,
    this.enabled = true,
  });
  final String name, label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final Widget Function(T)? leading;
  final String Function(T)? optionName;
  final double labelSize, optionSize;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: AppText(
          label,
          style: TextStyle(fontSize: labelSize, fontWeight: FontWeight.w600),
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final entry in options.entries)
            Semantics(
              selected: entry.key == value,
              inMutuallyExclusiveGroup: true,
              child: GlassTextButton(
                compact: true,
                selected: entry.key == value,
                key: ValueKey(
                  '$name-${optionName?.call(entry.key) ?? entry.key}',
                ),
                onPressed: enabled ? () => onChanged(entry.key) : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null) ...[
                      leading!(entry.key),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: AppText(
                        entry.value,
                        style: TextStyle(
                          fontSize: optionSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ],
  );
}
