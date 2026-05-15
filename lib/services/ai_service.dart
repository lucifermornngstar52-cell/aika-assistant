import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  static const String _geminiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _openaiKey = String.fromEnvironment('OPENAI_API_KEY');

  Future<String> sendMessage(
    String message, {
    String userName = '',
    String assistantName = 'Aika',
    List<String> history = const [],
  }) async {
    try {
      return await _callGemini(message,
          userName: userName, assistantName: assistantName, history: history);
    } catch (e) {
      try {
        return await _callOpenAI(message,
            userName: userName, assistantName: assistantName, history: history);
      } catch (e2) {
        throw Exception('AI недоступен: $e2');
      }
    }
  }

  String _buildSystemPrompt(String userName, String assistantName) {
    final userPart = userName.isNotEmpty ? ', пользователя зовут $userName' : '';
    return """Ты $assistantName — умный AI-ассистент для Android$userPart. 
Ты говоришь кратко, умно и с характером. Можешь управлять телефоном через команды вида [ACTION:название].

Доступные действия:
[ACTION:open_youtube] [ACTION:open_telegram] [ACTION:open_tiktok] [ACTION:open_chrome]
[ACTION:open_spotify] [ACTION:open_settings] [ACTION:open_camera]
[ACTION:flashlight_on] [ACTION:flashlight_off] [ACTION:flashlight_toggle]
[ACTION:volume_up] [ACTION:volume_down] [ACTION:volume_max] [ACTION:volume_mute]
[ACTION:battery] [ACTION:search_запрос]

Используй действия только когда пользователь явно просит. Отвечай на языке пользователя.""";
  }

  Future<String> _callGemini(String message,
      {String userName = '', String assistantName = 'Aika', List<String> history = const []}) async {
    if (_geminiKey.isEmpty) throw Exception('No Gemini key');
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_geminiKey');

    final contents = <Map<String, dynamic>>[];
    for (final h in history.take(10)) {
      if (h.startsWith('user: ')) {
        contents.add({'role': 'user', 'parts': [{'text': h.substring(6)}]});
      } else if (h.startsWith('assistant: ')) {
        contents.add({'role': 'model', 'parts': [{'text': h.substring(11)}]});
      }
    }
    contents.add({'role': 'user', 'parts': [{'text': message}]});

    final body = {
      'system_instruction': {'parts': [{'text': _buildSystemPrompt(userName, assistantName)}]},
      'contents': contents,
      'generationConfig': {'temperature': 0.8, 'maxOutputTokens': 512},
    };

    final response = await http.post(url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body));

    if (response.statusCode != 200) throw Exception('Gemini error: ${response.statusCode}');
    final data = jsonDecode(response.body);
    return data['candidates'][0]['content']['parts'][0]['text'] as String;
  }

  Future<String> _callOpenAI(String message,
      {String userName = '', String assistantName = 'Aika', List<String> history = const []}) async {
    if (_openaiKey.isEmpty) throw Exception('No OpenAI key');
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _buildSystemPrompt(userName, assistantName)},
    ];
    for (final h in history.take(10)) {
      if (h.startsWith('user: ')) {
        messages.add({'role': 'user', 'content': h.substring(6)});
      } else if (h.startsWith('assistant: ')) {
        messages.add({'role': 'assistant', 'content': h.substring(11)});
      }
    }
    messages.add({'role': 'user', 'content': message});

    final response = await http.post(url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_openaiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o',
          'messages': messages,
          'max_tokens': 512,
          'temperature': 0.8,
        }));

    if (response.statusCode != 200) throw Exception('OpenAI error: ${response.statusCode}');
    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content'] as String;
  }
}
