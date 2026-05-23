import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис переключения темы Айка ↔ Джарвис
class ThemeSwitcherService extends ChangeNotifier {
  static const _key = 'assistant_theme';
  static final ThemeSwitcherService _instance = ThemeSwitcherService._();
  factory ThemeSwitcherService() => _instance;
  ThemeSwitcherService._();

  AssistantTheme _theme = AssistantTheme.aika;
  AssistantTheme get theme => _theme;
  bool get isJarvis => _theme == AssistantTheme.jarvis;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_key) ?? 'aika';
    _theme = val == 'jarvis' ? AssistantTheme.jarvis : AssistantTheme.aika;
    notifyListeners();
  }

  Future<void> toggle() async {
    _theme = isJarvis ? AssistantTheme.aika : AssistantTheme.jarvis;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, isJarvis ? 'jarvis' : 'aika');
    notifyListeners();
  }

  Future<void> setTheme(AssistantTheme t) async {
    _theme = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, t == AssistantTheme.jarvis ? 'jarvis' : 'aika');
    notifyListeners();
  }
}

enum AssistantTheme { aika, jarvis }
