import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'screen_reader_service.dart';
import 'app_launcher_service.dart';

/// Поиск в браузере, генерация текстов и изображений через Gemini.
class AikaBrowserService {
  static const _geminiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _launcher = MethodChannel('com.aika.assistant/launcher');

  // ── Детектор команды ──────────────────────────────────────────────
  static bool isBrowserCommand(String text) {
    final t = text.toLowerCase();
    return t.contains('найди в интернете') ||
        t.contains('поищи в гугл') ||
        t.contains('поищи в интернете') ||
        t.contains('загугли') ||
        t.contains('найди информацию') ||
        t.contains('открой сайт') ||
        t.contains('перейди на сайт') ||
        t.contains('сгенерируй текст') ||
        t.contains('напиши текст') ||
        t.contains('составь текст') ||
        t.contains('придумай текст') ||
        t.contains('сгенерируй изображение') ||
        t.contains('нарисуй') ||
        t.contains('создай изображение') ||
        t.contains('придумай картинку');
  }

  static Future<String> execute(String text) async {
    final t = text.toLowerCase().trim();

    // ── Поиск в браузере ────────────────────────────────────────────
    if (t.contains('найди в интернете') || t.contains('загугли') ||
        t.contains('поищи в гугл') || t.contains('поищи в интернете') ||
        t.contains('найди информацию')) {
      final query = _extractAfter(text, [
        'найди в интернете', 'загугли', 'поищи в гугл',
        'поищи в интернете', 'найди информацию о', 'найди информацию'
      ]).trim();
      if (query.isEmpty) return 'Что именно искать? 🔍';
      return await _searchInBrowser(query);
    }

    // ── Открыть сайт ────────────────────────────────────────────────
    if (t.contains('открой сайт') || t.contains('перейди на сайт')) {
      final site = _extractAfter(text, ['открой сайт', 'перейди на сайт']).trim();
      if (site.isEmpty) return 'Какой сайт открыть? 🌐';
      return await _openWebsite(site);
    }

    // ── Генерация текста ────────────────────────────────────────────
    if (t.contains('сгенерируй текст') || t.contains('напиши текст') ||
        t.contains('составь текст') || t.contains('придумай текст')) {
      final prompt = _extractAfter(text, [
        'сгенерируй текст', 'напиши текст', 'составь текст', 'придумай текст'
      ]).trim();
      if (prompt.isEmpty) return 'О чём написать текст? ✍️';
      return await _generateText(prompt);
    }

    // ── Генерация изображения ────────────────────────────────────────
    if (t.contains('нарисуй') || t.contains('сгенерируй изображение') ||
        t.contains('создай изображение') || t.contains('придумай картинку')) {
      final prompt = _extractAfter(text, [
        'нарисуй', 'сгенерируй изображение', 'создай изображение', 'придумай картинку'
      ]).trim();
      if (prompt.isEmpty) return 'Что нарисовать? 🎨';
      return await _generateImage(prompt);
    }

    return 'Не поняла запрос 🤔';
  }

  // ── Поиск: открываем Chrome/браузер с запросом ──────────────────
  static Future<String> _searchInBrowser(String query) async {
    try {
      final encoded = Uri.encodeComponent(query);
      final url = 'https://www.google.com/search?q=$encoded';
      // Пробуем через launcher channel (deeplink)
      try {
        await _launcher.invokeMethod('launchUrl', {'url': url});
      } catch (_) {
        // Fallback: открываем Chrome напрямую
        await AppLauncherService.tryLaunch('браузер');
        await Future.delayed(const Duration(milliseconds: 1500));
        // Вводим поиск через Accessibility
        await ScreenReaderService.typeText(query);
        await ScreenReaderService.pressEnter();
      }
      return 'Ищу "$query" в браузере 🔍';
    } catch (e) {
      return 'Не смогла открыть браузер: $e';
    }
  }

  // ── Открыть сайт ──────────────────────────────────────────────────
  static Future<String> _openWebsite(String site) async {
    try {
      var url = site.trim();
      if (!url.startsWith('http')) url = 'https://$url';
      await _launcher.invokeMethod('launchUrl', {'url': url});
      return 'Открываю $site 🌐';
    } catch (_) {
      await AppLauncherService.tryLaunch('браузер');
      return 'Открываю браузер 🌐';
    }
  }

  // ── Генерация текста через Gemini ─────────────────────────────────
  static Future<String> _generateText(String prompt) async {
    if (_geminiKey.isEmpty) {
      return 'Нет API ключа для генерации. Но вот что я думаю: попробую через основной чат!';
    }
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_geminiKey'
      );
      final body = jsonEncode({
        'contents': [{
          'parts': [{'text': 'Напиши текст на русском: $prompt. Дай только текст, без пояснений.'}]
        }]
      });
      final resp = await http.post(url,
          headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
        return text.isNotEmpty ? '✍️ Вот текст:

$text' : 'Не смогла сгенерировать текст';
      }
      return 'Ошибка генерации текста';
    } catch (e) {
      return 'Ошибка соединения: $e';
    }
  }

  // ── Генерация изображения (Imagen через Gemini) ──────────────────
  static Future<String> _generateImage(String prompt) async {
    if (_geminiKey.isEmpty) {
      return 'Нет API ключа для генерации изображений 🎨';
    }
    try {
      // Используем Imagen 3 через Gemini API
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict?key=$_geminiKey'
      );
      final body = jsonEncode({
        'instances': [{'prompt': '$prompt, anime style, high quality'}],
        'parameters': {'sampleCount': 1, 'aspectRatio': '1:1'}
      });
      final resp = await http.post(url,
          headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final b64 = data['predictions']?[0]?['bytesBase64Encoded'] as String?;
        if (b64 != null && b64.isNotEmpty) {
          // Сохраняем картинку локально и возвращаем путь
          return '[IMAGE_GENERATED]$b64';
        }
      }
      // Fallback — открываем поиск картинок
      await _searchInBrowser('$prompt картинка');
      return 'Генерация изображения недоступна, ищу похожее в браузере 🎨';
    } catch (e) {
      return 'Ошибка генерации изображения: $e';
    }
  }

  static String _extractAfter(String text, List<String> keywords) {
    final t = text.toLowerCase();
    for (final k in keywords) {
      final idx = t.indexOf(k);
      if (idx >= 0) return text.substring(idx + k.length).trim();
    }
    return '';
  }
}
