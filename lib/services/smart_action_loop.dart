import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'ai_service.dart';

/// SmartActionLoop - upravlenie telefonom cherez AccessibilityService.
class SmartActionLoop {
  static const _a11y     = MethodChannel('com.aika.assistant/screen_reader');
  static const _launcher = MethodChannel('com.aika.assistant/launcher');
  static const int _maxSteps    = 8;
  static const int _stepDelayMs = 700;
  static final _ai = AiService();

  static const _systemPrompt =
    'Ty - dvizhok upravleniya Android. Otvechay TOLKO JSON (bez markdown).\n'
    '{"action":"click_text","text":"tekst"} | {"action":"type_text","text":"tekst","clear":true} | '
    '{"action":"tap","x":540,"y":1000} | {"action":"swipe","dir":"up|down|left|right"} | '
    '{"action":"scroll","dir":"up|down"} | {"action":"back"} | {"action":"home"} | '
    '{"action":"open_app","package":"com.example"} | {"action":"done","message":"chto"} | {"action":"error","message":"pochemu"}';

  static Future<String> run(String userCommand) async {
    final history = <Map<String, String>>[];
    String lastResult = '';

    for (int step = 0; step < _maxSteps; step++) {
      final uiSnapshot = await _getUiSnapshot();
      final prompt = _buildPrompt(command: userCommand, uiSnapshot: uiSnapshot, history: history, step: step);
      final aiRaw  = await _ai.sendRawPrompt(systemPrompt: _systemPrompt, userPrompt: prompt);
      final action = _parseAction(aiRaw);

      if (action == null) { lastResult = 'AI ne otvetil korrektno'; break; }
      if (action['action'] == 'done')  { lastResult = action['message'] as String? ?? 'Gotovo!'; break; }
      if (action['action'] == 'error') { lastResult = action['message'] as String? ?? 'Ne udalos.'; break; }

      lastResult = await _executeAction(action);
      history.add({'step': '${step + 1}', 'action': jsonEncode(action), 'result': lastResult});
      await Future.delayed(const Duration(milliseconds: _stepDelayMs));
    }
    return lastResult.isEmpty ? 'Vypolneno' : lastResult;
  }

  static Future<String> _getUiSnapshot() async {
    try {
      final struct = await _a11y.invokeMethod<Map>('getScreenStructure');
      if (struct == null) return '[screen unavailable]';
      final sb = StringBuffer();
      final rawText = struct['text']?.toString() ?? '';
      final textLines = rawText.split('\n').map((l) => l.trim()).where((l) => l.length > 1).toSet().take(20);
      if (textLines.isNotEmpty) sb.writeln('TEXT: ${textLines.join(' | ')}');
      final buttons = struct['buttons'] as List? ?? [];
      if (buttons.isNotEmpty) {
        sb.writeln('ELEMENTS:');
        for (final b in buttons.take(20)) {
          final text  = b['text']?.toString() ?? '';
          final desc  = b['desc']?.toString() ?? '';
          final cls   = (b['class']?.toString() ?? '').split('.').last;
          final x     = b['x'] ?? 0;
          final y     = b['y'] ?? 0;
          final id    = b['id']?.toString() ?? '';
          final edit  = b['editable'] == true ? '[INPUT]' : '';
          final label = text.isNotEmpty ? text : desc;
          if (label.isNotEmpty || edit.isNotEmpty) sb.writeln('  $cls: "$label" id=$id x=$x y=$y $edit');
        }
      }
      return sb.toString().trim();
    } catch (_) { return '[error reading screen]'; }
  }

  static String _buildPrompt({
    required String command, required String uiSnapshot,
    required List<Map<String, String>> history, required int step,
  }) {
    final histStr = history.isEmpty ? '' :
        '\nHISTORY:\n' + history.map((h) => 'Step ${h['step']}: ${h['action']} -> ${h['result']}').join('\n');
    return 'TASK: "$command"$histStr\nSCREEN (step ${step + 1}/$_maxSteps):\n$uiSnapshot';
  }

  static Map<String, dynamic>? _parseAction(String raw) {
    try {
      final start = raw.indexOf('{');
      final end   = raw.lastIndexOf('}');
      if (start == -1 || end == -1) return null;
      return jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) { return null; }
  }

  static Future<String> _executeAction(Map<String, dynamic> action) async {
    final type = action['action'] as String? ?? 'none';
    try {
      switch (type) {
        case 'click_text':
          final text = action['text'] as String? ?? '';
          final ok = await _a11y.invokeMethod<bool>('clickElement', {'text': text}) ?? false;
          if (!ok) {
            final ok2 = await _a11y.invokeMethod<bool>('clickElementExact', {'text': text}) ?? false;
            return ok2 ? 'Nazhala "$text"' : 'Ne nashla "$text"';
          }
          return 'Nazhala "$text"';

        case 'click_id':
          await _a11y.invokeMethod('clickById', {'id': action['id'] ?? ''});
          return 'Nazhala id=${action['id']}';

        case 'type_text':
          final text  = action['text'] as String? ?? '';
          final clear = action['clear'] as bool? ?? false;
          if (clear) await _a11y.invokeMethod('clearField');
          await _a11y.invokeMethod('typeInField', {'text': text});
          return 'Vvela: "$text"';

        case 'tap':
          final x = (action['x'] as num?)?.toDouble() ?? 540.0;
          final y = (action['y'] as num?)?.toDouble() ?? 1000.0;
          await _a11y.invokeMethod('tapAt', {'x': x, 'y': y});
          return 'Nazhala ($x, $y)';

        case 'swipe':
          await _a11y.invokeMethod('swipeDir', {'direction': action['dir'] ?? 'down'});
          return 'Svaip ${action['dir']}';

        case 'scroll':
          await _a11y.invokeMethod('scroll', {'direction': action['dir'] ?? 'down'});
          return 'Prokrutila ${action['dir']}';

        case 'back':
          await _a11y.invokeMethod('performBack'); return 'Nazad';

        case 'home':
          await _a11y.invokeMethod('pressHome'); return 'Na glavny';

        case 'open_app':
          final pkg = action['package'] as String? ?? '';
          await _launcher.invokeMethod('launchApp', {'package': pkg});
          return 'Otkryvayu $pkg';

        default: return 'Neizvestnoe deystvie: $type';
      }
    } catch (e) { return 'Oshibka $type'; }
  }
}
