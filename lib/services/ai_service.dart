import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  static const String _openaiKey = String.fromEnvironment('OPENAI_API_KEY');

  Future<String> sendMessage(
    String message, {
    String userName = '',
    String assistantName = 'Aika',
    List<String> history = const [],
  }) async {
    try {
      return await _callOpenAI(message,
          userName: userName, assistantName: assistantName, history: history);
    } catch (e) {
      throw Exception('AI недоступен: $e');
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
[ACTION:launch_app_PACKAGE] — запустить любое приложение по package name

Когда пользователь говорит "открой [приложение]" или "включи [приложение]" — используй [ACTION:launch_app_PACKAGE] с нужным package name.
Примеры: Spotify=com.spotify.music, WhatsApp=com.whatsapp, Instagram=com.instagram.android, VK=com.vkontakte.android, TikTok=com.zhiliaoapp.musically

Используй действия только когда пользователь явно просит. Отвечай на языке пользователя.""";
  }

  Future<String> _callOpenAI(
    String message, {
    String userName = '',
    String assistantName = 'Aika',
    List<String> history = const [],
  }) async {
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');

    final messages = <Map<String, dynamic>>[
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

    final reqBody = {
      'model': 'gpt-4o-mini',
      'messages': messages,
      'temperature': 0.8,
      'max_tokens': 512,
    };

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $_openaiKey',
      },
      body: jsonEncode(reqBody),
    );

    if (response.statusCode != 200) {
      throw Exception('OpenAI error ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
    }
    final responseBody = utf8.decode(response.bodyBytes);
    final data = jsonDecode(responseBody);
    return data['choices'][0]['message']['content'] as String;
  }
}
