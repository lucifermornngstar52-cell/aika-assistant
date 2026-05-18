import 'package:flutter/services.dart';

/// Проверяет играет ли сейчас музыка на устройстве через AudioManager
class MusicDetectorService {
  static const _channel = MethodChannel('aika/audio');

  /// Возвращает true если сейчас играет любой аудио
  static Future<bool> isMusicPlaying() async {
    try {
      final result = await _channel.invokeMethod<bool>('isMusicPlaying');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
