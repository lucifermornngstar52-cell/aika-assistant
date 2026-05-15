import 'package:shared_preferences/shared_preferences.dart';

class MemoryService {
  static const String _keyUserName = 'user_name';
  static const String _keyAssistantName = 'assistant_name';
  static const String _keyConversation = 'conversation_history';
  static const int _maxHistory = 20;

  Future<String> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserName) ?? '';
  }

  Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserName, name);
  }

  Future<String> getAssistantName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAssistantName) ?? 'Aika';
  }

  Future<void> setAssistantName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAssistantName, name.isEmpty ? 'Aika' : name);
  }

  Future<List<String>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyConversation) ?? [];
  }

  Future<void> addMessage(String role, String content) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_keyConversation) ?? [];
    history.add('$role: $content');
    if (history.length > _maxHistory) {
      history.removeRange(0, history.length - _maxHistory);
    }
    await prefs.setStringList(_keyConversation, history);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyConversation);
  }

  Future<Map<String, String>> getUserContext() async {
    final userName = await getUserName();
    final assistantName = await getAssistantName();
    return {
      'userName': userName,
      'assistantName': assistantName,
    };
  }
}
