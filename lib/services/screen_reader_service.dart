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

extension PhoneControl on ScreenReaderService {
  // ── Управление жестами ──────────────────────────────────────────────────

  static Future<void> tapAt(double x, double y) async {
    try { await _channel.invokeMethod('tapAt', {'x': x, 'y': y}); } catch (_) {}
  }

  static Future<void> longTapAt(double x, double y) async {
    try { await _channel.invokeMethod('longTapAt', {'x': x, 'y': y}); } catch (_) {}
  }

  static Future<void> swipe(double x1, double y1, double x2, double y2, {int durationMs = 300}) async {
    try {
      await _channel.invokeMethod('swipe', {
        'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'duration': durationMs
      });
    } catch (_) {}
  }

  // Стандартные свайпы по экрану
  static Future<void> swipeLeft()  async => swipe(800, 960, 280, 960);
  static Future<void> swipeRight() async => swipe(280, 960, 800, 960);
  static Future<void> swipeUp()    async => swipe(540, 1600, 540, 400);
  static Future<void> swipeDown()  async => swipe(540, 400, 540, 1600);

  // ── Системные кнопки ─────────────────────────────────────────────────────

  static Future<void> pressHome()          async {
    try { await _channel.invokeMethod('pressHome'); } catch (_) {}
  }
  static Future<void> pressRecents()       async {
    try { await _channel.invokeMethod('pressRecents'); } catch (_) {}
  }
  static Future<void> openNotifications()  async {
    try { await _channel.invokeMethod('openNotifications'); } catch (_) {}
  }
  static Future<void> openQuickSettings()  async {
    try { await _channel.invokeMethod('openQuickSettings'); } catch (_) {}
  }

  // ── Ввод текста ──────────────────────────────────────────────────────────

  static Future<bool> typeText(String text) async {
    try {
      return await _channel.invokeMethod<bool>('typeText', {'text': text}) ?? false;
    } catch (_) { return false; }
  }

  static Future<bool> clearText() async {
    try { return await _channel.invokeMethod<bool>('clearText') ?? false; } catch (_) { return false; }
  }

  static Future<bool> pressEnter() async {
    try { return await _channel.invokeMethod<bool>('pressEnter') ?? false; } catch (_) { return false; }
  }

  // ── Размер экрана ────────────────────────────────────────────────────────
  static Future<Map<String, int>> getScreenSize() async {
    try {
      final r = await _channel.invokeMethod<Map>('getScreenSize');
      if (r != null) return {'width': r['width'] as int, 'height': r['height'] as int};
    } catch (_) {}
    return {'width': 1080, 'height': 1920};
  }

  // ── Парсер голосовых команд управления ───────────────────────────────────
  static bool isPhoneControlRequest(String text) {
    final t = text.toLowerCase();
    return t.contains('нажми home') || t.contains('домой') ||
           t.contains('кнопка home') || t.contains('на главный') ||
           t.contains('недавние') || t.contains('последние приложения') ||
           t.contains('шторка') || t.contains('уведомления открой') ||
           t.contains('быстрые настройки') ||
           t.contains('свайп') || t.contains('проведи') ||
           t.contains('напиши в поле') || t.contains('введи текст') ||
           t.contains('нажми enter') || t.contains('подтверди');
  }

  static Future<String?> tryHandlePhoneControl(String text) async {
    final t = text.toLowerCase();

    if (t.contains('home') || t.contains('домой') || t.contains('главный экран')) {
      await pressHome(); return 'Нажала Home 🏠';
    }
    if (t.contains('недавние') || t.contains('последние приложения')) {
      await pressRecents(); return 'Открыла список приложений 📱';
    }
    if (t.contains('шторка') || t.contains('уведомления открой') || t.contains('открой уведомления')) {
      await openNotifications(); return 'Открыла уведомления 🔔';
    }
    if (t.contains('быстрые настройки')) {
      await openQuickSettings(); return 'Открыла быстрые настройки ⚙️';
    }
    if (t.contains('свайп влево') || t.contains('проведи влево')) {
      await swipeLeft(); return 'Свайп влево ←';
    }
    if (t.contains('свайп вправо') || t.contains('проведи вправо')) {
      await swipeRight(); return 'Свайп вправо →';
    }
    if (t.contains('свайп вверх') || t.contains('проведи вверх')) {
      await swipeUp(); return 'Свайп вверх ↑';
    }
    if (t.contains('свайп вниз') || t.contains('проведи вниз')) {
      await swipeDown(); return 'Свайп вниз ↓';
    }
    if (t.contains('нажми enter') || t.contains('подтверди') || t.contains('отправь')) {
      await pressEnter(); return 'Нажала Enter ✓';
    }
    // Ввод текста: "напиши в поле Привет"
    final typeMatch = RegExp(r'(?:напиши в поле|введи текст|напечатай)\s+(.+)', caseSensitive: false).firstMatch(t);
    if (typeMatch != null) {
      final txt = typeMatch.group(1)?.trim() ?? '';
      if (txt.isNotEmpty) {
        final ok = await typeText(txt);
        return ok ? 'Ввела "$txt" ✓' : 'Не нашла поле для ввода';
      }
    }
    return null;
  }
}
