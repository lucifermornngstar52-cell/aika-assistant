import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Управление медиа-плеером через MediaSession API
class MusicControlService {
  static const _channel = MethodChannel('com.aika.assistant/media');

  static Future<void> play()         => send('play');
  static Future<void> pause()        => send('pause');
  static Future<void> next()         => send('next');
  static Future<void> previous()     => send('previous');
  static Future<void> stop()         => send('stop');

  static Future<void> send(String action) async {
    try {
      await _channel.invokeMethod('mediaControl', {'action': action});
    } on PlatformException catch (e) {
      debugPrint('[MusicControl] ошибка \$action: \${e.message}');
    }
  }

  /// Парсим голосовую команду управления музыкой
  static String? parseCommand(String text) {
    final lower = text.toLowerCase();
    if (_matches(lower, ['стоп', 'останови музыку', 'выключи музыку', 'замолчи музыка'])) return 'stop';
    if (_matches(lower, ['пауза', 'поставь на паузу', 'на паузу'])) return 'pause';
    if (_matches(lower, ['играй', 'продолжи', 'продолжай', 'возобнови', 'включи музыку', 'запусти музыку'])) return 'play';
    if (_matches(lower, ['следующая', 'следующий трек', 'дальше', 'пропусти', 'скип'])) return 'next';
    if (_matches(lower, ['предыдущая', 'предыдущий трек', 'назад', 'перемотай назад'])) return 'previous';
    return null;
  }

  static bool _matches(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));
}
