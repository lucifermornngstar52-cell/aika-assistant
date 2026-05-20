import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис таймеров и напоминаний.
/// Поддерживает "через N минут/часов" и "в HH:MM".
class ReminderService {
  static const _keyReminders = 'aika_reminders';

  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();

  Function(String text)? onReminderFired; // callback → Айка зачитывает вслух

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload ?? '';
        onReminderFired?.call(payload);
      },
    );
    _initialized = true;
    _restoreActiveReminders();
    debugPrint('[Reminder] инициализирован');
  }

  // ──────────────────────── ПУБЛИЧНЫЕ МЕТОДЫ ────────────────────────

  /// Установить напоминание через N минут/часов
  Future<String> remindAfter({
    required Duration duration,
    required String text,
  }) async {
    final fireAt = DateTime.now().add(duration);
    return await _schedule(text: text, fireAt: fireAt);
  }

  /// Установить напоминание на конкретное время сегодня
  Future<String> remindAt({
    required int hour,
    required int minute,
    required String text,
  }) async {
    var fireAt = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day,
      hour, minute,
    );
    if (fireAt.isBefore(DateTime.now())) {
      fireAt = fireAt.add(const Duration(days: 1)); // завтра
    }
    return await _schedule(text: text, fireAt: fireAt);
  }

  /// Парсит голосовую команду и устанавливает напоминание.
  /// Возвращает строку-ответ или null если не распознал.
  Future<String?> tryParseReminder(String text) async {
    final t = text.toLowerCase().trim();

    // "напомни через N минут/часов [что сделать]"
    final afterRegex = RegExp(
      r'напомни(?:\s+мне)?\s+через\s+(\d+)\s*(минут|минуту|минуты|час|часа|часов)(.*)$',
      caseSensitive: false,
    );
    final afterMatch = afterRegex.firstMatch(t);
    if (afterMatch != null) {
      final amount = int.parse(afterMatch.group(1)!);
      final unit   = afterMatch.group(2)!;
      final what   = afterMatch.group(3)!.trim()
          .replaceFirst(RegExp(r'^(что|о том что|что нужно|про)\s*'), '').trim();
      final label  = what.isEmpty ? 'Напоминание' : _capitalize(what);

      final isHours = unit.startsWith('час');
      final duration = isHours
          ? Duration(hours: amount)
          : Duration(minutes: amount);

      await remindAfter(duration: duration, text: label);

      final unitStr = isHours
          ? _pluralHours(amount)
          : _pluralMinutes(amount);
      return 'Окей, напомню через $amount $unitStr${what.isNotEmpty ? ': $label' : ''}';
    }

    // "напомни в HH:MM [что]"
    final atRegex = RegExp(
      r'напомни(?:\s+мне)?\s+в\s+(\d{1,2})[:\.]?(\d{2})(.*)$',
      caseSensitive: false,
    );
    final atMatch = atRegex.firstMatch(t);
    if (atMatch != null) {
      final hour   = int.parse(atMatch.group(1)!);
      final minute = int.parse(atMatch.group(2)!);
      final what   = atMatch.group(3)!.trim()
          .replaceFirst(RegExp(r'^(что|о том что|что нужно|про)\s*'), '').trim();
      final label  = what.isEmpty ? 'Напоминание' : _capitalize(what);

      await remindAt(hour: hour, minute: minute, text: label);

      return 'Окей, напомню в ${hour.toString().padLeft(2,'0')}:${minute.toString().padLeft(2,'0')}${what.isNotEmpty ? ': $label' : ''}';
    }

    // "таймер на N минут"
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
      return 'Таймер на $amount $unitStr запущен!';
    }

    return null;
  }

  // ──────────────────────── INTERNAL ────────────────────────

  Future<String> _schedule({required String text, required DateTime fireAt}) async {
    final id = fireAt.millisecondsSinceEpoch ~/ 1000 % 100000;

    // Сохраняем в prefs
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyReminders) ?? '[]';
    final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
    list.add({'id': id, 'text': text, 'fireAt': fireAt.toIso8601String()});
    await prefs.setString(_keyReminders, jsonEncode(list));

    // Показываем уведомление через Duration
    final delay = fireAt.difference(DateTime.now());
    Timer(delay, () async {
      await _showNotification(id: id, title: 'Айка напоминает', body: text);
      onReminderFired?.call(text);
      _removeReminder(id);
    });

    debugPrint('[Reminder] запланировано: "$text" в $fireAt');
    return 'OK';
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const details = AndroidNotificationDetails(
      'aika_reminders',
      'Напоминания Айки',
      channelDescription: 'Голосовые напоминания',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );
    await _notif.show(id, title, body, const NotificationDetails(android: details), payload: body);
  }

  Future<void> _removeReminder(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyReminders) ?? '[]';
    final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
    list.removeWhere((r) => r['id'] == id);
    await prefs.setString(_keyReminders, jsonEncode(list));
  }

  void _restoreActiveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyReminders) ?? '[]';
    final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
    final now = DateTime.now();
    for (final r in list) {
      final fireAt = DateTime.parse(r['fireAt']);
      if (fireAt.isAfter(now)) {
        final delay = fireAt.difference(now);
        Timer(delay, () async {
          await _showNotification(
            id: r['id'], title: 'Айка напоминает', body: r['text']);
          onReminderFired?.call(r['text']);
          _removeReminder(r['id']);
        });
        debugPrint('[Reminder] восстановлено: "${r['text']}" через ${delay.inMinutes} мин');
      }
    }
  }

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
