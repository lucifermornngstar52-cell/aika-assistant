import 'dart:convert';
import 'package:flutter/services.dart';
import 'ai_service.dart';
import 'smart_action_loop.dart';

/// Универсальный сервис голосового управления телефоном.
/// Читает экран, умно интерпретирует команды через AI, выполняет действия.
class ScreenCommandService {
  static const _reader  = MethodChannel('com.aika.assistant/screen_reader');
  static const _phone   = MethodChannel('com.aika.assistant/screen_reader');
  static const _screen  = MethodChannel('com.aika.assistant/screen');

  // ═══════════════════════════════════════════════════════════════════
  // TRIGGER DETECTION
  // ═══════════════════════════════════════════════════════════════════

  static bool isScreenCommand(String text) {
    final t = text.toLowerCase();
    return t.contains('нажми') || t.contains('кликни') || t.contains('тапни') ||
           t.contains('свайп') || t.contains('смахни') ||
           t.contains('прокрути') || t.contains('листай') || t.contains('мотай') ||
           t.contains('вернись') || t.contains('назад') ||
           t.contains('домой') || t.contains('недавние') ||
           t.contains('шторка') || t.contains('уведомлени') ||
           t.contains('быстрые настройки') || t.contains('скриншот') ||
           t.contains('что на экране') || t.contains('прочитай экран') ||
           t.contains('что написано') || t.contains('что можно нажать') ||
           t.contains('введи текст') || t.contains('напечатай') || t.contains('напиши') ||
           t.contains('заблокируй') || t.contains('потяни') || t.contains('проведи') ||
           t.contains('зажми') || t.contains('долгое нажатие') || t.contains('зажать') ||
           t.contains('дважды нажми') || t.contains('дважды тапни') ||
           t.contains('открой настройки') || t.contains('покажи уведомления') ||
           t.contains('структуру экрана') || t.contains('все кнопки') ||
           t.contains('скопируй') || t.contains('вставь') || t.contains('очисти поле') ||
           t.contains('нажми enter') || t.contains('нажми ок') || t.contains('нажми готово');
  }

  // ═══════════════════════════════════════════════════════════════════
  // MAIN EXECUTE
  // ═══════════════════════════════════════════════════════════════════

