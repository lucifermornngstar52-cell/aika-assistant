import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Запуск приложений по голосовой команде.
/// Использует нативный getLaunchIntentForPackage — гарантирует
/// что откроется именно нужный пакет, а не случайная Activity.
class AppLauncherService {
  static const _prefsKey = 'custom_app_commands';
  static const _channel = MethodChannel('com.aika.assistant/launcher');

  // ── Таблица: голосовой триггер -> package name ────────────────────────────
  // Отсортировано от ДЛИННЫХ к КОРОТКИМ — чтобы "ютуб музыка" раньше "ютуб"
  static const List<MapEntry<String, String>> _orderedCommands = [
    // YouTube Music
    MapEntry('ютуб музыку',             'com.google.android.apps.youtube.music'),
    MapEntry('ютуб музыка',             'com.google.android.apps.youtube.music'),
    MapEntry('youtube music',           'com.google.android.apps.youtube.music'),
    MapEntry('яндекс музыку',           'ru.yandex.music'),
    MapEntry('яндекс музыка',           'ru.yandex.music'),
    // Spotify
    MapEntry('спотифай',                'com.spotify.music'),
    MapEntry('spotify',                 'com.spotify.music'),
    // YouTube
    MapEntry('ютуб',                    'com.google.android.youtube'),
    MapEntry('youtube',                 'com.google.android.youtube'),
    // TikTok
    MapEntry('тикток',                  'com.zhiliaoapp.musically'),
    MapEntry('тик ток',                 'com.zhiliaoapp.musically'),
    MapEntry('tiktok',                  'com.zhiliaoapp.musically'),
    // Telegram
    MapEntry('телеграм',                'org.telegram.messenger'),
    MapEntry('телеграмм',               'org.telegram.messenger'),
    MapEntry('telegram',                'org.telegram.messenger'),
    // WhatsApp — все варианты STT
    MapEntry('ватсап',                  'com.whatsapp'),
    MapEntry('вацап',                   'com.whatsapp'),
    MapEntry('вотсап',                  'com.whatsapp'),
    MapEntry('воцап',                   'com.whatsapp'),
    MapEntry('whatsapp',                'com.whatsapp'),
    MapEntry('what s app',              'com.whatsapp'),
    MapEntry('uatsap',                  'com.whatsapp'),
    // Instagram
    MapEntry('инстаграм',               'com.instagram.android'),
    MapEntry('инстаграмм',              'com.instagram.android'),
    MapEntry('инста',                   'com.instagram.android'),
    MapEntry('instagram',               'com.instagram.android'),
    // VK
    MapEntry('вконтакте',               'com.vkontakte.android'),
    MapEntry('вк',                      'com.vkontakte.android'),
    MapEntry('vkontakte',               'com.vkontakte.android'),
    // Netflix
    MapEntry('нетфликс',                'com.netflix.mediaclient'),
    MapEntry('netflix',                 'com.netflix.mediaclient'),
    // Twitch
    MapEntry('твич',                    'tv.twitch.android.app'),
    MapEntry('twitch',                  'tv.twitch.android.app'),
    // Discord
    MapEntry('дискорд',                 'com.discord'),
    MapEntry('discord',                 'com.discord'),
    // Maps
    MapEntry('гугл карты',              'com.google.android.apps.maps'),
    MapEntry('карты',                   'com.google.android.apps.maps'),
    // Chrome
    MapEntry('браузер',                 'com.android.chrome'),
    MapEntry('хром',                    'com.android.chrome'),
    MapEntry('chrome',                  'com.android.chrome'),
    // Gmail
    MapEntry('почту',                   'com.google.android.gm'),
    MapEntry('почта',                   'com.google.android.gm'),
    MapEntry('gmail',                   'com.google.android.gm'),
    MapEntry('гмейл',                   'com.google.android.gm'),
    // Settings
    MapEntry('настройки',               'com.android.settings'),
    // Camera — ТОЛЬКО с явным словом "камер"
    MapEntry('камеру',                  'com.android.camera2'),
    MapEntry('камера',                  'com.android.camera2'),
    // Calculator
    MapEntry('калькулятор',             'com.google.android.calculator'),
    // Clock
    MapEntry('будильник',               'com.google.android.deskclock'),
    MapEntry('часы',                    'com.google.android.deskclock'),
    // Files
    MapEntry('файлы',                   'com.google.android.documentsui'),
    // Музыка (общее — после всех конкретных)
    MapEntry('музыку',                  'com.spotify.music'),
    MapEntry('музыка',                  'com.spotify.music'),
  ];

  static Map<String, String> get builtinCommands =>
      Map.fromEntries(_orderedCommands);

  /// Главная точка входа — разбираем фразу и запускаем приложение
  static Future<String?> tryLaunch(String phrase) async {
    // 1. Пользовательские команды — высший приоритет
    final custom = await _loadCustomCommands();
    final normalized = _normalize(phrase);
    for (final entry in custom.entries) {
      if (_matchesPhrase(normalized, _normalize(entry.key))) {
        return await _launch(entry.value);
      }
    }

    // 2. Встроенные команды — строгое совпадение по словам
    for (final entry in _orderedCommands) {
      if (_matchesPhrase(normalized, _normalize(entry.key))) {
        return await _launch(entry.value);
      }
    }

    return null;
  }

  /// Нормализация: нижний регистр, без пунктуации, одинарные пробелы
  static String _normalize(String s) =>
      s.toLowerCase().trim()
       .replaceAll(RegExp(r'[.,!?;:\-]'), '')
       .replaceAll(RegExp(r'\s+'), ' ');

  /// Строгое совпадение: ключ должен стоять как отдельная фраза
  /// (окружён пробелами или находится в начале/конце строки).
  /// Защищает от "вк" внутри "включи" и т.п.
  static bool _matchesPhrase(String text, String key) {
    if (key.isEmpty) return false;
    // Оборачиваем пробелами для единообразия
    final paddedText = ' $text ';
    final paddedKey  = ' $key ';
    return paddedText.contains(paddedKey);
  }

  /// Запуск через нативный MethodChannel — getLaunchIntentForPackage
  /// гарантирует открытие именно этого пакета.
  static Future<String> _launch(String packageName) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'launchApp', {'package': packageName}
      );
      if (result == true) return 'Открываю 📱';
      // Нативный канал недоступен — fallback через android_intent_plus
      return await _launchFallback(packageName);
    } catch (_) {
      return await _launchFallback(packageName);
    }
  }

  static Future<String> _launchFallback(String packageName) async {
    // Нативный канал недоступен — просто сообщаем
    return 'Приложение не найдено 😔';
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
