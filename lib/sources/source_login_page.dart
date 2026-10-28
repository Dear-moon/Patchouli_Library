import 'source_declarations.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../app_ui.dart';
import '../app_interactions.dart';
import '../feature_pages.dart';
import '../glass_choices.dart';
import 'book_source.dart';
import 'source_fields.dart';
import 'source_repository.dart';
import 'source_account_card.dart';

class SourceLoginPage extends StatefulWidget {
  const SourceLoginPage({
    super.key,
    required this.source,
    required this.repository,
    this.footer,
  });
  final BookSource source;
  final SourceNovelRepository repository;
  final Widget? footer;
  @override
  State<SourceLoginPage> createState() => _SourceLoginPageState();
}

class _SourceLoginPageState extends State<SourceLoginPage> {
  static int _next = 0;
  late final _request = 'login-ui-${++_next}';
  final _fields = <String, TextEditingController>{};
  final _choices = <String, String>{};
  List<Map<String, dynamic>> _rows = const [];
  String? _webUrl, _error;
  bool _loading = true, _busy = false;
  int _contentRevision = 0;
  String _rowSignature = '';
  bool _silent = false;
  String? _queuedAction;
  Timer? _debounce;
  bool _v2 = false;
  Map<String, dynamic> _loginState = {};
  Map<String, String> _fieldErrors = {};
  final _countdowns = <String, int>{};
  Timer? _countdownTimer;

  String _fieldKey(Map<String, dynamic> row) =>
      '${_v2 ? row['key'] : row['name']}';

  Map<String, String> _form() => {
    for (final row in _rows)
      if (row['type'] == 'text' || row['type'] == 'password')
        _fieldKey(row): _fields[_fieldKey(row)]?.text ?? ''
      else if (row['type'] == 'select' || row['type'] == 'toggle')
        _fieldKey(row): _choices[_fieldKey(row)] ?? '',
  };

  void _applyUi(Map<String, dynamic> result) {
    _v2 = result['version'] == 2;
    if (result['state'] is Map) {
      _loginState = Map<String, dynamic>.from(result['state'] as Map);
    }
    _fieldErrors = {
      for (final e in (result['error'] as Map? ?? {}).entries)
        '${e.key}': '${e.value}',
    };
    if (result['rows'] is! List) return;
    final info = Map<String, dynamic>.from(result['info'] as Map? ?? {});
    final rows = [
      for (final row in result['rows'] as List) Map<String, dynamic>.from(row),
    ];
    for (final row in rows) {
      final name = _fieldKey(row);
      final type = '${row['type'] ?? 'text'}';
      if (![
        'text',
        'password',
        'button',
        'select',
        'toggle',
        'label',
      ].contains(type)) {
        throw const SourceFailure('书源登录控件类型不支持');
      }
      final session = _fields[name]?.text ?? _choices[name];
      var value =
          '${_v2 ? row['value'] ?? session ?? info[name] ?? '' : info[name] ?? row['default'] ?? ''}';
      final options = row[_v2 ? 'options' : 'chars'] as List? ?? const [];
      if (type == 'select' && options.isNotEmpty && !options.contains(value)) {
        value = '${options.first}';
      }
      if (type == 'text' || type == 'password') {
        final controller = _fields[name] ??= TextEditingController();
        if (controller.text != value) controller.text = value;
      } else if (type == 'toggle' || type == 'select') {
        _choices[name] = value;
      }
    }
    final signature = rows
        .map(
          (r) =>
              '${r['key'] ?? r['name']}/${r['type']}/${r['label']}/${r['options'] ?? r['chars']}',
        )
        .join('|');
    if (signature != _rowSignature) {
      _rowSignature = signature;
      _contentRevision++;
    }
    _rows = rows;
    _webUrl = result['webUrl'] as String?;
  }

  void _startCountdown(String action, int seconds) {
    if (seconds <= 0) return;
    _countdowns[action] = seconds;
    _countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _countdowns.updateAll((_, left) => left - 1);
        _countdowns.removeWhere((_, left) => left <= 0);
        if (_countdowns.isEmpty) {
          _countdownTimer?.cancel();
          _countdownTimer = null;
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final result = Map<String, dynamic>.from(
        await widget.repository.platform.run(
              widget.source,
              'loginUi',
              book: {'loginState': _loginState},
              requestId: _request,
            )
            as Map,
      );
      if (!mounted) return;
      setState(() {
        _applyUi(result);
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = sourceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool silent = false,
  }) async {
    if (_busy) return;
    if (!silent) FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _silent = silent;
      _error = null;
      _fieldErrors = {};
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = sourceErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        final queued = _queuedAction;
        _queuedAction = null;
        if (queued != null) unawaited(_submit(queued, false));
      }
    }
  }

