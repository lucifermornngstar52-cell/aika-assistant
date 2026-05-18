import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Маппинг фраз → пакеты приложений.
/// Пользователь может добавлять свои через настройки.
class AppLauncherService {
  static const _prefsKey = 'custom_app_commands';

  // Встроенные команды (фраза → package name)
  static const Map<String, String> _builtinCommands = {
    // Музыка
    'открой музыку':      'com.spotify.music',
    'включи музыку':      'com.spotify.music',
    'открой спотифай':    'com.spotify.music',
    'открой spotify':     'com.spotify.music',
    'открой ютуб музыку': 'com.google.android.apps.youtube.music',
    // Видео
    'открой ютуб':        'com.google.android.youtube',
    'открой youtube':     'com.google.android.youtube',
    'включи ютуб':        'com.google.android.youtube',
    'открой тикток':      'com.zhiliaoapp.musically',
    'открой tiktok':      'com.zhiliaoapp.musically',
    // Мессенджеры
    'открой телеграм':    'org.telegram.messenger',
    'открой telegram':    'org.telegram.messenger',
    'открой вацап':       'com.whatsapp',
    'открой whatsapp':    'com.whatsapp',
    'открой вк':          'com.vkontakte.android',
    'открой вконтакте':   'com.vkontakte.android',
    'открой инстаграм':   'com.instagram.android',
    'открой instagram':   'com.instagram.android',
    // Система
    'открой настройки':   'com.android.settings',
    'открой камеру':      'com.android.camera2',
    'открой калькулятор': 'com.google.android.calculator',
    'открой карты':       'com.google.android.apps.maps',
    'открой гугл карты':  'com.google.android.apps.maps',
    'открой браузер':     'com.android.chrome',
    'открой хром':        'com.android.chrome',
    'открой chrome':      'com.android.chrome',
    // Файлы/прочее
    'открой файлы':       'com.google.android.documentsui',
    'открой почту':       'com.google.android.gm',
    'открой гмейл':       'com.google.android.gm',
    'открой gmail':       'com.google.android.gm',
    'открой часы':        'com.google.android.deskclock',
    'открой будильник':   'com.google.android.deskclock',
  };

  /// Попытаться запустить приложение по фразе.
  /// Возвращает строку-результат или null если команда не найдена.
  static Future<String?> tryLaunch(String phrase) async {
    final normalized = phrase.toLowerCase().trim();

    // Сначала ищем в пользовательских командах
    final custom = await _loadCustomCommands();
    for (final entry in custom.entries) {
      if (normalized.contains(entry.key)) {
        return await _launch(entry.key, entry.value);
      }
    }

    // Потом в встроенных
    for (final entry in _builtinCommands.entries) {
      if (normalized.contains(entry.key)) {
        return await _launch(entry.key, entry.value);
      }
    }

    return null;
  }

  /// Запустить приложение по package name
  static Future<String> _launch(String phrase, String packageName) async {
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: packageName,
        flags: [
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
        ],
      );
      await intent.launch();
      return 'Открываю приложение';
    } catch (e) {
      // Приложение не установлено — открываем Play Store
      try {
        final storeIntent = AndroidIntent(
          action: 'android.intent.action.VIEW',
          data: 'market://details?id=$packageName',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await storeIntent.launch();
        return 'Приложение не найдено. Открываю Play Store.';
      } catch (_) {
        return 'Приложение не установлено.';
      }
    }
  }

  // ── Пользовательские команды ─────────────────────────────────────────────

  static Future<Map<String, String>> _loadCustomCommands() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw));
  }

  /// Добавить пользовательскую команду (например: "открой банк" → "kz.halyk.homebank")
  static Future<void> addCommand(String phrase, String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final commands = await _loadCustomCommands();
    commands[phrase.toLowerCase().trim()] = packageName.trim();
    await prefs.setString(_prefsKey, jsonEncode(commands));
  }

  /// Удалить пользовательскую команду
  static Future<void> removeCommand(String phrase) async {
    final prefs = await SharedPreferences.getInstance();
    final commands = await _loadCustomCommands();
    commands.remove(phrase.toLowerCase().trim());
    await prefs.setString(_prefsKey, jsonEncode(commands));
  }

  /// Получить все команды (встроенные + пользовательские)
  static Future<Map<String, String>> getAllCommands() async {
    final custom = await _loadCustomCommands();
    return {..._builtinCommands, ...custom};
  }
}
