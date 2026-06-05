import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'ai_service.dart';

/// ════════════════════════════════════════════════════════════════════
/// SmartActionLoop — безотказное управление телефоном через UI Tree.
///
/// Принцип работы:
/// 1. Читаем AccessibilityTree → компактный текст (50-200 токенов)
/// 2. AI (GPT-4o-mini) выбирает ТОЧНОЕ действие по тексту/nodeId
/// 3. Выполняем через performAction (не tapAt по координатам!)
/// 4. Ждём 600мс → читаем новое дерево → следующий шаг
/// 5. До 8 шагов или пока задача не выполнена
///
/// ПРЕИМУЩЕСТВО перед скриншотом:
/// - Не угадываем координаты — кликаем на конкретный node
/// - Работает в любом приложении (WhatsApp, банки, TikTok)
/// - 30x дешевле по токенам
/// - Не ломается от смены темы/шрифта/разрешения
/// ════════════════════════════════════════════════════════════════════

class SmartActionLoop {
  static const _a11y = MethodChannel('com.aika.assistant/screen_reader');
  static const int _maxSteps = 8;
  static const int _stepDelayMs = 700;

  // ─── Публичный вход ────────────────────────────────────────────────

  /// Выполняет задачу пользователя в несколько шагов.
  /// Возвращает итоговый ответ для озвучки.
  static Future<String> run(String userCommand) async {
    final history = <Map<String, String>>[];
    String lastResult = '';

    for (int step = 0; step < _maxSteps; step++) {
      // 1. Читаем дерево UI
      final uiSnapshot = await _getUiSnapshot();

      // 2. Строим промпт
      final prompt = _buildPrompt(
        command: userCommand,
        uiSnapshot: uiSnapshot,
        history: history,
        step: step,
      );

      // 3. Спрашиваем AI
      final aiRaw = await _askAi(prompt);
      final action = _parseAction(aiRaw);

      if (action == null) {
        lastResult = 'Не смогла разобрать команду.';
        break;
      }

      // 4. Если задача выполнена — выходим
      if (action['action'] == 'done') {
        lastResult = action['message'] as String? ?? 'Готово!';
        break;
      }
      if (action['action'] == 'error') {
        lastResult = action['message'] as String? ?? 'Не удалось выполнить.';
        break;
      }

      // 5. Выполняем действие
      final resultMsg = await _executeAction(action);
      history.add({'step': '${step + 1}', 'action': aiRaw, 'result': resultMsg});
      lastResult = resultMsg;

      // 6. Пауза — ждём пока UI обновится
      await Future.delayed(const Duration(milliseconds: _stepDelayMs));
    }

    return lastResult;
  }

  // ─── UI Snapshot ───────────────────────────────────────────────────

