import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'dock_layout.dart';

/// The book editors compose the same header and two-pill Dock as detail pages.
class LocalBookEditLayout extends StatelessWidget {
  const LocalBookEditLayout({
    super.key,
    required this.title,
    required this.code,
    required this.onBack,
    required this.slivers,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.secondaryIcon,
    required this.onSecondary,
    this.primaryKey,
    this.secondaryKey,
  });

  final String title, code, primaryLabel, secondaryLabel;
  final IconData primaryIcon, secondaryIcon;
  final VoidCallback? onBack, onPrimary, onSecondary;
  final Key? primaryKey, secondaryKey;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final geometry = glassActionDockGeometry(
      context,
      primary: primaryLabel,
      secondary: secondaryLabel,
    );
    final safe = MediaQuery.viewPaddingOf(context);
    Widget action({required bool primary}) => GlassPillButton(
      key: primary ? primaryKey : secondaryKey,
      icon: primary ? primaryIcon : secondaryIcon,
      label: primary ? primaryLabel : secondaryLabel,
      onPressed: primary ? onPrimary : onSecondary,
      height: DockLayout.heightOf(context),
      iconSize: DockLayout.iconSize,
      fontSize: DockLayout.labelFontSize,
    );
    return Scaffold(
      body: Atmosphere(
        child: GlassHeaderLayout(
          header: ArchiveHeaderBar(
            leading: GlassIconButton(
              icon: CupertinoIcons.back,
              label: '返回',
              onPressed: onBack,
            ),
            title: ArchiveRouteTitle(title: title, code: code),
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: CustomScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      ...slivers,
                      SliverToBoxAdapter(
                        child: SizedBox(height: geometry.extent + 20),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: DockUnderlay(contentHeight: geometry.height),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    DockLayout.actionSideInset + safe.left,
                    0,
                    DockLayout.actionSideInset + safe.right,
                    DockLayout.bottomPaddingOf(context, viewPadding: true),
                  ),
                  child: ControlMaterialScope.chrome(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: DockLayout.actionMaxWidth,
                      ),
                      child: SizedBox(
                        height: geometry.height,
                        child: geometry.stacked
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  action(primary: false),
                                  const SizedBox(height: DockLayout.actionGap),
                                  action(primary: true),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: action(primary: false),
                                  ),
                                  const SizedBox(width: DockLayout.actionGap),
                                  Expanded(
                                    flex: 7,
                                    child: action(primary: true),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LocalBookEditField extends StatelessWidget {
  const LocalBookEditField({
    super.key,
    required this.label,
    required this.controller,
    this.inputKey,
    this.enabled = true,
    this.autofocus = false,
    this.onSubmitted,
    this.onChanged,
    this.maxLength = 160,
    this.minLines = 1,
    this.maxLines = 1,
    this.placeholder,
  });
  final String label;
  final TextEditingController controller;
  final Key? inputKey;
  final bool enabled, autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final int maxLength, minLines, maxLines;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium!;
    final style = body.copyWith(
      inherit: false,
      fontFamily:
          body.fontFamily ?? theme.typography.black.bodyMedium?.fontFamily,
      fontSize: 16,
      height: 1.5,
      leadingDistribution: TextLeadingDistribution.even,
      color: scheme.onSurface,
    );
    final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(ArchiveDesign.panelRadius),
      borderSide: BorderSide.none,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppText(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 9),
        DefaultSelectionStyle.merge(
          cursorColor: scheme.primary,
          selectionColor: scheme.onSurface.withValues(
            alpha: theme.brightness == Brightness.dark ? .20 : .18,
          ),
          child: DefaultTextStyle.merge(
            textHeightBehavior: const TextHeightBehavior(),
            child: DefaultTextHeightBehavior(
              textHeightBehavior: const TextHeightBehavior(),
              child: TextField(
                key: inputKey,
                controller: controller,
                enabled: enabled,
                autofocus: autofocus,
                maxLength: maxLength,
                minLines: minLines,
                maxLines: maxLines,
                style: style,
                strutStyle: strut,
                textAlignVertical: maxLines > 1
                    ? TextAlignVertical.top
                    : TextAlignVertical.center,
                cursorHeight: MediaQuery.textScalerOf(
                  context,
                ).scale(style.fontSize!),
                cursorColor: scheme.primary,
                keyboardAppearance: theme.brightness,
                onTap: () => AppHaptics.play(context, HapticCue.selection),
                onSubmitted: onSubmitted,
                onChanged: onChanged,
                decoration: InputDecoration(
                  hint: placeholder == null
                      ? null
                      : Text(
                          appText(context, placeholder!),
                          style: style.copyWith(color: scheme.onSurfaceVariant),
                          strutStyle: strut,
                          textHeightBehavior: const TextHeightBehavior(),
                        ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: scheme.onSurface.withValues(alpha: .045),
                  border: border,
                  enabledBorder: border,
                  focusedBorder: border,
                  disabledBorder: border,
                  counterText: '',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
