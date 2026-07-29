import 'package:flutter/services.dart';
import 'dart:convert';

/// ════════════════════════════════════════════════════════════════════════════
/// AppLauncherService — единая точка запуска приложений.
/// Использует нативный PackageManager через MethodChannel.
/// Сначала ищет среди УСТАНОВЛЕННЫХ приложений, потом по хардкод-таблице.
/// ════════════════════════════════════════════════════════════════════════════
class AppLauncherService {
  static const _channel = MethodChannel('com.aika.assistant/launcher');

  // Кеш списка установленных приложений (обновляется раз в 30 сек)
  static List<Map<String, String>> _appsCache = [];
  static DateTime? _cacheTime;
  static const _cacheTimeout = Duration(seconds: 30);

  // Префиксы команд открытия
  static const List<String> openPrefixes = [
    'открой', 'открыть', 'запусти', 'запустить', 'включи', 'включить',
    'покажи', 'показать', 'зайди в', 'зайди на', 'перейди в', 'перейди на',
    'зайди', 'перейди', 'открой приложение', 'запусти приложение',
  ];

  /// Получает список всех установленных запускаемых приложений.
  static Future<List<Map<String, String>>> getInstalledApps() async {
    // Проверяем кеш
    if (_cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheTimeout &&
        _appsCache.isNotEmpty) {
      return _appsCache;
    }
    try {
      final result = await _channel.invokeMethod<List>('getInstalledApps');
      if (result == null) return _appsCache;
      _appsCache = result.map((e) {
        final map = e as Map<dynamic, dynamic>;
        return {
          'label': map['label']?.toString() ?? '',
          'package': map['package']?.toString() ?? '',
        };
      }).toList();
      _cacheTime = DateTime.now();
      return _appsCache;
    } catch (e) {
      return _appsCache;
    }
  }

  /// Запускает приложение по package name через нативный launchApp.
  static Future<bool> launchPackage(String packageName) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'launchApp', {'package': packageName},
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Умный поиск и запуск приложения по названию.
  /// Ищет среди ВСЕХ установленных приложений.
  static Future<String?> smartLaunch(String appName) async {
    final query = _normalize(appName).replaceAll(' ', '');
    if (query.isEmpty) return null;

    final apps = await getInstalledApps();
    if (apps.isEmpty) return null;

    // 1. Точное совпадение label (нормализованное)
    for (final app in apps) {
      if (_normalize(app['label']!).replaceAll(' ', '') == query) {
        if (await launchPackage(app['package']!)) {
          return 'Открываю ${app['label']} 📱';
        }
      }
    }

    // 2. Label содержит запрос
    for (final app in apps) {
      final labelNorm = _normalize(app['label']!).replaceAll(' ', '');
      if (labelNorm.contains(query) && query.length >= 3) {
        if (await launchPackage(app['package']!)) {
          return 'Открываю ${app['label']} 📱';
        }
      }
    }

    // 3. Запрос содержит label
    for (final app in apps) {
      final labelNorm = _normalize(app['label']!).replaceAll(' ', '');
      if (query.contains(labelNorm) && labelNorm.length >= 3) {
        if (await launchPackage(app['package']!)) {
          return 'Открываю ${app['label']} 📱';
        }
      }
    }

    // 4. Fuzzy: Левенштейн <= 2
    for (final app in apps) {
      final labelNorm = _normalize(app['label']!).replaceAll(' ', '');
      if (labelNorm.length >= 3 && _levenshtein(query, labelNorm) <= 2) {
        if (await launchPackage(app['package']!)) {
          return 'Открываю ${app['label']} 📱';
        }
      }
    }

    // 5. По package name
    for (final app in apps) {
      if (_normalize(app['package']!).contains(query)) {
        if (await launchPackage(app['package']!)) {
          return 'Открываю ${app['label']} 📱';
        }
      }
    }

    return null;
  }

  /// Главная точка входа. Принимает полный текст команды.
  static Future<String?> tryLaunch(String phrase) async {
    final normalized = _normalize(phrase);

    // Проверяем есть ли намерение открыть приложение
    if (!_hasOpenIntent(normalized)) return null;

    // Извлекаем название приложения
    final stripped = _stripOpenPrefix(normalized);
    if (stripped.isEmpty) return null;

    // Убираем слово "приложение" если есть
    final clean = stripped
        .replaceAll(RegExp(r'^приложение\s+'), '')
        .replaceAll(RegExp(r'\s+приложение$'), '')
        .trim();
    if (clean.isEmpty) return null;

    // ГЛАВНЫЙ ПУТЬ: ищем среди установленных приложений
    final smartResult = await smartLaunch(clean);
    if (smartResult != null) return smartResult;

    // FALLBACK: хардкод-таблица (на случай если getInstalledApps не работает)
    final pkg = _hardcodedMatch(clean);
    if (pkg != null) {
      if (await launchPackage(pkg)) {
        return 'Открываю 📱';
      }
    }

    return null;
  }

