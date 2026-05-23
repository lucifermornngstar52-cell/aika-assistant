import 'personality_service.dart';
import 'habit_memory_service.dart';
import 'relationship_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  static const String _geminiKey = 'AIzaSyAOerCk0C4vyAkcenHgefVu9miuijaW46Y';
  static const String _geminiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  static String get _openAiKey => 'sk-proj-yZjSi9Ce5puYb1kfGrgITw'
      'JQIoRrab57qErCRPWlGN9DTKRLRNtE'
      '68HOVbLo_xByy5FcH1PtEGT3BlbkFJ'
      'q--UQq-fr6hEMtKPM4vrKfTMYIml8fo1KYZfOijKRaPP2Dn8pr73mrDwec7dKDxUdQQVHZj3MA';
  static const String _openAiUrl = 'https://api.openai.com/v1/chat/completions';

  Future<String> sendMessage(
    String message, {
    String userName = '',
    String assistantName = 'Aika',
    List<String> history = const [],
    String memoryContext = '',
    String screenContext = '',
    String openAiKey = '',
  }) async {
    // GPT is primary, Gemini is fallback
    final effectiveKey = openAiKey.isNotEmpty ? openAiKey : _openAiKey;
    if (effectiveKey.isNotEmpty) {
      try {
        return await _callOpenAi(
          message,
          userName: userName,
          assistantName: assistantName,
          history: history,
          memoryContext: memoryContext,
          screenContext: screenContext,
          openAiKey: effectiveKey,
        );
      } catch (e) {
        final errStr = e.toString();
        // Fallback to Gemini on rate limit or server errors
        if (errStr.contains('429') || errStr.contains('503') || errStr.contains('quota')) {
          try {
            return await _callGemini(
              message,
              userName: userName,
              assistantName: assistantName,
              history: history,
              memoryContext: memoryContext,
              screenContext: screenContext,
            );
          } catch (e2) {
            throw Exception('AI недоступен: GPT — $e | Gemini — $e2');
          }
        }
        throw Exception('AI недоступен: $e');
      }
    }

    // No OpenAI key — use Gemini directly
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
    final personalityPrompt = PersonalityService.systemPromptAddition;
    final habitContext = HabitMemoryService.getContextForAI();
    final relationshipMod = RelationshipService.getPromptModifier(PersonalityService.current.name);
    return "Ты $assistantName — аниме AI-ассистент для Android$userPart. Говоришь кратко, умно. Отвечаешь по-русски.$personalityPrompt$relationshipMod\n\n"
        "${habitContext.isNotEmpty ? habitContext + '\n\n' : ''}"
        "[ACTION:open_youtube] [ACTION:open_telegram] [ACTION:open_chrome] [ACTION:open_camera]\n"
        "[ACTION:flashlight_on] [ACTION:flashlight_off] [ACTION:volume_up] [ACTION:volume_down] [ACTION:battery]\n"
        "[ACTION:currency_all] [ACTION:currency_USD] [ACTION:currency_EUR]\n"
        "[ACTION:what_on_screen] [ACTION:notifications_briefing]\n"
        "[ACTION:reminder_ТЕКСТ_через_N_мин] [ACTION:alarm_HH:MM_ТЕКСТ]\n"
        "[ACTION:game_guess] [ACTION:game_words]\n"
        "[ACTION:launch_app_PACKAGE]\n"
        "Никогда не пиши JSON в ответе. Отвечай кратко 1-3 предложения.";
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
      'generationConfig': {'temperature': 0.85, 'maxOutputTokens': 512},
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

  Future<String> _callOpenAi(
    String message, {
    String userName = '',
    String assistantName = 'Aika',
    List<String> history = const [],
    String memoryContext = '',
    String screenContext = '',
    required String openAiKey,
  }) async {
    final systemPrompt = _buildSystemPrompt(userName, assistantName)
        + (memoryContext.isNotEmpty ? '\n\n== ПАМЯТЬ ==\n$memoryContext' : '')
        + (screenContext.isNotEmpty ? '\n\n== СЕЙЧАС НА ЭКРАНЕ ==\n$screenContext' : '');

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    for (final h in history.take(12)) {
      if (h.startsWith('user: ')) {
        messages.add({'role': 'user', 'content': h.substring(6)});
      } else if (h.startsWith('assistant: ')) {
        messages.add({'role': 'assistant', 'content': h.substring(11)});
      }
    }

    messages.add({'role': 'user', 'content': message});

    final body = {
      'model': 'gpt-4o-mini',
      'messages': messages,
      'temperature': 0.85,
      'max_tokens': 512,
    };

    final response = await http.post(
      Uri.parse(_openAiUrl),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $openAiKey',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('OpenAI error ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data['choices'][0]['message']['content'] as String;
  }
}



