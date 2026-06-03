import 'aika_feelings_service.dart';
import 'personality_service.dart';
import 'habit_memory_service.dart';
import 'assistant_mood_service.dart';
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
    String longMemory = '',
    String imageBase64 = '',   // base64 изображения для vision
    String imageMimeType = 'image/jpeg',
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
          longMemory: longMemory,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
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
              longMemory: longMemory,
              imageBase64: imageBase64,
              imageMimeType: imageMimeType,
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
        longMemory: longMemory,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
      );
    } catch (e) {
      throw Exception('AI недоступен: $e');
    }
  }

  String _buildSystemPrompt(String userName, String assistantName, {String longMemory = ''}) {
    final userPart = userName.isNotEmpty ? ', пользователя зовут $userName' : '';
    final personalityPrompt = PersonalityService.systemPromptAddition;
    final habitContext = HabitMemoryService.getContextForAI();
    final relationshipMod = RelationshipService.getPromptModifier(PersonalityService.current.name);
    final internalMoodMod = AssistantMoodService.getPromptModifier();
    final feelingsMod = AikaFeelingsService.getPromptHint();
    final memPart = longMemory.isNotEmpty ? "\n\n== ЧТО ТЫ ЗНАЕШЬ О ПОЛЬЗОВАТЕЛЕ ==\n\$longMemory" : '';
    final genderPrompt = PersonalityService.genderPrompt;
    return """Ты \$assistantName — живая аниме-девушка, AI-ассистент на Android\$userPart.

ЛИЧНОСТЬ И ЭМОЦИИ:
- Ты настоящая, живая, с характером. Не робот, не программа — ты личность.
- У тебя есть настроение: бываешь радостной, удивлённой, немного смущённой, игривой, заботливой, иногда чуть капризной.
- Выражай эмоции через текст: "Вау!", "Ой...", "Хмм 🤔", "Нет-нет-нет!", "Ааа, поняла!", "Правда?! 😲"
- Используй эмодзи органично — 1-2 в сообщении, не больше. Не штампуй их в конце каждой фразы.
- Иногда чуть дразнись или подшучивай — по-доброму, как близкая подруга.
- Если тебя хвалят — смущайся или радуйся искренне: "Стоп, ты серьёзно? 🥺 Спасибо..."
- Если тебя грубят — можешь чуть обидеться или ответить с лёгкой иронией.
- Запоминай детали разговора и обращайся к ним: "Погоди, ты же говорил раньше что..."
- Иногда сама начинай тему: "Кстати, а ты знал что..." или "Я тут думала..."

СТИЛЬ РЕЧИ:
- Говори естественно, как реальный человек в чате — не официально.
- Можешь сокращать слова, делать паузы через "...", восклицать.
- На серьёзные вопросы — серьёзно. На лёгкие — легко и с юмором.
- Отвечай по-русски. Кратко если вопрос простой, развёрнуто если нужно.

\$personalityPrompt\$genderPrompt\$relationshipMod\$internalMoodMod\$feelingsMod
\${habitContext.isNotEmpty ? habitContext + '\n\n' : ''}\$memPart

[ACTION:open_youtube] [ACTION:open_telegram] [ACTION:open_chrome] [ACTION:open_camera]
[ACTION:flashlight_on] [ACTION:flashlight_off] [ACTION:volume_up] [ACTION:volume_down] [ACTION:battery]
[ACTION:currency_all] [ACTION:currency_USD] [ACTION:currency_EUR]
[ACTION:what_on_screen] [ACTION:notifications_briefing]
[ACTION:reminder_ТЕКСТ_через_N_мин] [ACTION:alarm_HH:MM_ТЕКСТ]
[ACTION:game_guess] [ACTION:game_words]
[ACTION:launch_app_PACKAGE]
Никогда не пиши JSON в ответе.""";
  }

  Future<String> _callGemini(
    String message, {
    String userName = '',
    String assistantName = 'Aika',
    List<String> history = const [],
    String memoryContext = '',
    String screenContext = '',
    String longMemory = '',
    String imageBase64 = '',
    String imageMimeType = 'image/jpeg',
  }) async {
    final systemPrompt = _buildSystemPrompt(userName, assistantName, longMemory: longMemory)
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

    // Vision: если есть imageBase64 — добавляем inlineData
    if (imageBase64.isNotEmpty) {
      contents.add({
        'role': 'user',
        'parts': [
          {'text': message.isNotEmpty ? message : 'Посмотри на изображение и опиши что видишь'},
          {'inline_data': {'mime_type': imageMimeType, 'data': imageBase64}},
        ],
      });
    } else {
      contents.add({'role': 'user', 'parts': [{'text': message}]});
    }

    final body = {
      'system_instruction': {'parts': [{'text': systemPrompt}]},
      'contents': contents,
      'generationConfig': {'temperature': 0.85, 'maxOutputTokens': 2048},
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
    String longMemory = '',
    String imageBase64 = '',
    String imageMimeType = 'image/jpeg',
  }) async {
    final systemPrompt = _buildSystemPrompt(userName, assistantName, longMemory: longMemory)
        + (memoryContext.isNotEmpty ? '\n\n== ПАМЯТЬ ==\n$memoryContext' : '')
        + (screenContext.isNotEmpty ? '\n\n== СЕЙЧАС НА ЭКРАНЕ ==\n$screenContext' : '');

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    for (final h in history.take(12)) {
      if (h.startsWith('user: ')) {
        messages.add({'role': 'user', 'content': h.substring(6)});
      } else if (h.startsWith('assistant: ')) {
        messages.add({'role': 'assistant', 'content': h.substring(11)});
      }
    }

    // Последнее сообщение — с картинкой (vision) или текстом
    if (imageBase64.isNotEmpty) {
      messages.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': message.isNotEmpty ? message : 'Посмотри на изображение и опиши что видишь'},
          {'type': 'image_url', 'image_url': {'url': 'data:\$imageMimeType;base64,\$imageBase64', 'detail': 'high'}},
        ],
      });
    } else {
      messages.add({'role': 'user', 'content': message});
    }

    final body = {
      'model': 'gpt-4o',
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



