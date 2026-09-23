import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// MemoryService — хранит историю чата и данные пользователя.
/// Локально в SharedPreferences + синхронизация с сервером.
class MemoryService {
  static const String _keyUserName       = 'user_name';
  static const String _keyAssistantName  = 'assistant_name';
  static const String _keyConversation   = 'chat_history';
  static const String _keyUserMemory     = 'user_long_memory';
  static const int    _maxHistory        = 30;

  // ─── Имя пользователя ──────────────────────────────────────────────────────
  Future<String> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserName) ?? '';
  }

  Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserName, name.trim());
  }

  // ─── Имя ассистента ────────────────────────────────────────────────────────
  Future<String> getAssistantName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAssistantName) ?? 'Aivora';
  }

  Future<void> setAssistantName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAssistantName, name.isEmpty ? 'Aivora' : name.trim());
  }

  // ─── История чата ──────────────────────────────────────────────────────────
  Future<List<String>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyConversation);
    if (raw == null || raw.isEmpty) return [];
    try {
      final entries = jsonDecode(raw);
      if (entries is! List) return [];
      return entries.whereType<Map>().map((entry) {
        final role = entry['role'];
        final content = entry['content'];
        if (content is! String || content.isEmpty) return '';
        if (role == 'user') return 'user: $content';
        if (role == 'aika' || role == 'assistant') return 'assistant: $content';
        return '';
      }).where((entry) => entry.isNotEmpty).toList();
    } catch (_) { return []; }
  }

  // The UI owns chat_history. Never write a second, incompatible string-list
  // representation to the same key; UI messages persist via _addMessage.
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyConversation);
  }

  // ─── Долгосрочная память (факты о пользователе) ────────────────────────────
  Future<String> getLongMemory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserMemory) ?? '';
  }

  Future<void> setLongMemory(String memory) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserMemory, memory);
  }

  Future<void> appendMemoryFact(String fact) async {
    final current = await getLongMemory();
    final updated = current.isEmpty ? fact : '$current\n- $fact';
    await setLongMemory(updated);
  }

  // ─── Контекст для AI ───────────────────────────────────────────────────────
  Future<Map<String, String>> getUserContext() async {
    final userName      = await getUserName();
    final assistantName = await getAssistantName();
    final longMemory    = await getLongMemory();
    return {
      'userName':      userName,
      'assistantName': assistantName,
      'longMemory':    longMemory,
    };
  }
}
