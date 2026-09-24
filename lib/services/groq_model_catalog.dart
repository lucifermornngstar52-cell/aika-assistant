import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Каталог живых моделей Groq.
///
/// Groq регулярно отключает старые модели (llama-4, qwen3.6 — все вернули
/// HTTP 404). Вместо зашитых имён берём актуальный список моделей у самого
/// Groq: GET /openai/v1/models — и выбираем подходящую для задачи.
/// Найденная и подтверждённая модель кэшируется, пока не упадёт с 404.
class GroqModelCatalog {
  static const _modelsUrl = 'https://api.groq.com/openai/v1/models';
  static const _textPrefsKey = 'groq_text_model';
  static const _visionPrefsKey = 'groq_vision_model';

  /// Кандидаты на случай, когда API каталога недоступен.
  static const fallbackVision = ['qwen/qwen3.8-27b'];
  static const fallbackText = ['openai/gpt-oss-120b'];

  static List<String>? _cachedLiveIds;
  static DateTime _fetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _ttl = Duration(minutes: 10);

  /// Признаки мультимодальной модели: qwen-27B всегда мультимодальные
  /// (замены scout/maverick по deprecations), плюс явные vision/vl/vlm.
  static final _visionPattern = RegExp(
      r'qwen[0-9.]+-27b|vision|-vl|vlm|pixtral|scout|maverick');

  static void invalidate() {
    _cachedLiveIds = null;
    _fetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Живой список id моделей; при ошибке сети — пустой список.
  static Future<List<String>> fetchIds(String key,
      {http.Client? client, Duration timeout = const Duration(seconds: 5)}) async {
    if (key.isEmpty) return [];
    if (_cachedLiveIds != null &&
        DateTime.now().difference(_fetchedAt) < _ttl) {
      return _cachedLiveIds!;
    }
    try {
      final c = client ?? http.Client();
      final resp = await c.get(Uri.parse(_modelsUrl), headers: {
        'Authorization': 'Bearer $key',
      }).timeout(timeout);
      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final list = data['data'];
        final ids = <String>[];
        if (list is List) {
          for (final m in list) {
            final id = m is Map ? m['id'] : null;
            if (id is String && id.isNotEmpty && !ids.contains(id)) {
              ids.add(id);
            }
          }
        }
        _cachedLiveIds = ids;
        _fetchedAt = DateTime.now();
        return ids;
      }
    } catch (_) {}
    return _cachedLiveIds ?? [];
  }

  /// Порядок vision-кандидатов: известный кандидат, затем все подходящие
  /// под паттерн из живого списка.
  static List<String> _visionCandidates(List<String> liveIds) {
    final picked = <String>[];
    void add(String? m) {
      if (m != null && m.isNotEmpty && !picked.contains(m)) picked.add(m);
    }

    add(fallbackVision.first);
    for (final id in liveIds.where((id) => _visionPattern.hasMatch(id))) {
      add(id);
    }
    return picked;
  }

  /// Полная цепочка vision-моделей для перебора.
  /// [confirmed] — модель, сохранённая после прошлого успешного запроса.
  static List<String> visionChain(List<String> liveIds, String? confirmed) {
    final chain = <String>[];
    if (confirmed != null && confirmed.isNotEmpty) chain.add(confirmed);
    chain.addAll(_visionCandidates(liveIds));
    if (liveIds.isNotEmpty) {
      // Живой список известен — доверяем только моделям из него.
      chain.retainWhere(liveIds.contains);
      if (chain.isEmpty) {
        // Ни одна знакомая модель не жива: берём первую по паттерну как есть.
        final matches =
            liveIds.where((id) => _visionPattern.hasMatch(id)).toList();
        if (matches.isNotEmpty) chain.add(matches.first);
      }
    }
    return chain;
  }

  /// Цепочка текстовых моделей: подтверждённая → gpt-oss-120b → живые gpt-oss.
  static List<String> textChain(List<String> liveIds, String? confirmed) {
    final chain = <String>[];
    if (confirmed != null && confirmed.isNotEmpty) chain.add(confirmed);
    for (final fb in fallbackText) {
      if (!chain.contains(fb)) chain.add(fb);
    }
    chain.addAll(liveIds.where((id) =>
        id.contains('gpt-oss') &&
        !id.contains('safeguard') &&
        !chain.contains(id)));
    if (liveIds.isNotEmpty) {
      chain.retainWhere(liveIds.contains);
    }
    return chain;
  }

  static Future<String?> _saved(String prefsKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(prefsKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _save(String prefsKey, String model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, model);
    } catch (_) {}
  }

  /// Готовая к использованию vision-цепочка (живой список + кэш).
  static Future<List<String>> resolveVision(String key,
      {http.Client? client}) async {
    final live = await fetchIds(key, client: client);
    final confirmed = await _saved(_visionPrefsKey);
    return visionChain(live, confirmed);
  }

  /// Готовая к использованию текстовая цепочка.
  static Future<List<String>> resolveText(String key,
      {http.Client? client}) async {
    final live = await fetchIds(key, client: client);
    final confirmed = await _saved(_textPrefsKey);
    return textChain(live, confirmed);
  }

  /// Запомнить модель, которая успешно ответила.
  static Future<void> confirmVision(String model) => _save(_visionPrefsKey, model);
  static Future<void> confirmText(String model) => _save(_textPrefsKey, model);
}
