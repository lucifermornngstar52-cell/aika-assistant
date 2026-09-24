import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Запасная обработка фото через OpenAI GPT-4o.
///
/// Основной поток остаётся Groq-only: текст всегда идёт в Groq, фото — в
/// Groq Vision (живой список моделей). Этот сервис включается ТОЛЬКО когда
/// Groq Vision не смог обработать изображение, и только если у юзера есть
/// ключ OpenAI. Без ключа приложение работает как раньше, чисто на Groq.
class OpenAiVisionService {
  static const _url = 'https://api.openai.com/v1/chat/completions';
  static const _models = ['gpt-4o-mini', 'gpt-4o'];

  static Future<String> _key() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('openai_key') ?? '';
      if (saved.isNotEmpty) return saved;
    } catch (_) {}
    return const String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
  }

  static Future<bool> get isAvailable async => (await _key()).isNotEmpty;

  /// Обработать изображение; null — ключа нет или OpenAI не ответил.
  static Future<String?> describeImage(
    String message,
    String imageBase64,
    String imageMimeType, {
    http.Client? client,
    int maxTokens = 1024,
  }) async {
    final key = await _key();
    if (key.isEmpty || imageBase64.isEmpty) return null;
    final c = client ?? http.Client();
    try {
      Object? last;
      for (final model in _models) {
        try {
          final resp = await c.post(Uri.parse(_url), headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer $key',
          }, body: jsonEncode({
            'model': model,
            'max_completion_tokens': maxTokens,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'text',
                    'text': message.isEmpty
                        ? 'Опиши что на изображении, коротко.'
                        : message,
                  },
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url': 'data:$imageMimeType;base64,$imageBase64',
                    },
                  },
                ],
              }
            ],
          })).timeout(const Duration(seconds: 30));
          if (resp.statusCode == 200) {
            final data = jsonDecode(utf8.decode(resp.bodyBytes));
            final choices = data['choices'];
            if (choices is List && choices.isNotEmpty) {
              final content = choices[0]['message']?['content'];
              final text =
                  content is String ? content.trim() : (content is List
                      ? content
                          .whereType<Map>()
                          .where((p) => p['type'] == 'text')
                          .map((p) => p['text'])
                          .whereType<String>()
                          .join('\n')
                      : '');
              if (text.isNotEmpty) return text;
            }
            return null;
          }
          // 401/403 — ключ битый, 429 — лимиты: следующие модели не помогут,
          // но всё равно пробуем без падения.
          last = HttpException('OpenAI HTTP ${resp.statusCode}');
        } catch (e) {
          last = e is Exception ? e : Exception(e.toString());
        }
      }
      debugLast = last;
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Последняя ошибка — для диагностики в логах.
  static Object? debugLast;
}
