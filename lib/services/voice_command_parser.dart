/// Полностью офлайн парсер голосовых команд v2.
/// Поддерживает 100+ паттернов, YouTube/Telegram/Instagram управление,
/// а также команды на русском/английском.
class VoiceCommand {
  final String action;
  final String? target;
  final String? app;
  final Map<String, String> params;
  const VoiceCommand({
    required this.action,
    this.target,
    this.app,
    this.params = const {},
  });
}

class VoiceCommandParser {
  static VoiceCommand? parse(String text) {
    final t = text.toLowerCase().trim();
    // ── ЗВОНКИ ─────────────────────────────────────────────────────
    if (_m(t, [r'позвони? (.+)', r'набери (.+)', r'вызови (.+)', r'call (.+)', r'звони (.+)']))
      return VoiceCommand(action: 'call', target: _cap(t, [r'позвони? (.+)', r'набери (.+)', r'вызови (.+)', r'call (.+)', r'звони (.+)']));
    if (_has(t, ['сбрось звонок', 'отклони', 'decline call']))
      return const VoiceCommand(action: 'decline_call');
    if (_has(t, ['ответь', 'принять звонок', 'answer call']))
      return const VoiceCommand(action: 'answer_call');
    if (_has(t, ['завершить звонок', 'end call', 'положи трубку']))
      return const VoiceCommand(action: 'end_call');

    // ── МЕДИА ──────────────────────────────────────────────────────
    if (_has(t, ['играй', 'воспроизведи', 'play', 'продолжи воспроизведение']))
      return const VoiceCommand(action: 'media_play');
    if (_has(t, ['пауза', 'стоп', 'останови', 'pause', 'stop']))
      return const VoiceCommand(action: 'media_pause');
    if (_has(t, ['следующий трек', 'следующая песня', 'next track', 'skip']))
      return const VoiceCommand(action: 'media_next');
    if (_has(t, ['предыдущий трек', 'назад трек', 'prev track', 'previous']))
      return const VoiceCommand(action: 'media_prev');

    // ── ГРОМКОСТЬ ───────────────────────────────────────────────────
    if (_has(t, ['громче', 'volume up', 'увеличь громкость']))
      return const VoiceCommand(action: 'volume_up');
    if (_has(t, ['тише', 'volume down', 'уменьши громкость']))
      return const VoiceCommand(action: 'volume_down');
    if (_has(t, ['без звука', 'выключи звук', 'mute', 'замолчи']))
      return const VoiceCommand(action: 'volume_mute');
    final volMatch = RegExp(r'громкость\s+(\d+)|volume\s+(\d+)').firstMatch(t);
    if (volMatch != null) {
      final level = volMatch.group(1) ?? volMatch.group(2) ?? '50';
      return VoiceCommand(action: 'volume_set', params: {'level': level});
    }

    // ── YOUTUBE ─────────────────────────────────────────────────────
    if (_has(t, ['лайкни видео', 'лайк видео', 'like this video', 'лайкни ролик']))
      return const VoiceCommand(action: 'youtube_like');
    if (_has(t, ['дизлайк', 'dislike']))
      return const VoiceCommand(action: 'youtube_dislike');
    if (_has(t, ['подписаться', 'subscribe']))
      return const VoiceCommand(action: 'youtube_subscribe');
    if (_has(t, ['пауза ютуб', 'youtube pause', 'останови ютуб', 'youtube stop']))
      return const VoiceCommand(action: 'youtube_pause');
    if (_has(t, ['воспроизведи ютуб', 'youtube play', 'ютуб играй']))
      return const VoiceCommand(action: 'youtube_play');
    if (_has(t, ['следующее видео', 'next video']))
      return const VoiceCommand(action: 'youtube_next');
    if (_has(t, ['предыдущее видео', 'prev video']))
      return const VoiceCommand(action: 'youtube_prev');
    if (_has(t, ['полный экран', 'fullscreen', 'фуллскрин']))
      return const VoiceCommand(action: 'youtube_fullscreen');
    if (_has(t, ['ускорь видео', 'скорость 1.5', 'speed up']))
      return const VoiceCommand(action: 'youtube_speed_up');
    if (_has(t, ['замедли видео', 'скорость 0.75', 'slow down']))
      return const VoiceCommand(action: 'youtube_speed_down');
    if (_has(t, ['перемотай вперёд', 'skip forward', 'вперёд 10']))
      return const VoiceCommand(action: 'youtube_skip');
    if (_has(t, ['перемотай назад', 'skip back', 'назад 10']))
      return const VoiceCommand(action: 'youtube_rewind');
    if (_has(t, ['комментарии', 'открой комменты', 'comments']))
      return const VoiceCommand(action: 'youtube_comments');
    final ytSearch = _cap(t, [r'найди на ютубе (.+)', r'ютуб найди (.+)', r'youtube search (.+)', r'ищи на ютубе (.+)']);
    if (ytSearch != null)
      return VoiceCommand(action: 'youtube_search', target: ytSearch);

    // ── TELEGRAM ────────────────────────────────────────────────────
    final tgChat = _cap(t, [r'открой чат (.+)', r'телеграм чат (.+)', r'telegram chat (.+)', r'напиши (.+) в телеграм']);
    if (tgChat != null)
      return VoiceCommand(action: 'telegram_open_chat', target: tgChat);
    if (_has(t, ['найди в телеграм', 'telegram search', 'поиск телеграм'])) {
      final q = _cap(t, [r'найди в телеграм (.+)', r'telegram search (.+)']);
      return VoiceCommand(action: 'telegram_search', target: q);
    }
    if (_has(t, ['новое сообщение телеграм', 'telegram new message']))
      return const VoiceCommand(action: 'telegram_new_message');

    // ── INSTAGRAM ───────────────────────────────────────────────────
    if (_has(t, ['лайкни пост', 'лайк пост', 'instagram like', 'два тапа']))
      return const VoiceCommand(action: 'instagram_like');
    if (_has(t, ['следующий пост', 'next post', 'instagram next']))
      return const VoiceCommand(action: 'instagram_next');
    if (_has(t, ['следующая история', 'next story', 'история следующая']))
      return const VoiceCommand(action: 'instagram_story_next');
    if (_has(t, ['комментарий инстаграм', 'instagram comment']))
      return const VoiceCommand(action: 'instagram_comment');

    // ── МУЗЫКА ──────────────────────────────────────────────────────
    if (_has(t, ['лайкни песню', 'лайк трек', 'like song', 'music like']))
      return const VoiceCommand(action: 'music_like');
    if (_has(t, ['перемешать', 'shuffle', 'рандом']))
      return const VoiceCommand(action: 'music_shuffle');
    if (_has(t, ['повторять трек', 'repeat', 'повтор']))
      return const VoiceCommand(action: 'music_repeat');

    // ── ОТКРЫТЬ ПРИЛОЖЕНИЕ ──────────────────────────────────────────
    final openApp = _cap(t, [
      r'открой (.+)', r'запусти (.+)', r'открыть (.+)', r'open (.+)', r'launch (.+)',
      r'зайди в (.+)', r'включи (.+)',
    ]);
    if (openApp != null && !_shouldIgnore(openApp))
      return VoiceCommand(action: 'open_app', target: openApp, app: _normalizeApp(openApp));
    if (_has(t, ['закрой', 'закрыть', 'close app']))
      return const VoiceCommand(action: 'close_app');
    if (_has(t, ['переключить приложение', 'недавние', 'recents', 'последние приложения']))
      return const VoiceCommand(action: 'switch_app');

    // ── БРАУЗЕР ─────────────────────────────────────────────────────
    final search = _cap(t, [r'найди (.+)', r'поищи (.+)', r'search (.+)', r'загугли (.+)', r'google (.+)']);
    if (search != null)
      return VoiceCommand(action: 'web_search', target: search);
    final urlMatch = RegExp(r'открой сайт (.+)|open site (.+)|open url (.+)').firstMatch(t);
    if (urlMatch != null) {
      final url = urlMatch.group(1) ?? urlMatch.group(2) ?? urlMatch.group(3) ?? '';
      return VoiceCommand(action: 'open_url', target: url);
    }

    // ── НАВИГАЦИЯ ───────────────────────────────────────────────────
    if (_has(t, ['назад', 'вернись', 'go back', 'back']))
      return const VoiceCommand(action: 'nav_back');
    if (_has(t, ['домой', 'на главный', 'home', 'go home']))
      return const VoiceCommand(action: 'nav_home');
    if (_has(t, ['листай вниз', 'прокрути вниз', 'scroll down', 'вниз']))
      return const VoiceCommand(action: 'scroll_down');
    if (_has(t, ['листай вверх', 'прокрути вверх', 'scroll up', 'вверх']))
      return const VoiceCommand(action: 'scroll_up');
    if (_has(t, ['листай влево', 'свайп влево', 'swipe left']))
      return const VoiceCommand(action: 'swipe_left');
    if (_has(t, ['листай вправо', 'свайп вправо', 'swipe right']))
      return const VoiceCommand(action: 'swipe_right');

    // ── ФОНАРИК ─────────────────────────────────────────────────────
    if (_has(t, ['включи фонарик', 'torch on', 'flashlight on', 'фонарь включи']))
      return const VoiceCommand(action: 'torch_on');
    if (_has(t, ['выключи фонарик', 'torch off', 'flashlight off', 'фонарь выключи']))
      return const VoiceCommand(action: 'torch_off');

    // ── СКРИНШОТ ────────────────────────────────────────────────────
    if (_has(t, ['скриншот', 'снимок экрана', 'screenshot', 'сделай скрин']))
      return const VoiceCommand(action: 'take_screenshot');

    // ── УВЕДОМЛЕНИЯ ─────────────────────────────────────────────────
    if (_has(t, ['открой уведомления', 'notifications', 'шторка', 'уведомления']))
      return const VoiceCommand(action: 'open_notifications');
    if (_has(t, ['быстрые настройки', 'quick settings', 'шторка настройки']))
      return const VoiceCommand(action: 'open_quick_settings');

    // ── СИСТЕМНЫЕ ───────────────────────────────────────────────────
    if (_has(t, ['заблокируй', 'lock screen', 'заблокировать экран']))
      return const VoiceCommand(action: 'lock_screen');
    if (_has(t, ['ярче', 'brightness up', 'увеличь яркость']))
      return const VoiceCommand(action: 'brightness_up');
    if (_has(t, ['темнее', 'brightness down', 'уменьши яркость']))
      return const VoiceCommand(action: 'brightness_down');
    if (_has(t, ['настройки wifi', 'wi-fi настройки', 'wifi settings']))
      return const VoiceCommand(action: 'open_wifi');
    if (_has(t, ['настройки bluetooth', 'bluetooth settings']))
      return const VoiceCommand(action: 'open_bluetooth');
    if (_has(t, ['настройки', 'settings', 'параметры']))
      return const VoiceCommand(action: 'open_settings');

    // ── КЛИКНУТЬ ПО ТЕКСТУ ──────────────────────────────────────────
    final clickText = _cap(t, [r'нажми на (.+)', r'кликни (.+)', r'click (.+)', r'tap (.+)']);
    if (clickText != null)
      return VoiceCommand(action: 'click_text', target: clickText);
    final typeText = _cap(t, [r'напечатай (.+)', r'введи текст (.+)', r'type (.+)', r'напиши (.+)']);
    if (typeText != null)
      return VoiceCommand(action: 'type_text', target: typeText);

    return null;
  }

