import 'dart:async';
import 'package:flutter/services.dart';

typedef NotificationCallback = void Function(Map<String, String> notif);

class NotificationService {
  static const _channel      = MethodChannel('com.aika.assistant/notifications');
  static const _eventChannel = EventChannel('com.aika.assistant/notification_events');

  static StreamSubscription? _sub;
  static final List<Map<String, String>> _cache = [];

  static List<Map<String, String>> get recent => List.unmodifiable(_cache);

  /// Запускает прослушку уведомлений
  static void startListening({NotificationCallback? onNew}) {
    _sub?.cancel();
    _sub = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final n = {
        'pkg':   (event['pkg']   ?? '') as String,
        'title': (event['title'] ?? '') as String,
        'text':  (event['text']  ?? '') as String,
        'time':  (event['time']  ?? '') as String,
      };
      _cache.add(n);
      if (_cache.length > 50) _cache.removeAt(0);
      onNew?.call(n);
    }, onError: (_) {});
  }

  static void stopListening() {
    _sub?.cancel();
    _sub = null;
  }

  /// Проверить, выдано ли разрешение на чтение уведомлений
  static Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) { return false; }
  }

  /// Открыть настройки доступа к уведомлениям
  static Future<void> openPermissionSettings() async {
    try { await _channel.invokeMethod('openPermissionSettings'); } catch (_) {}
  }

  /// Возвращает текст брифинга по уведомлениям
  static String buildBriefingText() {
    if (_cache.isEmpty) return 'Уведомлений не было.';

    // Группируем по приложению
    final Map<String, List<Map<String, String>>> byApp = {};
    for (final n in _cache) {
      final app = _appLabel(n['pkg'] ?? '');
      byApp.putIfAbsent(app, () => []).add(n);
    }

    final buf = StringBuffer('Пока тебя не было:\n');
    byApp.forEach((app, notifs) {
      buf.writeln('📱 $app — ${notifs.length} сообщ.:');
      for (final n in notifs.take(3)) {
        final who  = n['title'] ?? '';
        final text = n['text']  ?? '';
        if (who.isNotEmpty) buf.writeln('  • $who: $text');
      }
    });
    return buf.toString().trim();
  }

  static void clearCache() => _cache.clear();

  static String _appLabel(String pkg) {
    switch (pkg) {
      case 'org.telegram.messenger': return 'Telegram';
      case 'com.whatsapp':           return 'WhatsApp';
      case 'com.vkontakte.android':  return 'ВКонтакте';
      case 'com.instagram.android':  return 'Instagram';
      case 'com.google.android.gm':  return 'Gmail';
      default:
        final parts = pkg.split('.');
        return parts.length > 1 ? parts.last : pkg;
    }
  }
}
