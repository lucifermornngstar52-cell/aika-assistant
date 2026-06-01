import 'package:flutter/material.dart';

/// Анимации аватара — привязаны к событиям приложения
enum AvatarAnimation {
  idle,       // покой
  wave,       // приветствие / слушает wake word
  dance,      // музыка играет
  walking,    // обычный фоновый режим
  running,    // активная работа
  thumbsUp,   // успех / ответ получен
  jump,       // будильник / уведомление
  no,         // ошибка
  yes,        // подтверждение
  sitting,    // неактивен долго
}

extension AvatarAnimationName on AvatarAnimation {
  String get glbName {
    switch (this) {
      case AvatarAnimation.idle:      return 'Idle';
      case AvatarAnimation.wave:      return 'Wave';
      case AvatarAnimation.dance:     return 'Dance';
      case AvatarAnimation.walking:   return 'Walking';
      case AvatarAnimation.running:   return 'Running';
      case AvatarAnimation.thumbsUp:  return 'ThumbsUp';
      case AvatarAnimation.jump:      return 'Jump';
      case AvatarAnimation.no:        return 'No';
      case AvatarAnimation.yes:       return 'Yes';
      case AvatarAnimation.sitting:   return 'Sitting';
    }
  }

  String get label {
    switch (this) {
      case AvatarAnimation.idle:      return 'Idle';
      case AvatarAnimation.wave:      return 'Wave 👋';
      case AvatarAnimation.dance:     return 'Dance 💃';
      case AvatarAnimation.walking:   return 'Walk 🚶';
      case AvatarAnimation.running:   return 'Run 🏃';
      case AvatarAnimation.thumbsUp:  return 'Nice 👍';
      case AvatarAnimation.jump:      return 'Jump! ⏰';
      case AvatarAnimation.no:        return 'No 🙅';
      case AvatarAnimation.yes:       return 'Yes ✅';
      case AvatarAnimation.sitting:   return 'AFK 😴';
    }
  }
}

/// Синглтон — любой сервис вызывает AvatarAnimationController.instance.set(...)
class AvatarAnimationController extends ChangeNotifier {
  static final AvatarAnimationController instance = AvatarAnimationController._();
  AvatarAnimationController._();

  AvatarAnimation _current = AvatarAnimation.idle;
  AvatarAnimation? _previous;
  bool _manualOverride = false; // пользователь вручную выбрал анимацию

  AvatarAnimation get current => _current;

  /// Установить анимацию от события системы
  void setFromEvent(AvatarAnimation anim) {
    if (_manualOverride) return; // не перебиваем ручной выбор
    if (_current == anim) return;
    _previous = _current;
    _current = anim;
    notifyListeners();
  }

  /// Установить вручную (пользователь нажал)
  void setManual(AvatarAnimation anim) {
    _manualOverride = (anim != AvatarAnimation.idle);
    _previous = _current;
    _current = anim;
    notifyListeners();
  }

  /// Сброс к автоматическому режиму
  void resetToAuto() {
    _manualOverride = false;
    _current = AvatarAnimation.idle;
    notifyListeners();
  }

  /// Временная анимация — вернётся к предыдущей через [duration]
  void playTemporary(AvatarAnimation anim, {Duration duration = const Duration(seconds: 3)}) {
    final prev = _current;
    _current = anim;
    notifyListeners();
    Future.delayed(duration, () {
      _current = prev;
      notifyListeners();
    });
  }
}
