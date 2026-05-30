import 'dart:convert';
import 'package:flutter/services.dart';
import 'ai_service.dart';

/// Универсальный сервис голосового управления экраном.
/// Принимает любую команду → решает что делать через AI или напрямую → выполняет.
class ScreenCommandService {
  static const _reader  = MethodChannel('com.aika.assistant/screen_reader');
  static const _phone   = MethodChannel('aika/phone_control');
  static const _screen  = MethodChannel('com.aika.assistant/screen');

  /// Определяет — это команда управления экраном?
  static bool isScreenCommand(String text) {
    final t = text.toLowerCase();
    return t.contains('нажми') || t.contains('кликни') ||
           t.contains('свайп') || t.contains('смахни') ||
           t.contains('прокрути') || t.contains('листай') ||
           t.contains('вернись') || t.contains('назад') ||
           t.contains('домой') || t.contains('недавние') ||
           t.contains('шторка') || t.contains('уведомлени') ||
           t.contains('быстрые настройки') ||
           t.contains('что на экране') || t.contains('прочитай экран') ||
           t.contains('что написано') || t.contains('что можно нажать') ||
           t.contains('введи текст') || t.contains('напечатай') ||
           t.contains('заблокируй экран') ||
           t.contains('потяни') || t.contains('проведи');
   }

    /// Главный метод — принимает голосовую команду, выполняет действие.
  /// Возвращает текст-ответ для Айки.
  static Future<String> execute(String command) async {
    final t = command.toLowerCase().trim();

    // ── Навигация ──────────────────────────────────────────────
    if (_is(t, ['назад', 'вернись', 'go back', 'back'])) {
      await _reader.invokeMethod('performBack');
      return 'Вернулась назад';
    }
    if (_is(t, ['домой', 'на главный', 'home screen', 'go home'])) {
      await _reader.invokeMethod('pressHome');
      return 'Перешла на главный экран';
    }
    if (_is(t, ['недавние', 'последние приложения', 'recent apps', 'переключить приложение'])) {
      await _reader.invokeMethod('pressRecents');
      return 'Открыла список приложений';
    }
    if (_is(t, ['шторка', 'уведомления', 'открой уведомления', 'notification'])) {
      await _reader.invokeMethod('openNotifications');
      return 'Открыла уведомления';
    }
    if (_is(t, ['быстрые настройки', 'quick settings', 'открой быстрые'])) {
      await _reader.invokeMethod('openQuickSettings');
      return 'Открыла быстрые настройки';
    }
    if (_is(t, ['заблокируй экран', 'lock screen', 'заблокировать'])) {
      await _reader.invokeMethod('lockScreen');
      return 'Экран заблокирован';
    }

    // ── Скролл ─────────────────────────────────────────────────
    if (_is(t, ['прокрути вниз', 'листай вниз', 'scroll down', 'вниз'])) {
      await _reader.invokeMethod('scroll', {'direction': 'down'});
      return 'Прокрутила вниз';
    }
    if (_is(t, ['прокрути вверх', 'листай вверх', 'scroll up', 'вверх'])) {
      await _reader.invokeMethod('scroll', {'direction': 'up'});
      return 'Прокрутила вверх';
    }

    // ── Читать экран ───────────────────────────────────────────
    if (_is(t, ['что на экране', 'прочитай экран', 'read screen', 'что написано'])) {
      final text = await _reader.invokeMethod<String>('getScreenText') ?? '';
      if (text.isEmpty) return 'Экран пуст или нет доступа';
      return 'На экране: $text';
    }

    // ── Нажать на элемент ──────────────────────────────────────
    if (_is(t, ['нажми на', 'нажать на', 'кликни на', 'tap on', 'click on'])) {
      final target = _extractAfter(t, ['нажми на', 'нажать на', 'кликни на', 'tap on', 'click on']);
      if (target != null) {
        final ok = await _reader.invokeMethod<bool>('clickElement', {'text': target}) ?? false;
        return ok ? 'Нажала на "$target"' : 'Не нашла "$target" на экране';
      }
    }

    // ── Ввод текста ────────────────────────────────────────────
    if (_is(t, ['введи текст', 'напечатай', 'type', 'введи в поле'])) {
      final text = _extractAfter(t, ['введи текст', 'напечатай', 'type', 'введи в поле']);
      if (text != null) {
        final focused = await _reader.invokeMethod<Map>('getFocusedElement');
        if (focused != null) {
          await _reader.invokeMethod('typeInField', {'hint': '', 'text': text});
          return 'Ввела текст: "$text"';
        }
        return 'Нет активного поля ввода';
      }
    }

    // ── Свайп ──────────────────────────────────────────────────
    if (_is(t, ['свайп влево', 'смахни влево', 'swipe left'])) {
      await _reader.invokeMethod('swipe', {'x1': 800.0, 'y1': 1000.0, 'x2': 200.0, 'y2': 1000.0, 'duration': 300});
      return 'Смахнула влево';
    }
    if (_is(t, ['свайп вправо', 'смахни вправо', 'swipe right'])) {
      await _reader.invokeMethod('swipe', {'x1': 200.0, 'y1': 1000.0, 'x2': 800.0, 'y2': 1000.0, 'duration': 300});
      return 'Смахнула вправо';
    }
    if (_is(t, ['свайп вниз', 'смахни вниз', 'swipe down', 'потяни вниз'])) {
      await _reader.invokeMethod('swipe', {'x1': 540.0, 'y1': 400.0, 'x2': 540.0, 'y2': 1400.0, 'duration': 400});
      return 'Смахнула вниз';
    }
    if (_is(t, ['свайп вверх', 'смахни вверх', 'swipe up', 'потяни вверх'])) {
      await _reader.invokeMethod('swipe', {'x1': 540.0, 'y1': 1400.0, 'x2': 540.0, 'y2': 400.0, 'duration': 400});
      return 'Смахнула вверх';
    }

    // ── Список кнопок на экране ────────────────────────────────
    if (_is(t, ['что можно нажать', 'какие кнопки', 'list buttons', 'что на экране кликабельно'])) {
      final items = await _reader.invokeMethod<List>('getClickableElements') ?? [];
      if (items.isEmpty) return 'Нет кликабельных элементов';
      final texts = items.take(10).map((e) => '• ${e['text']}').join('\n');
      return 'Кнопки на экране:\n$texts';
    }

    // ── Умная команда через AI (скрин + запрос) ────────────────
    // Читаем экран и просим AI решить что нажать
    return await _smartAction(command);
  }

