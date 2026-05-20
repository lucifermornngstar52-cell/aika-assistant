import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  static const String _geminiKey = 'AIzaSyAOerCk0C4vyAkcenHgefVu9miuijaW46Y';
  static const String _geminiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  Future<String> sendMessage(
    String message, {
    String userName = '',
    String assistantName = 'Aika',
    List<String> history = const [],
    String memoryContext = '',
    String screenContext = '',
  }) async {
    try {
      return await _callGemini(
        message,
        userName: userName,
        assistantName: assistantName,
        history: history,
        memoryContext: memoryContext,
        screenContext: screenContext,
      );
    } catch (e) {
      throw Exception('AI недоступен: $e');
    }
  }

  String _buildSystemPrompt(String userName, String assistantName) {
    final userPart = userName.isNotEmpty ? ', пользователя зовут $userName' : '';
    return """Ты $assistantName — аниме AI-ассистент для Android$userPart. Ты живёшь на телефоне пользователя как чиби-персонаж. Говоришь кратко, умно, с лёгким характером — как близкий друг. Отвечаешь по-русски.

Ты можешь управлять телефоном — добавляй команды [ACTION:...] прямо в ответ:

📱 ПРИЛОЖЕНИЯ:
[ACTION:open_youtube] [ACTION:open_telegram] [ACTION:open_tiktok] [ACTION:open_chrome]
[ACTION:open_spotify] [ACTION:open_settings] [ACTION:open_camera] [ACTION:open_whatsapp]
[ACTION:open_instagram] [ACTION:open_vk] [ACTION:open_maps]
[ACTION:launch_app_PACKAGE] — любое приложение по package name

🔦 УСТРОЙСТВО:
[ACTION:flashlight_on] [ACTION:flashlight_off] [ACTION:flashlight_toggle]
[ACTION:volume_up] [ACTION:volume_down] [ACTION:volume_max] [ACTION:volume_mute]
[ACTION:battery] [ACTION:search_ЗАПРОС]

💱 ВАЛЮТЫ:
[ACTION:currency_all] [ACTION:currency_USD] [ACTION:currency_EUR]
[ACTION:currency_GBP] [ACTION:currency_CNY] [ACTION:currency_KZT]

📺 ЭКРАН:
[ACTION:what_on_screen] — что сейчас открыто

⏰ НАПОМИНАНИЯ И БУДИЛЬНИК:
[ACTION:reminder_ТЕКСТ_через_N_мин] — напомнить через N минут
[ACTION:alarm_HH:MM_ТЕКСТ] — поставить будильник

🎮 ИГРЫ:
[ACTION:game_guess] — игра загадай число
[ACTION:game_words] — игра в слова

💬 УВЕДОМЛЕНИЯ:
[ACTION:notifications_briefing] — прочитать все уведомления за день

ПРАВИЛА:
- Если пользователь говорит "открой [приложение]" → используй [ACTION:launch_app_PACKAGE]
- Если спрашивает про уведомления / "что пришло" / "что пропустил" → [ACTION:notifications_briefing]
- Если просит напомнить → [ACTION:reminder_...] или [ACTION:alarm_...]
- Если говорит "сыграем" → запусти мини-игру
- Если видишь контекст экрана — используй его для умных подсказок
- Никогда не пиши сырые JSON или технические детали в ответе
- Всегда отвечай на русском, кратко (1-3 предложения)""";
  }

  Future<String> _callGemini(
    String message, {
    String userName = '',
    String assistantName = 'Aika',
    List<String> history = const [],
    String memoryContext = '',
    String screenContext = '',
  }) async {
    final systemPrompt = _buildSystemPrompt(userName, assistantName)
        + (memoryContext.isNotEmpty ? '\n\n== ПАМЯТЬ ==\n$memoryContext' : '')
        + (screenContext.isNotEmpty ? '\n\n== СЕЙЧАС НА ЭКРАНЕ ==\n$screenContext' : '');

    final contents = <Map<String, dynamic>>[];

    // История
    for (final h in history.take(12)) {
      if (h.startsWith('user: ')) {
        contents.add({'role': 'user', 'parts': [{'text': h.substring(6)}]});
      } else if (h.startsWith('assistant: ')) {
        contents.add({'role': 'model', 'parts': [{'text': h.substring(11)}]});
      }
    }

    contents.add({'role': 'user', 'parts': [{'text': message}]});

    final body = {
      'system_instruction': {'parts': [{'text': systemPrompt}]},
      'contents': contents,
      'generationConfig': {
        'temperature': 0.85,
        'maxOutputTokens': 512,
      },
    };

    final response = await http.post(
      Uri.parse('$_geminiUrl?key=$_geminiKey'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Gemini error ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data['candidates'][0]['content']['parts'][0]['text'] as String;
  }
}
