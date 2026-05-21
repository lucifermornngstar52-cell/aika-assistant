import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MoodDiaryService {
  static const _key = 'mood_diary_entries';

  Future<void> saveMood(String mood, int score) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? '[]';
    final List entries = json.decode(raw);
    entries.add({
      'date': DateTime.now().toIso8601String(),
      'mood': mood,
      'score': score,
    });
    // Оставляем только последние 30 дней
    if (entries.length > 30) entries.removeRange(0, entries.length - 30);
    await prefs.setString(_key, json.encode(entries));
  }

  Future<List<Map>> getEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? '[]';
    return List<Map>.from(json.decode(raw));
  }

  Future<String> getWeekSummary() async {
    final entries = await getEntries();
    if (entries.isEmpty) return '📊 Пока нет записей настроения. Скажи "моё настроение" чтобы начать!';

    final week = entries.where((e) {
      final d = DateTime.parse(e['date']);
      return DateTime.now().difference(d).inDays <= 7;
    }).toList();

    if (week.isEmpty) return '📊 За последнюю неделю нет записей.';

    final avg = week.map((e) => (e['score'] as num).toDouble()).reduce((a, b) => a + b) / week.length;
    final best = week.reduce((a, b) => (a['score'] as num) > (b['score'] as num) ? a : b);
    final worst = week.reduce((a, b) => (a['score'] as num) < (b['score'] as num) ? a : b);

    final emoji = avg >= 8 ? '🌟' : avg >= 6 ? '😊' : avg >= 4 ? '😐' : '😔';
    return '$emoji Дневник настроения за неделю:\n\n'
        '• Среднее: ${avg.toStringAsFixed(1)}/10\n'
        '• Лучший день: ${_formatDate(best['date'])} — ${best['mood']}\n'
        '• Тяжёлый день: ${_formatDate(worst['date'])} — ${worst['mood']}\n'
        '• Записей: ${week.length}';
  }

  String _formatDate(String iso) {
    final d = DateTime.parse(iso);
    return '${d.day}.${d.month}';
  }

  bool isMoodRequest(String text) {
    final t = text.toLowerCase();
    return t.contains('моё настроение') || t.contains('мое настроение') ||
        t.contains('дневник настроения') || t.contains('как я себя чувствую') ||
        t.contains('настроение за неделю') || t.contains('статистика настроения');
  }

  bool isMoodReport(String text) {
    final t = text.toLowerCase();
    return t.contains('настроение') && (
        t.contains('отлично') || t.contains('хорошо') || t.contains('норм') ||
        t.contains('плохо') || t.contains('ужасно') || t.contains('супер') ||
        t.contains('грустно') || t.contains('счастлив') || t.contains('устал'));
  }

  int scoreFromText(String text) {
    final t = text.toLowerCase();
    if (t.contains('отлично') || t.contains('супер') || t.contains('счастлив')) return 10;
    if (t.contains('хорошо') || t.contains('класс') || t.contains('замечательно')) return 8;
    if (t.contains('норм') || t.contains('нормально') || t.contains('средне')) return 5;
    if (t.contains('устал') || t.contains('так себе')) return 4;
    if (t.contains('плохо') || t.contains('грустно')) return 3;
    if (t.contains('ужасно') || t.contains('кошмар')) return 1;
    return 5;
  }

  Future<String?> tryHandle(String text) async {
    if (isMoodRequest(text)) {
      return await getWeekSummary();
    }
    if (isMoodReport(text)) {
      final score = scoreFromText(text);
      await saveMood(text, score);
      if (score >= 8) return '🌟 Рада за тебя! Запомнила — сегодня было ${score}/10.';
      if (score >= 5) return '😊 Окей, запомнила настроение. Главное держись!';
      return '🤗 Запомнила. Если хочешь поговорить — я здесь. ${score}/10 сегодня.';
    }
    return null;
  }
}
