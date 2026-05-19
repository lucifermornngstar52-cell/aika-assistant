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

  static String? _buildReaction(String pkg, String label) {
    switch (pkg) {
      case 'com.google.android.youtube':
        return 'О, ютуб открыл. Что смотришь?';
      case 'com.zhiliaoapp.musically':
        return 'ТикТок? Осторожно, там время исчезает 😄';
      case 'com.spotify.music':
      case 'com.google.android.apps.youtube.music':
        return 'Музыка — хороший выбор. Сказать танцевать?';
      case 'com.netflix.mediaclient':
        return 'Netflix! Кино или сериал?';
      case 'com.instagram.android':
        return 'Инстаграм. Листаем ленту?';
      case 'com.vkontakte.android':
        return 'ВКонтакте открыл.';
      case 'org.telegram.messenger':
        return 'Телеграм. Есть что-то важное?';
      case 'com.whatsapp':
        return 'Вацап. Не забудь ответить всем 😏';
      case 'com.google.android.apps.docs':
        return 'Гугл документы. Работаем?';
      case 'com.google.android.apps.spreadsheets':
        return 'Таблицы. Считаем что-то?';
      case 'com.microsoft.office.word':
      case 'com.microsoft.office.excel':
        return 'Office открыт. Помочь с чем-нибудь?';
      case 'com.android.chrome':
        return null; // Браузер — слишком часто, молчим
      default:
        if (_isGamePackage(pkg, label)) return 'Игра? Удачи! 🎮';
        return null;
    }
  }

  static bool _isGamePackage(String pkg, String label) {
    final keywords = ['game', 'games', 'play', 'clash', 'pubg', 'brawl', 'arena'];
    final lower = pkg.toLowerCase();
    return keywords.any((k) => lower.contains(k));
  }
}
