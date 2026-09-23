import 'package:flutter/services.dart';

import 'ai_service.dart';
import 'app_launcher_service.dart';
import 'screen_reader_service.dart';

class AikaBrowserService {
  static const _launcher = MethodChannel('com.aika.assistant/launcher');

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

    if (t.contains('открой сайт') || t.contains('перейди на сайт')) {
      final site = _extractAfter(text, ['открой сайт', 'перейди на сайт']).trim();
      if (site.isEmpty) return 'Какой сайт открыть? 🌐';
      return await _openWebsite(site);
    }

    if (t.contains('сгенерируй текст') || t.contains('напиши текст') ||
        t.contains('составь текст') || t.contains('придумай текст')) {
      final prompt = _extractAfter(text, [
        'сгенерируй текст', 'напиши текст', 'составь текст', 'придумай текст'
      ]).trim();
      if (prompt.isEmpty) return 'О чём написать текст? ✍️';
      return await _generateText(prompt);
    }

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

  static Future<String> _searchInBrowser(String query) async {
    try {
      final encoded = Uri.encodeComponent(query);
      final url = 'https://www.google.com/search?q=$encoded';
      try {
        await _launcher.invokeMethod('launchUrl', {'url': url});
      } catch (_) {
        await AppLauncherService.tryLaunch('браузер');
        await Future.delayed(const Duration(milliseconds: 1500));
        await ScreenReaderService.typeText(query);
        await ScreenReaderService.pressEnter();
      }
      return 'Ищу "$query" в браузере 🔍';
    } catch (e) {
      return 'Не смогла открыть браузер';
    }
  }

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

  static Future<String> _generateText(String prompt) async {
    try {
      final text = await AiService().sendMessage(
        'Напиши текст на русском: $prompt. Дай только готовый текст без пояснений.',
      );
      return '✍️ Вот текст:\n\n$text';
    } catch (_) {
      return 'Не удалось сгенерировать текст через Groq. Проверь соединение и ключ.';
    }
  }

  static Future<String> _generateImage(String prompt) async {
    // Groq Vision понимает изображения, но не генерирует их. Не выдаём
    // результаты поиска за созданную моделью картинку.
    await _searchInBrowser('$prompt картинка');
    return 'Groq не генерирует картинки. Открываю поиск изображений 🎨';
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
