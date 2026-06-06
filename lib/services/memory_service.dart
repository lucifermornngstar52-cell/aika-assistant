import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// MemoryService — хранит историю чата и данные пользователя.
/// Локально в SharedPreferences + синхронизация с сервером.
class MemoryService {
  static const String _keyUserName       = 'user_name';
  static const String _keyAssistantName  = 'assistant_name';
  static const String _keyConversation   = 'conversation_history';
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
    return prefs.getStringList(_keyConversation) ?? [];
  }

  Future<void> addMessage(String role, String content) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_keyConversation) ?? [];
    history.add('\$role: \$content');
    if (history.length > _maxHistory) {
      history.removeRange(0, history.length - _maxHistory);
    }
    await prefs.setStringList(_keyConversation, history);
  }

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
    final updated = current.isEmpty ? fact : '\$current\n- \$fact';
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
