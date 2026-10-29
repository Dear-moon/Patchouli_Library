import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'languages.dart';
import 'enhancement.dart';

/// Speech preferences/cursors are separate from reading anchors and existing backup schema.
class ListeningStore {
  ListeningStore(this.preferences);
  final SharedPreferences preferences;
  Future<void> _writes = Future.value();
  Future<void> _write(Future<bool> Function() action, String message) {
    final next = _writes.then((_) async {
      if (!await action()) throw SpeechFailure(message);
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  SpeechVoice get voice {
    try {
      final raw = preferences.getString('listening.voice.v1');
      if (raw != null) {
        final record = jsonDecode(raw) as Map<String, dynamic>;
        if (record['source'] == 'system' && record['systemApi'] != 1) {
          return defaultEdgeVoice;
        }
        final voice = SpeechVoice.fromJson(record);
        return voice.availableForListening ? voice : defaultEdgeVoice;
      }
    } catch (_) {
      /* Keep a damaged speech setting isolated from the reading library. */
    }
    return defaultEdgeVoice;
  }

  double get speed => (preferences.getDouble('listening.speed.v1') ?? 1).clamp(
    listeningMinimumSpeed,
    listeningMaximumSpeed,
  );
  bool get follow => preferences.getBool('listening.follow.v1') ?? true;
  int get paragraphGapMs => normalizeListeningParagraphGap(
    preferences.getInt('listening.paragraphGapMs.v1') ?? 0,
  );

  /// Enhancement preferences do not alter voice caches or reading backups.
  ListeningEnhancementPreference get enhancement {
    try {
      final raw = preferences.getString('listening.enhancement.v1');
      if (raw != null) {
        final value = jsonDecode(raw);
        if (value is Map) return ListeningEnhancementPreference.fromJson(value);
      }
    } catch (_) {
      // A damaged optional gain preference must leave ordinary playback usable.
    }
    return const ListeningEnhancementPreference();
  }

  Future<void> saveEnhancement(ListeningEnhancementPreference value) => _write(
    () => preferences.setString(
      'listening.enhancement.v1',
      jsonEncode(value.toJson()),
    ),
    '声音增强设置保存失败',
  );
  String? spokenLanguage(int novelId) {
    final code = speechLanguageCode(
      preferences.getString('listening.language.v1.$novelId') ?? '',
    );
    return code.isEmpty ? null : code;
  }

  Future<void> saveSpokenLanguage(int novelId, String? language) {
    final code = speechLanguageCode(language ?? '');
    return _write(
      () => code.isEmpty
          ? preferences.remove('listening.language.v1.$novelId')
          : preferences.setString('listening.language.v1.$novelId', code),
      '朗读语言保存失败',
    );
  }

  String _voiceScope(SpeechVoice voice) =>
      'listening.languageVoices.v1.${voice.source.name}.${Uri.encodeComponent(voice.engine ?? '')}';

  Map<String, SpeechVoice> languageVoices(SpeechVoice preferred) {
    final found = <String, SpeechVoice>{};
    try {
      final raw = preferences.getString(_voiceScope(preferred));
      final values = raw == null ? null : jsonDecode(raw);
      if (values is Map) {
        for (final entry in values.entries) {
          try {
            if (entry.key is! String || entry.value is! Map) continue;
            final record = Map<String, dynamic>.from(entry.value);
            final voice = SpeechVoice.fromJson(record);
            final code = speechLanguageCode(entry.key);
            if (code.isNotEmpty &&
                voice.availableForListening &&
                voice.id != '@default' &&
                voice.source == preferred.source &&
                voice.engine == preferred.engine &&
                speechLanguageCode(voice.locale) == code &&
                (voice.source != ListeningSource.system ||
                    record['systemApi'] == 1)) {
              found[code] = voice;
            }
          } catch (_) {
            /* A damaged choice must not hide the other languages. */
          }
        }
      }
    } catch (_) {
      /* Fall back to automatic matching. */
    }
    return Map.unmodifiable(found);
  }

  Future<void> saveLanguageVoice(
    SpeechVoice preferred,
    String language,
    SpeechVoice? voice,
  ) => _write(() {
    final values = Map<String, SpeechVoice>.of(languageVoices(preferred));
    final code = speechLanguageCode(language);
    if (voice == null) {
      values.remove(code);
    } else {
      values[code] = voice;
    }
    return preferences.setString(
      _voiceScope(preferred),
      jsonEncode({
        for (final entry in values.entries) entry.key: entry.value.toJson(),
      }),
    );
  }, '分语言音色保存失败');

  Future<void> saveVoice(SpeechVoice voice) {
    if (!voice.availableForListening) {
      return Future.error(const SpeechFailure('请选择可用的朗读引擎'));
    }
    return _write(
      () => preferences.setString(
        'listening.voice.v1',
        jsonEncode(voice.toJson()),
      ),
      '音色设置保存失败',
    );
  }

  Future<void> saveSpeed(double value) => _write(
    () => preferences.setDouble(
      'listening.speed.v1',
      value.clamp(listeningMinimumSpeed, listeningMaximumSpeed),
    ),
    '语速设置保存失败',
  );
  Future<void> saveFollow(bool value) => _write(
    () => preferences.setBool('listening.follow.v1', value),
    '跟读设置保存失败',
  );
  Future<void> saveParagraphGap(int value) => _write(
    () => preferences.setInt(
      'listening.paragraphGapMs.v1',
      normalizeListeningParagraphGap(value),
    ),
    '段落间隔保存失败',
  );
  ListeningCursor? cursor(int novelId) {
    try {
      final raw = preferences.getString('listening.cursor.v1.$novelId');
      return raw == null
          ? null
          : ListeningCursor.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCursor(ListeningCursor cursor) => _write(
    () => preferences.setString(
      'listening.cursor.v1.${cursor.novelId}',
      jsonEncode(cursor.toJson()),
    ),
    '续听位置保存失败',
  );
}