  static Future<String> execute(String command) async {
    final t = command.toLowerCase().trim();

    // ── Навигация ──────────────────────────────────────────────────
    if (_is(t, ['назад', 'вернись назад', 'go back', 'back'])) {
      await _reader.invokeMethod('performBack'); return 'Вернулась назад';
    }
    if (_is(t, ['домой', 'на главный', 'home screen', 'go home', 'рабочий стол'])) {
      await _reader.invokeMethod('pressHome'); return 'Перешла на главный экран';
    }
    if (_is(t, ['недавние', 'последние приложения', 'recent apps', 'переключить приложение'])) {
      await _reader.invokeMethod('pressRecents'); return 'Открыла список приложений';
    }
    if (_is(t, ['шторка', 'открой уведомления', 'покажи уведомления'])) {
      await _reader.invokeMethod('openNotifications'); return 'Открыла уведомления';
    }
    if (_is(t, ['быстрые настройки', 'quick settings', 'открой быстрые'])) {
      await _reader.invokeMethod('openQuickSettings'); return 'Открыла быстрые настройки';
    }
    if (_is(t, ['заблокируй', 'заблокируй экран', 'lock screen', 'заблокировать'])) {
      await _reader.invokeMethod('lockScreen'); return 'Экран заблокирован';
    }
    if (_is(t, ['скриншот', 'снимок экрана', 'screenshot', 'сделай скриншот'])) {
      await _reader.invokeMethod('takeScreenshot'); return 'Скриншот сделан';
    }
    if (_is(t, ['меню питания', 'выключить телефон', 'power menu', 'питание'])) {
      await _reader.invokeMethod('powerDialog'); return 'Открыла меню питания';
    }
    if (_is(t, ['разделённый экран', 'split screen', 'режим разделения'])) {
      await _reader.invokeMethod('toggleSplitScreen'); return 'Переключила разделённый экран';
    }

    // ── Скролл ────────────────────────────────────────────────────
    if (_is(t, ['прокрути вниз', 'листай вниз', 'scroll down', 'мотай вниз'])) {
      await _reader.invokeMethod('scroll', {'direction': 'down'}); return 'Прокрутила вниз';
    }
    if (_is(t, ['прокрути вверх', 'листай вверх', 'scroll up', 'мотай вверх'])) {
      await _reader.invokeMethod('scroll', {'direction': 'up'}); return 'Прокрутила вверх';
    }

    // ── Свайпы ────────────────────────────────────────────────────
    if (_is(t, ['свайп влево', 'смахни влево', 'swipe left', 'проведи влево'])) {
      await _reader.invokeMethod('swipe', {'x1': 900.0, 'y1': 1000.0, 'x2': 150.0, 'y2': 1000.0, 'duration': 350});
      return 'Смахнула влево';
    }
    if (_is(t, ['свайп вправо', 'смахни вправо', 'swipe right', 'проведи вправо'])) {
      await _reader.invokeMethod('swipe', {'x1': 150.0, 'y1': 1000.0, 'x2': 900.0, 'y2': 1000.0, 'duration': 350});
      return 'Смахнула вправо';
    }
    if (_is(t, ['свайп вниз', 'смахни вниз', 'swipe down', 'потяни вниз'])) {
      await _reader.invokeMethod('swipe', {'x1': 540.0, 'y1': 300.0, 'x2': 540.0, 'y2': 1600.0, 'duration': 450});
      return 'Смахнула вниз';
    }
    if (_is(t, ['свайп вверх', 'смахни вверх', 'swipe up', 'потяни вверх'])) {
      await _reader.invokeMethod('swipe', {'x1': 540.0, 'y1': 1600.0, 'x2': 540.0, 'y2': 300.0, 'duration': 450});
      return 'Смахнула вверх';
    }

    // ── Чтение экрана ─────────────────────────────────────────────
    if (_is(t, ['что на экране', 'прочитай экран', 'read screen', 'что написано', 'что открыто'])) {
      final text = await _reader.invokeMethod<String>('getScreenText') ?? '';
      if (text.isEmpty) return 'Экран пуст или нет доступа к Accessibility';
      final lines = text.split('\n').where((l) => l.trim().length > 1).toSet().take(30).join('\n');
      return 'На экране:\n$lines';
    }
    if (_is(t, ['структуру экрана', 'детальный экран', 'все элементы'])) {
      final struct = await _reader.invokeMethod<Map>('getScreenStructure');
      if (struct == null) return 'Нет данных';
      final text = struct['text']?.toString() ?? '';
      final btns = (struct['buttons'] as List?)?.take(15).map((e) => '• ${e['text']}').join('\n') ?? '';
      return 'Текст: $text\n\nКнопки:\n$btns';
    }

    // ── Кликабельные элементы ─────────────────────────────────────
    if (_is(t, ['что можно нажать', 'какие кнопки', 'все кнопки', 'что кликабельно'])) {
      final items = await _reader.invokeMethod<List>('getClickableElements') ?? [];
      if (items.isEmpty) return 'Нет кликабельных элементов';
      final texts = items.take(15).map((e) => '• ${e['text']}').join('\n');
      return 'Кнопки на экране:\n$texts';
    }

    // ── Нажатие ───────────────────────────────────────────────────
    if (_containsAny(t, ['нажми на', 'нажать на', 'кликни на', 'тапни на', 'tap on', 'click on'])) {
      final target = _extractAfter(t, ['нажми на', 'нажать на', 'кликни на', 'тапни на', 'tap on', 'click on']);
      if (target != null) {
        final ok = await _reader.invokeMethod<bool>('clickElement', {'text': target}) ?? false;
        return ok ? 'Нажала на "$target"' : 'Не нашла "$target" на экране';
      }
    }

    // ── Долгое нажатие ────────────────────────────────────────────
    if (_containsAny(t, ['зажми', 'долгое нажатие', 'зажать', 'long press', 'long tap'])) {
      final target = _extractAfter(t, ['зажми', 'долгое нажатие на', 'зажать', 'long press']);
      if (target != null) {
        await _reader.invokeMethod('longClickByText', {'text': target});
        return 'Зажала "$target"';
      }
    }

    // ── Двойной тап ───────────────────────────────────────────────
    if (_containsAny(t, ['дважды нажми', 'дважды тапни', 'double tap', 'два раза нажми'])) {
      final target = _extractAfter(t, ['дважды нажми на', 'дважды тапни на', 'double tap']);
      if (target != null) {
        final ok = await _reader.invokeMethod<bool>('clickElementExact', {'text': target}) ?? false;
        return ok ? 'Двойной тап по "$target"' : 'Не нашла "$target"';
      }
    }

    // ── Ввод текста ───────────────────────────────────────────────
    if (_containsAny(t, ['введи текст', 'напечатай', 'напиши', 'type', 'введи в поле'])) {
      final text = _extractAfter(t, ['введи текст', 'напечатай', 'напиши', 'type в поле', 'введи в поле']);
      if (text != null) {
        await _reader.invokeMethod('typeInField', {'hint': '', 'text': text});
        return 'Ввела: "$text"';
      }
    }

    // ── Clipboard ─────────────────────────────────────────────────
    if (_is(t, ['скопируй текст', 'скопировать', 'copy text'])) {
      await _reader.invokeMethod('copySelectedText');
      return 'Скопировала текст';
    }
    if (_is(t, ['вставь текст', 'вставить', 'paste'])) {
      await _reader.invokeMethod('pasteText');
      return 'Вставила текст';
    }
    if (_is(t, ['очисти поле', 'удали текст', 'clear field'])) {
      await _reader.invokeMethod('clearField');
      return 'Поле очищено';
    }

    // ── Enter / OK ────────────────────────────────────────────────
    if (_is(t, ['нажми enter', 'нажми ок', 'нажми готово', 'подтверди', 'отправь'])) {
      await _reader.invokeMethod('pressEnter');
      return 'Нажала Enter';
    }

    // ── AI-умная команда (скрин + AI → действие) ──────────────────
    return await _smartAction(command);
  }

