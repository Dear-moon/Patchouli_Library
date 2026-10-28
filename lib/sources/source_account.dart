import 'book_source.dart';

/// Only safe, host-owned account metadata crosses the platform boundary.
class SourceAccountStatus {
  const SourceAccountStatus({
    this.status = 'none',
    this.hasSession = false,
    this.displayName = '',
    this.avatarUrl = '',
    this.failureReason = '',
    this.loginAvailable = false,
    this.canVerify = false,
    this.canSync = false,
    this.canCheckIn = false,
    this.checkedInToday = false,
    this.configurationError = false,
    this.checkInSteps = const [],
    this.checkedAt,
  });
  factory SourceAccountStatus.fromMap(Map<dynamic, dynamic> value) {
    final capabilities = value['capabilities'] as Map? ?? const {};
    final profile = value['profile'] as Map? ?? const {};
    return SourceAccountStatus(
      status: '${value['status'] ?? 'none'}',
      hasSession: value['hasSession'] == true,
      displayName: profile['displayName'] as String? ?? '',
      avatarUrl: profile['avatarUrl'] as String? ?? '',
      failureReason: value['validationError'] as String? ?? '',
      loginAvailable: value['loginAvailable'] == true,
      canVerify: capabilities['verify'] == true,
      canSync: capabilities['shelf'] == true,
      canCheckIn: capabilities['checkIn'] == true,
      checkedInToday: value['checkedInToday'] == true,
      checkInSteps: [
        for (final raw in value['checkInSteps'] as List? ?? const [])
          SourceCheckInStep.fromMap(raw as Map),
      ],
      configurationError: value['configurationError'] == true,
      checkedAt: value['checkedAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (value['checkedAt'] as num).toInt(),
            )
          : null,
    );
  }
  final String status, displayName, avatarUrl, failureReason;
  final List<SourceCheckInStep> checkInSteps;
  final bool hasSession;
  final bool loginAvailable, canVerify, canSync, canCheckIn;
  final bool checkedInToday, configurationError;
  final DateTime? checkedAt;
  String get label => switch (status) {
    'verified' => '已登录',
    'signedOut' => '登录已失效',
    'saved' => '登录信息已保存，待验证',
    'unchecked' => '待验证登录',
    'error' => '暂时无法验证登录',
    _ => loginAvailable || canVerify ? '未登录' : '未提供登录',
  };
  String? get explanation => configurationError
      ? '账号扩展规则不完整，请编辑书源检查。'
      : switch (status) {
          'saved' => '本机会话已保存${canVerify ? '，可验证是否仍有效。' : '；书源未提供独立登录验证。'}',
          'unchecked' => '登录操作已结束${canVerify ? '，请验证当前状态。' : '；书源未提供独立登录验证。'}',
          'signedOut' => '书源未接受当前登录，请重新登录。',
          'error' =>
            '${failureReason.isEmpty ? '验证暂未完成' : failureReason}；登录信息仍保留，可稍后重试。',
          'verified' => checkedAt == null ? null : '最近验证 ${_time(checkedAt!)}',
          _ => null,
        };
  static String _time(DateTime value) =>
      '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

bool sourceCanVerifyAccount(BookSource source) {
  final rules = source.data['ruleAccount'];
  if (rules is! Map || rules['verify'] is! Map) return false;
  final verify = rules['verify'] as Map;
  if (source.key == 'builtin:wenku8' && verify['native'] == 'wenku8') {
    return true;
  }
  if (verify['js'] is String && (verify['js'] as String).isNotEmpty) {
    return true;
  }
  return verify['url'] is String &&
      (verify['url'] as String).isNotEmpty &&
      verify['loggedIn'] is String &&
      (verify['loggedIn'] as String).isNotEmpty;
}

class SourceCheckInStep {
  const SourceCheckInStep({
    required this.id,
    required this.label,
    required this.complete,
    required this.already,
    this.message = '',
  });
  factory SourceCheckInStep.fromMap(Map value) => SourceCheckInStep(
    id: value['id'] as String,
    label: value['label'] as String,
    complete: value['complete'] == true,
    already: value['already'] == true,
    message: value['message'] as String? ?? '',
  );
  final String id, label, message;
  final bool complete, already;
}

class SourceCheckInResult {
  const SourceCheckInResult({
    required this.complete,
    required this.already,
    this.steps = const [],
  });
  factory SourceCheckInResult.fromMap(Map value) => SourceCheckInResult(
    complete: value['complete'] != false,
    already: value['already'] == true,
    steps: [
      for (final raw in value['steps'] as List? ?? const [])
        SourceCheckInStep.fromMap(raw as Map),
    ],
  );
  final bool complete, already;
  final List<SourceCheckInStep> steps;
  String get label => steps.isEmpty
      ? already
            ? '今日已签到'
            : '签到成功'
      : complete
      ? '各项签到均已完成'
      : '部分签到未完成，可重试未完成项目';
}
