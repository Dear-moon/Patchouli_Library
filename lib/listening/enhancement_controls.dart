import 'package:flutter/material.dart';

import '../app_ui.dart';
import '../ui_notifiers.dart';
import 'enhancement.dart';

/// Only visible settings listen to updates; background audio retains its effect.
class ListeningEnhancementSettings extends StatelessWidget {
  const ListeningEnhancementSettings({
    super.key,
    required this.enhancement,
    required this.onChanged,
  });

  final ListeningEnhancement enhancement;
  final ValueChanged<ListeningEnhancementPreference> onChanged;

  @override
  Widget build(BuildContext context) =>
      SelectedValueBuilder<
        ListeningEnhancementPreference,
        ListeningEnhancementPreference
      >(
        listenable: enhancement.preferences,
        pauseWhenCovered: true,
        select: (value) => value,
        builder: (context, preference, _) =>
            SelectedValueBuilder<
              ListeningEnhancementState,
              ListeningEnhancementState
            >(
              listenable: enhancement.status,
              pauseWhenCovered: true,
              select: (value) => value,
              builder: (context, status, _) => ListeningEnhancementControls(
                preference: preference,
                status: status,
                onChanged: onChanged,
              ),
            ),
      );
}

/// Listening-only gain settings; the shared controls retain the app's styling.
class ListeningEnhancementControls extends StatelessWidget {
  const ListeningEnhancementControls({
    super.key,
    required this.preference,
    required this.status,
    required this.onChanged,
  });

  final ListeningEnhancementPreference preference;
  final ListeningEnhancementState status;
  final ValueChanged<ListeningEnhancementPreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final available = status.supported;
    final enabled = available && preference.enabled;
    final message = switch (status.phase) {
      ListeningEnhancementPhase.checking => '正在检查播放器支持情况',
      ListeningEnhancementPhase.unavailable ||
      ListeningEnhancementPhase.failed => status.reason ?? '当前播放器暂不支持声音增强',
      ListeningEnhancementPhase.waitingSession => '开始播放后生效',
      ListeningEnhancementPhase.active =>
        status.active
            ? '已生效 · +${status.gainDb.toStringAsFixed(0)} dB'
            : '声音增强暂未生效',
      ListeningEnhancementPhase.off => '仅增强听书响度，不改变系统音量',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(
              child: AppText(
                '声音增强',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            AppControls.toggle(
              context,
              key: const ValueKey('listening-enhancement-toggle'),
              value: enabled,
              onChanged: available
                  ? (value) => onChanged(
                      ListeningEnhancementPreference(
                        enabled: value,
                        gainDb: preference.gainDb,
                      ),
                    )
                  : null,
            ),
          ],
        ),
        AppText(
          message,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (enabled) ...[
          const SizedBox(height: 12),
          AppControls.segments<int>(
            context,
            key: const ValueKey('listening-enhancement-gain'),
            groupValue: preference.gainDb,
            children: const {
              2: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: AppText('轻柔 +2 dB'),
              ),
              4: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: AppText('适中 +4 dB'),
              ),
              6: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: AppText('较强 +6 dB'),
              ),
            },
            onValueChanged: (gain) {
              if (gain != null) {
                onChanged(
                  ListeningEnhancementPreference(enabled: true, gainDb: gain),
                );
              }
            },
          ),
        ],
      ],
    );
  }
}
