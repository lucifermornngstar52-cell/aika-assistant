import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Умная память привычек пользователя.
/// Запоминает паттерны поведения и предлагает их в нужный момент.
class HabitMemoryService {
  static const _habitsKey = 'habit_memory_v1';

  // ── Структура привычек ─────────────────────────────────────
  static Map<String, dynamic> _habits = {};

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_habitsKey);
    if (raw != null) {
      try { _habits = Map<String, dynamic>.from(jsonDecode(raw)); } catch (_) {}
    }
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_habitsKey, jsonEncode(_habits));
  }

  // ── Запись событий ─────────────────────────────────────────

  /// Записываем время отхода ко сну
  static Future<void> recordSleepTime() async {
    await load();
    final hour = DateTime.now().hour;
    final times = List<int>.from(_habits['sleep_times'] ?? []);
    times.add(hour);
    if (times.length > 14) times.removeAt(0); // 2 недели
    _habits['sleep_times'] = times;
    await _save();
  }

  /// Записываем запрос пользователя для анализа частых тем
  static Future<void> recordRequest(String text) async {
    await load();
    final t = text.toLowerCase();

    // Музыка
    if (_containsAny(t, ['музык', 'spotify', 'ютуб', 'включи', 'поставь песню'])) {
      _habits['music_requests'] = (_habits['music_requests'] ?? 0) + 1;
    }
    // Погода
    if (_containsAny(t, ['погода', 'температура', 'дождь', 'холодно', 'тепло'])) {
      _habits['weather_requests'] = (_habits['weather_requests'] ?? 0) + 1;
    }
    // Напоминания
    if (_containsAny(t, ['напомни', 'reminder', 'не забудь', 'через'])) {
      _habits['reminder_requests'] = (_habits['reminder_requests'] ?? 0) + 1;
    }
    // Время последней активности
    _habits['last_active_hour'] = DateTime.now().hour;
    await _save();
  }

  // ── Проактивные подсказки ──────────────────────────────────

  /// Проверяет — есть ли что предложить пользователю прямо сейчас.
  /// Вызывать раз в несколько минут из основного экрана.
  static Future<String?> getProactiveSuggestion() async {
    await load();
    final now = DateTime.now();

    // Подсказка про сон
    final sleepSuggestion = _getSleepSuggestion(now);
    if (sleepSuggestion != null) return sleepSuggestion;

    // Подсказка про музыку вечером
    if (now.hour >= 20 && now.hour <= 23) {
      final musicCount = _habits['music_requests'] ?? 0;
      if (musicCount >= 5) {
        // Показываем раз в день
        final lastMusicHint = _habits['last_music_hint_day'];
        final today = '${now.year}-${now.month}-${now.day}';
        if (lastMusicHint != today) {
          _habits['last_music_hint_day'] = today;
          await _save();
          return 'Вечер настал 🎵 Обычно ты слушаешь музыку — включить что-нибудь?';
        }
      }
    }

    return null;
  }

  static String? _getSleepSuggestion(DateTime now) {
    final times = List<int>.from(_habits['sleep_times'] ?? []);
    if (times.length < 5) return null; // недостаточно данных

    // Средний час отхода ко сну
    final avg = times.reduce((a, b) => a + b) ~/ times.length;
    final nowHour = now.hour;

    // Если сейчас за 15 минут до обычного времени сна
    // (проверяем в конце часа: минуты 45-59)
    if (now.minute >= 45 && nowHour == avg - 1) {
      final lastSleepHint = _habits['last_sleep_hint_day'];
      final today = '${now.year}-${now.month}-${now.day}';
      if (lastSleepHint != today) {
        _habits['last_sleep_hint_day'] = today;
        _save();
        final displayHour = avg.toString().padLeft(2, '0');
        return 'Обычно ты ложишься в $displayHour:00, уже ${nowHour.toString().padLeft(2,'0')}:${now.minute} 🌙';
      }
    }
    return null;
  }

  // ── Геттеры для системного промпта ────────────────────────

  /// Возвращает контекст привычек для AI
  static String getContextForAI() {
    if (_habits.isEmpty) return '';
    final sb = StringBuffer('== ПРИВЫЧКИ ПОЛЬЗОВАТЕЛЯ ==\n');
    final times = List<int>.from(_habits['sleep_times'] ?? []);
    if (times.length >= 3) {
      final avg = times.reduce((a, b) => a + b) ~/ times.length;
      sb.writeln('Обычно ложится спать около $avg:00.');
    }
    final music = _habits['music_requests'] ?? 0;
    if (music >= 3) sb.writeln('Часто просит включить музыку.');
    final weather = _habits['weather_requests'] ?? 0;
    if (weather >= 3) sb.writeln('Регулярно интересуется погодой.');
    return sb.toString();
  }

  static bool _containsAny(String text, List<String> words) =>
      words.any((w) => text.contains(w));
}
