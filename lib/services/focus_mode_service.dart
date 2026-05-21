import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class FocusModeService {
  static bool _isActive = false;
  static Timer? _timer;
  static int _minutesLeft = 0;
  static Function(String)? onMessage;

  static bool get isActive => _isActive;

  static bool isFocusCommand(String text) {
    final t = text.toLowerCase();
    return (t.contains('режим фокуса') || t.contains('фокус') || t.contains('pomodoro') || t.contains('помодоро'))
        && (t.contains('войди') || t.contains('включи') || t.contains('старт') || t.contains('начни') || t.contains('запусти'));
  }

  static bool isStopCommand(String text) {
    final t = text.toLowerCase();
    return _isActive && (t.contains('выйди из фокуса') || t.contains('стоп фокус') || t.contains('отмени фокус') || t.contains('выключи фокус'));
  }

  static int _parseMinutes(String text) {
    final match = RegExp(r'(\d+)\s*(минут|мин)').firstMatch(text.toLowerCase());
    if (match != null) return int.parse(match.group(1)!);
    if (text.contains('час')) return 60;
    return 25; // default pomodoro
  }

  static Future<String> startFocus(String text) async {
    final minutes = _parseMinutes(text);
    _isActive = true;
    _minutesLeft = minutes;

    _timer?.cancel();
    _timer = Timer(Duration(minutes: minutes), () {
      _isActive = false;
      onMessage?.call('🎉 Фокус-сессия завершена! Ты отлично поработал — заслуженный перерыв 10 минут! 💪');
    });

    // Напоминание на половине пути
    Timer(Duration(minutes: minutes ~/ 2), () {
      if (_isActive) {
        onMessage?.call('⏱ Половина пути! Ещё ${minutes ~/ 2} минут — ты справляешься!');
      }
    });

    return '🎯 Режим фокуса включён на $minutes минут!\n\n'
        'Я заблокирую отвлечения и напомню когда время выйдет.\n'
        'Чтобы остановить — скажи "стоп фокус".';
  }

  static String stopFocus() {
    _isActive = false;
    _timer?.cancel();
    return '⏹ Режим фокуса остановлен. Сколько успел сделать? 😊';
  }

  static Future<String?> tryHandle(String text) async {
    if (isStopCommand(text)) return stopFocus();
    if (isFocusCommand(text)) return await startFocus(text);
    return null;
  }
}
