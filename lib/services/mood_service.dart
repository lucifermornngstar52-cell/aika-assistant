import 'dart:async';
import 'package:flutter/foundation.dart';

/// Настроение Айки — меняет анимацию в зависимости от контекста.
enum AikaMood {
  idle,     // обычное состояние
  happy,    // пользователь только что поговорил
  music,    // играет музыка
  thinking, // обрабатывает запрос
  dancing,  // танцует
  sleepy,   // долго не было активности (15+ мин)
  surprised,// получила неожиданную команду
  listening,// слушает голос
}

class MoodService {
  AikaMood _current = AikaMood.idle;
  Timer? _idleTimer;
  Timer? _happyTimer;

  final StreamController<AikaMood> _controller =
      StreamController<AikaMood>.broadcast();

  Stream<AikaMood> get moodStream => _controller.stream;
  AikaMood get currentMood => _current;

  // Имена PNG анимаций для каждого настроения
  static String animationFolder(AikaMood mood) {
    switch (mood) {
      case AikaMood.idle:      return 'aika_idle';
      case AikaMood.happy:     return 'aika_happy';
      case AikaMood.music:     return 'aika_dance';
      case AikaMood.thinking:  return 'aika_think';
      case AikaMood.dancing:   return 'aika_dance';
      case AikaMood.sleepy:    return 'aika_idle'; // пока используем idle
      case AikaMood.surprised: return 'aika_idle';
      case AikaMood.listening: return 'aika_idle';
    }
  }

  /// Кол-во кадров для каждой анимации
  static int frameCount(AikaMood mood) {
    switch (mood) {
      case AikaMood.dancing:
      case AikaMood.music:    return 16;
      default:                return 16;
    }
  }

  /// Интервал смены кадров (мс)
  static int frameInterval(AikaMood mood) {
    switch (mood) {
      case AikaMood.dancing:
      case AikaMood.music:    return 220;
      case AikaMood.thinking: return 300;
      case AikaMood.happy:    return 250;
      default:                return 280;
    }
  }

  void _set(AikaMood mood) {
    if (_current == mood) return;
    _current = mood;
    _controller.add(mood);
    debugPrint('[Mood] → $mood');
  }

  // ── Триггеры ──

  void onUserSpoke() {
    _idleTimer?.cancel();
    _set(AikaMood.happy);
    _happyTimer?.cancel();
    _happyTimer = Timer(const Duration(seconds: 8), () {
      if (_current == AikaMood.happy) setIdle();
    });
    _startIdleTimer();
  }

  void onListening() {
    _idleTimer?.cancel();
    _set(AikaMood.listening);
  }

  void onThinking() {
    _set(AikaMood.thinking);
  }

  void onMusicPlaying() {
    _idleTimer?.cancel();
    _set(AikaMood.music);
  }

  void onMusicStopped() {
    _set(AikaMood.idle);
    _startIdleTimer();
  }

  void onDancing() {
    _idleTimer?.cancel();
    _set(AikaMood.dancing);
  }

  void onDanceStopped() {
    _set(AikaMood.idle);
    _startIdleTimer();
  }

  void setIdle() {
    _set(AikaMood.idle);
    _startIdleTimer();
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    // Через 15 минут без активности — Айка "засыпает"
    _idleTimer = Timer(const Duration(minutes: 15), () {
      if (_current == AikaMood.idle) {
        _set(AikaMood.sleepy);
      }
    });
  }

  void dispose() {
    _idleTimer?.cancel();
    _happyTimer?.cancel();
    _controller.close();
  }
}
