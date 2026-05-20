import 'dart:async';
import 'package:flutter/foundation.dart';

enum AikaMood {
  idle,
  happy,
  music,
  thinking,
  dancing,
  sleepy,
  surprised,
  listening,
}

class MoodService {
  AikaMood _current = AikaMood.idle;
  Timer? _idleTimer;
  Timer? _happyTimer;
  Timer? _surprisedTimer;

  final StreamController<AikaMood> _controller =
      StreamController<AikaMood>.broadcast();

  Stream<AikaMood> get moodStream => _controller.stream;
  AikaMood get currentMood => _current;

  /// Маппинг настроения → имя PNG спрайта для оверлея
  static String spriteName(AikaMood mood) {
    switch (mood) {
      case AikaMood.idle:      return 'aika_idle';
      case AikaMood.happy:     return 'aika_wave';      // машет рукой
      case AikaMood.music:     return 'aika_dance1';    // начало танца
      case AikaMood.thinking:  return 'aika_think';
      case AikaMood.dancing:   return 'aika_dance1';
      case AikaMood.sleepy:    return 'aika_idle';      // TODO: aika_sleep
      case AikaMood.surprised: return 'aika_wave';      // TODO: aika_surprised
      case AikaMood.listening: return 'aika_listen';
    }
  }

  /// Имя папки/анимации для AnimatedSprite виджета
  static String animationFolder(AikaMood mood) {
    switch (mood) {
      case AikaMood.idle:      return 'aika_idle';
      case AikaMood.happy:     return 'aika_idle';
      case AikaMood.music:
      case AikaMood.dancing:   return 'aika_dance';
      case AikaMood.thinking:  return 'aika_think';
      case AikaMood.sleepy:    return 'aika_idle';
      case AikaMood.surprised: return 'aika_idle';
      case AikaMood.listening: return 'aika_listen';
    }
  }

  static int frameCount(AikaMood mood) {
    switch (mood) {
      case AikaMood.dancing:
      case AikaMood.music:    return 15;
      default:                return 1;
    }
  }

  static int frameInterval(AikaMood mood) {
    switch (mood) {
      case AikaMood.dancing:
      case AikaMood.music:    return 180;
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

  // ── Триггеры ─────────────────────────────────────────────────

  void onUserSpoke() {
    _idleTimer?.cancel();
    _set(AikaMood.happy);
    _happyTimer?.cancel();
    _happyTimer = Timer(const Duration(seconds: 6), () {
      if (_current == AikaMood.happy) setIdle();
    });
    _startIdleTimer();
  }

  void onListening() {
    _idleTimer?.cancel();
    _set(AikaMood.listening);
  }

  void onThinking() => _set(AikaMood.thinking);

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

  /// Вызывается когда Айка получает неожиданный запрос (например мини-игра)
  void onSurprised() {
    _set(AikaMood.surprised);
    _surprisedTimer?.cancel();
    _surprisedTimer = Timer(const Duration(seconds: 4), () {
      if (_current == AikaMood.surprised) onUserSpoke();
    });
  }

  void setIdle() {
    _set(AikaMood.idle);
    _startIdleTimer();
  }

  /// Когда Айка "засыпает" — меняем оверлей
  void onSleepy() => _set(AikaMood.sleepy);

  void _startIdleTimer() {
    _idleTimer?.cancel();
    // 15 минут без активности → засыпает
    _idleTimer = Timer(const Duration(minutes: 15), () {
      if (_current == AikaMood.idle) _set(AikaMood.sleepy);
    });
  }

  void dispose() {
    _idleTimer?.cancel();
    _happyTimer?.cancel();
    _surprisedTimer?.cancel();
    _controller.close();
  }
}
