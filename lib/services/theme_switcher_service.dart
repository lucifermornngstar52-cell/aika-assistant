import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AssistantTheme { aika, jarvis, friday }

/// Сервис переключения тем: Айка ↔ Джарвис ↔ Пятница
class ThemeSwitcherService extends ChangeNotifier {
  static const _key = 'assistant_theme';
  static final ThemeSwitcherService _instance = ThemeSwitcherService._();
  factory ThemeSwitcherService() => _instance;
  ThemeSwitcherService._();

  AssistantTheme _theme = AssistantTheme.aika;
  AssistantTheme get theme => _theme;
  bool get isJarvis  => _theme == AssistantTheme.jarvis;
  bool get isFriday  => _theme == AssistantTheme.friday;
  bool get isAika    => _theme == AssistantTheme.aika;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_key) ?? 'aika';
    _theme = _fromString(val);
    notifyListeners();
  }

  Future<void> toggle() async {
    // Цикл: aika → jarvis → friday → aika
    switch (_theme) {
      case AssistantTheme.aika:    await setTheme(AssistantTheme.jarvis);  break;
      case AssistantTheme.jarvis:  await setTheme(AssistantTheme.friday);  break;
      case AssistantTheme.friday:  await setTheme(AssistantTheme.aika);    break;
    }
  }

  Future<void> setTheme(AssistantTheme t) async {
    _theme = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _toString(t));
    notifyListeners();
  }

  static AssistantTheme _fromString(String s) {
    switch (s) {
      case 'jarvis':  return AssistantTheme.jarvis;
      case 'friday':  return AssistantTheme.friday;
      default:        return AssistantTheme.aika;
    }
  }

  static String _toString(AssistantTheme t) {
    switch (t) {
      case AssistantTheme.jarvis:  return 'jarvis';
      case AssistantTheme.friday:  return 'friday';
      default:                     return 'aika';
    }
  }

  String get displayName {
    switch (_theme) {
      case AssistantTheme.aika:    return '🌸 Aika';
      case AssistantTheme.jarvis:  return '🤖 J.A.R.V.I.S.';
      case AssistantTheme.friday:  return '💚 F.R.I.D.A.Y.';
    }
  }

  String get nextThemeName {
    switch (_theme) {
      case AssistantTheme.aika:    return 'J.A.R.V.I.S.';
      case AssistantTheme.jarvis:  return 'F.R.I.D.A.Y.';
      case AssistantTheme.friday:  return 'Aika';
    }
  }
}
