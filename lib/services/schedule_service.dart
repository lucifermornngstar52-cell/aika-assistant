import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleEvent {
  final String id;
  final String title;
  final int hour;
  final int minute;
  final String date; // yyyy-MM-dd
  final String note;

  ScheduleEvent({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    required this.date,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'hour': hour,
    'minute': minute,
    'date': date,
    'note': note,
  };

  factory ScheduleEvent.fromJson(Map<String, dynamic> j) => ScheduleEvent(
    id: j['id'],
    title: j['title'],
    hour: j['hour'],
    minute: j['minute'],
    date: j['date'],
    note: j['note'] ?? '',
  );

  String get timeStr => '${hour.toString().padLeft(2,'0')}:${minute.toString().padLeft(2,'0')}';
}

class ScheduleService {
  static const _key = 'aika_schedule_events';

  Future<List<ScheduleEvent>> getEvents({String? date}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? '[]';
    final List all = json.decode(raw);
    final events = all.map((e) => ScheduleEvent.fromJson(Map<String,dynamic>.from(e))).toList();
    if (date != null) {
      return events.where((e) => e.date == date).toList()
        ..sort((a,b) => a.hour != b.hour ? a.hour.compareTo(b.hour) : a.minute.compareTo(b.minute));
    }
    return events..sort((a,b) {
      final cmp = a.date.compareTo(b.date);
      return cmp != 0 ? cmp : a.hour != b.hour ? a.hour.compareTo(b.hour) : a.minute.compareTo(b.minute);
    });
  }

  Future<void> addEvent(ScheduleEvent event) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? '[]';
    final List all = json.decode(raw);
    all.add(event.toJson());
    await prefs.setString(_key, json.encode(all));
  }

  Future<void> deleteEvent(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? '[]';
    final List all = json.decode(raw);
    all.removeWhere((e) => e['id'] == id);
    await prefs.setString(_key, json.encode(all));
  }

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }

  String _tomorrowStr() {
    final n = DateTime.now().add(const Duration(days: 1));
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }

  Future<String> getTodaySchedule() async {
    final events = await getEvents(date: _todayStr());
    if (events.isEmpty) return '📅 На сегодня ничего не запланировано. Скажи "добавь событие" чтобы начать!';
    final buf = StringBuffer('📅 Расписание на сегодня:\n\n');
    for (final e in events) {
      buf.writeln('🕐 ${e.timeStr} — ${e.title}${e.note.isNotEmpty ? '\n   📝 ${e.note}' : ''}');
    }
    return buf.toString().trim();
  }

  Future<String> getTomorrowSchedule() async {
    final events = await getEvents(date: _tomorrowStr());
    if (events.isEmpty) return '📅 На завтра ничего не запланировано.';
    final buf = StringBuffer('📅 Расписание на завтра:\n\n');
    for (final e in events) {
      buf.writeln('🕐 ${e.timeStr} — ${e.title}');
    }
    return buf.toString().trim();
  }

  bool isScheduleRequest(String text) {
    final t = text.toLowerCase();
    return t.contains('расписание') || t.contains('план на') ||
        t.contains('что сегодня') || t.contains('что завтра') ||
        t.contains('мои события') || t.contains('мой день');
  }

  bool isAddEventRequest(String text) {
    final t = text.toLowerCase();
    return (t.contains('добавь') || t.contains('запомни') || t.contains('поставь') || t.contains('занеси')) &&
        (t.contains('событие') || t.contains('встреч') || t.contains('в ') && RegExp(r'\d{1,2}:\d{2}').hasMatch(t) ||
        t.contains('в ') && RegExp(r'в \d{1,2}').hasMatch(t));
  }

  Future<String?> tryParseAddEvent(String text) async {
    if (!isAddEventRequest(text)) return null;

    final timeMatch = RegExp(r'(\d{1,2})[:\.](\d{2})').firstMatch(text);
    final hourMatch = RegExp(r'в (\d{1,2})(?!\d)').firstMatch(text);

    int hour = 12, minute = 0;
    if (timeMatch != null) {
      hour = int.parse(timeMatch.group(1)!);
      minute = int.parse(timeMatch.group(2)!);
    } else if (hourMatch != null) {
      hour = int.parse(hourMatch.group(1)!);
    } else {
      return null;
    }

    // Определяем дату
    final t = text.toLowerCase();
    String date = _todayStr();
    if (t.contains('завтра')) date = _tomorrowStr();

    // Название события — всё что не время и не служебные слова
    String title = text
        .replaceAll(RegExp(r'добавь|запомни|поставь|занеси|событие|встречу|встреча|завтра|сегодня', caseSensitive: false), '')
        .replaceAll(RegExp(r'\d{1,2}[:.]\d{2}'), '')
        .replaceAll(RegExp(r'в \d{1,2}(?!\d)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.isEmpty) title = 'Событие';

    final event = ScheduleEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      hour: hour,
      minute: minute,
      date: date,
    );
    await addEvent(event);
    return '✅ Записала! ${t.contains('завтра') ? 'Завтра' : 'Сегодня'} в ${event.timeStr} — ${event.title}';
  }
}
