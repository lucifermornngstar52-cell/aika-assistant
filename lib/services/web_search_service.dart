import 'dart:convert';
import 'package:http/http.dart' as http;

/// WebSearchService — бесплатный веб-поиск для AI-контекста
/// Использует DuckDuckGo Instant Answer API (без ключа)
/// + Brave Search API (если есть ключ, 2000 бесплатных запросов/мес)
class WebSearchService {
  static String _braveKey = '';
  static void setBraveKey(String k) => _braveKey = k;

  /// Поиск — возвращает текст для вставки в контекст AI
  static Future<String> search(String query) async {
    // Пробуем Brave если есть ключ (лучше результаты)
    if (_braveKey.isNotEmpty) {
      try {
        final result = await _braveSearch(query);
        if (result.isNotEmpty) return result;
      } catch (_) {}
    }

    // DuckDuckGo — бесплатно, всегда
    try {
      final result = await _duckDuckGoSearch(query);
      if (result.isNotEmpty) return result;
    } catch (_) {}

    return '';
  }

  /// DuckDuckGo Instant Answer API — полностью бесплатно
  static Future<String> _duckDuckGoSearch(String query) async {
    final encoded = Uri.encodeComponent(query);
    final response = await http.get(
      Uri.parse(
          'https://api.duckduckgo.com/?q=$encoded&format=json&no_redirect=1&no_html=1&skip_disambig=1'),
      headers: {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) return '';

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final parts = <String>[];

    // Основной ответ
    final abstract_ = data['Abstract'] as String? ?? '';
    if (abstract_.isNotEmpty) parts.add(abstract_);

    // Связанные темы
    final related = data['RelatedTopics'] as List? ?? [];
    for (final r in related.take(3)) {
      if (r is Map && r['Text'] != null) {
        final text = r['Text'] as String;
        if (text.isNotEmpty) parts.add(text);
      }
    }

    // Определение
    final definition = data['Definition'] as String? ?? '';
    if (definition.isNotEmpty && !parts.contains(definition)) {
      parts.add(definition);
    }

    // Ответ (например на вопрос "сколько...")
    final answer = data['Answer'] as String? ?? '';
    if (answer.isNotEmpty) parts.insert(0, answer);

    if (parts.isEmpty) return '';
    return '[Поиск: "$query"]\n${parts.join('\n')}';
  }

  /// Brave Search API — 2000 запросов/месяц бесплатно
  static Future<String> _braveSearch(String query) async {
    final encoded = Uri.encodeComponent(query);
    final response = await http.get(
      Uri.parse('https://api.search.brave.com/res/v1/web/search?q=$encoded&count=3&text_decorations=false'),
      headers: {
        'Accept': 'application/json',
        'X-Subscription-Token': _braveKey,
      },
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) return '';

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final results = data['web']?['results'] as List? ?? [];
    if (results.isEmpty) return '';

    final parts = <String>[];
    for (final r in results.take(3)) {
      final title = r['title'] as String? ?? '';
      final desc = r['description'] as String? ?? '';
      if (desc.isNotEmpty) parts.add('• $title: $desc');
    }

    if (parts.isEmpty) return '';
    return '[Веб-поиск: "$query"]\n${parts.join('\n')}';
  }
}
