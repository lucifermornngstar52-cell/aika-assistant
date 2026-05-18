import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AppLauncherService {
  static const _prefsKey = 'custom_app_commands';

  // Публичный — нужен для CommandsScreen чтобы отличить встроенные от пользовательских
  static const Map<String, String> builtinCommands = {
    'открой музыку':      'com.spotify.music',
    'включи музыку':      'com.spotify.music',
    'открой спотифай':    'com.spotify.music',
    'открой spotify':     'com.spotify.music',
    'открой ютуб музыку': 'com.google.android.apps.youtube.music',
    'открой ютуб':        'com.google.android.youtube',
    'открой youtube':     'com.google.android.youtube',
    'включи ютуб':        'com.google.android.youtube',
    'открой тикток':      'com.zhiliaoapp.musically',
    'открой tiktok':      'com.zhiliaoapp.musically',
    'открой телеграм':    'org.telegram.messenger',
    'открой telegram':    'org.telegram.messenger',
    'открой вацап':       'com.whatsapp',
    'открой whatsapp':    'com.whatsapp',
    'открой вк':          'com.vkontakte.android',
    'открой вконтакте':   'com.vkontakte.android',
    'открой инстаграм':   'com.instagram.android',
    'открой instagram':   'com.instagram.android',
    'открой настройки':   'com.android.settings',
    'открой камеру':      'com.android.camera2',
    'открой калькулятор': 'com.google.android.calculator',
    'открой карты':       'com.google.android.apps.maps',
    'открой гугл карты':  'com.google.android.apps.maps',
    'открой браузер':     'com.android.chrome',
    'открой хром':        'com.android.chrome',
    'открой chrome':      'com.android.chrome',
    'открой файлы':       'com.google.android.documentsui',
    'открой почту':       'com.google.android.gm',
    'открой гмейл':       'com.google.android.gm',
    'открой gmail':       'com.google.android.gm',
    'открой часы':        'com.google.android.deskclock',
    'открой будильник':   'com.google.android.deskclock',
  };

  static Future<String?> tryLaunch(String phrase) async {
    final normalized = phrase.toLowerCase().trim();

    // Сначала пользовательские (приоритет)
    final custom = await _loadCustomCommands();
    for (final entry in custom.entries) {
      if (normalized.contains(entry.key)) {
        return await _launch(entry.value);
      }
    }

    // Потом встроенные
    for (final entry in builtinCommands.entries) {
      if (normalized.contains(entry.key)) {
        return await _launch(entry.value);
      }
    }

    return null;
  }

  static Future<String> _launch(String packageName) async {
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
      return 'Открываю';
    } catch (e) {
      try {
        final store = AndroidIntent(
          action: 'android.intent.action.VIEW',
          data: 'market://details?id=$packageName',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await store.launch();
        return 'Приложение не найдено, открываю Play Store';
      } catch (_) {
        return 'Не удалось открыть приложение';
      }
    }
  }

  static Future<Map<String, String>> _loadCustomCommands() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw));
  }

  static Future<void> addCommand(String phrase, String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final commands = await _loadCustomCommands();
    commands[phrase.toLowerCase().trim()] = packageName.trim();
    await prefs.setString(_prefsKey, jsonEncode(commands));
  }

  static Future<void> removeCommand(String phrase) async {
    final prefs = await SharedPreferences.getInstance();
    final commands = await _loadCustomCommands();
    commands.remove(phrase.toLowerCase().trim());
    await prefs.setString(_prefsKey, jsonEncode(commands));
  }

  static Future<Map<String, String>> getAllCommands() async {
    final custom = await _loadCustomCommands();
    return {...builtinCommands, ...custom};
  }
}
