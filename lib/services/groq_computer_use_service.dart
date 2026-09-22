import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Сервис умных кликов через Groq Vision (бесплатный).
/// Получает скриншот → отправляет в Groq → получает координаты/действие → выполняет.
/// НЕ заменяет AccessibilityService — работает поверх него как "умный слой".
/// ФИКС: раньше висел на Gemini (платные «мозги») — юзер просил чисто Groq.
class GroqComputerUseService {
  static const _screenReaderChannel = MethodChannel('com.aika.assistant/screen_reader');
  static const String _groqKey = String.fromEnvironment('GROQ_API_KEY', defaultValue: '');

  // Мультимодальная модель Groq — та же, что в AiService для фоток
  static const String _model = 'qwen/qwen3.6-27b';
  static const String _url = 'https://api.groq.com/openai/v1/chat/completions';

  /// Основной метод: получи скриншот и выполни задачу
  /// Возвращает текстовый результат что было сделано
  static Future<String> executeTask(String task) async {
    if (_groqKey.isEmpty) return 'Нет Groq API ключа';

    // Шаг 1 — делаем скриншот
    final b64 = await _captureScreen();
    if (b64 == null) return 'Не удалось сделать скриншот — нет разрешения AccessibilityService';

    // Шаг 2 — спрашиваем Groq что нажать
    final action = await _askGroqForAction(task, b64);
    if (action == null) return 'Groq не смог определить действие';

    // Шаг 3 — выполняем действие
    return await _executeAction(action);
  }

  /// Анализ скриншота — найти координаты элемента без нажатия
  static Future<ScreenElement?> findElement(String description, String screenshotB64) async {
    if (_groqKey.isEmpty) return null;
    return await _askGroqForCoordinates(description, screenshotB64);
  }

  /// Просто анализируй экран и опиши что видишь
  static Future<String> describeScreen() async {
    if (_groqKey.isEmpty) return 'Нет Groq API ключа';
    final b64 = await _captureScreen();
    if (b64 == null) return 'Не удалось сделать скриншот';
    return await _askGroqDescribe(b64);
  }

  // ── Приватные методы ─────────────────────────────────────────────────

  static Future<String?> _captureScreen() async {
    try {
      return await _screenReaderChannel.invokeMethod<String>('captureScreenBase64', {'quality': 70});
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $_groqKey',
      };

  static Future<String?> _chat(String prompt, String imageB64,
      {int maxTokens = 256, int timeoutSec = 20}) async {
    final body = {
      'model': _model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'image_url',
             'image_url': {'url': 'data:image/jpeg;base64,$imageB64'}},
            {'type': 'text', 'text': prompt},
          ],
        }
      ],
      'temperature': 0.1,
      'max_tokens': maxTokens,
    };

    final resp = await http.post(
      Uri.parse(_url),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(Duration(seconds: timeoutSec));

    if (resp.statusCode != 200) return null;
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    // OpenAI-совместимый формат: choices[0].message.content
    return data['choices']?[0]?['message']?['content'] as String?;
  }

  static Map<String, dynamic>? _parseJson(String raw) {
    try {
      final clean = raw
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final start = clean.indexOf('{');
      final end = clean.lastIndexOf('}');
      if (start >= 0 && end > start) {
        return jsonDecode(clean.substring(start, end + 1)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<ComputerUseAction?> _askGroqForAction(String task, String imageB64) async {
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
      final text = await _chat(prompt, imageB64, maxTokens: 300);
      if (text == null) return null;
      final json = _parseJson(text);
      if (json == null) return null;
      return ComputerUseAction.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<ScreenElement?> _askGroqForCoordinates(String description, String imageB64) async {
    final prompt = '''
На этом скриншоне найди элемент: "$description"
Ответь ТОЛЬКО в JSON (без markdown):
{"found": true|false, "x": число, "y": число, "label": "что нашёл"}
Координаты: X от 0 до 1000 (ширина экрана), Y от 0 до 2000 (высота).
''';

    try {
      final text = await _chat(prompt, imageB64, maxTokens: 128);
      if (text == null) return null;
      final json = _parseJson(text);
      if (json == null || json['found'] != true) return null;
      return ScreenElement(
        x: (json['x'] as num?)?.toDouble() ?? 500,
        y: (json['y'] as num?)?.toDouble() ?? 1000,
        label: json['label'] as String? ?? description,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String> _askGroqDescribe(String imageB64) async {
    const prompt = 'Опиши коротко что сейчас на экране Android смартфона. '
        'На русском языке, 1-2 предложения.';

    try {
      final text = await _chat(prompt, imageB64, maxTokens: 200, timeoutSec: 15);
      if (text == null) return 'Ошибка Groq Vision';
      return text.trim();
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