  /// Умное действие: читаем экран → AI решает что делать → выполняем
  static Future<String> _smartAction(String command) async {
    try {
      // Читаем текущий экран
      final screenText = await _reader.invokeMethod<String>('getScreenText') ?? '';
      final elements = await _reader.invokeMethod<List>('getClickableElements') ?? [];

      final elemList = elements.take(20)
          .map((e) => '"${e['text']}" (id: ${e['id']}, x:${e['x']}, y:${e['y']})')
          .join('\n');

      final prompt = '''
Ты управляешь Android телефоном через Accessibility API.
Текущий экран содержит следующий текст:
$screenText

Кликабельные элементы:
$elemList

Пользователь сказал: "$command"

Ответь СТРОГО в JSON формате, одним действием:
{"action": "click", "target": "текст кнопки"}
{"action": "swipe", "direction": "up|down|left|right"}
{"action": "back"}
{"action": "home"}
{"action": "type", "text": "текст для ввода"}
{"action": "scroll", "direction": "up|down"}
{"action": "tap", "x": 540, "y": 1000}
{"action": "none", "reason": "не понял команду"}

Только JSON, без объяснений.
''';

      final aiService = AiService();
      final aiResponse = await aiService.sendMessage(prompt);
      final jsonStr = _extractJson(aiResponse);
      if (jsonStr == null) return await _fallback(command);

      final Map<String, dynamic> action = jsonDecode(jsonStr);
      return await _executeAiAction(action);
    } catch (e) {
      return await _fallback(command);
    }
  }

  static Future<String> _executeAiAction(Map<String, dynamic> action) async {
    final type = action['action'] as String? ?? 'none';
    switch (type) {
      case 'click':
        final target = action['target'] as String? ?? '';
        final ok = await _reader.invokeMethod<bool>('clickElement', {'text': target}) ?? false;
        return ok ? 'Нажала на "$target"' : 'Не нашла "$target"';

      case 'swipe':
        final dir = action['direction'] as String? ?? 'down';
        final coords = _swipeCoords(dir);
        await _reader.invokeMethod('swipe', coords);
        return 'Свайп $dir';

      case 'back':
        await _reader.invokeMethod('performBack');
        return 'Нажала назад';

      case 'home':
        await _reader.invokeMethod('pressHome');
        return 'На главный экран';

      case 'type':
        final text = action['text'] as String? ?? '';
        await _reader.invokeMethod('typeInField', {'hint': '', 'text': text});
        return 'Ввела: "$text"';

      case 'scroll':
        final dir = action['direction'] as String? ?? 'down';
        await _reader.invokeMethod('scroll', {'direction': dir});
        return 'Прокрутила $dir';

      case 'tap':
        final x = (action['x'] as num?)?.toDouble() ?? 540.0;
        final y = (action['y'] as num?)?.toDouble() ?? 1000.0;
        await _reader.invokeMethod('tapAt', {'x': x, 'y': y});
        return 'Нажала на экран';

      default:
        final reason = action['reason'] as String? ?? '';
        return reason.isNotEmpty ? reason : 'Не поняла что делать';
    }
  }

  static Future<String> _fallback(String command) async {
    return 'Не смогла выполнить: "$command". Скажи точнее что нажать или открыть.';
  }

  static Map<String, dynamic> _swipeCoords(String dir) {
    switch (dir) {
      case 'up':   return {'x1': 540.0, 'y1': 1400.0, 'x2': 540.0, 'y2': 400.0,  'duration': 400};
      case 'down': return {'x1': 540.0, 'y1': 400.0,  'x2': 540.0, 'y2': 1400.0, 'duration': 400};
      case 'left': return {'x1': 800.0, 'y1': 1000.0, 'x2': 200.0, 'y2': 1000.0, 'duration': 300};
      case 'right':return {'x1': 200.0, 'y1': 1000.0, 'x2': 800.0, 'y2': 1000.0, 'duration': 300};
      default:     return {'x1': 540.0, 'y1': 400.0,  'x2': 540.0, 'y2': 1400.0, 'duration': 400};
    }
  }

  static String? _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  static bool _is(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  static String? _extractAfter(String text, List<String> prefixes) {
    for (final prefix in prefixes) {
      final idx = text.indexOf(prefix);
      if (idx != -1) {
        final result = text.substring(idx + prefix.length).trim();
        if (result.isNotEmpty) return result;
      }
    }
    return null;
  }
}
