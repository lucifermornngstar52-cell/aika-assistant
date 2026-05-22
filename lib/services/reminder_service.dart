import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Сервис таймеров и напоминаний.
/// Поддерживает "через N минут/часов" и "в HH:MM".
/// Напоминания сохраняются и переживают перезапуск приложения
/// (через flutter_local_notifications zoned scheduling).
class ReminderService {
  static const _keyReminders = 'aika_reminders_v2';
  static const _alarmChannel = MethodChannel('com.aika.assistant/alarm');

  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();

  Function(String text)? onReminderFired;

  bool _initialized = false;
  bool _tzInitialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    // Timezone
    if (!_tzInitialized) {
      tz_data.initializeTimeZones();
      _tzInitialized = true;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload ?? '';
        onReminderFired?.call(payload);
      },
    );

    // Запрашиваем разрешение на точные будильники (Android 12+)
    final androidPlugin = _notif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    try {
      await androidPlugin?.requestExactAlarmsPermission();
    } catch (_) {}

    _initialized = true;
    await _restoreActiveReminders();
    debugPrint('[Reminder] инициализирован (persistent)');
  }

  // ──────────────────────── ПУБЛИЧНЫЕ МЕТОДЫ ────────────────────────

  Future<String> remindAfter({required Duration duration, required String text}) async {
    final fireAt = DateTime.now().add(duration);
    return await _schedule(text: text, fireAt: fireAt);
  }

  Future<String> remindAt({required int hour, required int minute, required String text}) async {
    var fireAt = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day,
      hour, minute,
    );
    if (fireAt.isBefore(DateTime.now())) {
      fireAt = fireAt.add(const Duration(days: 1));
    }
    return await _schedule(text: text, fireAt: fireAt);
  }

  Future<String?> tryParseReminder(String text) async {
    final t = text.toLowerCase().trim();

    // "напомни через N минут/часов"
    final afterRegex = RegExp(
      r'напомни(?:\s+мне)?\s+через\s+(\d+)\s*(минут|минуту|минуты|час|часа|часов)(.*)',
      caseSensitive: false,
    );
    final afterMatch = afterRegex.firstMatch(t);
    if (afterMatch != null) {
      final amount = int.parse(afterMatch.group(1)!);
      final unit   = afterMatch.group(2)!;
      final what   = _cleanWhat(afterMatch.group(3) ?? '');
      final label  = what.isEmpty ? 'Напоминание' : _capitalize(what);
      final isHours = unit.startsWith('час');
      final duration = isHours ? Duration(hours: amount) : Duration(minutes: amount);
      await remindAfter(duration: duration, text: label);
      final unitStr = isHours ? _pluralHours(amount) : _pluralMinutes(amount);
      return 'Окей, напомню через $amount $unitStr${what.isNotEmpty ? ': "$label"' : ''} ⏰';
    }

    // "напомни в HH:MM"
    final atRegex = RegExp(
      r'напомни(?:\s+мне)?\s+в\s+(\d{1,2})[:\.\s]?(\d{2})(.*)',
      caseSensitive: false,
    );
    final atMatch = atRegex.firstMatch(t);
    if (atMatch != null) {
      final hour   = int.parse(atMatch.group(1)!);
      final minute = int.parse(atMatch.group(2)!);
      final what   = _cleanWhat(atMatch.group(3) ?? '');
      final label  = what.isEmpty ? 'Напоминание' : _capitalize(what);
      await remindAt(hour: hour, minute: minute, text: label);
      return 'Окей, напомню в ${hour.toString().padLeft(2,'0')}:${minute.toString().padLeft(2,'0')}${what.isNotEmpty ? ': "$label"' : ''} ⏰';
    }

    // "таймер на N минут/часов"
    final timerRegex = RegExp(
      r'таймер\s+(?:на\s+)?(\d+)\s*(минут|минуту|минуты|час|часа|часов)',
      caseSensitive: false,
    );
    final timerMatch = timerRegex.firstMatch(t);
    if (timerMatch != null) {
      final amount = int.parse(timerMatch.group(1)!);
      final unit   = timerMatch.group(2)!;
      final isHours = unit.startsWith('час');
      final duration = isHours ? Duration(hours: amount) : Duration(minutes: amount);
      await remindAfter(duration: duration, text: 'Таймер истёк!');
      final unitStr = isHours ? _pluralHours(amount) : _pluralMinutes(amount);
      return 'Таймер на $amount $unitStr запущен! ⏱';
    }

    // "поставь будильник на HH:MM"
    final alarmRegex = RegExp(
      r'(?:поставь|установи|заведи)\s+будильник\s+(?:на\s+)?(\d{1,2})[:\.\s]?(\d{2})',
      caseSensitive: false,
    );
    final alarmMatch = alarmRegex.firstMatch(t);
    if (alarmMatch != null) {
      final hour   = int.parse(alarmMatch.group(1)!);
      final minute = int.parse(alarmMatch.group(2)!);
      await remindAt(hour: hour, minute: minute, text: 'Будильник!');
      return 'Будильник поставила на ${hour.toString().padLeft(2,'0')}:${minute.toString().padLeft(2,'0')} ⏰';
    }

    return null;
  }

  // ──────────────────────── INTERNAL ────────────────────────

  Future<String> _schedule({required String text, required DateTime fireAt}) async {
    final id = fireAt.millisecondsSinceEpoch ~/ 1000 % 2000000000;

    // Сохраняем в SharedPreferences (переживает перезапуск)
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyReminders) ?? '[]';
    final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
    list.add({'id': id, 'text': text, 'fireAt': fireAt.toIso8601String()});
    await prefs.setString(_keyReminders, jsonEncode(list));

    // Планируем через flutter_local_notifications (переживает перезапуск)
    try {
      final tzFireAt = tz.TZDateTime.from(fireAt, tz.local);
      await _notif.zonedSchedule(
        id,
        'Айка напоминает ⏰',
        text,
        tzFireAt,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'aika_reminders',
            'Напоминания Айки',
            channelDescription: 'Голосовые напоминания',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            fullScreenIntent: true,
          ),
        ),
        payload: text,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('[Reminder] запланировано (persistent): "$text" в $fireAt');
    } catch (e) {
      // Fallback: Timer (работает только пока приложение открыто)
      debugPrint('[Reminder] zonedSchedule failed: $e → fallback Timer');
      final delay = fireAt.difference(DateTime.now());
      if (delay.isNegative) return 'OK';
      Timer(delay, () async {
        await _showNotification(id: id, title: 'Айка напоминает ⏰', body: text);
        onReminderFired?.call(text);
        _removeReminder(id);
      });
    }

    return 'OK';
  }

  Future<void> _showNotification({
    required int id, required String title, required String body,
  }) async {
    const details = AndroidNotificationDetails(
      'aika_reminders', 'Напоминания Айки',
      channelDescription: 'Голосовые напоминания',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    await _notif.show(id, title, body,
        const NotificationDetails(android: details), payload: body);
  }

  Future<void> _removeReminder(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyReminders) ?? '[]';
    final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
    list.removeWhere((r) => r['id'] == id);
    await prefs.setString(_keyReminders, jsonEncode(list));
    await _notif.cancel(id);
  }

  Future<void> _restoreActiveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyReminders) ?? '[]';
    final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
    final now = DateTime.now();
    final toRemove = <int>[];

    for (final r in list) {
      try {
        final fireAt = DateTime.parse(r['fireAt']);
        final id = r['id'] as int;
        if (fireAt.isAfter(now)) {
          // Запускаем Timer на случай если zoned notification не сработал
          final delay = fireAt.difference(now);
          Timer(delay, () async {
            await _showNotification(id: id, title: 'Айка напоминает ⏰', body: r['text']);
            onReminderFired?.call(r['text']);
            _removeReminder(id);
          });
          debugPrint('[Reminder] восстановлено: "${r['text']}" через ${delay.inMinutes} мин');
        } else {
          toRemove.add(id);
        }
      } catch (_) {}
    }

    // Чистим просроченные
    if (toRemove.isNotEmpty) {
      final cleaned = list.where((r) => !toRemove.contains(r['id'])).toList();
      await prefs.setString(_keyReminders, jsonEncode(cleaned));
    }
  }

  String _cleanWhat(String s) => s.trim()
      .replaceFirst(RegExp(r'^(что|о том что|что нужно|про|напомни что)\s*',
          caseSensitive: false), '').trim();

  String _pluralMinutes(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'минуту';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'минуты';
    return 'минут';
  }

  String _pluralHours(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'час';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'часа';
    return 'часов';
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
