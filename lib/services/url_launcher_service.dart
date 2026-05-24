import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Открытие веб-сайтов через Intent
class UrlLauncherService {
  static const _channel = MethodChannel('com.aika.assistant/url');

  /// Открыть URL в браузере
  static Future<bool> openUrl(String url) async {
    try {
      // Нормализуем URL
      String normalized = url.trim();
      if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
        normalized = 'https://\$normalized';
      }
      final result = await _channel.invokeMethod<bool>('openUrl', {'url': normalized});
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[UrlLauncher] ошибка: \${e.message}');
      return false;
    }
  }

  /// Парсим голосовую команду и извлекаем URL/сайт
  /// "открой гугл" → "google.com"
  /// "зайди на ютуб" → "youtube.com"
  /// "открой сайт base44.com" → "base44.com"
  static String? parseUrlCommand(String text) {
    final lower = text.toLowerCase().trim();

    // Триггерные фразы
    final triggers = ['зайди на', 'открой сайт', 'перейди на', 'открой страницу', 
                      'покажи сайт', 'загрузи сайт', 'открой в браузере'];
    for (final t in triggers) {
      if (lower.contains(t)) {
        final idx = lower.indexOf(t) + t.length;
        final site = lower.substring(idx).trim();
        return _resolveUrl(site);
      }
    }

    // Прямые имена известных сайтов
    return _resolveKnownSite(lower);
  }

  static String? _resolveKnownSite(String text) {
    final sites = {
      'google': 'https://google.com',
      'гугл': 'https://google.com',
      'youtube': 'https://youtube.com',
      'ютуб': 'https://youtube.com',
      'yandex': 'https://yandex.ru',
      'яндекс': 'https://yandex.ru',
      'wikipedia': 'https://ru.wikipedia.org',
      'википедия': 'https://ru.wikipedia.org',
      'vk': 'https://vk.com',
      'вконтакте': 'https://vk.com',
      'twitter': 'https://twitter.com',
      'твиттер': 'https://twitter.com',
      'instagram': 'https://instagram.com',
      'инстаграм': 'https://instagram.com',
      'tiktok': 'https://tiktok.com',
      'тикток': 'https://tiktok.com',
      'reddit': 'https://reddit.com',
      'редит': 'https://reddit.com',
      'amazon': 'https://amazon.com',
      'амазон': 'https://amazon.com',
      'github': 'https://github.com',
      'гитхаб': 'https://github.com',
      'netflix': 'https://netflix.com',
      'нетфликс': 'https://netflix.com',
      'aliexpress': 'https://aliexpress.ru',
      'алиэкспресс': 'https://aliexpress.ru',
      'avito': 'https://avito.ru',
      'авито': 'https://avito.ru',
      'ozon': 'https://ozon.ru',
      'озон': 'https://ozon.ru',
      'wildberries': 'https://wildberries.ru',
      'вайлдберис': 'https://wildberries.ru',
      'карты': 'https://maps.google.com',
      'maps': 'https://maps.google.com',
    };

    for (final entry in sites.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return null;
  }

  static String _resolveUrl(String input) {
    // Если выглядит как домен — добавляем https
    if (input.contains('.') && !input.contains(' ')) {
      return 'https://\$input';
    }
    // Иначе — поиск в гугле
    final encoded = Uri.encodeComponent(input);
    return 'https://www.google.com/search?q=\$encoded';
  }
}