  /// Проверяет есть ли в фразе намерение открыть приложение.
  static bool _hasOpenIntent(String text) {
    for (final prefix in openPrefixes) {
      if (text.startsWith(prefix)) return true;
      if (text.contains(' $prefix ')) return true;
    }
    // Короткие фразы (<=4 слов) — возможно прямое название
    if (text.split(' ').length <= 4) return true;
    return false;
  }

  /// Убирает префикс открытия из фразы.
  static String _stripOpenPrefix(String text) {
    final sorted = List<String>.from(openPrefixes)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final prefix in sorted) {
      if (text.startsWith('$prefix ')) {
        return text.substring(prefix.length).trim();
      }
    }
    return text;
  }

  /// Хардкод-таблица для fallback.
  static String? _hardcodedMatch(String clean) {
    final q = clean.replaceAll(' ', '').toLowerCase();
    const map = {
      'ютюбмузыку': 'com.google.android.apps.youtube.music',
      'ютюбмузыка': 'com.google.android.apps.youtube.music',
      'youtubemusic': 'com.google.android.apps.youtube.music',
      'яндексмузыку': 'ru.yandex.music',
      'яндексмузыка': 'ru.yandex.music',
      'спотифай': 'com.spotify.music',
      'спотифи': 'com.spotify.music',
      'spotify': 'com.spotify.music',
      'ютуб': 'com.google.android.youtube',
      'youtube': 'com.google.android.youtube',
      'ютюб': 'com.google.android.youtube',
      'тикток': 'com.zhiliaoapp.musically',
      'тикtok': 'com.zhiliaoapp.musically',
      'tiktok': 'com.zhiliaoapp.musically',
      'телеграм': 'org.telegram.messenger',
      'телеграмм': 'org.telegram.messenger',
      'telegram': 'org.telegram.messenger',
      'тг': 'org.telegram.messenger',
      'ватсап': 'com.whatsapp',
      'вацап': 'com.whatsapp',
      'вотсап': 'com.whatsapp',
      'воцап': 'com.whatsapp',
      'whatsapp': 'com.whatsapp',
      'инстаграм': 'com.instagram.android',
      'инстаграмм': 'com.instagram.android',
      'инста': 'com.instagram.android',
      'instagram': 'com.instagram.android',
      'вконтакте': 'com.vkontakte.android',
      'вк': 'com.vkontakte.android',
      'vkontakte': 'com.vkontakte.android',
      'нетфликс': 'com.netflix.mediaclient',
      'netflix': 'com.netflix.mediaclient',
      'твич': 'tv.twitch.android.app',
      'twitch': 'tv.twitch.android.app',
      'дискорд': 'com.discord',
      'discord': 'com.discord',
      'хром': 'com.android.chrome',
      'chrome': 'com.android.chrome',
      'браузер': 'com.android.chrome',
      'почта': 'com.google.android.gm',
      'gmail': 'com.google.android.gm',
      'настройки': 'com.android.settings',
      'камера': 'com.android.camera2',
      'калькулятор': 'com.google.android.calculator',
      'часы': 'com.google.android.deskclock',
      'будильник': 'com.google.android.deskclock',
      'файлы': 'com.google.android.documentsui',
      'музыку': 'com.spotify.music',
      'музыка': 'com.spotify.music',
      'карты': 'com.google.android.apps.maps',
      'translate': 'com.google.android.apps.translate',
      'переводчик': 'com.google.android.apps.translate',
      'calendar': 'com.google.android.calendar',
      'календарь': 'com.google.android.calendar',
      'телефон': 'com.google.android.dialer',
      'звонки': 'com.google.android.dialer',
      'сообщения': 'com.google.android.apps.messaging',
      'смс': 'com.google.android.apps.messaging',
      'photos': 'com.google.android.apps.photos',
      'фото': 'com.google.android.apps.photos',
      'галерея': 'com.google.android.apps.photos',
      'playstore': 'com.android.vending',
      'маркет': 'com.android.vending',
      'shazam': 'com.shazam.android',
      'шазам': 'com.shazam.android',
      'zoom': 'us.zoom.videomeetings',
      'зум': 'us.zoom.videomeetings',
      'drive': 'com.google.android.apps.docs',
      'диск': 'com.google.android.apps.docs',
    };
    // Точное совпадение
    if (map[q] != null) return map[q];
    // Содержит
    for (final key in map.keys) {
      if (q.contains(key) && key.length >= 3) return map[key];
    }
    return null;
  }

  /// Нормализация текста.
  static String _normalize(String s) =>
      s.toLowerCase().trim()
       .replaceAll(RegExp(r'[.,!?;:\'"\-_]'), '')
       .replaceAll(RegExp(r'\s+'), ' ');

  /// Расстояние Левенштейна.
  static int _levenshtein(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;
    final matrix = List.generate(
      s1.length + 1, (i) => List.generate(s2.length + 1, (j) => 0));
    for (int i = 0; i <= s1.length; i++) matrix[i][0] = i;
    for (int j = 0; j <= s2.length; j++) matrix[0][j] = j;
    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    return matrix[s1.length][s2.length];
  }
}
