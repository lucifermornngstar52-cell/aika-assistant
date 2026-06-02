import 'dart:async';
import 'package:flutter/services.dart';

typedef ScreenReactionCallback = void Function(String reaction, String overlayState);

class ScreenWatcherService {
  static const _channel      = MethodChannel('com.aika.assistant/screen');
  static const _eventChannel = EventChannel('com.aika.assistant/screen_events');

  static String _currentPackage = '';
  static String _currentLabel   = '';
  static StreamSubscription? _sub;
  static String _lastReactedPackage = '';
  static DateTime? _lastReactionTime;
  static const _cooldown = Duration(minutes: 5);

  static Map<String, String>? getCurrentAppInfo() {
    if (_currentPackage.isEmpty) return null;
    return {'package': _currentPackage, 'label': _currentLabel};
  }

  static String get currentPackage => _currentPackage;
  static String get currentLabel   => _currentLabel;

  static void startWatching({ScreenReactionCallback? onReaction}) {
    _sub?.cancel();
    _sub = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final pkg   = (event['package'] ?? '') as String;
      final label = (event['label']   ?? '') as String;
      if (pkg.isEmpty) return;
      _currentPackage = pkg;
      _currentLabel   = label;
      if (onReaction == null) return;
      final now = DateTime.now();
      final isSamePkg = pkg == _lastReactedPackage;
      final cooldownExpired = _lastReactionTime == null ||
          now.difference(_lastReactionTime!) > _cooldown;
      if (!isSamePkg || cooldownExpired) {
        final result = _buildReaction(pkg, label);
        if (result != null) {
          _lastReactedPackage = pkg;
          _lastReactionTime   = now;
          onReaction(result.$1, result.$2);
        }
      }
    }, onError: (_) {});
  }

  static void stopWatching() { _sub?.cancel(); _sub = null; }

  static Future<bool> isAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } catch (_) { return false; }
  }

  static Future<void> openAccessibilitySettings() async {
    try { await _channel.invokeMethod('openAccessibilitySettings'); } catch (_) {}
  }

  static String _pick(List<String> phrases) {
    final idx = DateTime.now().millisecondsSinceEpoch % phrases.length;
    return phrases[idx];
  }

  /// Возвращает (текст, overlayState) или null
  static (String, String)? _buildReaction(String pkg, String label) {
    switch (pkg) {
      // ── Мессенджеры ──────────────────────────────────────────────────
      case 'com.whatsapp':
        return (_pick([
          'WhatsApp открыт 💬 Не забудь ответить!',
          'Ватсап! Кто пишет?',
          'WhatsApp — давай отвечай, не заставляй ждать 😄',
        ]), 'telegram');

      case 'org.telegram.messenger':
      case 'org.telegram.messenger.web':
        return (_pick([
          'Телеграм открыт 📨 Там что-то важное?',
          'О, телеграм! Много непрочитанных?',
          'Телеграм — надеюсь не спам 😄',
        ]), 'telegram');

      case 'com.instagram.android':
        return (_pick([
          'Инстаграм 📸 Листаем ленту?',
          'Инста открыт. Что интересного?',
          'Инстаграм — только не залипни! 😄',
        ]), 'greeting');

      case 'com.vkontakte.android':
        return (_pick([
          'ВКонтакте открыл 🎵 Музыку или ленту?',
          'О, ВК! Что смотрим?',
          'ВКонтакте — видосы, музыка или переписка?',
        ]), 'vk');

      case 'com.discord':
        return (_pick([
          'Discord 🎧 В игре или общаешься?',
          'Дискорд открыт. Что за сервер?',
        ]), 'greeting');

      case 'com.viber.voip':
        return ('Вайбер открыт. Не забудь ответить!', 'greeting');

      case 'ru.ok.android':
        return ('Одноклассники 🐦 Кому привет пишем?', 'greeting');

      // ── Видео ────────────────────────────────────────────────────────
      case 'com.google.android.youtube':
        return (_pick([
          'YouTube открыл ▶️ Что смотришь?',
          'Ютуб! Обучение или развлечение? 😄',
          'YouTube — только не застрянь на роликах 😄',
        ]), 'youtube');

      case 'com.zhiliaoapp.musically':
      case 'com.ss.android.ugc.trill':
        return (_pick([
          'ТикТок? Осторожно, там время исчезает 😄',
          'О, тикток! Уже 2 часа прошло? 😄',
        ]), 'dance');

      case 'com.netflix.mediaclient':
        return (_pick([
          'Netflix 🍿 Кино или сериал?',
          'Нетфликс! Что смотрим сегодня?',
          'Netflix — один эпизод, обещаешь? 😄',
        ]), 'youtube');

      case 'tv.twitch.android.app':
        return (_pick([
          'Twitch 🎮 Кого смотришь?',
          'О, твич! Стримы или турниры?',
        ]), 'youtube');

      case 'org.videolan.vlc':
      case 'com.mxtech.videoplayer.ad':
        return ('Видеоплеер запущен 🎬 Приятного просмотра!', 'youtube');

      // ── Музыка ───────────────────────────────────────────────────────
      case 'com.spotify.music':
        return (_pick([
          'Spotify 🎵 Что слушаем?',
          'Спотифай! Хочешь я потанцую? 💃',
          'Музыка — это хорошо 🎵',
        ]), 'music');

      case 'com.google.android.apps.youtube.music':
        return ('YouTube Music 🎵 Что в плейлисте?', 'music');

      case 'ru.yandex.music':
        return ('Яндекс Музыка 🎵 Хороший вкус!', 'music');

      case 'com.vk.music':
        return ('VK Музыка 🎵 Что слушаем?', 'music');

      case 'com.soundcloud.android':
        return ('SoundCloud 🎵 Независимая музыка!', 'music');

      // ── Игры ─────────────────────────────────────────────────────────
      // обрабатывается ниже

      // ── Работа и учёба ───────────────────────────────────────────────
      case 'com.google.android.apps.docs':
        return (_pick([
          'Google Docs 📝 Работаем?',
          'Документы. Пишем что-то важное?',
        ]), 'thinking');

      case 'com.microsoft.office.word':
        return ('Word открыт 📝 Нужна помощь с текстом?', 'thinking');

      case 'com.google.android.apps.classroom':
        return ('Google Classroom 📚 Учимся!', 'happy');

      case 'com.duolingo':
        return ('Duolingo 🦜 Молодец, учишь язык!', 'happy');

      // ── Браузер — реагируем кратко ────────────────────────────────
      case 'com.android.chrome':
      case 'org.mozilla.firefox':
      case 'com.yandex.browser':
        return null; // слишком часто

      // ── Системное — молчим ────────────────────────────────────────
      case 'com.android.settings':
      case 'com.google.android.apps.photos':
        return null;

      default:
        if (_isGamePackage(pkg, label)) {
          return (_pick([
            'Игра запущена 🎮 Удачи!',
            'Играем? Ни пуха! 🎮',
            'О, игра! Красавчик 🎮',
          ]), 'happy');
        }
        return null;
    }
  }

  static bool _isGamePackage(String pkg, String label) {
    final keywords = ['game', 'games', 'play', 'clash', 'pubg', 'brawl', 'arena', 'mobile'];
    final lower = pkg.toLowerCase();
    return keywords.any((k) => lower.contains(k));
  }
}