  // ── Helpers ─────────────────────────────────────────────────────────
  static bool _has(String t, List<String> kw) => kw.any((k) => t.contains(k));

  static bool _m(String t, List<String> patterns) =>
      patterns.any((p) => RegExp(p).hasMatch(t));

  static String? _cap(String t, List<String> patterns) {
    for (final p in patterns) {
      final m = RegExp(p).firstMatch(t);
      if (m != null && m.groupCount >= 1) return m.group(1)?.trim();
    }
    return null;
  }

  static bool _shouldIgnore(String app) {
    const ignore = ['youtube', 'telegram', 'instagram', 'spotify', 'vk',
      'whatsapp', 'tiktok', 'maps', 'chrome', 'settings', 'camera'];
    return ignore.any((k) => app.contains(k));
  }

  static String _normalizeApp(String app) {
    const map = {
      'ютуб': 'youtube', 'ютубе': 'youtube', 'youtube': 'youtube',
      'телеграм': 'telegram', 'telegram': 'telegram',
      'инстаграм': 'instagram', 'instagram': 'instagram',
      'вк': 'vk', 'vkontakte': 'vk',
      'вотсап': 'whatsapp', 'whatsapp': 'whatsapp',
      'тикток': 'tiktok', 'tiktok': 'tiktok',
      'спотифай': 'spotify', 'spotify': 'spotify',
      'хром': 'chrome', 'chrome': 'chrome',
      'карты': 'maps', 'maps': 'maps',
      'камера': 'camera', 'camera': 'camera',
      'калькулятор': 'calculator',
      'настройки': 'settings', 'settings': 'settings',
      'яндекс': 'yandex',
      'контакты': 'contacts',
      'телефон': 'phone',
      'сообщения': 'messages',
      'почта': 'gmail', 'gmail': 'gmail',
    };
    for (final e in map.entries) {
      if (app.contains(e.key)) return e.value;
    }
    return app;
  }
}
