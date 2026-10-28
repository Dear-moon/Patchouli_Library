import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_ui.dart';
import 'glass_choices.dart';

/// Keeps the user's preference, submitted votes, and system report distinct.
class DisplayRateInfo {
  const DisplayRateInfo(
    this.target,
    this.current,
    this.rates, {
    this.canSelect = true,
    this.maximum,
    this.currentModeId,
    this.selectedModeId,
    this.selectedRate,
    this.requestStatusAvailable = false,
    this.requestedModeId,
    this.requestedRate,
    this.controllerActive,
    this.windowFocused,
    this.surfaceRequestedRate,
    this.surfaceRequestState,
    this.surfaceRequestError,
    this.powerSaveMode,
    this.thermalStatus,
  });
  factory DisplayRateInfo.fromMap(Map<dynamic, dynamic> value) =>
      DisplayRateInfo(
        (value['target'] as num).toDouble(),
        (value['current'] as num?)?.toDouble(),
        (value['rates'] as List).cast<num>().map((n) => n.toDouble()).toList(),
        canSelect: value['canSelect'] != false,
        maximum: (value['maximum'] as num?)?.toDouble(),
        currentModeId: (value['currentModeId'] as num?)?.toInt(),
        selectedModeId: (value['selectedModeId'] as num?)?.toInt(),
        selectedRate: (value['selectedRate'] as num?)?.toDouble(),
        requestStatusAvailable: value['requestStatusAvailable'] == true,
        requestedModeId: (value['requestedModeId'] as num?)?.toInt(),
        requestedRate: (value['requestedRate'] as num?)?.toDouble(),
        controllerActive: value['controllerActive'] as bool?,
        windowFocused: value['windowFocused'] as bool?,
        surfaceRequestedRate: (value['surfaceRequestedRate'] as num?)
            ?.toDouble(),
        surfaceRequestState: value['surfaceRequestState'] as String?,
        surfaceRequestError: value['surfaceRequestError'] as String?,
        powerSaveMode: value['powerSaveMode'] as bool?,
        thermalStatus: (value['thermalStatus'] as num?)?.toInt(),
      );
  final double target;
  // A hardware ceiling is not a measurement of the display or rendered frames.
  final double? current, maximum;
  final int? currentModeId, selectedModeId;
  final double? selectedRate;
  final List<double> rates;
  final bool canSelect;
  final bool requestStatusAvailable;
  final int? requestedModeId, thermalStatus;
  final double? requestedRate, surfaceRequestedRate;
  final bool? controllerActive, windowFocused, powerSaveMode;
  final String? surfaceRequestState, surfaceRequestError;

  bool get _windowRequestMatches =>
      requestedRate != null &&
      selectedRate != null &&
      (requestedRate! - selectedRate!).abs() < .5 &&
      requestedModeId == selectedModeId;

  /// An unmet request is not evidence of a specific OEM or thermal restriction.
  String? get requestNotice {
    if (!requestStatusAvailable) return null;
    if (controllerActive == false) return '返回文库前台后恢复刷新率请求';
    if (!_windowRequestMatches) return '正在向窗口提交刷新率请求';
    if (surfaceRequestState == 'failed') return '渲染表面的刷新率请求未成功，返回页面后重试';
    if (surfaceRequestState == 'waiting_for_surface' ||
        surfaceRequestState == 'pending') {
      return '等待阅读画面就绪后提交刷新率请求';
    }
    if (requestedRate != null &&
        current != null &&
        requestedRate! > current! + .5 &&
        windowFocused == true) {
      return '系统当前未采用请求的刷新率，可检查系统对文库的高刷新率设置';
    }
    return null;
  }

  String? get systemNotice {
    final states = <String>[
      if (powerSaveMode == true) '系统省电模式已开启',
      if (thermalStatus != null && thermalStatus! >= 3) '系统报告设备处于高温状态',
    ];
    return states.isEmpty ? null : states.join(' · ');
  }
}