  // ═══════════════════════════════════════════════════════════════════
  // SMART AI ACTION
  // ═══════════════════════════════════════════════════════════════════

  /// SmartActionLoop — многошаговое выполнение через UI Tree.
  /// Читает дерево AccessibilityService как текст (не скриншот),
  /// AI выбирает точный node/действие, цикл до 8 шагов.
  static Future<String> _smartAction(String command) async {
    try {
      return await SmartActionLoop.run(command);
    } catch (e) {
      return 'Не смогла выполнить: $e';
    }
  }

  static Future<String> _executeAiAction(Map<String, dynamic> action) async {
    final type = action['action'] as String? ?? 'none';
    switch (type) {
      case 'click':
        final target = action['target'] as String? ?? '';
        final ok = await _reader.invokeMethod<bool>('clickElement', {'text': target}) ?? false;
        return ok ? 'Нажала на "$target"' : 'Не нашла "$target"';

      case 'click_desc':
        final desc = action['desc'] as String? ?? '';
        await _reader.invokeMethod('clickByDescription', {'desc': desc});
        return 'Нажала на "$desc"';

      case 'tap':
        final x = (action['x'] as num?)?.toDouble() ?? 540.0;
        final y = (action['y'] as num?)?.toDouble() ?? 1000.0;
        await _reader.invokeMethod('tapAt', {'x': x, 'y': y});
        return 'Нажала на координаты ($x, $y)';

      case 'long_tap':
        final x = (action['x'] as num?)?.toDouble() ?? 540.0;
        final y = (action['y'] as num?)?.toDouble() ?? 1000.0;
        await _reader.invokeMethod('longTapAt', {'x': x, 'y': y});
        return 'Долгое нажатие на ($x, $y)';

      case 'double_tap':
        final x = (action['x'] as num?)?.toDouble() ?? 540.0;
        final y = (action['y'] as num?)?.toDouble() ?? 1000.0;
        await _reader.invokeMethod('doubleTapAt', {'x': x, 'y': y});
        return 'Двойной тап на ($x, $y)';

      case 'swipe':
        final dir    = action['direction'] as String? ?? 'down';
        final coords = _swipeCoords(dir);
        await _reader.invokeMethod('swipe', coords);
        return 'Свайп $dir';

      case 'swipe_coords':
        await _reader.invokeMethod('swipe', {
          'x1': (action['x1'] as num?)?.toDouble() ?? 540.0,
          'y1': (action['y1'] as num?)?.toDouble() ?? 1000.0,
          'x2': (action['x2'] as num?)?.toDouble() ?? 540.0,
          'y2': (action['y2'] as num?)?.toDouble() ?? 500.0,
          'duration': action['duration'] as int? ?? 300,
        });
        return 'Свайп выполнен';

      case 'scroll':
        final dir = action['direction'] as String? ?? 'down';
        await _reader.invokeMethod('scroll', {'direction': dir});
        return 'Прокрутила $dir';

      case 'back':
        await _reader.invokeMethod('performBack'); return 'Нажала назад';

      case 'home':
        await _reader.invokeMethod('pressHome'); return 'На главный экран';

      case 'recents':
        await _reader.invokeMethod('pressRecents'); return 'Открыла последние';

      case 'screenshot':
        await _reader.invokeMethod('takeScreenshot'); return 'Скриншот сделан';

      case 'lock':
        await _reader.invokeMethod('lockScreen'); return 'Экран заблокирован';

      case 'notifications':
        await _reader.invokeMethod('openNotifications'); return 'Открыла уведомления';

      case 'quick_settings':
        await _reader.invokeMethod('openQuickSettings'); return 'Открыла быстрые настройки';

      case 'type':
        final text = action['text'] as String? ?? '';
        await _reader.invokeMethod('typeInField', {'hint': '', 'text': text});
        return 'Ввела: "$text"';

      default:
        final reason = action['reason'] as String? ?? '';
        return reason.isNotEmpty ? reason : 'Не поняла команду';
    }
  }

