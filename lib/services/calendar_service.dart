import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// CalendarService — голосовой доступ к системному календарю Android.
/// Читает и создаёт события через нативный канал.
/// Адаптировано из openclaw-assistant CalendarHandler (MIT).
///
/// Команды:
///   "что у меня сегодня", "события на завтра",
///   "добавь встречу [название] в [время]", "напомни о [событии] в [время]"
class CalendarService {
  static final CalendarService _i = CalendarService._();
  factory CalendarService() => _i;
  CalendarService._();

  static const _channel = MethodChannel('com.aika.assistant/calendar');

  // ──────────────────────── ЧИТАТЬ СОБЫТИЯ ──────────────────────────

  Future<List<Map<String, dynamic>>> getEventsForDay(DateTime day) async {
    try {
      final start = DateTime(day.year, day.month, day.day, 0, 0);
      final end   = DateTime(day.year, day.month, day.day, 23, 59);
      final result = await _channel.invokeMethod<List>('getEvents', {
        'startMs': start.millisecondsSinceEpoch,
        'endMs':   end.millisecondsSinceEpoch,
      });
      if (result == null) return [];
      return result.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('[Calendar] getEvents error: $e');
      return [];
    }
  }

  // ──────────────────────── СОЗДАТЬ СОБЫТИЕ ──────────────────────────

  Future<bool> createEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String description = '',
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('createEvent', {
        'title':       title,
        'startMs':     start.millisecondsSinceEpoch,
        'endMs':       end.millisecondsSinceEpoch,
        'description': description,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[Calendar] createEvent error: $e');
      return false;
    }
  }

  // ──────────────────────── ГОЛОСОВОЙ ПАРСЕР ──────────────────────────

  Future<String?> parseCommand(String input) async {
    final t = input.toLowerCase().trim();

    // Показать события сегодня
    if (_matches(t, ['что сегодня', 'события сегодня', 'что у меня сегодня',
                      'расписание на сегодня', 'план на сегодня'])) {
      return await _describeDay(DateTime.now());
    }

    // Показать события завтра
    if (_matches(t, ['что завтра', 'события завтра', 'расписание на завтра', 'план на завтра'])) {
      return await _describeDay(DateTime.now().add(const Duration(days: 1)));
    }

    // Создать событие: "добавь встречу X в 15:00"
    for (final trigger in ['добавь событие', 'добавь встречу', 'создай событие',
                            'запиши в календарь', 'добавь в календарь']) {
      if (t.contains(trigger)) {
        return await _parseCreateEvent(input, trigger);
      }
    }

    return null;
  }

  // ──────────────────────── ВСПОМОГАТЕЛЬНЫЕ ──────────────────────────

  Future<String> _describeDay(DateTime day) async {
    final events = await getEventsForDay(day);
    if (events.isEmpty) {
      final label = _isSameDay(day, DateTime.now()) ? 'сегодня' : 'завтра';
      return 'На $label событий нет.';
    }
    final label = _isSameDay(day, DateTime.now()) ? 'Сегодня' : 'Завтра';
    final list = events.take(5).map((e) {
      final title = e['title']?.toString() ?? 'Без названия';
      final startMs = e['startMs'] as int?;
      if (startMs == null) return '• $title';
      final t = DateTime.fromMillisecondsSinceEpoch(startMs);
      return '• ${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')} — $title';
    }).join('\n');
    return '$label ${events.length} событий:\n$list';
  }

  Future<String> _parseCreateEvent(String input, String trigger) async {
    String rest = input.substring(
      input.toLowerCase().indexOf(trigger) + trigger.length,
    ).trim();

    // Ищем время "в HH:MM" или "в X часов"
    DateTime? startTime;
    String title = rest;

    final timeRx = RegExp(r'в\s+(\d{1,2})(?::(\d{2}))?(\s*час)?', caseSensitive: false);
    final match = timeRx.firstMatch(rest);
    if (match != null) {
      final hour = int.tryParse(match.group(1) ?? '') ?? 0;
      final min  = int.tryParse(match.group(2) ?? '') ?? 0;
      final now  = DateTime.now();
      startTime  = DateTime(now.year, now.month, now.day, hour, min);
      title = rest.replaceAll(match.group(0)!, '').trim();
    }

    startTime ??= DateTime.now().add(const Duration(hours: 1));
    final endTime = startTime.add(const Duration(hours: 1));

    final ok = await createEvent(title: title.isEmpty ? 'Событие' : title, start: startTime, end: endTime);
    if (!ok) return 'Не удалось добавить событие. Проверь разрешения календаря.';

    final timeStr = '${startTime.hour.toString().padLeft(2,'0')}:${startTime.minute.toString().padLeft(2,'0')}';
    return 'Добавила "${title.isEmpty ? "Событие" : title}" в $timeStr.';
  }

  bool _matches(String text, List<String> triggers) =>
      triggers.any((tr) => text.contains(tr));

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
