import 'dart:convert';
import 'package:http/http.dart' as http;

class NewsService {
  /// Получить топ-5 новостей из RSS Lenta.ru
  Future<String> getTopNews({String category = ''}) async {
    try {
      // Lenta.ru RSS — бесплатно, без ключа
      final url = category.isEmpty
          ? 'https://lenta.ru/rss/news'
          : 'https://lenta.ru/rss/$category';

      final resp = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'AikaAssistant/1.0'})
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return _fallbackNews();

      final body = utf8.decode(resp.bodyBytes);
      return _parseRss(body);
    } catch (e) {
      return _fallbackNews();
    }
  }

  String _parseRss(String xml) {
    final titleRegex = RegExp(r'<item>.*?<title><!\[CDATA\[(.*?)\]\]></title>', dotAll: true);
    final matches = titleRegex.allMatches(xml).take(5).toList();

    if (matches.isEmpty) {
      // Fallback regex without CDATA
      final simple = RegExp(r'<item>.*?<title>(.*?)</title>', dotAll: true);
      final m2 = simple.allMatches(xml).take(5).toList();
      if (m2.isEmpty) return 'Не удалось загрузить новости';
      final buf = StringBuffer('📰 Последние новости:\n\n');
      for (int i = 0; i < m2.length; i++) {
        buf.writeln('${i + 1}. ${m2[i].group(1)?.trim() ?? ''}');
      }
      return buf.toString().trim();
    }

    final buf = StringBuffer('📰 Последние новости:\n\n');
    for (int i = 0; i < matches.length; i++) {
      buf.writeln('${i + 1}. ${matches[i].group(1)?.trim() ?? ''}');
    }
    return buf.toString().trim();
  }

  String _fallbackNews() =>
      '📰 Новости временно недоступны. Попробуй позже.';

  /// Парсим команду пользователя
  Future<String?> tryParseNews(String text) async {
    final t = text.toLowerCase();
    if (t.contains('новост') || t.contains('что нового') || t.contains('что происходит')) {
      String category = '';
      if (t.contains('технолог') || t.contains('техно')) category = 'rubrics/science';
      if (t.contains('спорт')) category = 'rubrics/sport';
      if (t.contains('мир') || t.contains('мировые')) category = 'rubrics/world';
      return await getTopNews(category: category);
    }
    return null;
  }
}