  static Future<String> _fallback(String command) async {
    return 'Не смогла выполнить: "$command". Скажи точнее.';
  }

  // ═══════════════════════════════════════════════════════════════════
  // UTILS
  // ═══════════════════════════════════════════════════════════════════

  static bool _is(String t, List<String> keys) => keys.any((k) => t.contains(k));
  static bool _containsAny(String t, List<String> keys) => keys.any((k) => t.contains(k));

  static String? _extractAfter(String text, List<String> prefixes) {
    for (final prefix in prefixes) {
      final idx = text.indexOf(prefix);
      if (idx != -1) {
        final after = text.substring(idx + prefix.length).trim();
        if (after.isNotEmpty) return after;
      }
    }
    return null;
  }

  static Map<String, dynamic> _swipeCoords(String dir) {
    switch (dir) {
      case 'up':    return {'x1': 540.0, 'y1': 1600.0, 'x2': 540.0, 'y2': 300.0,  'duration': 450};
      case 'down':  return {'x1': 540.0, 'y1': 300.0,  'x2': 540.0, 'y2': 1600.0, 'duration': 450};
      case 'left':  return {'x1': 900.0, 'y1': 1000.0, 'x2': 150.0, 'y2': 1000.0, 'duration': 350};
      case 'right': return {'x1': 150.0, 'y1': 1000.0, 'x2': 900.0, 'y2': 1000.0, 'duration': 350};
      default:      return {'x1': 540.0, 'y1': 300.0,  'x2': 540.0, 'y2': 1600.0, 'duration': 450};
    }
  }

  static String? _extractJson(String text) {
    final start = text.indexOf('{');
    final end   = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }
}
