import 'package:flutter/material.dart';

/// Анимации аватара — привязаны к событиям приложения
/// Модель: Michelle (anime-style) + XBot animations merged
enum AvatarAnimation {
  idle,       // 'idle'       — покой, дышит
  walk,       // 'walk'       — ходит, ожидание
  run,        // 'run'        — активная работа
  dance,      // 'SambaDance' — музыка играет
  agree,      // 'agree'      — подтверждение / да
  headShake,  // 'headShake'  — нет / ошибка
  sadPose,    // 'sad_pose'   — грусть / долго неактивен
  sneakPose,  // 'sneak_pose' — думает / обрабатывает
  tPose,      // 'TPose'      — сброс
}

extension AvatarAnimationName on AvatarAnimation {
  /// Точное имя анимации в GLB файле
  String get glbName {
    switch (this) {
      case AvatarAnimation.idle:      return 'idle';
      case AvatarAnimation.walk:      return 'walk';
      case AvatarAnimation.run:       return 'run';
      case AvatarAnimation.dance:     return 'SambaDance';
      case AvatarAnimation.agree:     return 'agree';
      case AvatarAnimation.headShake: return 'headShake';
      case AvatarAnimation.sadPose:   return 'sad_pose';
      case AvatarAnimation.sneakPose: return 'sneak_pose';
      case AvatarAnimation.tPose:     return 'TPose';
    }
  }

  String get label {
    switch (this) {
      case AvatarAnimation.idle:      return 'Idle 😌';
      case AvatarAnimation.walk:      return 'Walk 🚶';
      case AvatarAnimation.run:       return 'Run 🏃';
      case AvatarAnimation.dance:     return 'Dance 💃';
      case AvatarAnimation.agree:     return 'Yes ✅';
      case AvatarAnimation.headShake: return 'No 🙅';
      case AvatarAnimation.sadPose:   return 'AFK 😴';
      case AvatarAnimation.sneakPose: return 'Think 🤔';
      case AvatarAnimation.tPose:     return 'Reset';
    }
  }

  Color get glowColor {
    switch (this) {
      case AvatarAnimation.dance:     return const Color(0xFFFF4081);  // pink
      case AvatarAnimation.agree:     return const Color(0xFF00E676);  // green
      case AvatarAnimation.headShake: return const Color(0xFFFF5252);  // red
      case AvatarAnimation.run:       return const Color(0xFFFFD740);  // yellow
      case AvatarAnimation.sadPose:   return const Color(0xFF78909C);  // grey-blue
      case AvatarAnimation.sneakPose: return const Color(0xFFCE93D8);  // purple
      default:                        return const Color(0xFF00B0FF);  // neon blue
    }
  }
}

/// Синглтон — любой сервис вызывает AvatarAnimationController.instance.setFromEvent(...)
class AvatarAnimationController extends ChangeNotifier {
  static final AvatarAnimationController instance = AvatarAnimationController._();
  AvatarAnimationController._();

  AvatarAnimation _current = AvatarAnimation.idle;
  bool _manualOverride = false;

  AvatarAnimation get current => _current;
  bool get isManual => _manualOverride;

  /// Событие системы (не перебивает ручной выбор)
  void setFromEvent(AvatarAnimation anim) {
    if (_manualOverride) return;
    if (_current == anim) return;
    _current = anim;
    notifyListeners();
  }

  /// Ручной выбор пользователем
  void setManual(AvatarAnimation anim) {
    _manualOverride = (anim != AvatarAnimation.idle);
    _current = anim;
    notifyListeners();
  }

  /// Сброс к авто-режиму
  void resetToAuto() {
    _manualOverride = false;
    _current = AvatarAnimation.idle;
    notifyListeners();
  }

  /// Временная анимация — потом возвращается к предыдущей
  void playTemporary(AvatarAnimation anim, {Duration duration = const Duration(seconds: 3)}) {
    if (_manualOverride) return;
    final prev = _current;
    _current = anim;
    notifyListeners();
    Future.delayed(duration, () {
      if (!_manualOverride) {
        _current = prev;
        notifyListeners();
      }
    });
  }
}
