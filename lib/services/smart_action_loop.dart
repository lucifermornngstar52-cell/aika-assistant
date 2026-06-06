import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'ai_service.dart';

/// ════════════════════════════════════════════════════════════════════
/// SmartActionLoop v2 — управление телефоном через UI Tree.
///
/// Улучшения на основе OpenClaw Assistant (MIT):
/// https://github.com/yuga-hashimoto/openclaw-assistant
///
/// 1. Динамический поиск приложений через PackageManager (не хардкод!)
/// 2. screenHash() — проверяем изменился ли экран после каждого шага
/// 3. findNodes() — точный поиск узлов по тексту/классу/кликабельности
/// 4. Надёжная цепочка: открыть → найти → нажать → ввести → отправить
/// ════════════════════════════════════════════════════════════════════

class SmartActionLoop {
  static const _a11y = MethodChannel('com.aika.assistant/screen_reader');
  static const int _maxSteps = 10;
  static const int _stepDelayMs = 800;

  // ─── Публичный вход ────────────────────────────────────────────────
  static Future<String> run(String userCommand) async {
    final history = <Map<String, String>>[];
    String lastResult = '';
    String? prevHash;

    for (int step = 0; step < _maxSteps; step++) {
      // 1. Читаем дерево UI
      final uiSnapshot = await _getUiSnapshot();

      // 2. Проверяем screenHash — изменился ли экран (как в OpenClaw)
      final currentHash = await _getScreenHash();
      final screenChanged = prevHash != null && currentHash != prevHash;
      prevHash = currentHash;

      // 3. Строим промпт
      final prompt = _buildPrompt(
        command: userCommand,
        uiSnapshot: uiSnapshot,
        history: history,
        step: step,
        screenChanged: screenChanged,
      );

      // 4. Спрашиваем AI
      final aiRaw = await _askAi(prompt);
      final action = _parseAction(aiRaw);

      if (action == null) {
        lastResult = 'Не смогла разобрать команду.';
        break;
      }
      if (action['action'] == 'done') {
        lastResult = action['message'] as String? ?? 'Готово!';
        break;
      }
      if (action['action'] == 'error') {
        lastResult = action['message'] as String? ?? 'Не удалось выполнить.';
        break;
      }

      // 5. Выполняем
      final resultMsg = await _executeAction(action);
      history.add({'step': '${step + 1}', 'action': aiRaw, 'result': resultMsg});
      lastResult = resultMsg;

      await Future.delayed(const Duration(milliseconds: _stepDelayMs));
    }

    return lastResult;
  }

