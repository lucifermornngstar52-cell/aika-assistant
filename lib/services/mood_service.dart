import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

enum AikaMood {
  idle,
  happy,
  music,
  thinking,
  dancing,
  sleepy,    // долго молчит пользователь
  surprised,
  listening,
}

class MoodService {
  AikaMood _current = AikaMood.idle;
  Timer? _idleTimer;
  Timer? _happyTimer;
  Timer? _surprisedTimer;
  Timer? _sleepyTimer;

  final _rng = Random();
  DateTime? _lastInteraction;

  final StreamController<AikaMood> _controller =
      StreamController<AikaMood>.broadcast();

  Stream<AikaMood> get moodStream => _controller.stream;
  AikaMood get currentMood => _current;

  /// Спрайт по настроению
  static String spriteName(AikaMood mood) {
    switch (mood) {
      case AikaMood.idle:      return 'aika_idle';
      case AikaMood.happy:     return 'aika_wave';
      case AikaMood.music:     return 'aika_dance1';
      case AikaMood.thinking:  return 'aika_think';
      case AikaMood.dancing:   return 'aika_dance1';
      case AikaMood.sleepy:    return 'aika_idle';   // TODO: aika_sleep
      case AikaMood.surprised: return 'aika_wave';
      case AikaMood.listening: return 'aika_listen';
    }
  }

  void _set(AikaMood mood) {
    if (_current == mood) return;
    _current = mood;
    _controller.add(mood);
    debugPrint('[Mood] → $mood');
  }

  // ──── Публичные события ────

  /// Пользователь что-то сказал
  void onUserSpoke() {
    _lastInteraction = DateTime.now();
    _sleepyTimer?.cancel();
    _idleTimer?.cancel();
    _set(AikaMood.happy);
    _happyTimer?.cancel();
    _happyTimer = Timer(const Duration(seconds: 4), () => _set(AikaMood.idle));
    // Запускаем таймер "грусти" — если 2 минуты тишины
    _scheduleSleepy();
  }

  /// Айка думает
  void onThinking() {
    _idleTimer?.cancel();
    _set(AikaMood.thinking);
  }

  /// Айка слушает
  void onListening() {
    _sleepyTimer?.cancel();
    _set(AikaMood.listening);
  }

  /// Включилась музыка
  void onMusicStarted() {
    _idleTimer?.cancel();
    _set(AikaMood.music);
  }

  /// Музыка остановилась
  void onMusicStopped() {
    _set(AikaMood.idle);
    _scheduleSleepy();
  }

  /// Будильник сработал — Айка радуется
  void onAlarmFired() {
    _sleepyTimer?.cancel();
    _set(AikaMood.happy);
    _happyTimer?.cancel();
    _happyTimer = Timer(const Duration(seconds: 8), () => _set(AikaMood.idle));
  }

  /// Удивление (игра, неожиданная команда)
  void onSurprised() {
    _surprisedTimer?.cancel();
    _set(AikaMood.surprised);
    _surprisedTimer = Timer(const Duration(seconds: 3), () => _set(AikaMood.idle));
  }

  void setIdle() => _set(AikaMood.idle);

  void setDancing(bool on) => _set(on ? AikaMood.dancing : AikaMood.idle);

  // ──── Внутренняя логика ────

  /// Через 2 минуты без взаимодействия — Айка "грустит"/засыпает
  void _scheduleSleepy() {
    _sleepyTimer?.cancel();
    _sleepyTimer = Timer(const Duration(minutes: 2), () {
      if (_current == AikaMood.idle) {
        _set(AikaMood.sleepy);
        debugPrint('[Mood] Айка засыпает — давно нет активности');
      }
    });
  }

  /// Возвращает сообщение которое Айка скажет когда пользователь вернулся
  String getWakeUpMessage() {
    final msgs = [
      'О, ты вернулся! Я уже скучала 🌸',
      'Привет! Долго тебя не было 😊',
      'Наконец-то! Я тут немного задремала 😅',
      'Ой, ты здесь! Я уже думала ты забыл про меня',
    ];
    return msgs[_rng.nextInt(msgs.length)];
  }

  bool get isSleepy => _current == AikaMood.sleepy;

  void dispose() {
    _idleTimer?.cancel();
    _happyTimer?.cancel();
    _surprisedTimer?.cancel();
    _sleepyTimer?.cancel();
    _controller.close();
  }
}