class FrameRateSettings extends ChangeNotifier {
  FrameRateSettings({
    this.channel = const MethodChannel('org.mewx.wenku8/frame_rate'),
  }) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') {
        if (busy) {
          _pending = true;
        } else if (hasListeners) {
          await load();
        }
      }
    });
  }
  static final shared = FrameRateSettings();
  final MethodChannel channel;
  DisplayRateInfo? info;
  bool busy = false, _disposed = false, _pending = false;
  String? error;
  Future<void> load() => _request('info');
  Future<void> select(double target) => _request('set', {'target': target});
  Future<void> _request(String method, [Map<String, Object>? arguments]) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final value = await channel.invokeMapMethod<dynamic, dynamic>(
        method,
        arguments,
      );
      if (!_disposed) info = DisplayRateInfo.fromMap(value!);
    } catch (failure) {
      if (!_disposed) {
        error = failure is PlatformException
            ? failure.message ?? '刷新率读取失败，请重试'
            : '刷新率读取失败，请重试';
      }
    } finally {
      busy = false;
      if (!_disposed) {
        notifyListeners();
        if (_pending) {
          _pending = false;
          unawaited(load());
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}

String displayRateLabel(double rate) =>
    '${(rate - rate.round()).abs() < .15 ? rate.round() : rate.toStringAsFixed(1)} Hz';

class FrameRateOptions extends StatefulWidget {
  const FrameRateOptions({super.key, this.settings});
  final FrameRateSettings? settings;
  @override
  State<FrameRateOptions> createState() => _FrameRateOptionsState();
}

class _FrameRateOptionsState extends State<FrameRateOptions>
    with WidgetsBindingObserver {
  late final settings = widget.settings ?? FrameRateSettings.shared;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(settings.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(settings.load());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (context, _) {
      final info = settings.info;
      final availableRates = info == null
          ? const <double>[]
          : info.rates.fold<List<double>>([], (values, rate) {
              if (values.every((known) => (known - rate).abs() >= .5)) {
                values.add(rate);
              }
              return values;
            });
      final selectedRate = info == null
          ? null
          : availableRates.cast<double?>().firstWhere(
                  (rate) => (rate! - info.target).abs() < .5,
                  orElse: () => null,
                ) ??
                info.target;
      return ContentPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                ArchiveIcon(CupertinoIcons.speedometer, size: 20),
                SizedBox(width: 10),
                AppText(
                  '帧率偏好',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (info != null) ...[
              if (info.canSelect)
                GlassChoiceGroup<double>(
                  name: 'frame-rate',
                  label: '滚动与动效',
                  value: selectedRate!,
                  options: {
                    0: '自动高刷',
                    -1: '系统调度',
                    for (final rate in availableRates)
                      rate: displayRateLabel(rate),
                    if (info.target > 0 &&
                        availableRates.every(
                          (rate) => (rate - info.target).abs() >= .5,
                        ))
                      info.target: '${displayRateLabel(info.target)} · 暂不可用',
                  },
                  optionName: (rate) => rate.toString(),
                  onChanged: (rate) {
                    if (!settings.busy) unawaited(settings.select(rate));
                  },
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 14, bottom: 6),
                  child: AppText(
                    '系统自动调度',
                    key: ValueKey('frame-rate-system-managed'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              const SizedBox(height: 6),
              if (info.current != null || info.maximum != null)
                AppText(
                  info.current != null
                      ? '系统报告 ${displayRateLabel(info.current!)}'
                      : '屏幕最高支持 ${displayRateLabel(info.maximum!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              if (info.requestStatusAvailable &&
                  info.controllerActive == true &&
                  info.requestedRate != null)
                AppText(
                  info.requestedRate! > 0
                      ? '窗口请求 ${displayRateLabel(info.requestedRate!)}'
                      : '窗口请求已交还系统调度',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              if (info.requestStatusAvailable &&
                  info.controllerActive == true &&
                  info.surfaceRequestedRate != null &&
                  info.surfaceRequestedRate! > 0)
                AppText(
                  '渲染表面请求 ${displayRateLabel(info.surfaceRequestedRate!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              if (!info.requestStatusAvailable &&
                  info.selectedRate != null &&
                  info.selectedRate! > 0)
                AppText(
                  '期望刷新率 ${displayRateLabel(info.selectedRate!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              if (info.requestNotice case final notice?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: AppText(
                    notice,
                    style: const TextStyle(fontSize: 12, height: 1.6),
                  ),
                ),
              if (info.systemNotice case final notice?)
                AppText(
                  notice,
                  style: const TextStyle(fontSize: 12, height: 1.6),
                ),
            ] else if (settings.busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: InlineSkeleton(width: 160, height: 16, label: '正在读取刷新率'),
              ),
            const SizedBox(height: 10),
            AppText(
              info?.canSelect == false
                  ? '滚动与动效由系统自动调度，不能手动锁定。屏幕上限和系统报告均不是实际渲染帧率。'
                  : '高刷新率适合滚动与翻页，较低刷新率更省电。系统报告是提供给本应用的刷新率，不是实际渲染帧率；最终调度由系统决定。',
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
            if (settings.error != null) ...[
              const SizedBox(height: 8),
              AppText(settings.error!, style: const TextStyle(fontSize: 12)),
              GlassTextButton(
                onPressed: settings.busy ? null : settings.load,
                child: const AppText('重新读取'),
              ),
            ],
          ],
        ),
      );
    },
  );
}