  Future<void> _submit([String action = '', bool finish = true]) =>
      _run(() async {
        if (finish) {
          _debounce?.cancel();
          _queuedAction = null;
        }
        final countdown =
            _rows.where((r) => r['action'] == action).firstOrNull?['countdown']
                as num?;
        final result = await widget.repository.platform.run(
          widget.source,
          'login',
          key: action,
          book: {'loginInfo': _form(), 'loginState': _loginState},
          requestId: _request,
        );
        if (!mounted) return;
        if (_v2) {
          final value = Map<String, dynamic>.from(result as Map);
          if (value['close'] == true) {
            TextInput.finishAutofillContext();
            await widget.repository.loginFinished(
              widget.source,
              requestId: _request,
            );
            if (!mounted) return;
            Navigator.of(context).pop();
            return;
          }
          setState(() {
            _applyUi(value);
            if (_fieldErrors.isEmpty && countdown != null) {
              _startCountdown(action, countdown.toInt());
            }
          });
          if (value['login'] != null) {
            await widget.repository.loginFinished(
              widget.source,
              requestId: _request,
            );
          }
          return;
        }
        final callbackUi = result is Map && result['version'] == 1;
        if (callbackUi) {
          setState(() => _applyUi(Map<String, dynamic>.from(result)));
          if (result['refreshExplore'] == true && !finish) {
            widget.repository.sessionChanged();
          }
        }
        if (finish) {
          if (action.isEmpty) TextInput.finishAutofillContext();
          await widget.repository.loginFinished(
            widget.source,
            requestId: _request,
          );
          if (!mounted) return;
          if (!callbackUi) await _load();
          if (mounted && (action.isEmpty || !callbackUi)) {
            showNovelFeedback(
              context,
              action.isEmpty ? '书源登录操作已完成，正在重新加载书目' : '书源操作已完成',
            );
          }
        }
      }, silent: !finish);

  Future<void> _clear() => _run(() async {
    _debounce?.cancel();
    _queuedAction = null;
    if (!await confirmNovelAction(
      context,
      title:
          SourceDeclarations.sessionKey(widget.source.key) != widget.source.key
          ? '清除 ${SourceDeclarations.platformName(widget.source.key)} 登录信息？'
          : '清除此书源的登录信息？',
      message:
          SourceDeclarations.sessionKey(widget.source.key) != widget.source.key
          ? '所有译文版本将共用退出状态，书籍、缓存和书签保留。'
          : '清除本机保存的登录表单、请求头、Cookie 与网页存储。书籍、缓存和书签保留。',
      confirmLabel: '清除登录',
    )) {
      return;
    }
    await widget.repository.platform.clearSession(widget.source);
    await widget.repository.accountCleared(widget.source);
    for (final field in _fields.values) {
      field.clear();
    }
    _choices.clear();
    _loginState = {};
    _countdowns.clear();
    await _load();
    if (mounted) showNovelFeedback(context, '已清除此书源的登录信息');
  });

  Future<void> _openWeb() => _run(() async {
    await widget.repository.platform.openLogin(
      widget.source,
      requestId: _request,
    );
    await widget.repository.loginFinished(widget.source, requestId: _request);
    await _load();
    if (mounted) showNovelFeedback(context, '网页会话已保存，正在重新加载书目');
  });