  // ─── UI Snapshot ───────────────────────────────────────────────────
  static Future<String> _getUiSnapshot() async {
    try {
      final struct = await _a11y.invokeMethod<Map>('getScreenStructure');
      if (struct == null) return '[экран недоступен]';

      final sb = StringBuffer();
      final pkg = struct['package']?.toString() ?? '';
      if (pkg.isNotEmpty) sb.writeln('APP: $pkg');

      final rawText = struct['text']?.toString() ?? '';
      final textLines = rawText
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.length > 1)
          .toSet()
          .take(30);
      if (textLines.isNotEmpty) {
        sb.writeln('=== ТЕКСТ ===');
        textLines.forEach(sb.writeln);
      }

      final buttons = struct['buttons'] as List? ?? [];
      if (buttons.isNotEmpty) {
        sb.writeln('=== ЭЛЕМЕНТЫ ===');
        for (final b in buttons.take(40)) {
          final text     = b['text']?.toString() ?? '';
          final desc     = b['desc']?.toString() ?? '';
          final cls      = b['class']?.toString()?.split('.')?.last ?? '';
          final x        = b['x'] ?? 0;
          final y        = b['y'] ?? 0;
          final id       = b['id']?.toString() ?? '';
          final editable = b['editable'] == true ? '[ПОЛЕ]' : '';
          final scroll   = b['scrollable'] == true ? '[SCROLL]' : '';
          final label    = text.isNotEmpty ? text : (desc.isNotEmpty ? desc : '?');
          sb.writeln('$cls:"$label" id=$id xy=($x,$y) $editable$scroll');
        }
      }

      return sb.toString().trim();
    } catch (e) {
      return '[ошибка чтения: $e]';
    }
  }

  static Future<String> _getScreenHash() async {
    try {
      return await _a11y.invokeMethod<String>('getScreenHash') ?? '';
    } catch (_) { return ''; }
  }

  // ─── Промпт ────────────────────────────────────────────────────────
  static String _buildPrompt({
    required String command,
    required String uiSnapshot,
    required List<Map<String, String>> history,
    required int step,
    bool screenChanged = false,
  }) {
    final historyStr = history.isEmpty ? '' :
        '\n=== ИСТОРИЯ ===\n' +
        history.map((h) => 'Шаг ${h['step']}: ${h['action']} → ${h['result']}').join('\n');

    final changeNote = screenChanged ? '\n[Экран изменился после последнего действия — это хорошо!]' : '';

    return '''Ты — движок управления Android телефоном через AccessibilityService.
Шаг ${step + 1} из $_maxSteps.$changeNote

ЗАДАЧА: "$command"
$historyStr

$uiSnapshot

ПРАВИЛА:
1. click_text — самый надёжный, используй если виден текст
2. find_app — найти package name по названию (когда нужно открыть приложение)
3. type_text — вводить текст в поле [ПОЛЕ]
4. Для WhatsApp: open_app → click_text("Новый чат" или контакт) → type_text → click_text("Отправить")
5. done — когда задача точно выполнена
6. Отвечай ТОЛЬКО JSON без markdown

{"action":"click_text","text":"..."}
{"action":"click_id","id":"..."}
{"action":"click_desc","desc":"..."}
{"action":"type_text","text":"...","clear":true}
{"action":"tap","x":540,"y":1000}
{"action":"long_tap","x":540,"y":1000}
{"action":"swipe","dir":"up|down|left|right"}
{"action":"scroll","dir":"down"}
{"action":"back"}
{"action":"home"}
{"action":"open_app","package":"com.whatsapp"}
{"action":"find_app","name":"spotify"}
{"action":"done","message":"..."}
{"action":"error","message":"..."}''';
  }

  // ─── AI запрос ────────────────────────────────────────────────────
  static Future<String> _askAi(String prompt) async {
    try {
      return await AiService().sendMessage(prompt);
    } catch (e) {
      return '{"action":"error","message":"AI ошибка: $e"}';
    }
  }

  // ─── Парсинг ─────────────────────────────────────────────────────
  static Map<String, dynamic>? _parseAction(String raw) {
    try {
      final start = raw.indexOf('{');
      final end   = raw.lastIndexOf('}');
      if (start == -1 || end == -1) return null;
      return jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) { return null; }
  }

  // ─── Выполнение ──────────────────────────────────────────────────
  static Future<String> _executeAction(Map<String, dynamic> action) async {
    final type = action['action'] as String? ?? '';
    try {
      switch (type) {

        case 'click_text':
          final text = action['text'] as String? ?? '';
          // Пробуем точное совпадение, потом частичное
          final ok1 = await _a11y.invokeMethod<bool>('clickByExactText', {'text': text}) ?? false;
          if (ok1) return 'Нажала "$text"';
          final ok2 = await _a11y.invokeMethod<bool>('clickByText', {'text': text}) ?? false;
          return ok2 ? 'Нажала "$text"' : 'Не нашла "$text"';

        case 'click_id':
          final id = action['id'] as String? ?? '';
          final ok = await _a11y.invokeMethod<bool>('clickById', {'id': id}) ?? false;
          return ok ? 'Нажала id=$id' : 'Не нашла id=$id';

        case 'click_desc':
          final desc = action['desc'] as String? ?? '';
          final ok = await _a11y.invokeMethod<bool>('clickByDescription', {'desc': desc}) ?? false;
          return ok ? 'Нажала "$desc"' : 'Не нашла "$desc"';

        case 'type_text':
          final text  = action['text'] as String? ?? '';
          final clear = action['clear'] as bool? ?? false;
          if (clear) await _a11y.invokeMethod('clearField');
          final ok = await _a11y.invokeMethod<bool>('typeInField', {'hint': '', 'text': text}) ?? false;
          return ok ? 'Ввела: "$text"' : 'Не смогла ввести текст';

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

        case 'swipe':
          final dir = action['dir'] as String? ?? 'down';
          await _a11y.invokeMethod('swipeDir', {'direction': dir});
          return 'Свайп $dir';

        case 'scroll':
          final dir = action['dir'] as String? ?? 'down';
          await _a11y.invokeMethod('scroll', {'direction': dir});
          return 'Прокрутила $dir';

        case 'back':
          await _a11y.invokeMethod('performBack');
          return 'Нажала назад';

        case 'home':
          await _a11y.invokeMethod('pressHome');
          return 'Главный экран';

        case 'open_app':
          final pkg = action['package'] as String? ?? '';
          final ok = await _a11y.invokeMethod<bool>('launchApp', {'package': pkg}) ?? false;
          return ok ? 'Открываю $pkg' : 'Не нашла приложение $pkg';

        // НОВОЕ: динамический поиск приложения по названию (из OpenClaw AppsListCapability)
        case 'find_app':
          final name = action['name'] as String? ?? '';
          final pkg = await _a11y.invokeMethod<String>('findPackageByName', {'name': name});
          if (pkg != null && pkg.isNotEmpty) {
            await _a11y.invokeMethod('launchApp', {'package': pkg});
            return 'Нашла и открываю $name ($pkg)';
          }
          return 'Не нашла приложение "$name" на телефоне';

        default:
          return 'Неизвестное действие: $type';
      }
    } catch (e) {
      return 'Ошибка $type: $e';
    }
  }
}
