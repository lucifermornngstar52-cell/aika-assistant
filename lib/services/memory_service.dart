import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';

class MemoryService {
  static const String _historyKey = 'chat_history';
  static const String _notesKey = 'user_notes';
  static const String _userNameKey = 'user_name';
  static const int _maxHistory = 100;

  Future<void> saveMessage(ChatMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList(_historyKey) ?? [];
    history.add(jsonEncode(message.toJson()));
    if (history.length > _maxHistory) {
      history.removeAt(0);
    }
    await prefs.setStringList(_historyKey, history);
  }

  Future<List<ChatMessage>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList(_historyKey) ?? [];
    return history
        .map((h) => ChatMessage.fromJson(jsonDecode(h)))
        .toList();
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  Future<void> saveNote(String note) async {
    final prefs = await SharedPreferences.getInstance();
    final notes = prefs.getStringList(_notesKey) ?? [];
    notes.add(jsonEncode({
      'text': note,
      'date': DateTime.now().toIso8601String(),
    }));
    await prefs.setStringList(_notesKey, notes);
  }

  Future<List<Map<String, dynamic>>> getNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notes = prefs.getStringList(_notesKey) ?? [];
    return notes.map((n) => jsonDecode(n) as Map<String, dynamic>).toList();
  }

  Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, name);
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey);
  }
}
