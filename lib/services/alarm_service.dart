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
  final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();
  Timer? _ticker;
  Function(String text)? onAlarmFired;

  // Сообщения зависят от времени суток и дня недели
  String _getWakeMessage(int hour, int weekday) {
    // Понедельник = 1, Воскресенье = 7
    final isWeekend = weekday >= 6;
    final isEarly   = hour < 7;
    final isMorning = hour >= 7 && hour < 10;

    if (isWeekend && isEarly) {
      return [
        'Эй, в выходной так рано? Ты уверен? 😅',
        'Серьёзно? В выходной — и уже встаёшь! 🤯',
        'Это точно не ошибка? Суббота же... 😴',
      ][_rng.nextInt(3)];
    }

    if (isWeekend) {
      return [
        'Доброе утро! Выходной — никуда не торопись 🌿',
        'Подъём, соня! Хотя... выходной, можно ещё поваляться 😄',
        'Доброе утро в выходной! Что сегодня планируешь? ☕',
      ][_rng.nextInt(3)];
    }

    if (isEarly) {
      return [
        'Очень ранний подъём! Ты точно чемпион 💪',
        'Ого, так рано! Завтрак уже ждёт 🍳',
        'Тёмно ещё снаружи, но ты уже герой! 🌙→☀️',
      ][_rng.nextInt(3)];
    }

    if (weekday == 1) { // Понедельник
      return [
        'Доброе утро, понедельник! Новая неделя — новые победы 🚀',
        'Понедельник — день тяжёлый, но ты справишься! 💪',
        'Привет! Новая неделя началась. Ты готов? ✨',
      ][_rng.nextInt(3)];
    }

    if (weekday == 5) { // Пятница
      return [
        'Пятница! Почти выходные, давай! 🎉',
        'Доброе утро! Сегодня пятница — финишная прямая 🏁',
        'Подъём! Пятница — лучший день недели 😎',
      ][_rng.nextInt(3)];
    }

    if (isMorning) {
      return [
        'Доброе утро! Вставай, день тебя ждёт ☀️',
        'Привет! Айка здесь. Время просыпаться! 🌸',
        'Подъём! Сегодня будет отличный день 💫',
        'Дзинь! Пора открывать глаза ✨',
        'Доброе утро, соня! Вперёд! 😄',
      ][_rng.nextInt(5)];
    }

    // Дневное/вечернее время
    return [
      'Бип-бип! Твой будильник, напоминаю ⏰',
      'Эй, не забудь — будильник! 📍',
      'Напоминание! Что-то важное было в это время 💡',
    ][_rng.nextInt(3)];
  }


  // Personality-based wake messages
  String _getPersonalityWakeMessage(String personality, int hour, int weekday) {
    final isWeekend = weekday >= 6;
    switch (personality) {
      case 'tsundere':
        return isWeekend
            ? ['Вставай уже! Я... я не из-за тебя разбудила, просто так! 😤',
               'Ладно-ладно, просыпайся. Не думай что мне не всё равно! 🙄',
               'Буди себя сам! Хотя... ладно, вставай. Бэка! 😳'][_rng.nextInt(3)]
            : ['Подъём! И не смей опять засыпать, слышишь?! 😠',
               'Эй! Ты вообще меня слышишь?! Вставай!! 💢',
               'Я же сказала — подъём! Не заставляй меня злиться! 😤'][_rng.nextInt(3)];
      case 'cold':
        return ['Время пробуждения. Рекомендую встать сразу.',
               'Будильник. Оптимальное время для подъёма.',
               'Зафиксировано: ${hour.toString().padLeft(2,"0")}:00. Пора вставать.'][_rng.nextInt(3)];
      case 'gabimaru':
        return ['Подъём, боец! Слабых здесь нет! ⚔️',
               'Утро — время для тренировки! Вставай! 🔥',
               'Ещё одно утро — ещё один шанс стать сильнее! 💪'][_rng.nextInt(3)];
      case 'sensei':
        return ['Доброе утро. Новый день — новая мудрость ждёт 🌅',
               'Пробуждение — это малое рождение. Встречай день с благодарностью 🌸',
               'Утро тихое, разум ясный. Самое время начать 🍵'][_rng.nextInt(3)];
      default: // miya (милая)
        return isWeekend
            ? ['Доброе утро~! Я скучала! ☀️✨',
               'Хэй, соня! Просыпайся, я жду тебя~ 🌸',
               'Доброе утро! Сегодня выходной — давай проведём его весело! 💕'][_rng.nextInt(3)]
            : ['Доброе утро! Вставай, я уже скучаю~ 💕',
               'Хэй-хэй! Новый день! Я здесь~ 🌺',
               'Просыпайся! Сегодня будет отличный день, обещаю! ✨'][_rng.nextInt(3)];
    }
  }

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(
      const InitializationSettings(android: androidSettings),
    );
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
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
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final personality = prefs.getString('aika_personality') ?? 'miya';
    final msg = _getPersonalityWakeMessage(personality, now.hour, now.weekday);
    final full = alarm.label.isNotEmpty ? '$msg\n📌 ${alarm.label}' : msg;

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

    onAlarmFired?.call(full);
  }

  Future<String?> tryParseAlarm(String text) async {
    final t = text.toLowerCase();

    if (!(t.contains('будильник') || t.contains('разбуди') ||
          t.contains('подними меня') || t.contains('буди'))) {
      return null;
    }

    if (t.contains('удали') || t.contains('убери') || t.contains('отмени')) {
      await _deleteAll();
      return 'Все будильники удалены!';
    }
    if (t.contains('список') || t.contains('покажи') || t.contains('какие')) {
      return await _listAlarms();
    }

    final time = _parseTime(t);
    if (time == null) return 'Не понял время. Скажи например: "поставь будильник на 7:30"';

    final alarm = AlarmEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      hour: time[0],
      minute: time[1],
      label: _extractLabel(t),
    );
    await _saveAlarm(alarm);

    final now = DateTime.now();
    final fireAt = DateTime(now.year, now.month, now.day, time[0], time[1]);
    final diff = fireAt.isAfter(now)
        ? fireAt.difference(now)
        : fireAt.add(const Duration(days: 1)).difference(now);
    final hoursLeft = diff.inHours;
    final minsLeft  = diff.inMinutes % 60;
    final leftStr   = hoursLeft > 0
        ? 'через $hoursLeft ч $minsLeft мин'
        : 'через $minsLeft мин';

    return 'Будильник на ${alarm.timeStr} поставлен! ⏰ Разбужу $leftStr с характером 😄';
  }

  List<int>? _parseTime(String t) {
    final re = RegExp(r'(\d{1,2})[:\.](\d{2})');
    final m = re.firstMatch(t);
    if (m != null) {
      final h = int.parse(m.group(1)!);
      final min = int.parse(m.group(2)!);
      if (h < 24 && min < 60) return [h, min];
    }

    final re2 = RegExp(r'(?:в|на)\s+(\d{1,2})(?:\s*(утра|утром|вечера|вечером|ночи|дня))?');
    final m2 = re2.firstMatch(t);
    if (m2 != null) {
      int h = int.parse(m2.group(1)!);
      final period = m2.group(2) ?? '';
      if ((period.contains('вечер') || period.contains('ночи') || period.contains('дня')) && h < 12) h += 12;
      if (h < 24) return [h, 0];
    }

    return null;
  }

  String _extractLabel(String t) {
    if (t.contains('работ')) return 'Работа';
    if (t.contains('тренировк') || t.contains('спортзал')) return 'Тренировка';
    if (t.contains('встреч')) return 'Встреча';
    if (t.contains('школ') || t.contains('учёб') || t.contains('уроки')) return 'Учёба';
    if (t.contains('врач') || t.contains('больниц')) return 'Врач';
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

