import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Сервис умных кликов через Gemini Vision.
/// Получает скриншот → отправляет в Gemini → получает координаты/действие → выполняет.
/// НЕ заменяет AccessibilityService — работает поверх него как "умный слой".
class GeminiComputerUseService {
  static const _screenReaderChannel = MethodChannel('com.aika.assistant/screen_reader');
  static const String _geminiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  // Модель с vision — обычный flash умеет смотреть изображения
  static const String _model = 'gemini-2.0-flash';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  /// Основной метод: получи скриншот и выполни задачу
  /// Возвращает текстовый результат что было сделано
  static Future<String> executeTask(String task) async {
    if (_geminiKey.isEmpty) return 'Нет Gemini API ключа';

    // Шаг 1 — делаем скриншот
    final b64 = await _captureScreen();
    if (b64 == null) return 'Не удалось сделать скриншот — нет разрешения AccessibilityService';

    // Шаг 2 — спрашиваем Gemini что нажать
    final action = await _askGeminiForAction(task, b64);
    if (action == null) return 'Gemini не смог определить действие';

    // Шаг 3 — выполняем действие
    return await _executeAction(action);
  }

  /// Анализ скриншота — найти координаты элемента без нажатия
  static Future<ScreenElement?> findElement(String description, String screenshotB64) async {
    if (_geminiKey.isEmpty) return null;
    return await _askGeminiForCoordinates(description, screenshotB64);
  }

  /// Просто анализируй экран и опиши что видишь
  static Future<String> describeScreen() async {
    if (_geminiKey.isEmpty) return 'Нет Gemini API ключа';
    final b64 = await _captureScreen();
    if (b64 == null) return 'Не удалось сделать скриншот';
    return await _askGeminiDescribe(b64);
  }

  // ── Приватные методы ─────────────────────────────────────────────────

  static Future<String?> _captureScreen() async {
    try {
      return await _screenReaderChannel.invokeMethod<String>('captureScreenBase64', {'quality': 70});
    } catch (_) {
      return null;
    }
  }

  static Future<ComputerUseAction?> _askGeminiForAction(String task, String imageB64) async {
    final prompt = '''
Ты управляешь Android смартфоном. Смотришь на скриншот экрана.
Задача: $task

Ответь ТОЛЬКО в JSON формате (без markdown, без пояснений):
{
  "action": "tap" | "type" | "scroll" | "back" | "home" | "none",
  "x": число (0-1000, координата X для tap),
  "y": число (0-2000, координата Y для tap),
  "text": "текст для ввода (только для action=type)",
  "direction": "up" | "down" | "left" | "right" (только для scroll),
  "reason": "краткое объяснение на русском"
}

Если задача невозможна или уже выполнена — используй action=none.
Координаты: X от 0 (левый край) до 1000 (правый), Y от 0 (верх) до 2000 (низ).
''';

    try {
      final body = {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': imageB64,
                }
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
          'maxOutputTokens': 256,
        }
      };

      final resp = await http.post(
        Uri.parse('$_baseUrl?key=$_geminiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
      if (text == null) return null;

      // Вычищаем markdown если Gemini всё равно добавил
      final clean = text.replaceAll('```json', '').replaceAll('```', '').trim();
      final json = jsonDecode(clean) as Map<String, dynamic>;
      return ComputerUseAction.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<ScreenElement?> _askGeminiForCoordinates(String description, String imageB64) async {
    final prompt = '''
На этом скриншоне найди элемент: "$description"
Ответь ТОЛЬКО в JSON (без markdown):
{"found": true|false, "x": число, "y": число, "label": "что нашёл"}
Координаты: X от 0 до 1000 (ширина экрана), Y от 0 до 2000 (высота).
''';

    try {
      final body = {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {'inline_data': {'mime_type': 'image/jpeg', 'data': imageB64}}
            ]
          }
        ],
        'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 128}
      };

      final resp = await http.post(
        Uri.parse('$_baseUrl?key=$_geminiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
      if (text == null) return null;
      final clean = text.replaceAll('```json', '').replaceAll('```', '').trim();
      final json = jsonDecode(clean) as Map<String, dynamic>;
      if (json['found'] != true) return null;
      return ScreenElement(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        label: json['label'] as String? ?? description,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String> _askGeminiDescribe(String imageB64) async {
    const prompt = 'Опиши коротко что сейчас на экране Android смартфона. '
        'На русском языке, 1-2 предложения.';

    try {
      final body = {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {'inline_data': {'mime_type': 'image/jpeg', 'data': imageB64}}
            ]
          }
        ],
        'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 200}
      };

      final resp = await http.post(
        Uri.parse('$_baseUrl?key=$_geminiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) return 'Ошибка Gemini Vision';
      final data = jsonDecode(resp.body);
      return data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? 'Не удалось описать экран';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  static Future<String> _executeAction(ComputerUseAction action) async {
    try {
      switch (action.type) {
        case 'tap':
          // Нормализуем координаты из 0-1000/0-2000 в реальные пиксели
          // AccessibilityService использует реальные координаты, но мы передаём нормализованные
          // и сервис сам конвертирует
          await _screenReaderChannel.invokeMethod('tapAt', {
            'x': action.x,
            'y': action.y,
          });
          return 'Нажал на координаты (${action.x.toInt()}, ${action.y.toInt()}) — ${action.reason}';

        case 'type':
          await _screenReaderChannel.invokeMethod('typeInField', {'text': action.text});
          return 'Ввёл текст: "${action.text}" — ${action.reason}';

        case 'scroll':
          await _screenReaderChannel.invokeMethod('swipeDir', {'direction': action.direction});
          return 'Прокрутил ${action.direction} — ${action.reason}';

        case 'back':
          await _screenReaderChannel.invokeMethod('performBack');
          return 'Нажал назад — ${action.reason}';

        case 'home':
          await _screenReaderChannel.invokeMethod('pressHome');
          return 'Вышел на главный экран — ${action.reason}';

        case 'none':
          return action.reason;

        default:
          return 'Неизвестное действие: ${action.type}';
      }
    } catch (e) {
      return 'Ошибка выполнения: $e';
    }
  }
}

// ── Модели данных ────────────────────────────────────────────────────────────

class ComputerUseAction {
  final String type;
  final double x;
  final double y;
  final String text;
  final String direction;
  final String reason;

  ComputerUseAction({
    required this.type,
    this.x = 500,
    this.y = 1000,
    this.text = '',
    this.direction = 'down',
    this.reason = '',
  });

  factory ComputerUseAction.fromJson(Map<String, dynamic> json) {
    return ComputerUseAction(
      type:      json['action']    as String? ?? 'none',
      x:         (json['x']        as num?)?.toDouble() ?? 500,
      y:         (json['y']        as num?)?.toDouble() ?? 1000,
      text:      json['text']      as String? ?? '',
      direction: json['direction'] as String? ?? 'down',
      reason:    json['reason']    as String? ?? '',
    );
  }
}

class ScreenElement {
  final double x;
  final double y;
  final String label;
  ScreenElement({required this.x, required this.y, required this.label});
}
