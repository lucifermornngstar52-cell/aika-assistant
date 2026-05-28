import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Запуск приложений по голосовой команде.
/// ФИКС: добавлены префиксы "открой/запусти/включи" — теперь "открой телеграм" работает.
/// ФИКС: порядок матчинга — сначала полная фраза с префиксом, потом без.
class AppLauncherService {
  static const _prefsKey = 'custom_app_commands';
  static const _channel = MethodChannel('com.aika.assistant/launcher');

  // Префиксы команд открытия
  static const List<String> _openPrefixes = [
    'открой', 'открыть', 'запусти', 'запустить', 'включи', 'включить',
    'покажи', 'показать', 'зайди в', 'зайди на', 'перейди в', 'перейди на',
    'запусти приложение', 'открой приложение',
  ];

  // Таблица: голосовой триггер -> package name
  // Отсортировано от ДЛИННЫХ к КОРОТКИМ — чтобы "ютуб музыка" раньше "ютуб"
  static const List<MapEntry<String, String>> _orderedCommands = [
    MapEntry('ютуб музыку',             'com.google.android.apps.youtube.music'),
    MapEntry('ютуб музыка',             'com.google.android.apps.youtube.music'),
    MapEntry('youtube music',           'com.google.android.apps.youtube.music'),
    MapEntry('яндекс музыку',           'ru.yandex.music'),
    MapEntry('яндекс музыка',           'ru.yandex.music'),
    MapEntry('спотифай',                'com.spotify.music'),
    MapEntry('spotify',                 'com.spotify.music'),
    MapEntry('ютуб',                    'com.google.android.youtube'),
    MapEntry('youtube',                 'com.google.android.youtube'),
    MapEntry('тикток',                  'com.zhiliaoapp.musically'),
    MapEntry('тик ток',                 'com.zhiliaoapp.musically'),
    MapEntry('tiktok',                  'com.zhiliaoapp.musically'),
    MapEntry('телеграм',                'org.telegram.messenger'),
    MapEntry('телеграмм',               'org.telegram.messenger'),
    MapEntry('telegram',                'org.telegram.messenger'),
    MapEntry('ватсап',                  'com.whatsapp'),
    MapEntry('вацап',                   'com.whatsapp'),
    MapEntry('вотсап',                  'com.whatsapp'),
    MapEntry('воцап',                   'com.whatsapp'),
    MapEntry('whatsapp',                'com.whatsapp'),
    MapEntry('what s app',              'com.whatsapp'),
    MapEntry('uatsap',                  'com.whatsapp'),
    MapEntry('инстаграм',               'com.instagram.android'),
    MapEntry('инстаграмм',              'com.instagram.android'),
    MapEntry('инста',                   'com.instagram.android'),
    MapEntry('instagram',               'com.instagram.android'),
    MapEntry('вконтакте',               'com.vkontakte.android'),
    MapEntry('вк',                      'com.vkontakte.android'),
    MapEntry('vkontakte',               'com.vkontakte.android'),
    MapEntry('нетфликс',                'com.netflix.mediaclient'),
    MapEntry('netflix',                 'com.netflix.mediaclient'),
    MapEntry('твич',                    'tv.twitch.android.app'),
    MapEntry('twitch',                  'tv.twitch.android.app'),
    MapEntry('дискорд',                 'com.discord'),
    MapEntry('discord',                 'com.discord'),
    MapEntry('гугл карты',              'com.google.android.apps.maps'),
    MapEntry('карты',                   'com.google.android.apps.maps'),
    MapEntry('браузер',                 'com.android.chrome'),
    MapEntry('хром',                    'com.android.chrome'),
    MapEntry('chrome',                  'com.android.chrome'),
    MapEntry('почту',                   'com.google.android.gm'),
    MapEntry('почта',                   'com.google.android.gm'),
    MapEntry('gmail',                   'com.google.android.gm'),
    MapEntry('гмейл',                   'com.google.android.gm'),
    MapEntry('настройки',               'com.android.settings'),
    MapEntry('камеру',                  'com.android.camera2'),
    MapEntry('камера',                  'com.android.camera2'),
    MapEntry('калькулятор',             'com.google.android.calculator'),
    MapEntry('будильник',               'com.google.android.deskclock'),
    MapEntry('часы',                    'com.google.android.deskclock'),
    MapEntry('файлы',                   'com.google.android.documentsui'),
    MapEntry('музыку',                  'com.spotify.music'),
    MapEntry('музыка',                  'com.spotify.music'),
  ];

