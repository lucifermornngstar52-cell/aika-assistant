import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис самообучения Айки.
class AikaSelfLearningService {

  static Future<void> recordAction({
    required String type,
    required String value,
    String? extra,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'self_learn_$type';
      final existing = prefs.getStringList(key) ?? [];
      existing.add(json.encode({
        'ts': DateTime.now().toIso8601String(),
        'v': value,
        if (extra != null) 'e': extra,
      }));
      if (existing.length > 100) existing.removeRange(0, existing.length - 100);
      await prefs.setStringList(key, existing);
    } catch (_) {}
  }

  static Future<List<String>> getFrequentApps({int top = 5}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = prefs.getStringList('self_learn_app_open') ?? [];
      final counts = <String, int>{};
      for (final e in entries) {
        final m = json.decode(e) as Map;
        final v = m['v'] as String? ?? '';
        counts[v] = (counts[v] ?? 0) + 1;
      }
      final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return sorted.take(top).map((e) => e.key).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String> getContextForAI() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sb = StringBuffer();

      final apps = await getFrequentApps();
      if (apps.isNotEmpty) {
        sb.writeln("Любимые приложения пользователя: ${apps.join(', ')}.");
      }

      final cmds = prefs.getStringList('self_learn_command') ?? [];
      if (cmds.isNotEmpty) {
        final recent = cmds.length > 5 ? cmds.sublist(cmds.length - 5) : cmds;
        final cmdTexts = recent.map((e) {
          final m = json.decode(e) as Map;
          return m['v'] as String? ?? '';
        }).where((s) => s.isNotEmpty).toList();
        if (cmdTexts.isNotEmpty) {
          sb.writeln("Последние команды: ${cmdTexts.join('; ')}.");
        }
      }

      final hour = DateTime.now().hour;
      if (hour >= 22 || hour < 6) {
        sb.writeln('Сейчас ночь — пользователь работает поздно.');
      } else if (hour >= 6 && hour < 12) {
        sb.writeln('Утро — пользователь только начинает день.');
      } else if (hour >= 12 && hour < 18) {
        sb.writeln('День — активное время.');
      } else {
        sb.writeln('Вечер — пользователь отдыхает или играет.');
      }

      return sb.toString();
    } catch (_) {
      return '';
    }
  }

  // Алиас для обратной совместимости
  static Future<String> buildContextSummary() => getContextForAI();

  static Future<void> savePreference(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pref_$key', value);
    } catch (_) {}
  }

  static Future<String?> getPreference(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('pref_$key');
    } catch (_) {
      return null;
    }
  }

  static Future<void> rememberFact(String fact) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final facts = prefs.getStringList('user_facts') ?? [];
      if (!facts.contains(fact)) {
        facts.add(fact);
        if (facts.length > 50) facts.removeAt(0);
        await prefs.setStringList('user_facts', facts);
      }
    } catch (_) {}
  }

  static Future<List<String>> getUserFacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('user_facts') ?? [];
    } catch (_) {
      return [];
    }
  }

  // Метод инициализации (вызывается при старте)
  static Future<void> load() async {
    // Ничего не нужно загружать — всё читается лениво
    return;
  }

  static Future<String> getUserFactsForAI() async {
    final facts = await getUserFacts();
    if (facts.isEmpty) return '';
    return "Что я знаю о пользователе:\n${facts.join('\n')}";
  }
}
