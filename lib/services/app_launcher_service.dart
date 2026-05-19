import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AppLauncherService {
  static const _prefsKey = 'custom_app_commands';

  static const Map<String, String> builtinCommands = {
    // Spotify / Музыка
    'открой музыку':           'com.spotify.music',
    'включи музыку':           'com.spotify.music',
    'запусти музыку':          'com.spotify.music',
    'открой спотифай':         'com.spotify.music',
    'открой spotify':          'com.spotify.music',
    'спотифай':                'com.spotify.music',
    'spotify':                 'com.spotify.music',
    // YouTube Music
    'открой ютуб музыку':      'com.google.android.apps.youtube.music',
    'ютуб музыка':             'com.google.android.apps.youtube.music',
    'youtube music':           'com.google.android.apps.youtube.music',
    // YouTube
    'открой ютуб':             'com.google.android.youtube',
    'открой youtube':          'com.google.android.youtube',
    'включи ютуб':             'com.google.android.youtube',
    'запусти ютуб':            'com.google.android.youtube',
    'ютуб':                    'com.google.android.youtube',
    'youtube':                 'com.google.android.youtube',
    // TikTok
    'открой тикток':           'com.zhiliaoapp.musically',
    'открой tiktok':           'com.zhiliaoapp.musically',
    'тикток':                  'com.zhiliaoapp.musically',
    'tiktok':                  'com.zhiliaoapp.musically',
    // Telegram
    'открой телеграм':         'org.telegram.messenger',
    'открой telegram':         'org.telegram.messenger',
    'запусти телеграм':        'org.telegram.messenger',
    'телеграм':                'org.telegram.messenger',
    'telegram':                'org.telegram.messenger',
    // WhatsApp
    'открой вацап':            'com.whatsapp',
    'открой whatsapp':         'com.whatsapp',
    'вацап':                   'com.whatsapp',
    'whatsapp':                'com.whatsapp',
    // VK
    'открой вк':               'com.vkontakte.android',
    'открой вконтакте':        'com.vkontakte.android',
    'вконтакте':               'com.vkontakte.android',
    'вк':                      'com.vkontakte.android',
    // Instagram
    'открой инстаграм':        'com.instagram.android',
    'открой instagram':        'com.instagram.android',
    'инстаграм':               'com.instagram.android',
    'instagram':               'com.instagram.android',
    // Yandex Music
    'яндекс музыка':           'ru.yandex.music',
    'открой яндекс музыку':    'ru.yandex.music',
    'включи яндекс музыку':    'ru.yandex.music',
    // Netflix
    'открой нетфликс':         'com.netflix.mediaclient',
    'открой netflix':          'com.netflix.mediaclient',
    'нетфликс':                'com.netflix.mediaclient',
    // Twitch
    'открой твич':             'tv.twitch.android.app',
    'открой twitch':           'tv.twitch.android.app',
    'твич':                    'tv.twitch.android.app',
    // Discord
    'открой дискорд':          'com.discord',
    'открой discord':          'com.discord',
    'дискорд':                 'com.discord',
    // System
    'открой настройки':        'com.android.settings',
    'настройки':               'com.android.settings',
    'открой камеру':           'com.android.camera2',
    'камера':                  'com.android.camera2',
    'открой калькулятор':      'com.google.android.calculator',
    'калькулятор':             'com.google.android.calculator',
    'открой карты':            'com.google.android.apps.maps',
    'открой гугл карты':       'com.google.android.apps.maps',
    'карты':                   'com.google.android.apps.maps',
    'открой браузер':          'com.android.chrome',
    'открой хром':             'com.android.chrome',
    'открой chrome':           'com.android.chrome',
    'хром':                    'com.android.chrome',
    'открой файлы':            'com.google.android.documentsui',
    'открой почту':            'com.google.android.gm',
    'открой гмейл':            'com.google.android.gm',
    'открой gmail':            'com.google.android.gm',
    'открой часы':             'com.google.android.deskclock',
    'открой будильник':        'com.google.android.deskclock',
    'будильник':               'com.google.android.deskclock',
  };

  /// Пытаемся распознать и запустить приложение по фразе.
  /// Возвращает null если команда не распознана.
  static Future<String?> tryLaunch(String phrase) async {
    final normalized = _normalize(phrase);

    // Пользовательские команды — приоритет
    final custom = await _loadCustomCommands();
    for (final entry in custom.entries) {
      if (normalized.contains(_normalize(entry.key))) {
        return await _launch(entry.value);
      }
    }

    // Встроенные команды
    for (final entry in builtinCommands.entries) {
      if (normalized.contains(_normalize(entry.key))) {
        return await _launch(entry.value);
      }
    }

    // Умный разбор: "открой/запусти/включи [название]"
    final smartResult = await _smartParse(normalized);
    if (smartResult != null) return smartResult;

    return null;
  }

  /// Нормализация: нижний регистр + убираем лишние символы
  static String _normalize(String s) =>
      s.toLowerCase().trim()
       .replaceAll(RegExp(r'[.,!?;:]'), '')
       .replaceAll(RegExp(r'\s+'), ' ');

  /// Умный разбор: ищем ключевое слово после глагола
  static Future<String?> _smartParse(String normalized) async {
    final verbs = ['открой', 'запусти', 'включи', 'покажи', 'запусти', 'открыть'];
    for (final verb in verbs) {
      if (normalized.startsWith(verb)) {
        final rest = normalized.substring(verb.length).trim();
        if (rest.isEmpty) continue;
        // Ищем rest в builtin как ключевое слово
        for (final entry in builtinCommands.entries) {
          final key = _normalize(entry.key);
          // Убираем глагол из ключа и сравниваем
          final keyRest = key.replaceFirst(RegExp(r'^(открой|запусти|включи|покажи)\s*'), '');
          if (keyRest.isNotEmpty && rest.contains(keyRest)) {
            return await _launch(entry.value);
          }
        }
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