  static Map<String, String> get builtinCommands =>
      Map.fromEntries(_orderedCommands);

  static const _musicPackages = [
    'com.spotify.music',
    'ru.yandex.music',
    'com.google.android.apps.youtube.music',
    'com.google.android.music',
    'com.apple.android.music',
    'com.amazon.mp3',
  ];

  static Future<String?> tryLaunchFirstAvailableMusic() async {
    for (final pkg in _musicPackages) {
      try {
        final result = await _channel.invokeMethod<bool>('launchApp', {'package': pkg});
        if (result == true) {
          final name = pkg.contains('spotify') ? 'Spotify' :
                       pkg.contains('yandex')  ? 'Яндекс Музыку' :
                       pkg.contains('youtube') ? 'YouTube Music' : 'Музыку';
          return 'Открываю $name 🎵';
        }
      } catch (_) {}
    }
    return null;
  }

  /// Главная точка входа.
  /// ФИКС: strip-ает префиксы ("открой", "запусти" и т.д.) перед матчингом.
  static Future<String?> tryLaunch(String phrase) async {
    // Быстрая проверка — есть ли вообще намерение открыть что-то
    final normalized = _normalize(phrase);
    if (!_hasOpenIntent(normalized)) return null;

    // Убираем префикс для матчинга
    final stripped = _stripOpenPrefix(normalized);

    // 1. Кастомные команды — высший приоритет
    final custom = await _loadCustomCommands();
    for (final entry in custom.entries) {
      if (_matchesPhrase(stripped, _normalize(entry.key)) ||
          _matchesPhrase(normalized, _normalize(entry.key))) {
        return await _launch(entry.value);
      }
    }

    // 2. Встроенные команды
    for (final entry in _orderedCommands) {
      final key = _normalize(entry.key);
      if (_matchesPhrase(stripped, key) || _matchesPhrase(normalized, key)) {
        if (entry.value == 'com.spotify.music' &&
            (entry.key == 'музыку' || entry.key == 'музыка')) {
          final musicResult = await tryLaunchFirstAvailableMusic();
          if (musicResult != null) return musicResult;
        }
        return await _launch(entry.value);
      }
    }

    return null;
  }

  /// Проверяет что в фразе есть слово открытия
  static bool _hasOpenIntent(String text) {
    for (final prefix in _openPrefixes) {
      if (text.startsWith(prefix) || text.contains(' $prefix ')) return true;
    }
    // Прямое совпадение с названием приложения (без префикса) — тоже ок
    // если фраза короткая (≤3 слова) — скорее всего это прямая команда
    if (text.split(' ').length <= 3) return true;
    return false;
  }

  /// Убирает префикс открытия из фразы
  static String _stripOpenPrefix(String text) {
    // Сортируем по длине — длинные сначала чтобы "открой приложение" убралось раньше "открой"
    final sorted = List<String>.from(_openPrefixes)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final prefix in sorted) {
      if (text.startsWith('$prefix ')) {
        return text.substring(prefix.length).trim();
      }
    }
    return text;
  }

  /// Нормализация: нижний регистр, без пунктуации, одинарные пробелы
  static String _normalize(String s) =>
      s.toLowerCase().trim()
       .replaceAll(RegExp(r'[.,!?;:\-]'), '')
       .replaceAll(RegExp(r'\s+'), ' ');

  /// Совпадение: ключ должен присутствовать как подстрока (слово/фраза)
  static bool _matchesPhrase(String text, String key) {
    if (key.isEmpty) return false;
    final paddedText = ' $text ';
    final paddedKey  = ' $key ';
    if (!paddedText.contains(paddedKey)) return false;
    if (key.length <= 2 && text != key) return false;
    return true;
  }

  static Future<String> launchPackage(String packageName) => _launch(packageName);

  static Future<String> _launch(String packageName) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'launchApp', {'package': packageName}
      );
      if (result == true) return 'Открываю 📱';
      return 'Приложение не найдено 😔';
    } catch (_) {
      return 'Приложение не найдено 😔';
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
