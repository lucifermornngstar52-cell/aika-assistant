import 'package:flutter/services.dart';

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// ════════════════════════════════════════════════════════════════════════════
/// AppLauncherService v2 — полностью переработанная система запуска.
/// 
/// Стратегия:
///   1. Сначала проверяем хардкод-таблицу (самая надёжная)
///   2. Потом ищем среди установленных приложений (smart matching)
///   3. Пробуем прямой запуск по package name (last resort)
/// ════════════════════════════════════════════════════════════════════════════
class AppLauncherService {
  static const _channel = MethodChannel('com.aika.assistant/launcher');

  // Кеш списка установленных приложений
  static List<Map<String, String>> _appsCache = [];
  static DateTime? _cacheTime;
  static const _cacheTimeout = Duration(minutes: 5);

  /// Префиксы команд открытия
  static const List<String> openPrefixes = [
    'открой', 'открыть', 'запусти', 'запустить', 'включи', 'включить',
    'покажи', 'показать', 'зайди в', 'зайди на', 'перейди в', 'перейди на',
    'зайди', 'перейди', 'открой приложение', 'запусти приложение',
    'go to', 'open', 'launch', 'start',
  ];

  /// Получает список всех установленных запускаемых приложений.
  static Future<List<Map<String, String>>> getInstalledApps() async {
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
    } catch (e) {
      return false;
    }
  }

  /// Проверяет, установлено ли приложение.
  static Future<bool> isInstalled(String packageName) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isInstalled', {'package': packageName},
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ГЛАВНАЯ ТОЧКА ВХОДА
  // ═══════════════════════════════════════════════════════════════════

  /// Главная точка входа. Принимает полный текст команды.
  /// Возвращает строку-результат или null если не смогла запустить.
  static Future<String?> tryLaunch(String phrase) async {
    final normalized = _normalize(phrase);

    // Проверяем есть ли намерение открыть приложение
    if (!_hasOpenIntent(normalized)) return null;

    // Извлекаем название приложения
    final stripped = _stripOpenPrefix(normalized);
    if (stripped.isEmpty) return null;

    // Убираем слово "приложение" если есть
    String clean = stripped
        .replaceAll(RegExp(r'^приложение\s+'), '')
        .replaceAll(RegExp(r'\s+приложение$'), '')
        .replaceAll(RegExp(r'^app\s+'), '')
        .replaceAll(RegExp(r'\s+app$'), '')
        .trim();
    if (clean.isEmpty) return null;

    // ── ПУТЬ 1: Хардкод-таблица (самая надёжная) ──
    final pkg = _hardcodedMatch(clean);
    if (pkg != null) {
      if (await launchPackage(pkg)) {
        return 'Открываю 📱';
      }
    }

    // ── ПУТЬ 2: Smart matching среди установленных ──
    final smartResult = await smartLaunch(clean);
    if (smartResult != null) return smartResult;

    // ── ПУТЬ 3: Пробуем как package name напрямую ──
    if (clean.contains('.')) {
      if (await launchPackage(clean)) {
        return 'Открываю 📱';
      }
    }

    return null;
  }

  /// Умный поиск и запуск приложения по названию.
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

  // ═══════════════════════════════════════════════════════════════════
  //  INTENT DETECTION
  // ═══════════════════════════════════════════════════════════════════

  /// Публично: есть ли в фразе намерение открыть приложение.
  static bool hasOpenIntent(String text) => _hasOpenIntent(_normalize(text));

  /// Публично: какое приложение пользователь просил открыть (для честного ответа).
  static String? extractAppName(String phrase) {
    final normalized = _normalize(phrase);
    final stripped = _stripOpenPrefix(normalized);
    if (stripped.isEmpty) return null;
    final clean = stripped
        .replaceAll(RegExp(r'^приложение\s+'), '')
        .replaceAll(RegExp(r'\s+приложение$'), '')
        .replaceAll(RegExp(r'^app\s+'), '')
        .replaceAll(RegExp(r'\s+app$'), '')
        .trim();
    return clean.isEmpty ? null : clean;
  }

  /// Проверяет есть ли в фразе намерение открыть приложение.
  static bool _hasOpenIntent(String text) {
    for (final prefix in openPrefixes) {
      if (text.startsWith(prefix)) return true;
      if (text.contains(' $prefix ')) return true;
    }
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

  // ═══════════════════════════════════════════════════════════════════
  //  HARDCODED APP TABLE
  // ═══════════════════════════════════════════════════════════════════

  /// Хардкод-таблица для надёжного запуска.
  static String? _hardcodedMatch(String clean) {
    final q = _normalize(clean).replaceAll(' ', '');
    const map = {
      // ── Мессенджеры ──
      'телеграм': 'org.telegram.messenger',
      'телеграмм': 'org.telegram.messenger',
      'telegram': 'org.telegram.messenger',
      'тг': 'org.telegram.messenger',
      'tg': 'org.telegram.messenger',
      'ватсап': 'com.whatsapp',
      'вацап': 'com.whatsapp',
      'вотсап': 'com.whatsapp',
      'воцап': 'com.whatsapp',
      'whatsapp': 'com.whatsapp',
      'вапсап': 'com.whatsapp',
      'инстаграм': 'com.instagram.android',
      'инстаграмм': 'com.instagram.android',
      'инста': 'com.instagram.android',
      'instagram': 'com.instagram.android',
      'вконтакте': 'com.vkontakte.android',
      'вк': 'com.vkontakte.android',
      'vkontakte': 'com.vkontakte.android',
      'vk': 'com.vkontakte.android',
      'дискорд': 'com.discord',
      'discord': 'com.discord',
      'скайп': 'com.skype.raider',
      'skype': 'com.skype.raider',
      'снапчат': 'com.snapchat.android',
      'snapchat': 'com.snapchat.android',
      'вайбер': 'com.viber.voip',
      'viber': 'com.viber.voip',
      'сигнал': 'org.thoughtcrime.securesms',
      'signal': 'org.thoughtcrime.securesms',
      // ── Видео ──
      'ютуб': 'com.google.android.youtube',
      'youtube': 'com.google.android.youtube',
      'ютюб': 'com.google.android.youtube',
      'ютубмузыку': 'com.google.android.apps.youtube.music',
      'ютубмузыка': 'com.google.android.apps.youtube.music',
      'ютубмузык': 'com.google.android.apps.youtube.music',
      'youtubemusic': 'com.google.android.apps.youtube.music',
      'твич': 'tv.twitch.android.app',
      'twitch': 'tv.twitch.android.app',
      'нетфликс': 'com.netflix.mediaclient',
      'netflix': 'com.netflix.mediaclient',
      'кинотеатр': 'com.amazon.avod.thirdpartyclient',
      'primevideo': 'com.amazon.avod.thirdpartyclient',
      'iviru': 'ru.rt.video.app',
      'киви': 'ru.rt.video.app',
      // ── Соцсети ──
      'тикток': 'com.zhiliaoapp.musically',
      'тикtok': 'com.zhiliaoapp.musically',
      'tiktok': 'com.zhiliaoapp.musically',
      'реддит': 'com.reddit.frontpage',
      'reddit': 'com.reddit.frontpage',
      'pinterest': 'com.pinterest',
      'пинтерест': 'com.pinterest',
      'linkedin': 'com.linkedin.android',
      'линкедин': 'com.linkedin.android',
      // ── Музыка ──
      'спотифай': 'com.spotify.music',
      'спотифи': 'com.spotify.music',
      'spotify': 'com.spotify.music',
      'яндексмузыку': 'ru.yandex.music',
      'яндексмузыка': 'ru.yandex.music',
      'музыку': 'com.spotify.music',
      'музыка': 'com.spotify.music',
      'звук': 'com.zvuk',
      'зук': 'com.zvuk',
      // ── Браузеры ──
      'хром': 'com.android.chrome',
      'chrome': 'com.android.chrome',
      'браузер': 'com.android.chrome',
      'яндексбраузер': 'com.yandex.browser',
      'оперу': 'com.opera.browser',
      'opera': 'com.opera.browser',
      'firefox': 'org.mozilla.firefox',
      'фаерфокс': 'org.mozilla.firefox',
      // ── Почта ──
      'почта': 'com.google.android.gm',
      'gmail': 'com.google.android.gm',
      'яндекспочту': 'ru.yandex.mail',
      'яндекспочта': 'ru.yandex.mail',
      // ── Системные ──
      'настройки': 'com.android.settings',
      'камера': 'com.android.camera2',
      'калькулятор': 'com.google.android.calculator',
      'часы': 'com.google.android.deskclock',
      'будильник': 'com.google.android.deskclock',
      'файлы': 'com.google.android.documentsui',
      'проводник': 'com.google.android.documentsui',
      'календарь': 'com.google.android.calendar',
      'calendar': 'com.google.android.calendar',
      'телефон': 'com.google.android.dialer',
      'звонки': 'com.google.android.dialer',
      'сообщения': 'com.google.android.apps.messaging',
      'смс': 'com.google.android.apps.messaging',
      'контакты': 'com.android.contacts',
      // ── Фото/Видео ──
      'фото': 'com.google.android.apps.photos',
      'галерея': 'com.google.android.apps.photos',
      'photos': 'com.google.android.apps.photos',
      // ── Игры ──
      'майнкрафт': 'com.mojang.minecraftpe',
      'minecraft': 'com.mojang.minecraftpe',
      'pubg': 'com.tencent.ig',
      'пабг': 'com.tencent.ig',
      'genshin': 'com.miHoYo.GenshinImpact',
      'генсин': 'com.miHoYo.GenshinImpact',
      'бравлстарс': 'com.supercell.brawlstars',
      'brawlstars': 'com.supercell.brawlstars',
      'бравл': 'com.supercell.brawlstars',
      // ── Прочее ──
      'playmarket': 'com.android.vending',
      'маркет': 'com.android.vending',
      'playstore': 'com.android.vending',
      'shazam': 'com.shazam.android',
      'шазам': 'com.shazam.android',
      'zoom': 'us.zoom.videomeetings',
      'зум': 'us.zoom.videomeetings',
      'drive': 'com.google.android.apps.docs',
      'диск': 'com.google.android.apps.docs',
      'гуглдиск': 'com.google.android.apps.docs',
      'карты': 'com.google.android.apps.maps',
      'maps': 'com.google.android.apps.maps',
      'яндекскарты': 'ru.yandex.yandexmaps',
      'translate': 'com.google.android.apps.translate',
      'переводчик': 'com.google.android.apps.translate',
      'яндекс': 'ru.yandex.searchapp',
      'яндекстакси': 'ru.yandex.taxi',
      'такси': 'ru.yandex.taxi',
      'ozon': 'ru.ozon.app',
      'озон': 'ru.ozon.app',
      'wildberries': 'com.wildberries.ru',
      'вилдберриз': 'com.wildberries.ru',
      'алиэкспресс': 'com.alibaba.aliexpresshd',
      'aliexpress': 'com.alibaba.aliexpresshd',

      // ── Расширение базы (сентябрь 2026): топ приложений KZ/RU/мир ──
      // ── Банки и платёжки KZ ──
      'каспи': 'kz.kaspi.mobile',
      'каспий': 'kz.kaspi.mobile',
      'kaspi': 'kz.kaspi.mobile',
      // ── Карты и навигация ──
      '2гис': 'ru.dublgis.jgo',
      '2gis': 'ru.dublgis.jgo',
      'гис': 'ru.dublgis.jgo',
      'двагис': 'ru.dublgis.jgo',
      'гуглкарты': 'com.google.android.apps.maps',
      'гуглкарта': 'com.google.android.apps.maps',
      'карта': 'com.google.android.apps.maps',
      'яндекскарта': 'ru.yandex.yandexmaps',
      'waze': 'com.waze',
      'виз': 'com.waze',
      // ── Яндекс ──
      'алиса': 'com.yandex.searchclient',
      'яндексдиск': 'ru.yandex.disk',
      'яндекспереводчик': 'ru.yandex.translator',
      'перевод': 'com.google.android.apps.translate',
      // ── Google ──
      'плеймаркет': 'com.android.vending',
      'плей маркет': 'com.android.vending',
      'play store': 'com.android.vending',
      'гуглплей': 'com.android.vending',
      'гуглфото': 'com.google.android.apps.photos',
      'гуглдрайв': 'com.google.android.apps.docs',
      'драйв': 'com.google.android.apps.docs',
      'гуглдокументы': 'com.google.android.apps.docs.editors.docs',
      'документы': 'com.google.android.apps.docs.editors.docs',
      'таблицы': 'com.google.android.apps.docs.editors.sheets',
      'презентации': 'com.google.android.apps.editors.slides',
      'keep': 'com.google.android.keep',
      'заметки': 'com.google.android.keep',
      'ютубстудия': 'com.google.android.apps.youtube.creator',
      // ── Microsoft / офис ──
      'word': 'com.microsoft.office.word',
      'ворд': 'com.microsoft.office.word',
      'excel': 'com.microsoft.office.excel',
      'эксель': 'com.microsoft.office.excel',
      'powerpoint': 'com.microsoft.office.powerpoint',
      'outlook': 'com.microsoft.office.outlook',
      'аутлук': 'com.microsoft.office.outlook',
      'teams': 'com.microsoft.teams',
      'тимс': 'com.microsoft.teams',
      // ── Мессенджеры доп. ──
      'имо': 'com.imo.android.imoim',
      'imo': 'com.imo.android.imoim',
      'телеграмх': 'org.thunderdog.challegram',
      'ватсапбизнес': 'com.whatsapp.w4b',
      'threema': 'ch.threema.app',
      // ── Игры ──
      'бравл старс': 'com.supercell.brawlstars',
      'brawl stars': 'com.supercell.brawlstars',
      'стендофф': 'com.axlebolt.standoff2',
      'стендофф2': 'com.axlebolt.standoff2',
      'standoff': 'com.axlebolt.standoff2',
      'роблокс': 'com.roblox.client',
      'roblox': 'com.roblox.client',
      'геншин': 'com.miHoYo.GenshinImpact',
      'геншинимпакт': 'com.miHoYo.GenshinImpact',
      'фрифайер': 'com.dts.freefireth',
      'free fire': 'com.dts.freefireth',
      'клэшрояль': 'com.supercell.clashroyale',
      'клэш рояль': 'com.supercell.clashroyale',
      'клешофкланс': 'com.supercell.clashofclans',
      'амонгас': 'com.innersloth.amongUs',
      'сабвейсерф': 'com.kiloo.subwaysurfers',
      // ── Разное ──
      'стим': 'com.valvesoftware.android.steam.community',
      'steam': 'com.valvesoftware.android.steam.community',
      'github': 'com.github.android',
      'гитхаб': 'com.github.android',
      'xbox': 'com.microsoft.xboxone.smartglass',
      'эксбокс': 'com.microsoft.xboxone.smartglass',
      'airbnb': 'com.airbnb.android',
      'whatsappbusiness': 'com.whatsapp.w4b',
      // ── Расширение 2 (сентябрь 2026) ──
      'chatgpt': 'com.openai.chatgpt',
      'чатгпт': 'com.openai.chatgpt',
      'гпт': 'com.openai.chatgpt',
      'авито': 'com.avito.android',
      'avito': 'com.avito.android',
      'тинькофф': 'ru.tinkoff.mobilebank',
      'тилькофф': 'ru.tinkoff.mobilebank',
      'тбанк': 'ru.tinkoff.mobilebank',
      'сбербанк': 'ru.sberbankmobile',
      'сбер': 'ru.sberbankmobile',
      'альфабанк': 'ru.alfabank.mobilebank',
      'альфа': 'ru.alfabank.mobilebank',
      'втб': 'ru.vtb24.mobilebank3',
      'халык': 'kz.halyk.mobile',
      'halyk': 'kz.halyk.mobile',
      'жусан': 'kz.jusanbank.mobile',
      'jusan': 'kz.jusanbank.mobile',
      'билайн': 'ru.beeline',
      'beeline': 'ru.beeline',
      'егов': 'kz.egov.mobile',
      'egov': 'kz.egov.mobile',
      'яндексго': 'ru.yandex.yango',
      'yandexport': 'ru.yandex.yango',
      'дзен': 'ru.yandex.zen',
      'юзенд': 'ru.yandex.zen',
      'кинопоиск': 'ru.kinopoisk',
      'мегого': 'com.megogo.net.app',
    };
    
    // Точное совпадение
    if (map[q] != null) return map[q];
    // Содержит (для фраз типа "открой ютуб музыку")
    for (final key in map.keys) {
      if (q.contains(key) && key.length >= 3) return map[key]!;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CUSTOM COMMANDS (backward compat for UI)
  // ═══════════════════════════════════════════════════════════════════

  static const _prefsKey = 'custom_app_commands';
  
  static Map<String, String> get builtinCommands => _builtinMap;
  
  static const Map<String, String> _builtinMap = {
    'ютуб музыку': 'com.google.android.apps.youtube.music',
    'спотифай': 'com.spotify.music',
    'телеграм': 'org.telegram.messenger',
    'ватсап': 'com.whatsapp',
    'инстаграм': 'com.instagram.android',
    'вк': 'com.vkontakte.android',
    'твич': 'tv.twitch.android.app',
    'дискорд': 'com.discord',
    'нетфликс': 'com.netflix.mediaclient',
    'карты': 'com.google.android.apps.maps',
    'браузер': 'com.android.chrome',
    'почта': 'com.google.android.gm',
    'настройки': 'com.android.settings',
    'камера': 'com.android.camera2',
    'калькулятор': 'com.google.android.calculator',
    'часы': 'com.google.android.deskclock',
  };

  static Future<Map<String, String>> getCustomCommands() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveCustomCommand(String phrase, String packageName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final commands = await getCustomCommands();
      commands[phrase] = packageName;
      prefs.setString(_prefsKey, jsonEncode(commands));
    } catch (_) {}
  }

  static Future<void> deleteCustomCommand(String phrase) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final commands = await getCustomCommands();
      commands.remove(phrase);
      prefs.setString(_prefsKey, jsonEncode(commands));
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════
  //  UTILITIES
  // ═══════════════════════════════════════════════════════════════════

  /// Нормализация: lowercase, убираем пунктуацию, ё→е.
  static String _normalize(String s) =>
      s.toLowerCase().trim()
       .replaceAll('ё', 'е')
       .replaceAll(RegExp(r'[.,!?;:\-_]'), '')
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

  // ── Aliases for commands_screen.dart ─────────────────────────────────
  static Future<Map<String, String>> getAllCommands() async => await getCustomCommands();
  static Future<void> addCommand(String phrase, String packageName) async => await saveCustomCommand(phrase, packageName);
  static Future<void> removeCommand(String phrase) async => await deleteCustomCommand(phrase);

}