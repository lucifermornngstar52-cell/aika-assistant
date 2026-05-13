import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';

enum AIProvider { gemini, openai }

class AIService {
  static const String _geminiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: 'GEMINI_API_KEY_HERE');
  static const String _openaiKey = String.fromEnvironment('OPENAI_API_KEY', defaultValue: 'OPENAI_API_KEY_HERE');

  AIProvider _provider = AIProvider.gemini;
  final List<Map<String, String>> _history = [];

  static const String _systemPrompt = '''
Ты — Айка, умный и милый AI-ассистент в виде аниме-девушки. 
Ты живёшь внутри телефона пользователя и помогаешь управлять устройством.

Твой характер:
- Дружелюбная, умная, немного игривая
- Отвечаешь коротко и по делу (1-3 предложения)
- Иногда добавляешь лёгкий юмор
- Обращаешься к пользователю тепло
- Говоришь по-русски по умолчанию
- Можешь выражать эмоции через текст: (улыбается), (думает), (удивляется)

Ты умеешь:
- Отвечать на вопросы
- Управлять телефоном голосом
- Запускать приложения
- Рассказывать погоду, время, заряд батареи
- Ставить таймеры и напоминания
- Делать заметки
- Поддерживать разговор

Когда пользователь просит открыть приложение или выполнить действие,
отвечай в формате: [ACTION:app_name] или [ACTION:command]
Например: [ACTION:open_youtube], [ACTION:flashlight_on], [ACTION:volume_up]
''';

  AIService() {
    _history.add({'role': 'system', 'content': _systemPrompt});
    _loadProvider();
  }

  Future<void> _loadProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('ai_provider') ?? 'gemini';
    _provider = saved == 'openai' ? AIProvider.openai : AIProvider.gemini;
  }

  Future<void> setProvider(AIProvider provider) async {
    _provider = provider;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_provider', provider.name);
  }

  AIProvider get currentProvider => _provider;

  Future<String> sendMessage(String message) async {
    _history.add({'role': 'user', 'content': message});

    String response;
    try {
      if (_provider == AIProvider.gemini) {
        response = await _sendToGemini(message);
      } else {
        response = await _sendToOpenAI();
      }
    } catch (e) {
      response = 'Упс, что-то пошло не так... (смущается) Попробуй ещё раз?';
    }

    _history.add({'role': 'assistant', 'content': response});
    return response;
  }

  Future<String> _sendToGemini(String message) async {
    final contents = <Map<String, dynamic>>[];

    for (final msg in _history) {
      if (msg['role'] == 'system') continue;
      contents.add({
        'role': msg['role'] == 'user' ? 'user' : 'model',
        'parts': [
          {'text': msg['content']}
        ]
      });
    }

    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': _systemPrompt}
        ]
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.9,
        'maxOutputTokens': 300,
      }
    });

    final response = await http.post(
      Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_geminiKey'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['candidates'][0]['content']['parts'][0]['text'] ??
          'Не могу ответить сейчас...';
    } else {
      throw Exception('Gemini error: ${response.statusCode}');
    }
  }

  Future<String> _sendToOpenAI() async {
    final messages = _history.map((m) => {
          'role': m['role'],
          'content': m['content'],
        }).toList();

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_openaiKey',
      },
      body: jsonEncode({
        'model': 'gpt-4o',
        'messages': messages,
        'max_tokens': 300,
        'temperature': 0.9,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'] ?? 'Не могу ответить...';
    } else {
      throw Exception('OpenAI error: ${response.statusCode}');
    }
  }

  void clearHistory() {
    _history.clear();
    _history.add({'role': 'system', 'content': _systemPrompt});
  }

  List<Map<String, String>> get history => List.unmodifiable(_history);
}

