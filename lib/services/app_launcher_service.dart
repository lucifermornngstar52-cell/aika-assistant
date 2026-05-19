import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AppLauncherService {
  static const _prefsKey = 'custom_app_commands';

  // Команды отсортированы от ДЛИННЫХ к КОРОТКИМ —
  // чтобы "ютуб музыка" проверялась раньше чем "ютуб"
  // и "яндекс музыку" раньше чем просто "музыку"
  static const List<MapEntry<String, String>> _orderedCommands = [
    // === YouTube Music (длиннее — проверяем первым) ===
    MapEntry('открой ютуб музыку',      'com.google.android.apps.youtube.music'),
    MapEntry('запусти ютуб музыку',     'com.google.android.apps.youtube.music'),
    MapEntry('включи ютуб музыку',      'com.google.android.apps.youtube.music'),
    MapEntry('ютуб музыка',             'com.google.android.apps.youtube.music'),
    MapEntry('youtube music',           'com.google.android.apps.youtube.music'),
    // === Yandex Music ===
    MapEntry('открой яндекс музыку',    'ru.yandex.music'),
    MapEntry('запусти яндекс музыку',   'ru.yandex.music'),
    MapEntry('включи яндекс музыку',    'ru.yandex.music'),
    MapEntry('яндекс музыка',           'ru.yandex.music'),
    MapEntry('яндекс музыку',           'ru.yandex.music'),
    // === Spotify ===
    MapEntry('открой спотифай',         'com.spotify.music'),
    MapEntry('запусти спотифай',        'com.spotify.music'),
    MapEntry('открой spotify',          'com.spotify.music'),
    MapEntry('спотифай',                'com.spotify.music'),
    MapEntry('spotify',                 'com.spotify.music'),
    // === YouTube (после YouTube Music!) ===
    MapEntry('открой ютуб',             'com.google.android.youtube'),
    MapEntry('включи ютуб',             'com.google.android.youtube'),
    MapEntry('запусти ютуб',            'com.google.android.youtube'),
    MapEntry('открой youtube',          'com.google.android.youtube'),
    MapEntry('ютуб',                    'com.google.android.youtube'),
    MapEntry('youtube',                 'com.google.android.youtube'),
    // === Музыка (общая — после всех конкретных!) ===
    MapEntry('открой музыку',           'com.spotify.music'),
    MapEntry('включи музыку',           'com.spotify.music'),
    MapEntry('запусти музыку',          'com.spotify.music'),
    // === TikTok ===
    MapEntry('открой тикток',           'com.zhiliaoapp.musically'),
    MapEntry('открой tiktok',           'com.zhiliaoapp.musically'),
    MapEntry('тикток',                  'com.zhiliaoapp.musically'),
    MapEntry('tiktok',                  'com.zhiliaoapp.musically'),
    // === Telegram ===
    MapEntry('открой телеграм',         'org.telegram.messenger'),
    MapEntry('запусти телеграм',        'org.telegram.messenger'),
    MapEntry('открой telegram',         'org.telegram.messenger'),
    MapEntry('телеграм',                'org.telegram.messenger'),
    MapEntry('telegram',                'org.telegram.messenger'),
    // === WhatsApp (вацап / ватсап / ватсап — все варианты STT) ===
    MapEntry('открой ватсап',           'com.whatsapp'),
    MapEntry('открой вацап',            'com.whatsapp'),
    MapEntry('открой whatsapp',         'com.whatsapp'),
    MapEntry('запусти ватсап',          'com.whatsapp'),
    MapEntry('запусти вацап',           'com.whatsapp'),
    MapEntry('включи ватсап',           'com.whatsapp'),
    MapEntry('ватсап',                  'com.whatsapp'),
    MapEntry('вацап',                   'com.whatsapp'),
    MapEntry('whatsapp',                'com.whatsapp'),
    // === Instagram ===
    MapEntry('открой инстаграм',        'com.instagram.android'),
    MapEntry('открой instagram',        'com.instagram.android'),
    MapEntry('инстаграм',               'com.instagram.android'),
    MapEntry('instagram',               'com.instagram.android'),
    // === VKontakte (ТОЛЬКО полные формы — "вк" слишком короткое!) ===
    MapEntry('открой вконтакте',        'com.vkontakte.android'),
    MapEntry('открой вк',               'com.vkontakte.android'),
    MapEntry('запусти вконтакте',       'com.vkontakte.android'),
    MapEntry('вконтакте',               'com.vkontakte.android'),
    // === Netflix ===
    MapEntry('открой нетфликс',         'com.netflix.mediaclient'),
    MapEntry('открой netflix',          'com.netflix.mediaclient'),
    MapEntry('нетфликс',                'com.netflix.mediaclient'),
    MapEntry('netflix',                 'com.netflix.mediaclient'),
    // === Twitch ===
    MapEntry('открой твич',             'tv.twitch.android.app'),
    MapEntry('открой twitch',           'tv.twitch.android.app'),
    MapEntry('твич',                    'tv.twitch.android.app'),
    MapEntry('twitch',                  'tv.twitch.android.app'),
    // === Discord ===
    MapEntry('открой дискорд',          'com.discord'),
    MapEntry('открой discord',          'com.discord'),
    MapEntry('дискорд',                 'com.discord'),
    MapEntry('discord',                 'com.discord'),
    // === Google Maps ===
    MapEntry('открой гугл карты',       'com.google.android.apps.maps'),
    MapEntry('открой карты',            'com.google.android.apps.maps'),
    MapEntry('гугл карты',              'com.google.android.apps.maps'),
    MapEntry('карты',                   'com.google.android.apps.maps'),
    // === Chrome ===
    MapEntry('открой браузер',          'com.android.chrome'),
    MapEntry('открой хром',             'com.android.chrome'),
    MapEntry('открой chrome',           'com.android.chrome'),
    MapEntry('хром',                    'com.android.chrome'),
    // === Gmail ===
    MapEntry('открой почту',            'com.google.android.gm'),
    MapEntry('открой гмейл',            'com.google.android.gm'),
    MapEntry('открой gmail',            'com.google.android.gm'),
    MapEntry('gmail',                   'com.google.android.gm'),
    // === Settings ===
    MapEntry('открой настройки',        'com.android.settings'),
    MapEntry('настройки',               'com.android.settings'),
    // === Camera ===
    MapEntry('открой камеру',           'com.android.camera2'),
    MapEntry('камера',                  'com.android.camera2'),
    // === Calculator ===
    MapEntry('открой калькулятор',      'com.google.android.calculator'),
    MapEntry('калькулятор',             'com.google.android.calculator'),
    // === Clock / Alarm ===
    MapEntry('открой будильник',        'com.google.android.deskclock'),
    MapEntry('открой часы',             'com.google.android.deskclock'),
    MapEntry('будильник',               'com.google.android.deskclock'),
    MapEntry('часы',                    'com.google.android.deskclock'),
    // === Files ===
    MapEntry('открой файлы',            'com.google.android.documentsui'),
  ];

  // Для совместимости с CommandsScreen
  static Map<String, String> get builtinCommands =>
      Map.fromEntries(_orderedCommands);

  /// Главный метод — разбираем фразу и запускаем приложение
  static Future<String?> tryLaunch(String phrase) async {
    final normalized = _normalize(phrase);

    // 1. Пользовательские команды — приоритет
    final custom = await _loadCustomCommands();
    for (final entry in custom.entries) {
      if (_matchesPhrase(normalized, _normalize(entry.key))) {
        return await _launch(entry.value);
      }
    }

    // 2. Встроенные — в порядке от длинных к коротким
    for (final entry in _orderedCommands) {
      if (_matchesPhrase(normalized, _normalize(entry.key))) {
        return await _launch(entry.value);
      }
    }

    return null;
  }

  /// Умное сопоставление: ключ должен быть отдельным словом/фразой,
  /// а не подстрокой внутри другого слова (например "вк" не должно
  /// триггерить на "включи").
  static bool _matchesPhrase(String text, String key) {
    if (!text.contains(key)) return false;

    // Проверяем что вокруг ключа — пробелы или начало/конец строки
    final idx = text.indexOf(key);
    final before = idx == 0 ? true : text[idx - 1] == ' ';
    final after  = (idx + key.length) >= text.length ? true
                  : text[idx + key.length] == ' ';
    return before && after;
  }

  /// Нормализация текста
  static String _normalize(String s) =>
      s.toLowerCase().trim()
       .replaceAll(RegExp(r'[.,!?;:\-]'), '')
       .replaceAll(RegExp(r'\s+'), ' ');

  // Карта явных Activity — только проверенные компоненты
  static const Map<String, String> _componentNames = {
    'org.telegram.messenger': 'org.telegram.messenger/org.telegram.ui.LaunchActivity',
    'com.discord':            'com.discord/com.discord.app.AppActivity\$Main',
  };

  static Future<String> _launch(String packageName) async {
    try {
      // Используем явный componentName только если он точно известен
      final component = _componentNames[packageName];
      if (component != null) {
        final intent = AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: packageName,
          componentName: component,
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK, Flag.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED],
        );
        await intent.launch();
        return 'Открываю';
      }
      // Для всех остальных — LAUNCHER intent без componentName (getLaunchIntentForPackage)
      final intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: packageName,
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK, Flag.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED],
        category: 'android.intent.category.LAUNCHER',
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

