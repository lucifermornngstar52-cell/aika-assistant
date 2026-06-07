import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// PingSoundService — звуки начала/конца прослушивания.
/// Вдохновлено Google Assistant Desktop Client (pingStart.mp3, pingStop.mp3, pingSuccess.mp3).
///
/// Использует HapticFeedback + системные звуки.
/// Можно заменить на кастомные mp3 файлы.
class PingSoundService {
  static final PingSoundService _i = PingSoundService._();
  factory PingSoundService() => _i;
  PingSoundService._();

  static const _channel = MethodChannel('com.aika.assistant/screen_reader');

  bool _enabled = true;

  void setEnabled(bool enabled) => _enabled = enabled;

  /// Звук начала прослушивания (короткий пинг вверх)
  Future<void> pingStart() async {
    if (!_enabled) return;
    try {
      HapticFeedback.lightImpact();
      await _channel.invokeMethod('playPingStart');
    } catch (_) {
      // fallback: только haptic
    }
  }

  /// Звук окончания прослушивания (пинг вниз)
  Future<void> pingStop() async {
    if (!_enabled) return;
    try {
      HapticFeedback.mediumImpact();
      await _channel.invokeMethod('playPingStop');
    } catch (_) {}
  }

  /// Звук успешного распознавания / выполнения команды
  Future<void> pingSuccess() async {
    if (!_enabled) return;
    try {
      HapticFeedback.selectionClick();
      await _channel.invokeMethod('playPingSuccess');
    } catch (_) {}
  }

  /// Звук ошибки
  Future<void> pingError() async {
    if (!_enabled) return;
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}