  @override
  void dispose() {
    _debounce?.cancel();
    _countdownTimer?.cancel();
    unawaited(widget.repository.platform.cancel(_request));
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title:
        '${SourceDeclarations.sessionKey(widget.source.key) != widget.source.key ? SourceDeclarations.platformName(widget.source.key) : widget.source.name} · 账号',
    code: 'SOURCES / SESSION',
    child: LoadedContentSequence(
      generation: _contentRevision,
      child: ListView(
        padding: featurePadding(context),
        children: [
          ArchiveSection(
            title:
                SourceDeclarations.sessionKey(widget.source.key) !=
                    widget.source.key
                ? SourceDeclarations.platformName(widget.source.key)
                : widget.source.name,
            code: 'YOUR SOURCE / YOUR ACCOUNT',
          ),
          SourceAccountPanel(
            source: widget.source,
            repository: widget.repository,
            enabled: !_busy,
          ),
          const SizedBox(height: 20),
          if (_loading)
            const SizedBox(
              height: 240,
              child: LoadingSkeleton(layout: SkeletonLayout.actions),
            )
          else
            AutofillGroup(
              onDisposeAction: AutofillContextAction.cancel,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppText(
                    '登录或切换当前平台账号',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  for (final (index, row) in _rows.indexed)
                    LoadedContentItem(
                      key: ValueKey(
                        '${row['type']}/${row['key'] ?? row['action'] ?? row['name']}',
                      ),
                      index: index,
                      child: _row(row),
                    ),
                  if (!_v2 && _rows.any((r) => r['type'] != 'button'))
                    GlassTextButton(
                      key: const ValueKey('source-login-submit'),
                      onPressed: _busy ? null : _submit,
                      child: const AppText('登录／保存'),
                    ),
                  if (_webUrl != null)
                    GlassTextButton(
                      key: const ValueKey('source-login-web'),
                      onPressed: _busy ? null : _openWeb,
                      child: const AppText('打开登录网页'),
                    ),
                  if (_webUrl != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: AppText(
                        '网页登录后，点“保存并返回”或使用系统返回，书目会自动重新加载。',
                        style: TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                  if (_rows.isEmpty && _webUrl == null && _error == null)
                    const AppText('这个书源没有提供登录入口。'),
                ],
              ),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: InlineSkeleton(label: '正在处理书源登录'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ContentNotice(
                icon: CupertinoIcons.exclamationmark_triangle,
                title: '登录操作未完成',
                message: _error,
                onRetry: () {
                  setState(() => _loading = true);
                  unawaited(_load());
                },
              ),
            ),
          for (final error in _fieldErrors.entries)
            if (!_rows.any(
              (row) =>
                  (row['type'] == 'text' || row['type'] == 'password') &&
                  _fieldKey(row) == error.key,
            ))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AppText(error.value),
              ),
          const SizedBox(height: 28),
          GlassTextButton(
            key: const ValueKey('source-login-clear'),
            onPressed: _busy ? null : _clear,
            child: const AppText('清除本机登录信息'),
          ),
          if (widget.footer case final footer?) ...[
            const SizedBox(height: 20),
            footer,
          ],
        ],
      ),
    ),
  );

  Widget _row(Map<String, dynamic> row) {
    final name = _fieldKey(row), type = '${row['type'] ?? 'text'}';
    final label = '${row['label'] ?? row['name'] ?? name}';
    if (type == 'label') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AppText(
          label,
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
      );
    }
    if (type == 'text' || type == 'password') {
      return sourceField(
        context,
        label,
        _fields[name]!,
        readOnly: _busy && !_silent,
        obscure: type == 'password',
        hint: row['hint'] as String?,
        error: _fieldErrors[name],
        textInputAction: type == 'password'
            ? TextInputAction.done
            : TextInputAction.next,
        onSubmitted: type == 'password' && !_v2 ? (_) => _submit() : null,
        autofillHints: [
          if (type == 'password')
            AutofillHints.password
          else if (RegExp(
            r'账号|账户|帳號|用户名|用戶名|邮箱|郵箱|user|email',
            caseSensitive: false,
          ).hasMatch(name))
            AutofillHints.username,
        ],
        onChanged: !_v2 && row['action'] is String
            ? (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 600), () {
                  if (!mounted) return;
                  final action = row['action'] as String;
                  if (_busy) {
                    _queuedAction = action;
                  } else {
                    unawaited(_submit(action, false));
                  }
                });
              }
            : null,
      );
    }
    if (type == 'button') {
      final action = '${row['action'] ?? ''}';
      final left = _countdowns[action] ?? 0;
      return GlassTextButton(
        key: ValueKey('source-login-action-$action'),
        onPressed: _busy || left > 0 ? null : () => _submit(action),
        child: AppText(left > 0 ? '$label (${left}s)' : label),
      );
    }
    final chars = [
      for (final value in row[_v2 ? 'options' : 'chars'] as List? ?? [])
        if (value != null) '$value',
    ];
    void select(String value) {
      setState(() => _choices[name] = value);
      if (row['action'] case final String action when action.isNotEmpty) {
        unawaited(_submit(action, false));
      }
    }

    if (type == 'toggle' && (_v2 || chars.length == 2)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: AppText(label, style: const TextStyle(fontSize: 14)),
            ),
            AppControls.toggle(
              context,
              value: _choices[name] == (_v2 ? 'true' : chars.last),
              onChanged: _busy
                  ? null
                  : (enabled) => select(
                      _v2
                          ? '$enabled'
                          : enabled
                          ? chars.last
                          : chars.first,
                    ),
            ),
          ],
        ),
      );
    }
    return GlassChoiceGroup<String>(
      name: 'source-login-$name',
      label: label,
      value: _choices[name] ?? '',
      options: {for (final value in chars) value: value},
      enabled: !_busy,
      onChanged: select,
    );
  }
}
