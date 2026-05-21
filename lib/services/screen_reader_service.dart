import 'package:flutter/services.dart';

/// Читает реальный текстовый контент с экрана через AccessibilityService
class ScreenReaderService {
  static const _channel = MethodChannel('com.aika.assistant/screen_reader');

  /// Получает весь текст с текущего экрана (через Accessibility)
  static Future<String?> getScreenText() async {
    try {
      final result = await _channel.invokeMethod<String>('getScreenText');
      return result?.isNotEmpty == true ? result : null;
    } catch (_) {
      return null;
    }
  }

  /// Получает структурированный контент — заголовки, кнопки, поля ввода
  static Future<Map<String, dynamic>?> getScreenStructure() async {
    try {
      final result = await _channel.invokeMethod<Map>('getScreenStructure');
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (_) {
      return null;
    }
  }

  /// Клик по элементу с текстом
  static Future<bool> clickElement(String text) async {
    try {
      return await _channel.invokeMethod<bool>('clickElement', {'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Прокрутка экрана
  static Future<void> scrollDown() async {
    try { await _channel.invokeMethod('scroll', {'direction': 'down'}); } catch (_) {}
  }

  static Future<void> scrollUp() async {
    try { await _channel.invokeMethod('scroll', {'direction': 'up'}); } catch (_) {}
  }

  /// Вернуться назад
  static Future<void> goBack() async {
    try { await _channel.invokeMethod('performBack'); } catch (_) {}
  }

  /// Форматирует текст экрана для отправки в AI
  static String formatForAI(String rawText, String appLabel) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.length > 2)
        .toSet() // убираем дубли
        .take(40) // максимум 40 строк
        .join('\n');
    return '=== СОДЕРЖИМОЕ ЭКРАНА ($appLabel) ===\n$lines';
  }

  /// Проверяем нужно ли читать экран для этого запроса
  static bool isScreenReadRequest(String text) {
    final t = text.toLowerCase();
    return t.contains('что на экране') ||
        t.contains('что написано') ||
        t.contains('прочитай экран') ||
        t.contains('что там') ||
        t.contains('что вижу') ||
        t.contains('что открыто') ||
        t.contains('прочитай страницу') ||
        t.contains('что в приложении') ||
        t.contains('переведи') && t.contains('экран') ||
        t.contains('суммаризируй') ||
        t.contains('кратко что') ||
        t.contains('о чём статья') ||
        t.contains('о чём пост') ||
        t.contains('что за видео');
  }

  /// Команды действий на экране
  static bool isScreenActionRequest(String text) {
    final t = text.toLowerCase();
    return t.contains('нажми') ||
        t.contains('кликни') ||
        t.contains('нажать') ||
        t.contains('листай вниз') ||
        t.contains('листай вверх') ||
        t.contains('прокрути') ||
        t.contains('вернись назад') ||
        t.contains('назад');
  }

  static Future<String?> tryHandleAction(String text) async {
    final t = text.toLowerCase();
    if (t.contains('листай вниз') || t.contains('прокрути вниз')) {
      await scrollDown();
      return 'Прокрутила вниз ↓';
    }
    if (t.contains('листай вверх') || t.contains('прокрути вверх')) {
      await scrollUp();
      return 'Прокрутила вверх ↑';
    }
    if (t.contains('вернись назад') || (t.contains('назад') && t.length < 20)) {
      await goBack();
      return 'Вернулась назад ←';
    }
    // Нажатие по тексту: "нажми на Отмена"
    final clickMatch = RegExp(r'нажми(?:\s+на)?\s+(.+)', caseSensitive: false).firstMatch(t);
    if (clickMatch != null) {
      final target = clickMatch.group(1)?.trim() ?? '';
      if (target.isNotEmpty) {
        final ok = await clickElement(target);
        return ok ? 'Нажала на "$target" ✓' : 'Не нашла кнопку "$target" на экране';
      }
    }
    return null;
  }
}
