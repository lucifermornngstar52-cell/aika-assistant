import 'dart:async';
import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AlarmEntry {
  final String id;
  final int hour;
  final int minute;
  final String label;
  final bool enabled;

  AlarmEntry({
    required this.id,
    required this.hour,
    required this.minute,
    this.label = '',
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'hour': hour, 'minute': minute,
    'label': label, 'enabled': enabled,
  };

  factory AlarmEntry.fromJson(Map<String, dynamic> j) => AlarmEntry(
    id: j['id'], hour: j['hour'], minute: j['minute'],
    label: j['label'] ?? '', enabled: j['enabled'] ?? true,
  );

  String get timeStr =>
      '${hour.toString().padLeft(2,'0')}:${minute.toString().padLeft(2,'0')}';
}

class AlarmService {
  static const _keyAlarms = 'aika_alarms';
  final _rng = Random();
  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();
  Timer? _ticker;
  Function(String text)? onAlarmFired;

  static const List<String> _wakeMessages = [
    'Доброе утро! Вставай, соня, день тебя ждёт! ☀️',
    'Привет! Будильник сработал — это Айка. Вставай! 🌸',
    'Эй, просыпайся! Мир не будет ждать вечно 😄',
    'Дзинь-дзинь! Пора открывать глаза! ✨',
    'Доброе утро! Ты отлично поспал, теперь вперёд! 🚀',
    'Эй, соня! Уже ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2,"0")}. Пора! 😏',
    'Подъём! Сегодня будет отличный день, обещаю 💪',
  ];

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(
      const InitializationSettings(android: androidSettings),
    );
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    // Проверяем каждые 30 секунд
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _checkAlarms());
  }

  Future<void> _checkAlarms() async {
    final alarms = await getAlarms();
    final now = DateTime.now();
    for (final alarm in alarms) {
      if (!alarm.enabled) continue;
      if (alarm.hour == now.hour && alarm.minute == now.minute) {
        await _fireAlarm(alarm);
      }
    }
  }

  Future<void> _fireAlarm(AlarmEntry alarm) async {
    final msg = _wakeMessages[_rng.nextInt(_wakeMessages.length)];
    final full = alarm.label.isNotEmpty ? '$msg\n(${alarm.label})' : msg;

    // Уведомление
    await _notif.show(
      alarm.id.hashCode,
      '⏰ Будильник Айки',
      full,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'aika_alarm', 'Будильники Айки',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
        ),
      ),
    );

    // Callback → Айка зачитывает вслух
    onAlarmFired?.call(full);
  }

  /// Парсим текстовую команду: "поставь будильник на 7 утра"
  Future<String?> tryParseAlarm(String text) async {
    final t = text.toLowerCase();

    if (!(t.contains('будильник') || t.contains('разбуди') ||
          t.contains('подними меня') || t.contains('буди'))) {
      return null;
    }

    // Удалить / список
    if (t.contains('удали') || t.contains('убери') || t.contains('отмени')) {
      await _deleteAll();
      return 'Все будильники удалены!';
    }
    if (t.contains('список') || t.contains('покажи') || t.contains('какие')) {
      return await _listAlarms();
    }

    // Парсим время HH:MM или "в X утра/вечера"
    final time = _parseTime(t);
    if (time == null) return 'Не понял время. Скажи например: "поставь будильник на 7:30"';

    final alarm = AlarmEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      hour: time[0],
      minute: time[1],
      label: _extractLabel(t),
    );
    await _saveAlarm(alarm);
    return 'Будильник на ${alarm.timeStr} поставлен! ⏰ Разбужу с характером 😄';
  }

  List<int>? _parseTime(String t) {
    // HH:MM
    final re = RegExp(r'(\d{1,2})[:\.](\d{2})');
    final m = re.firstMatch(t);
    if (m != null) {
      final h = int.parse(m.group(1)!);
      final min = int.parse(m.group(2)!);
      if (h < 24 && min < 60) return [h, min];
    }

    // "в 7 утра" / "в 8 вечера" / "в 7" / "на 7"
    final re2 = RegExp(r'(?:в|на)\s+(\d{1,2})(?:\s*(утра|утром|вечера|вечером|ночи|дня))?');
    final m2 = re2.firstMatch(t);
    if (m2 != null) {
      int h = int.parse(m2.group(1)!);
      final period = m2.group(2) ?? '';
      if ((period.contains('вечер') || period.contains('ночи') || period.contains('дня')) && h < 12) {
        h += 12;
      }
      if (h < 24) return [h, 0];
    }

    return null;
  }

  String _extractLabel(String t) {
    if (t.contains('работ')) return 'Работа';
    if (t.contains('тренировк') || t.contains('спортзал') || t.contains('зал')) return 'Тренировка';
    if (t.contains('встреч')) return 'Встреча';
    if (t.contains('школ') || t.contains('учёб') || t.contains('уроки')) return 'Учёба';
    return '';
  }

  Future<List<AlarmEntry>> getAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyAlarms) ?? [];
    return raw.map((s) => AlarmEntry.fromJson(jsonDecode(s))).toList();
  }

  Future<void> _saveAlarm(AlarmEntry alarm) async {
    final alarms = await getAlarms();
    alarms.add(alarm);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyAlarms, alarms.map((a) => jsonEncode(a.toJson())).toList());
  }

  Future<void> _deleteAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAlarms);
  }

  Future<String> _listAlarms() async {
    final alarms = await getAlarms();
    if (alarms.isEmpty) return 'Будильников нет.';
    final buf = StringBuffer('Будильники:\n');
    for (final a in alarms) {
      buf.writeln('⏰ ${a.timeStr}${a.label.isNotEmpty ? " — ${a.label}" : ""}');
    }
    return buf.toString().trim();
  }

  void dispose() => _ticker?.cancel();
}