  /// Читает дерево UI и возвращает компактный текст для AI.
  /// Формат: "BUTTON:Отправить(540,1200) TEXT:Привет... EDIT:(пусто)"
  static Future<String> _getUiSnapshot() async {
    try {
      final struct = await _a11y.invokeMethod<Map>('getScreenStructure');
      if (struct == null) return '[экран недоступен]';

      final sb = StringBuffer();

      // Текст на экране (уникальные строки, не более 30)
      final rawText = struct['text']?.toString() ?? '';
      final textLines = rawText
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.length > 1)
          .toSet()
          .take(30);
      if (textLines.isNotEmpty) {
        sb.writeln('=== ТЕКСТ НА ЭКРАНЕ ===');
        textLines.forEach(sb.writeln);
      }

      // Кликабельные элементы
      final buttons = struct['buttons'] as List? ?? [];
      if (buttons.isNotEmpty) {
        sb.writeln('=== КНОПКИ И ПОЛЯ ===');
        for (final b in buttons.take(30)) {
          final text  = b['text']?.toString() ?? '';
          final desc  = b['desc']?.toString() ?? '';
          final cls   = b['class']?.toString()?.split('.')?.last ?? '';
          final x     = b['x'] ?? 0;
          final y     = b['y'] ?? 0;
          final id    = b['id']?.toString() ?? '';
          final editable = b['editable'] == true ? '[ПОЛЕ_ВВОДА]' : '';
          final label = text.isNotEmpty ? text : desc;
          if (label.isNotEmpty || editable.isNotEmpty) {
            sb.writeln('$cls: "$label" id=$id x=$x y=$y $editable');
          }
        }
      }

      return sb.toString().trim();
    } catch (e) {
      return '[ошибка чтения экрана: $e]';
    }
  }

  // ─── Промпт ────────────────────────────────────────────────────────

  static String _buildPrompt({
    required String command,
    required String uiSnapshot,
    required List<Map<String, String>> history,
    required int step,
  }) {
    final historyStr = history.isEmpty
        ? ''
        : '\n=== ИСТОРИЯ ШАГОВ ===\n' +
          history.map((h) => 'Шаг ${h['step']}: ${h['action']} → ${h['result']}').join('\n');

    return '''
Ты — движок управления Android телефоном. Работаешь через AccessibilityService.
Шаг ${step + 1} из $_maxSteps.

ЗАДАЧА ПОЛЬЗОВАТЕЛЯ: "$command"
$historyStr

=== ТЕКУЩЕЕ СОСТОЯНИЕ ЭКРАНА ===
$uiSnapshot

ПРАВИЛА ВЫБОРА ДЕЙСТВИЯ:
1. Если нашёл нужный элемент по тексту — используй click_text (самый надёжный!)
2. Если есть resource id — используй click_id
3. Если нужно ввести текст — используй type_text (найди поле по hint/class EditText)
4. tap по координатам — ТОЛЬКО если ничего другого нет
5. Если задача полностью выполнена — action: done
6. Если невозможно выполнить — action: error

ОТВЕТЬ СТРОГО В JSON (один объект, без markdown):
{"action": "click_text",   "text": "точный текст кнопки"}
{"action": "click_id",     "id": "resource.id.кнопки"}
{"action": "click_desc",   "desc": "content-description"}
{"action": "type_text",    "text": "текст для ввода", "clear": true}
{"action": "tap",          "x": 540, "y": 1000}
{"action": "long_tap",     "x": 540, "y": 1000}
{"action": "swipe",        "dir": "up|down|left|right"}
{"action": "back"}
{"action": "home"}
{"action": "scroll",       "dir": "up|down"}
{"action": "open_app",     "package": "com.whatsapp"}
{"action": "done",         "message": "что сделала"}
{"action": "error",        "message": "почему не могу"}
''';
  }

  // ─── AI запрос ────────────────────────────────────────────────────

  static Future<String> _askAi(String prompt) async {
    try {
      final ai = AiService();
      return await ai.sendMessage(prompt);
    } catch (e) {
      return '{"action":"error","message":"AI недоступен: $e"}';
    }
  }

  // ─── Парсинг ответа AI ────────────────────────────────────────────

  static Map<String, dynamic>? _parseAction(String raw) {
    try {
      // Ищем JSON в ответе
      final start = raw.indexOf('{');
      final end   = raw.lastIndexOf('}');
      if (start == -1 || end == -1) return null;
      return jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ─── Выполнение действия ─────────────────────────────────────────

  static Future<String> _executeAction(Map<String, dynamic> action) async {
    final type = action['action'] as String? ?? 'none';

    try {
      switch (type) {

        // ── Клик по тексту (самый надёжный) ──────────────────────
        case 'click_text':
          final text = action['text'] as String? ?? '';
          final ok = await _a11y.invokeMethod<bool>('clickElement', {'text': text}) ?? false;
          if (!ok) {
            // Fallback: ищем через containsText
            final ok2 = await _a11y.invokeMethod<bool>('clickByExactText', {'text': text}) ?? false;
            return ok2 ? 'Нажала "$text"' : 'Не нашла "$text" на экране';
          }
          return 'Нажала "$text"';

        // ── Клик по resource id ──────────────────────────────────
        case 'click_id':
          final id = action['id'] as String? ?? '';
          await _a11y.invokeMethod('clickById', {'id': id});
          return 'Нажала элемент id=$id';

        // ── Клик по content-description ──────────────────────────
        case 'click_desc':
          final desc = action['desc'] as String? ?? '';
          await _a11y.invokeMethod('clickByDescription', {'desc': desc});
          return 'Нажала "$desc"';

        // ── Ввод текста ───────────────────────────────────────────
        case 'type_text':
          final text  = action['text'] as String? ?? '';
          final clear = action['clear'] as bool? ?? false;
          if (clear) await _a11y.invokeMethod('clearField');
          await _a11y.invokeMethod('typeInField', {'hint': '', 'text': text});
          return 'Ввела: "$text"';

        // ── Тап по координатам ────────────────────────────────────
        case 'tap':
          final x = (action['x'] as num?)?.toDouble() ?? 540.0;
          final y = (action['y'] as num?)?.toDouble() ?? 1000.0;
          await _a11y.invokeMethod('tapAt', {'x': x, 'y': y});
          return 'Нажала ($x, $y)';

        case 'long_tap':
          final x = (action['x'] as num?)?.toDouble() ?? 540.0;
          final y = (action['y'] as num?)?.toDouble() ?? 1000.0;
          await _a11y.invokeMethod('longTapAt', {'x': x, 'y': y});
          return 'Долгое нажатие ($x, $y)';

        // ── Свайп ────────────────────────────────────────────────
        case 'swipe':
          final dir = action['dir'] as String? ?? 'down';
          await _a11y.invokeMethod('swipeDir', {'direction': dir});
          return 'Свайп $dir';

        // ── Прокрутка ─────────────────────────────────────────────
        case 'scroll':
          final dir = action['dir'] as String? ?? 'down';
          await _a11y.invokeMethod('scroll', {'direction': dir});
          return 'Прокрутила $dir';

        // ── Навигация ─────────────────────────────────────────────
        case 'back':
          await _a11y.invokeMethod('performBack');
          return 'Нажала назад';

        case 'home':
          await _a11y.invokeMethod('pressHome');
          return 'На главный экран';

        // ── Открыть приложение ────────────────────────────────────
        case 'open_app':
          final pkg = action['package'] as String? ?? '';
          await _a11y.invokeMethod('launchApp', {'package': pkg});
          return 'Открываю $pkg';

        default:
          return 'Неизвестное действие: $type';
      }
    } catch (e) {
      return 'Ошибка выполнения $type: $e';
    }
  }
}
