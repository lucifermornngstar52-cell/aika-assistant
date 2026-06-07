/// VoiceCommandParser — офлайн парсер голосовых команд.
/// Никаких API, никакого интернета — только паттерны + регулярки.
/// 
/// Возвращает [VoiceCommand] с action, target, params.
/// Неизвестная команда → action = "unknown".

class VoiceCommand {
  final String action;
  final String? target;    // имя контакта, приложения, песни...
  final String? app;       // пакет целевого приложения
  final Map<String, String> params;
  final String rawText;

  const VoiceCommand({
    required this.action,
    required this.rawText,
    this.target,
    this.app,
    this.params = const {},
  });

  bool get isUnknown => action == 'unknown';

  @override
  String toString() => 'VoiceCommand{action=$action, target=$target, app=$app, params=$params}';
}

class VoiceCommandParser {
  static VoiceCommandParser? _instance;
  factory VoiceCommandParser() => _instance ??= VoiceCommandParser._();
  VoiceCommandParser._();

  /// Главный метод — принимает распознанный текст, возвращает команду
  VoiceCommand parse(String rawText) {
    final text = rawText.toLowerCase().trim();
    if (text.isEmpty) return VoiceCommand(action: 'unknown', rawText: rawText);

    // Порядок важен — более специфичные паттерны выше
    return _tryPhone(text, rawText)
        ?? _tryMedia(text, rawText)
        ?? _tryApp(text, rawText)
        ?? _tryBrowser(text, rawText)
        ?? _trySettings(text, rawText)
        ?? _tryMessaging(text, rawText)
        ?? _tryNavigation(text, rawText)
        ?? _tryYoutube(text, rawText)
        ?? _trySpotify(text, rawText)
        ?? _tryTelegram(text, rawText)
        ?? _tryWhatsApp(text, rawText)
        ?? _trySystem(text, rawText)
        ?? _tryGlobal(text, rawText)
        ?? VoiceCommand(action: 'unknown', rawText: rawText);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ТЕЛЕФОННЫЕ ЗВОНКИ
  // ─────────────────────────────────────────────────────────────────────────

  VoiceCommand? _tryPhone(String t, String raw) {
    // "позвони маме", "вызови пашу", "набери номер 89001234567"
    final callPat = RegExp(r'(позвони|позвать|вызови|набери|звони|call)\s+(.+)');
    final m = callPat.firstMatch(t);
    if (m != null) {
      final who = m.group(2)!.trim()
        .replaceAll(RegExp(r'\b(пожалуйста|пожалуйста|на|в|по)\b'), '')
        .trim();
      return VoiceCommand(action: 'call', target: who, rawText: raw);
    }

    // "сбрось звонок", "отклони"
    if (_matches(t, ['сбрось звонок', 'сброс', 'отклони вызов', 'отклони звонок', 'decline'])) {
      return VoiceCommand(action: 'decline_call', rawText: raw);
    }
    // "ответь", "принять вызов"
    if (_matches(t, ['ответь', 'принять вызов', 'принять', 'answer'])) {
      return VoiceCommand(action: 'answer_call', rawText: raw);
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // МЕДИА — универсальные команды (работают в любом плеере)
  // ─────────────────────────────────────────────────────────────────────────

  VoiceCommand? _tryMedia(String t, String raw) {
    if (_matches(t, ['пауза', 'стоп', 'останови музыку', 'pause', 'stop music', 'стоп музыка'])) {
      return VoiceCommand(action: 'media_pause', rawText: raw);
    }
    if (_matches(t, ['играй', 'продолжи', 'возобнови', 'play', 'resume music', 'продолжи музыку'])) {
      return VoiceCommand(action: 'media_play', rawText: raw);
    }
    if (_matches(t, ['следующая песня', 'следующий трек', 'дальше', 'next track', 'skip', 'следующее'])) {
      return VoiceCommand(action: 'media_next', rawText: raw);
    }
    if (_matches(t, ['предыдущая', 'назад трек', 'prev track', 'предыдущий трек'])) {
      return VoiceCommand(action: 'media_prev', rawText: raw);
    }

    // Громкость
    final volUp = RegExp(r'(громче|увеличь громкость|прибавь|volume up)');
    final volDn = RegExp(r'(тише|уменьши громкость|убавь|volume down)');
    final volSet = RegExp(r'(поставь|установи) громкость (?:на\s+)?(\d+)');

    if (volUp.hasMatch(t)) return VoiceCommand(action: 'volume_up', rawText: raw);
    if (volDn.hasMatch(t)) return VoiceCommand(action: 'volume_down', rawText: raw);
    final vs = volSet.firstMatch(t);
    if (vs != null) return VoiceCommand(action: 'volume_set', params: {'level': vs.group(2)!}, rawText: raw);

    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ЗАПУСК ПРИЛОЖЕНИЙ
  // ─────────────────────────────────────────────────────────────────────────

  VoiceCommand? _tryApp(String t, String raw) {
    final openPat = RegExp(r'(открой|запусти|включи|зайди в|launch|open)\s+(.+)');
    final m = openPat.firstMatch(t);
    if (m != null) {
      final appName = m.group(2)!.trim()
        .replaceAll(RegExp(r'\b(приложение|пожалуйста)\b'), '').trim();
      final pkg = _resolveAppPackage(appName);
      return VoiceCommand(action: 'open_app', target: appName, app: pkg, rawText: raw);
    }

    // "закрой", "выйди"
    if (_matches(t, ['закрой приложение', 'выйди', 'закрой', 'close app'])) {
      return VoiceCommand(action: 'close_app', rawText: raw);
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // БРАУЗЕР
  // ─────────────────────────────────────────────────────────────────────────

  VoiceCommand? _tryBrowser(String t, String raw) {
    final searchPat = RegExp(r'(найди|поищи|загугли|ищи|search for)\s+(.+)');
    final m = searchPat.firstMatch(t);
    if (m != null) {
      return VoiceCommand(action: 'web_search', target: m.group(2)!.trim(), rawText: raw);
    }

    final openUrl = RegExp(r'(открой сайт|перейди на|go to)\s+(.+)');
    final mu = openUrl.firstMatch(t);
    if (mu != null) {
      return VoiceCommand(action: 'open_url', target: mu.group(2)!.trim(), rawText: raw);
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // НАСТРОЙКИ ТЕЛЕФОНА
  // ─────────────────────────────────────────────────────────────────────────

  VoiceCommand? _trySettings(String t, String raw) {
    // WiFi
    if (_matches(t, ['включи wifi', 'включи вайфай', 'turn on wifi', 'wifi on'])) {
      return VoiceCommand(action: 'wifi_on', rawText: raw);
    }
    if (_matches(t, ['выключи wifi', 'выключи вайфай', 'turn off wifi', 'wifi off'])) {
      return VoiceCommand(action: 'wifi_off', rawText: raw);
    }
    // Bluetooth
    if (_matches(t, ['включи bluetooth', 'включи блютус', 'bluetooth on'])) {
      return VoiceCommand(action: 'bluetooth_on', rawText: raw);
    }
    if (_matches(t, ['выключи bluetooth', 'выключи блютус', 'bluetooth off'])) {
      return VoiceCommand(action: 'bluetooth_off', rawText: raw);
    }
    // Фонарик
    if (_matches(t, ['включи фонарик', 'фонарик', 'flashlight on', 'torch on'])) {
      return VoiceCommand(action: 'torch_on', rawText: raw);
    }
    if (_matches(t, ['выключи фонарик', 'torch off', 'flashlight off'])) {
      return VoiceCommand(action: 'torch_off', rawText: raw);
    }
    // Авиарежим
    if (_matches(t, ['авиарежим', 'режим полёта', 'airplane mode'])) {
      return VoiceCommand(action: 'airplane_mode_toggle', rawText: raw);
    }
    // Бесшумный режим
    if (_matches(t, ['бесшумный', 'тихий режим', 'silent mode', 'не беспокоить'])) {
      return VoiceCommand(action: 'silent_mode', rawText: raw);
    }
    // Яркость
    final brightness = RegExp(r'(установи|поставь|сделай) яркость (?:на\s+)?(\d+)');
    final mb = brightness.firstMatch(t);
    if (mb != null) return VoiceCommand(action: 'set_brightness', params: {'level': mb.group(2)!}, rawText: raw);

    if (_matches(t, ['максимальная яркость', 'ярче', 'яркость максимум'])) {
      return VoiceCommand(action: 'brightness_max', rawText: raw);
    }
    if (_matches(t, ['минимальная яркость', 'темнее', 'яркость минимум'])) {
      return VoiceCommand(action: 'brightness_min', rawText: raw);
    }
    // Блокировка
    if (_matches(t, ['заблокируй экран', 'блокировка', 'lock screen', 'заблокируй телефон'])) {
      return VoiceCommand(action: 'lock_screen', rawText: raw);
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // СООБЩЕНИЯ
  // ─────────────────────────────────────────────────────────────────────────

  VoiceCommand? _tryMessaging(String t, String raw) {
    // "напиши маше в телеграме привет"
    final msgPat = RegExp(
      r'(напиши|отправь|пошли|напишите|send)\s+(.+?)\s+(?:в\s+)?(телеграм|telegram|whatsapp|вотсап|вконтакте|вк)\s+(.+)',
    );
    final m1 = msgPat.firstMatch(t);
    if (m1 != null) {
      final contact = m1.group(2)!.trim();
      final app = m1.group(3)!.trim();
      final message = m1.group(4)!.trim();
      return VoiceCommand(
        action: 'send_message',
        target: contact,
        app: _resolveAppPackage(app),
        params: {'message': message, 'app': app},
        rawText: raw,
      );
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // НАВИГАЦИЯ В ТЕЛЕФОНЕ
  // ─────────────────────────────────────────────────────────────────────────

  VoiceCommand? _tryNavigation(String t, String raw) {
    if (_matches(t, ['домой', 'на главный', 'home', 'на главный экран'])) {
      return VoiceCommand(action: 'go_home', rawText: raw);
    }
    if (_matches(t, ['назад', 'вернись', 'back', 'go back'])) {
      return VoiceCommand(action: 'go_back', rawText: raw);
    }
    if (_matches(t, ['последние приложения', 'список приложений', 'recents', 'недавние'])) {
      return VoiceCommand(action: 'open_recents', rawText: raw);
    }
    if (_matches(t, ['шторка', 'уведомления', 'открой уведомления', 'notifications'])) {
      return VoiceCommand(action: 'open_notifications', rawText: raw);
    }
    if (_matches(t, ['быстрые настройки', 'открой панель', 'quick settings'])) {
      return VoiceCommand(action: 'open_quick_settings', rawText: raw);
    }
    // Прокрутка
    if (_matches(t, ['прокрути вверх', 'вверх', 'scroll up'])) {
      return VoiceCommand(action: 'scroll_up', rawText: raw);
    }
    if (_matches(t, ['прокрути вниз', 'вниз', 'scroll down'])) {
      return VoiceCommand(action: 'scroll_down', rawText: raw);
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // YOUTUBE — команды внутри приложения
  // ─────────────────────────────────────────────────────────────────────────

  VoiceCommand? _tryYoutube(String t, String raw) {
    if (!_isInContext(t, ['youtube', 'ютуб', 'ютубе'])) return null;

    if (_matches(t, ['лайк', 'нравится', 'like video'])) {
      return VoiceCommand(action: 'yt_like', app: 'com.google.android.youtube', rawText: raw);
    }
    if (_matches(t, ['дизлайк', 'не нравится', 'dislike'])) {
      return VoiceCommand(action: 'yt_dislike', app: 'com.google.android.youtube', rawText: raw);
    }
    if (_matches(t, ['на весь экран', 'fullscreen', 'полноэкранный'])) {
      return VoiceCommand(action: 'yt_fullscreen', app: 'com.google.android.youtube', rawText: raw);
    }
    if (_matches(t, ['подписаться', 'subscribe'])) {
      return VoiceCommand(action: 'yt_subscribe', app: 'com.google.android.youtube', rawText: raw);
    }
    if (_matches(t, ['комментарии', 'открой комментарии'])) {
      return VoiceCommand(action: 'yt_comments', app: 'com.google.android.youtube', rawText: raw);
    }

    final searchYt = RegExp(r'(?:найди|поищи|search)\s+(.+?)(?:\s+в\s+ютубе?)?$');
    final ms = searchYt.firstMatch(t);
    if (ms != null) {
      return VoiceCommand(action: 'yt_search', target: ms.group(1)!.trim(),
          app: 'com.google.android.youtube', rawText: raw);
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SPOTIFY
  // ─────────────────────────────────────────────────────────────────────────

  VoiceCommand? _trySpotify(String t, String raw) {
    if (!_isInContext(t, ['spotify', 'спотифай', 'спотифай'])) return null;

    final play = RegExp(r'(?:включи|играй|play)\s+(.+?)(?:\s+в\s+(?:spotify|спотифай))?$');
    final mp = play.firstMatch(t);
    if (mp != null) {
      return VoiceCommand(action: 'spotify_play', target: mp.group(1)!.trim(),
          app: 'com.spotify.music', rawText: raw);
    }
    if (_matches(t, ['лайк', 'в избранное', 'добавь в плейлист'])) {
      return VoiceCommand(action: 'spotify_like', app: 'com.spotify.music', rawText: raw);
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TELEGRAM
  // ─────────────────────────────────────────────────────────────────────────

  VoiceCommand? _tryTelegram(String t, String raw) {
    if (!_isInContext(t, ['телеграм', 'telegram'])) return null;

    final open = RegExp(r'(?:открой|зайди к|напиши)\s+(.+?)(?:\s+в\s+телеграм)?$');
    final mo = open.firstMatch(t);
    if (mo != null) {
      return VoiceCommand(action: 'tg_open_chat', target: mo.group(1)!.trim(),
          app: 'org.telegram.messenger', rawText: raw);
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WHATSAPP
  // ─────────────────────────────────────────────────────────────────────────

  VoiceCommand? _tryWhatsApp(String t, String raw) {
    if (!_isInContext(t, ['вотсап', 'whatsapp', 'ватсап'])) return null;

    final open = RegExp(r'(?:открой|напиши|зайди к)\s+(.+?)(?:\s+в\s+(?:вотсап|whatsapp))?$');
    final mo = open.firstMatch(t);
    if (mo != null) {
      return VoiceCommand(action: 'wa_open_chat', target: mo.group(1)!.trim(),
          app: 'com.whatsapp', rawText: raw);
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // СИСТЕМНЫЕ КОМАНДЫ
  // ─────────────────────────────────────────────────────────────────────────

  VoiceCommand? _trySystem(String t, String raw) {
    if (_matches(t, ['скриншот', 'снимок экрана', 'screenshot'])) {
      return VoiceCommand(action: 'screenshot', rawText: raw);
    }
    if (_matches(t, ['виброрежим', 'вибрация', 'vibration mode'])) {
      return VoiceCommand(action: 'vibration_mode', rawText: raw);
    }
    if (_matches(t, ['выключи телефон', 'перезагрузи', 'power off'])) {
      return VoiceCommand(action: 'power_dialog', rawText: raw);
    }
    // Будильник
    final alarm = RegExp(r'(?:поставь|установи|буди) (?:будильник )?(?:на\s+)?(\d{1,2})[:\s]?(\d{2})?');
    final ma = alarm.firstMatch(t);
    if (ma != null) {
      return VoiceCommand(action: 'set_alarm',
        params: {'hour': ma.group(1)!, 'minute': ma.group(2) ?? '00'},
        rawText: raw,
      );
    }
    // Таймер
    final timer = RegExp(r'(?:поставь|установи) таймер (?:на\s+)?(\d+)\s*(секунд|минут|час)');
    final mt = timer.firstMatch(t);
    if (mt != null) {
      return VoiceCommand(action: 'set_timer',
        params: {'amount': mt.group(1)!, 'unit': mt.group(2)!},
        rawText: raw,
      );
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ГЛОБАЛЬНЫЕ — свайпы, тапы
  // ─────────────────────────────────────────────────────────────────────────

  VoiceCommand? _tryGlobal(String t, String raw) {
    if (_matches(t, ['свайп вверх', 'смахни вверх'])) {
      return VoiceCommand(action: 'swipe', params: {'dir': 'up'}, rawText: raw);
    }
    if (_matches(t, ['свайп вниз', 'смахни вниз'])) {
      return VoiceCommand(action: 'swipe', params: {'dir': 'down'}, rawText: raw);
    }
    if (_matches(t, ['свайп влево', 'смахни влево'])) {
      return VoiceCommand(action: 'swipe', params: {'dir': 'left'}, rawText: raw);
    }
    if (_matches(t, ['свайп вправо', 'смахни вправо'])) {
      return VoiceCommand(action: 'swipe', params: {'dir': 'right'}, rawText: raw);
    }

    // "нажми на [текст]"
    final tap = RegExp(r'(?:нажми на|кликни на|tap|click)\s+(.+)');
    final mt = tap.firstMatch(t);
    if (mt != null) {
      return VoiceCommand(action: 'tap_by_text', target: mt.group(1)!.trim(), rawText: raw);
    }

    // "введи [текст]"
    final type = RegExp(r'(?:введи|напечатай|напиши|type)\s+(.+)');
    final mty = type.firstMatch(t);
    if (mty != null) {
      return VoiceCommand(action: 'type_text', target: mty.group(1)!.trim(), rawText: raw);
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  bool _matches(String text, List<String> patterns) {
    for (final p in patterns) {
      if (text.contains(p)) return true;
    }
    return false;
  }

  bool _isInContext(String text, List<String> appHints) {
    for (final h in appHints) {
      if (text.contains(h)) return true;
    }
    return false;
  }

  String? _resolveAppPackage(String name) {
    final n = name.toLowerCase();
    const map = {
      'youtube':    'com.google.android.youtube',
      'ютуб':       'com.google.android.youtube',
      'spotify':    'com.spotify.music',
      'спотифай':   'com.spotify.music',
      'telegram':   'org.telegram.messenger',
      'телеграм':   'org.telegram.messenger',
      'whatsapp':   'com.whatsapp',
      'вотсап':     'com.whatsapp',
      'вконтакте':  'com.vkontakte.android',
      'вк':         'com.vkontakte.android',
      'instagram':  'com.instagram.android',
      'инстаграм':  'com.instagram.android',
      'chrome':     'com.android.chrome',
      'хром':       'com.android.chrome',
      'maps':       'com.google.android.apps.maps',
      'карты':      'com.google.android.apps.maps',
      'gmail':      'com.google.android.gm',
      'яндекс':     'ru.yandex.searchplugin',
      'yandex':     'ru.yandex.searchplugin',
      'tiktok':     'com.zhiliaoapp.musically',
      'тикток':     'com.zhiliaoapp.musically',
      'netflix':    'com.netflix.mediaclient',
      'нетфликс':   'com.netflix.mediaclient',
      'settings':   'com.android.settings',
      'настройки':  'com.android.settings',
      'discord':    'com.discord',
      'дискорд':    'com.discord',
      'twitch':     'tv.twitch.android.app',
      'твич':       'tv.twitch.android.app',
    };
    for (final entry in map.entries) {
      if (n.contains(entry.key)) return entry.value;
    }
    return null;
  }
}
