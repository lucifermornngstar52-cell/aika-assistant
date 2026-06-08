import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:torch_light/torch_light.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';
import 'voice_command_parser.dart';
import 'personality_service.dart';

/// VoiceCommandExecutor v2 — глубокое управление приложениями через Accessibility.
/// Работает полностью офлайн. Поддерживает YouTube, Telegram, Instagram, браузер и др.
class VoiceCommandExecutor {
  static VoiceCommandExecutor? _instance;
  factory VoiceCommandExecutor() => _instance ??= VoiceCommandExecutor._();
  VoiceCommandExecutor._();

  static const _acc      = MethodChannel('com.aika.assistant/screen');
  static const _launcher = MethodChannel('com.aika.assistant/launcher');
  static const _media    = MethodChannel('com.aika.assistant/media');
  static const _msng     = MethodChannel('com.aika.assistant/messenger');
  static const _audio    = MethodChannel('aika/audio');

  // ════════════════════════════════════════════════════════════════════
  // ПУБЛИЧНЫЙ API
  // ════════════════════════════════════════════════════════════════════
  Future<String> execute(VoiceCommand cmd) async {
    debugPrint('[Executor] ${cmd.action} | target=${cmd.target} | app=${cmd.app}');
    try {
      return await _dispatch(cmd);
    } catch (e) {
      debugPrint('[Executor] error: $e');
      return _reply('Не удалось выполнить команду');
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // ДИСПЕТЧЕР
  // ════════════════════════════════════════════════════════════════════
  Future<String> _dispatch(VoiceCommand cmd) async {
    switch (cmd.action) {

      // ── ЗВОНКИ ─────────────────────────────────────────────────────
      case 'call':          return _makeCall(cmd.target ?? '');
      case 'decline_call':
        await _acc.invokeMethod('pressBack');
        return _reply('Звонок сброшен');
      case 'answer_call':
        await _acc.invokeMethod('clickByText', {'text': 'Ответить'});
        return _reply('Отвечаю');
      case 'end_call':
        await _acc.invokeMethod('clickByText', {'text': 'Завершить'});
        return _reply('Звонок завершён');

      // ── МЕДИА ──────────────────────────────────────────────────────
      case 'media_play':   await _media.invokeMethod('play');    return _reply('Воспроизвожу');
      case 'media_pause':  await _media.invokeMethod('pause');   return _reply('Пауза');
      case 'media_next':   await _media.invokeMethod('next');    return _reply('Следующий трек');
      case 'media_prev':   await _media.invokeMethod('prev');    return _reply('Предыдущий трек');

      // ── ГРОМКОСТЬ ──────────────────────────────────────────────────
      case 'volume_up':
        await _acc.invokeMethod('changeVolume', {'direction': 'up', 'steps': 2});
        return _reply('Громче');
      case 'volume_down':
        await _acc.invokeMethod('changeVolume', {'direction': 'down', 'steps': 2});
        return _reply('Тише');
      case 'volume_set':
        final level = int.tryParse(cmd.params['level'] ?? '50') ?? 50;
        await _acc.invokeMethod('changeVolume', {'direction': 'set', 'level': level});
        return _reply('Громкость ${level}%');
      case 'volume_mute':
        await _acc.invokeMethod('changeVolume', {'direction': 'mute'});
        return _reply('Звук отключён');

      // ── ОТКРЫТЬ / ЗАКРЫТЬ ПРИЛОЖЕНИЕ ───────────────────────────────
      case 'open_app':    return _openApp(cmd.target ?? '', cmd.app);
      case 'close_app':
        await _acc.invokeMethod('closeCurrentApp');
        return _reply('Закрываю');
      case 'switch_app':
        await _acc.invokeMethod('openRecents');
        return _reply('Открываю список приложений');

      // ── БРАУЗЕР ────────────────────────────────────────────────────
      case 'web_search':
        final q = Uri.encodeComponent(cmd.target ?? '');
        await _launcher.invokeMethod('launchUrl', {'url': 'https://www.google.com/search?q=$q'});
        return _reply('Ищу ${cmd.target}');
      case 'open_url':
        var url = cmd.target ?? '';
        if (!url.startsWith('http')) url = 'https://$url';
        await _launcher.invokeMethod('launchUrl', {'url': url});
        return _reply('Открываю $url');

      // ── ФОНАРИК ────────────────────────────────────────────────────
      case 'torch_on':    await TorchLight.enableTorch();  return _reply('Фонарик включён');
      case 'torch_off':   await TorchLight.disableTorch(); return _reply('Фонарик выключен');

      // ── НАВИГАЦИЯ ЖЕСТАМИ ──────────────────────────────────────────
      case 'nav_back':    await _acc.invokeMethod('pressBack');   return _reply('Назад');
      case 'nav_home':    await _acc.invokeMethod('pressHome');   return _reply('Домой');
      case 'nav_recents': await _acc.invokeMethod('openRecents'); return _reply('Открываю');
      case 'scroll_down':
        await _acc.invokeMethod('swipe', {'direction': 'down', 'speed': 'normal'});
        return _reply('Листаю вниз');
      case 'scroll_up':
        await _acc.invokeMethod('swipe', {'direction': 'up', 'speed': 'normal'});
        return _reply('Листаю вверх');
      case 'swipe_left':
        await _acc.invokeMethod('swipe', {'direction': 'left', 'speed': 'fast'});
        return _reply('Листаю влево');
      case 'swipe_right':
        await _acc.invokeMethod('swipe', {'direction': 'right', 'speed': 'fast'});
        return _reply('Листаю вправо');

      // ── УВЕДОМЛЕНИЯ / ШТОРКА ───────────────────────────────────────
      case 'open_notifications':
        await _acc.invokeMethod('openNotifications');
        return _reply('Открываю уведомления');
      case 'open_quick_settings':
        await _acc.invokeMethod('openQuickSettings');
        return _reply('Открываю быстрые настройки');

      // ── СКРИНШОТ ────────────────────────────────────────────────────
      case 'take_screenshot':
        await _acc.invokeMethod('takeScreenshot');
        return _reply('Скриншот сделан');

      // ════════════════════════════════════════════════════
      // УПРАВЛЕНИЕ YOUTUBE
      // ════════════════════════════════════════════════════
      case 'youtube_like':      return _ytLike();
      case 'youtube_dislike':   return _ytAction('dislike');
      case 'youtube_subscribe': return _ytAction('subscribe');
      case 'youtube_pause':     return _ytPlayPause();
      case 'youtube_play':      return _ytPlayPause();
      case 'youtube_next':
        await _acc.invokeMethod('swipe', {'direction': 'left', 'speed': 'fast'});
        return _reply('Следующее видео');
      case 'youtube_prev':
        await _acc.invokeMethod('swipe', {'direction': 'right', 'speed': 'fast'});
        return _reply('Предыдущее видео');
      case 'youtube_fullscreen': return _ytFullscreen();
      case 'youtube_mute':
        await _media.invokeMethod('pause');
        return _reply('Видео поставлено на паузу');
      case 'youtube_speed_up':  return _ytSpeed('1.5');
      case 'youtube_speed_down': return _ytSpeed('0.75');
      case 'youtube_skip':
        // Skip 10 seconds forward — tap right side of video
        await _acc.invokeMethod('tapAtPercent', {'x': 0.75, 'y': 0.5});
        return _reply('Перемотал вперёд');
      case 'youtube_rewind':
        await _acc.invokeMethod('tapAtPercent', {'x': 0.25, 'y': 0.5});
        return _reply('Перемотал назад');
      case 'youtube_search':
        await _ytSearch(cmd.target ?? '');
        return _reply('Ищу ${cmd.target} на YouTube');
      case 'youtube_comments':
        await _acc.invokeMethod('swipe', {'direction': 'up', 'speed': 'slow'});
        return _reply('Открываю комментарии');

      // ════════════════════════════════════════════════════
      // УПРАВЛЕНИЕ TELEGRAM
      // ════════════════════════════════════════════════════
      case 'telegram_open_chat': return _tgOpenChat(cmd.target ?? '');
      case 'telegram_back':
        await _acc.invokeMethod('pressBack');
        return _reply('Назад');
      case 'telegram_search':
        await _acc.invokeMethod('clickByContentDesc', {'desc': 'Search'});
        await Future.delayed(const Duration(milliseconds: 400));
        await _acc.invokeMethod('typeText', {'text': cmd.target ?? ''});
        return _reply('Ищу ${cmd.target} в Telegram');
      case 'telegram_new_message':
        await _acc.invokeMethod('clickByContentDesc', {'desc': 'Compose'});
        return _reply('Новое сообщение');

      // ════════════════════════════════════════════════════
      // УПРАВЛЕНИЕ INSTAGRAM
      // ════════════════════════════════════════════════════
      case 'instagram_like':    return _igDoubleTap();
      case 'instagram_comment':
        await _acc.invokeMethod('clickByContentDesc', {'desc': 'Comment'});
        return _reply('Открываю комментарии');
      case 'instagram_next':
        await _acc.invokeMethod('swipe', {'direction': 'up', 'speed': 'fast'});
        return _reply('Следующий пост');
      case 'instagram_story_next':
        await _acc.invokeMethod('tapAtPercent', {'x': 0.85, 'y': 0.5});
        return _reply('Следующая история');

      // ════════════════════════════════════════════════════
      // УПРАВЛЕНИЕ МУЗЫКОЙ (Spotify/YM/VK)
      // ════════════════════════════════════════════════════
      case 'music_like':
        await _acc.invokeMethod('clickByContentDesc', {'desc': 'Like'});
        return _reply('Трек лайкнут');
      case 'music_shuffle':
        await _acc.invokeMethod('clickByContentDesc', {'desc': 'Shuffle'});
        return _reply('Перемешать');
      case 'music_repeat':
        await _acc.invokeMethod('clickByContentDesc', {'desc': 'Repeat'});
        return _reply('Повтор');

      // ════════════════════════════════════════════════════
      // КЛИК ПО ТЕКСТУ / ЭЛЕМЕНТУ (универсальный)
      // ════════════════════════════════════════════════════
      case 'click_text':
        await _acc.invokeMethod('clickByText', {'text': cmd.target ?? ''});
        return _reply('Нажал на "${cmd.target}"');
      case 'type_text':
        await _acc.invokeMethod('typeText', {'text': cmd.target ?? ''});
        return _reply('Напечатал');
      case 'press_enter':
        await _acc.invokeMethod('pressEnter');
        return _reply('Enter');

      // ── СИСТЕМНЫЕ ─────────────────────────────────────────────────
      case 'lock_screen':
        await _acc.invokeMethod('lockScreen');
        return _reply('Экран заблокирован');
      case 'brightness_up':
        await _acc.invokeMethod('changeBrightness', {'direction': 'up'});
        return _reply('Яркость увеличена');
      case 'brightness_down':
        await _acc.invokeMethod('changeBrightness', {'direction': 'down'});
        return _reply('Яркость уменьшена');
      case 'open_settings':
        final intent = AndroidIntent(action: 'android.settings.SETTINGS');
        await intent.launch();
        return _reply('Открываю настройки');
      case 'open_wifi':
        final intent = AndroidIntent(action: 'android.settings.WIFI_SETTINGS');
        await intent.launch();
        return _reply('Открываю Wi-Fi');
      case 'open_bluetooth':
        final intent = AndroidIntent(action: 'android.settings.BLUETOOTH_SETTINGS');
        await intent.launch();
        return _reply('Открываю Bluetooth');

      // ── СООБЩЕНИЯ ─────────────────────────────────────────────────
      case 'send_sms':
        await _msng.invokeMethod('sendSms', {
          'contact': cmd.target ?? '',
          'message': cmd.params['message'] ?? '',
        });
        return _reply('Отправляю сообщение ${cmd.target}');

      default:
        return _reply('Команда "${cmd.action}" не распознана');
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // YOUTUBE HELPERS
  // ════════════════════════════════════════════════════════════════════

  Future<String> _ytLike() async {
    // Try clicking like button by content description
    final tried = await _acc.invokeMethod<bool>('clickByContentDesc', {'desc': 'like this video'});
    if (tried != true) {
      await _acc.invokeMethod('clickByContentDesc', {'desc': 'Like'});
    }
    return _reply('Лайк поставлен');
  }

  Future<String> _ytAction(String action) async {
    await _acc.invokeMethod('clickByContentDesc', {'desc': action});
    return _reply('Готово');
  }

  Future<String> _ytPlayPause() async {
    // YouTube tap center to show controls, then tap play/pause
    await _acc.invokeMethod('tapAtPercent', {'x': 0.5, 'y': 0.5});
    await Future.delayed(const Duration(milliseconds: 300));
    final ok = await _acc.invokeMethod<bool>('clickByContentDesc', {'desc': 'Pause'});
    if (ok != true) {
      await _acc.invokeMethod('clickByContentDesc', {'desc': 'Play'});
    }
    return _reply('Пауза / воспроизведение');
  }

  Future<String> _ytFullscreen() async {
    await _acc.invokeMethod('clickByContentDesc', {'desc': 'Enter fullscreen'});
    return _reply('Полный экран');
  }

  Future<String> _ytSpeed(String speed) async {
    // Open video options → playback speed
    await _acc.invokeMethod('clickByContentDesc', {'desc': 'More options'});
    await Future.delayed(const Duration(milliseconds: 500));
    await _acc.invokeMethod('clickByText', {'text': 'Playback speed'});
    await Future.delayed(const Duration(milliseconds: 400));
    await _acc.invokeMethod('clickByText', {'text': speed});
    return _reply('Скорость: ${speed}x');
  }

  Future<void> _ytSearch(String query) async {
    await _acc.invokeMethod('clickByContentDesc', {'desc': 'Search YouTube'});
    await Future.delayed(const Duration(milliseconds: 600));
    await _acc.invokeMethod('typeText', {'text': query});
    await Future.delayed(const Duration(milliseconds: 300));
    await _acc.invokeMethod('pressEnter');
  }

  // ════════════════════════════════════════════════════════════════════
  // TELEGRAM HELPERS
  // ════════════════════════════════════════════════════════════════════

  Future<String> _tgOpenChat(String name) async {
    // Open Telegram search and find the chat
    await _acc.invokeMethod('clickByContentDesc', {'desc': 'Search'});
    await Future.delayed(const Duration(milliseconds: 500));
    await _acc.invokeMethod('typeText', {'text': name});
    await Future.delayed(const Duration(milliseconds: 800));
    // Click first result
    await _acc.invokeMethod('clickFirstListItem');
    return _reply('Открываю чат $name');
  }

  // ════════════════════════════════════════════════════════════════════
  // INSTAGRAM HELPERS
  // ════════════════════════════════════════════════════════════════════

  Future<String> _igDoubleTap() async {
    // Double tap center of screen to like
    await _acc.invokeMethod('tapAtPercent', {'x': 0.5, 'y': 0.5});
    await Future.delayed(const Duration(milliseconds': 100));
    await _acc.invokeMethod('tapAtPercent', {'x': 0.5, 'y': 0.5});
    return _reply('Лайк!');
  }

  // ════════════════════════════════════════════════════════════════════
  // ОТКРЫТЬ ПРИЛОЖЕНИЕ
  // ════════════════════════════════════════════════════════════════════

  Future<String> _openApp(String target, String? app) async {
    final pkgMap = {
      'youtube':    'com.google.android.youtube',
      'telegram':   'org.telegram.messenger',
      'instagram':  'com.instagram.android',
      'whatsapp':   'com.whatsapp',
      'vk':         'com.vkontakte.android',
      'tiktok':     'com.zhiliaoapp.musically',
      'spotify':    'com.spotify.music',
      'chrome':     'com.android.chrome',
      'maps':       'com.google.android.apps.maps',
      'camera':     'android.media.action.IMAGE_CAPTURE',
      'calculator': 'com.android.calculator2',
      'calendar':   'com.google.android.calendar',
      'settings':   'com.android.settings',
      'gallery':    'com.android.gallery3d',
      'contacts':   'com.android.contacts',
      'phone':      'com.android.dialer',
      'messages':   'com.android.mms',
      'gmail':      'com.google.android.gm',
      'clock':      'com.android.deskclock',
      'files':      'com.android.documentsui',
      'yandex':     'ru.yandex.searchplugin',
      'ok':         'ru.ok.android',
    };

    final key = (app ?? target).toLowerCase().trim();
    final pkg = pkgMap[key] ?? pkgMap.entries
        .firstWhere((e) => key.contains(e.key), orElse: () => const MapEntry('', ''))
        .value;

    if (pkg.isNotEmpty) {
      try {
        await _launcher.invokeMethod('launchPackage', {'package': pkg});
        return _reply('Открываю ${target.isEmpty ? app ?? '' : target}');
      } catch (_) {}
    }

    // Fallback — search by name
    try {
      await _launcher.invokeMethod('launchByName', {'name': target});
      return _reply('Открываю $target');
    } catch (_) {}

    return _reply('Не нашёл приложение $target');
  }

  // ════════════════════════════════════════════════════════════════════
  // ЗВОНОК
  // ════════════════════════════════════════════════════════════════════

  Future<String> _makeCall(String target) async {
    if (target.isEmpty) return _reply('Кому звонить?');
    final digits = target.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isNotEmpty) {
      final uri = Uri.parse('tel:$digits');
      await launchUrl(uri);
      return _reply('Звоню на $target');
    }
    // Search in contacts
    await _msng.invokeMethod('callByName', {'name': target});
    return _reply('Звоню $target');
  }

  // ════════════════════════════════════════════════════════════════════
  // ПЕРСОНАЖНЫЙ ОТВЕТ
  // ════════════════════════════════════════════════════════════════════

  String _reply(String base) {
    switch (PersonalityService.current) {
      case AikaPersonality.jarvis:
        return 'Разумеется, сэр. $base.';
      case AikaPersonality.friday:
        return '$base, босс.';
      case AikaPersonality.kawaii:
        return '$base нья~ ✨';
      case AikaPersonality.kuudere:
        return base;
      case AikaPersonality.genki:
        return '$base ⚡ Готово!';
      default:
        return base;
    }
  }
}
