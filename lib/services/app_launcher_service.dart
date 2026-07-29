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
    if (paddedText.contains(paddedKey)) {
      if (key.length <= 2 && text != key) return false;
      return true;
    }
    // Fuzzy: убираем все пробелы и проверяем подстроку
    // "вот сап" → "вотсап" matches key "ватсап"? Нет, но "вотсап" matches "вотсап"
    final noSpaceText = text.replaceAll(' ', '');
    final noSpaceKey  = key.replaceAll(' ', '');
    if (noSpaceKey.length >= 4 && noSpaceText.contains(noSpaceKey)) return true;
    // Levenshtein-lite: если текст очень похож на ключ (1 опечатка)
    if (noSpaceKey.length >= 5 && _levenshtein(noSpaceText, noSpaceKey) <= 2) return true;
    return false;
  }

  /// Простое расстояние Левенштейна для fuzzy matching
  static int _levenshtein(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;
    final matrix = List.generate(s1.length + 1, (i) => List.generate(s2.length + 1, (j) => 0));
    for (int i = 0; i <= s1.length; i++) matrix[i][0] = i;
    for (int j = 0; j <= s2.length; j++) matrix[0][j] = j;
    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost].reduce((a, b) => a < b ? a : b);
      }
    }
    return matrix[s1.length][s2.length];
  }

  static Future<String> launchPackage(String packageName) => _launch(packageName);

  // Карта пакет → человекочитаемое имя
  static const _pkgNames = {
    'com.whatsapp':                          'WhatsApp',
    'org.telegram.messenger':                'Телеграм',
    'com.instagram.android':                 'Инстаграм',
    'com.vkontakte.android':                 'ВКонтакте',
    'com.google.android.youtube':            'YouTube',
    'com.zhiliaoapp.musically':              'TikTok',
    'com.spotify.music':                     'Spotify',
    'ru.yandex.music':                       'Яндекс Музыку',
    'com.google.android.apps.youtube.music': 'YouTube Music',
    'com.netflix.mediaclient':               'Netflix',
    'tv.twitch.android.app':                 'Twitch',
    'com.discord':                           'Discord',
    'com.google.android.apps.maps':          'Google Карты',
    'com.android.chrome':                    'Chrome',
    'com.google.android.gm':                 'Gmail',
    'com.android.settings':                  'Настройки',
    'com.android.camera2':                   'Камеру',
    'com.google.android.calculator':         'Калькулятор',
    'com.google.android.deskclock':          'Часы',
  };

  // Умные фразы при открытии — как раньше
  static const _launchPhrases = {
    'com.whatsapp':               'Открываю WhatsApp 💬 Не забудь ответить всем 😏',
    'org.telegram.messenger':     'Открываю Телеграм 📨 Там что-то важное?',
    'com.instagram.android':      'Открываю Инстаграм 📸 Листаем ленту?',
    'com.vkontakte.android':      'Открываю ВКонтакте 🎵',
    'com.google.android.youtube': 'Открываю YouTube ▶️ Что смотришь?',
    'com.zhiliaoapp.musically':   'Открываю TikTok 🕺 Осторожно, там время исчезает!',
    'com.netflix.mediaclient':    'Открываю Netflix 🍿 Кино или сериал?',
    'tv.twitch.android.app':      'Открываю Twitch 🎮 Смотришь стримы?',
    'com.discord':                'Открываю Discord 🎧',
    'com.spotify.music':          'Открываю Spotify 🎵 Хороший выбор!',
    'ru.yandex.music':            'Открываю Яндекс Музыку 🎵',
    'com.google.android.apps.youtube.music': 'Открываю YouTube Music 🎵',
  };

  static Future<String> _launch(String packageName) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'launchApp', {'package': packageName}
      );
      if (result == true) {
        // Персонализированный ответ если есть
        if (_launchPhrases.containsKey(packageName)) {
          return _launchPhrases[packageName]!;
        }
        final name = _pkgNames[packageName] ?? 'приложение';
        return 'Открываю \$name 📱';
      }
      // Приложение не установлено
      final name = _pkgNames[packageName] ?? 'это приложение';
      return 'Не нашла \$name на телефоне 😔 Может оно не установлено?';
    } catch (_) {
      return 'Не могу открыть приложение 😔';
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
