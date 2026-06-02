import 'dart:async';
import 'package:flutter/services.dart';

typedef ScreenReactionCallback = void Function(String reaction);

class ScreenWatcherService {
  static const _channel      = MethodChannel('com.aika.assistant/screen');
  static const _eventChannel = EventChannel('com.aika.assistant/screen_events');

  static String _currentPackage = '';
  static String _currentLabel   = '';
  static StreamSubscription? _sub;

  // Последний пакет на который среагировали + время реакции
  static String _lastReactedPackage = '';
  static DateTime? _lastReactionTime;

  // Минимальный интервал между реакциями на ОДНО И ТО ЖЕ приложение — 5 минут
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

      // Обновляем текущее приложение
      _currentPackage = pkg;
      _currentLabel   = label;

      if (onReaction == null) return;

      final now = DateTime.now();
      final isSamePkg = pkg == _lastReactedPackage;
      final cooldownExpired = _lastReactionTime == null ||
          now.difference(_lastReactionTime!) > _cooldown;

      // Реагируем если: другое приложение ИЛИ то же но прошло >5 мин
      if (!isSamePkg || cooldownExpired) {
        final reaction = _buildReaction(pkg, label);
        if (reaction != null) {
          _lastReactedPackage = pkg;
          _lastReactionTime   = now;
          onReaction(reaction);
        }
      }
    }, onError: (_) {});
  }

  static void stopWatching() {
    _sub?.cancel();
    _sub = null;
  }

  static Future<bool> isAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } catch (_) { return false; }
  }

  static Future<void> openAccessibilitySettings() async {
    try { await _channel.invokeMethod('openAccessibilitySettings'); } catch (_) {}
  }

  // Случайная фраза из списка
  static String _pick(List<String> phrases) {
    final idx = DateTime.now().millisecondsSinceEpoch % phrases.length;
    return phrases[idx];
  }

  static String? _buildReaction(String pkg, String label) {
    switch (pkg) {
      // ── Мессенджеры ──────────────────────────────────────────────
      case 'com.whatsapp':
        return _pick([
          'WhatsApp открыт 💬 Не забудь ответить всем 😏',
          'О, ватсап! Кто пишет?',
          'Вацап открыл. Давай отвечай, не заставляй людей ждать 😄',
        ]);
      case 'org.telegram.messenger':
        return _pick([
          'Телеграм открыл 📨 Там что-то важное?',
          'О, телеграм. Много непрочитанных?',
          'Телеграм? Надеюсь не спам 😄',
        ]);
      case 'com.instagram.android':
        return _pick([
          'Инстаграм 📸 Листаем ленту?',
          'Инста открыт. Что интересного?',
          'Инстаграм — только не залипни надолго 😄',
        ]);
      case 'com.vkontakte.android':
        return _pick([
          'ВКонтакте открыл 🎵',
          'О, ВК. Музыку слушаешь или ленту листаешь?',
        ]);
      case 'com.discord':
        return _pick([
          'Discord 🎧 В игре или просто общаешься?',
          'Дискорд открыт. Что за сервер?',
        ]);
      case 'com.viber.voip':
        return 'Вайбер открыл. Не забудь ответить!';

      // ── Видео и развлечения ───────────────────────────────────────
      case 'com.google.android.youtube':
        return _pick([
          'О, ютуб открыл ▶️ Что смотришь?',
          'YouTube! Учёба или развлечение? 😄',
          'Ютуб открыт. Только не застрянь на роликах 😄',
        ]);
      case 'com.zhiliaoapp.musically':
        return _pick([
          'ТикТок? Осторожно, там время исчезает 😄',
          'О, тикток открыл. Уже 2 часа прошло? 😄',
          'Тикток! Ну ладно, 5 минут максимум 😄',
        ]);
      case 'com.netflix.mediaclient':
        return _pick([
          'Netflix 🍿 Кино или сериал?',
          'Нетфликс открыл. Что смотрим сегодня?',
          'Netflix! Один эпизод — обещаешь? 😄',
        ]);
      case 'tv.twitch.android.app':
        return _pick([
          'Twitch 🎮 Кого смотришь?',
          'О, твич! Стримы или турниры?',
        ]);

      // ── Музыка ───────────────────────────────────────────────────
      case 'com.spotify.music':
        return _pick([
          'Spotify 🎵 Хороший выбор! Хочешь я потанцую?',
          'Спотифай открыт. Что слушаем?',
          'Музыка — это хорошо 🎵',
        ]);
      case 'com.google.android.apps.youtube.music':
        return 'YouTube Music 🎵 Что в плейлисте?';
      case 'ru.yandex.music':
        return 'Яндекс Музыка 🎵 Хороший вкус!';

      // ── Игры ─────────────────────────────────────────────────────
      // обрабатывается ниже через _isGamePackage

      // ── Работа и учёба ───────────────────────────────────────────
      case 'com.google.android.apps.docs':
        return _pick([
          'Google Docs открыт 📝 Работаем?',
          'Документы. Пишем что-то важное?',
        ]);
      case 'com.google.android.apps.spreadsheets':
        return 'Google Таблицы 📊 Считаем что-то?';
      case 'com.microsoft.office.word':
        return 'Word открыт 📝 Нужна помощь с текстом?';
      case 'com.microsoft.office.excel':
        return 'Excel открыт 📊 Сложные формулы?';
      case 'com.google.android.apps.classroom':
        return 'Google Classroom 📚 Учимся!';

      // ── Браузер — молчим, слишком часто ──────────────────────────
      case 'com.android.chrome':
      case 'org.mozilla.firefox':
      case 'com.yandex.browser':
        return null;

      // ── Системное — молчим ───────────────────────────────────────
      case 'com.android.settings':
      case 'com.google.android.apps.photos':
        return null;

      default:
        if (_isGamePackage(pkg, label)) {
          return _pick([
            'Игра! Удачи 🎮',
            'Играем? Ни пуха! 🎮',
            'О, игра! Красавчик 🎮',
          ]);
        }
        return null;
    }
  }

  static bool _isGamePackage(String pkg, String label) {
    final keywords = ['game', 'games', 'play', 'clash', 'pubg', 'brawl', 'arena'];
    final lower = pkg.toLowerCase();
    return keywords.any((k) => lower.contains(k));
  }
}
