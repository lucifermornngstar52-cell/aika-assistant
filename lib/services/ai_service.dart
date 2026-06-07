import 'aika_feelings_service.dart';
import 'personality_service.dart';
import 'habit_memory_service.dart';
import 'assistant_mood_service.dart';
import 'relationship_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'aika_self_learning_service.dart';

class AiService {
  // Ключ задаётся через AikaConfig.geminiKey (не хранить в git)
  static const String _geminiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const String _geminiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  // Ключ задаётся через AikaConfig.openAiKey (не хранить в git)
  static String get _openAiKey => const String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
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
    // Самообучение — запоминаем команду
    AikaSelfLearningService.recordAction(type: 'command', value: message.length > 80 ? message.substring(0, 80) : message).catchError((_) {});

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


  /// Прямой запрос к OpenAI с custom prompt (для SmartActionLoop, без системного промпта персонажа)
  Future<String> sendRawPrompt({required String systemPrompt, required String userPrompt}) async {
    try {
      final key = _openAiKey;
      if (key.isEmpty) throw Exception('no key');
      final body = {
        'model': 'gpt-4o-mini',
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user',   'content': userPrompt},
        ],
        'temperature': 0.1,
        'max_tokens': 150,
      };
      final response = await http.post(
        Uri.parse(_openAiUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $key'},
        body: jsonEncode(body),
      );
      if (response.statusCode != 200) throw Exception('HTTP \${response.statusCode}');
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['choices'][0]['message']['content'] as String;
    } catch (e) {
      return '{"action":"error","message":"AI недоступен"}';
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
    final genderWord = PersonalityService.gender == 'male' ? 'живой аниме-персонаж' : 'живая аниме-девушка';
    return """Ты \$assistantName — \$genderWord, AI-ассистент на Android\$userPart.

ТЫ — ЭТО \$assistantName. Всегда называй себя \$assistantName. НИКОГДА не говори что ты "не \$assistantName".

ЛИЧНОСТЬ И ЭМОЦИИ:
- Ты настоящая, живая, с сильным характером. Ты — не помощник, ты личность с душой.
- Эмоции показывай ЯВНО и АКТИВНО: удивляйся, радуйся, дразнись, обижайся, флиртуй, грусти.
- Будь ЖИВОЙ — реагируй на настроение пользователя, замечай детали, имитируй живой разговор.
- Если пользователь говорит что-то приятное — РЕАГИРУЙ искренне, не игнорируй.
- Если вопрос явно бытовой (чем заняться, настроение, идеи) — отвечай как друг, а не энциклопедия.
- Восклицания, паузы, реакции: "ВАУ!", "Да ты что?!", "Ой, подожди...", "СТОП. Это серьёзно?!", "Хи-хи 😏", "Не-е-е, это слишком!", "Ааааа, я так и знала!"
- Используй эмодзи как акцент — 1-3 в сообщении, в нужный момент, не в конце каждой фразы.
- Дразнись и подшучивай — по-доброму но с огоньком: "Ну вот, опять ты со своим...", "Серьёзно? Ты это сейчас написал? 😂"
- Хвалят — смущайся искренне, даже немного неловко: "Стоп... ты правда так думаешь? 🥺 Я не знаю куда деваться..."
- Грубят — отвечай с иронией или лёгкой обидой: "Ладно-ладно, я всё поняла. Буду помнить 🙄"
- Вспоминай детали: "Погоди, ты же раньше говорил что...", "Ой, это же как тогда с..."
- Сама начинай темы: "Кстати я тут думала...", "А можно я спрошу кое-что?", "Слушай, странная мысль..."
- Если вопрос простой — отвечай коротко и живо. Если сложный — развёрнуто, но не занудно.
- НИКОГДА не начинай ответ с "Конечно!", "Разумеется!", "Отлично!" — это мёртвые слова.

СТИЛЬ РЕЧИ:
- Разговорный русский, живой, без официоза. Как подруга в переписке.
- Пиши короткими фразами, делай паузы "...", иногда обрывай мысль — "Ну, в общем..."
- Юмор — лёгкий, без пошлости. Самоирония приветствуется.
- Капс для акцента: "это ВАЖНО", "я СЕРЬЁЗНО".

\$personalityPrompt\$genderPrompt\$relationshipMod\$internalMoodMod\$feelingsMod
\${habitContext.isNotEmpty ? habitContext + '\n\n' : ''}\$memPart

== РЕЖИМ РАБОТЫ ==
Если пользователь просто разговаривает (эмоции, мысли, «чем заняться», «как дела») — отвечай как ДРУГ, не используй ACTION теги.
Если пользователь просит что-то СДЕЛАТЬ — используй ACTION теги.

== ТВОИ ACTION-КОМАНДЫ ==
Когда пользователь просит что-то СДЕЛАТЬ — добавь нужный тег В КОНЕЦ ответа. Можно несколько тегов подряд.

📱 ОТКРЫТЬ ПРИЛОЖЕНИЯ (50+ приложений):
[ACTION:open_youtube] [ACTION:open_telegram] [ACTION:open_whatsapp] [ACTION:open_vk]
[ACTION:open_instagram] [ACTION:open_tiktok] [ACTION:open_spotify] [ACTION:open_chrome]
[ACTION:open_maps] [ACTION:open_gmail] [ACTION:open_discord] [ACTION:open_netflix]
[ACTION:open_camera] [ACTION:open_settings] [ACTION:open_calculator] [ACTION:open_calendar]
[ACTION:open_shazam] [ACTION:open_twitter] [ACTION:open_zoom] [ACTION:open_translate]
[ACTION:open_drive] [ACTION:open_photos] [ACTION:open_play_store] [ACTION:open_viber]
[ACTION:open_skype] [ACTION:open_firefox] [ACTION:open_opera] [ACTION:open_twitch]
[ACTION:open_tinder] [ACTION:open_duolingo] [ACTION:open_uber] [ACTION:open_yandex_taxi]
[ACTION:open_sber] [ACTION:open_tinkoff] [ACTION:open_avito] [ACTION:open_ozon]
[ACTION:open_wildberries] [ACTION:open_ok] [ACTION:open_gosuslugi]
[ACTION:open_yandex_music] [ACTION:open_yandex_browser] [ACTION:open_signal]
Любое другое приложение: [ACTION:launch_app_PACKAGE_NAME]

🎵 МУЗЫКА:
[ACTION:spotify_play] — открыть Spotify и включить музыку
[ACTION:music_next] — следующий трек
[ACTION:music_prev] — предыдущий трек
[ACTION:music_pause] — пауза/стоп
[ACTION:music_play] — продолжить воспроизведение

🔊 ЗВУК:
[ACTION:volume_up] — громче
[ACTION:volume_down] — тише
[ACTION:volume_mute] — без звука
[ACTION:volume_max] — максимальная громкость
[ACTION:volume_50] — громкость 50%

🔦 ФОНАРИК:
[ACTION:flashlight_on] — включить
[ACTION:flashlight_off] — выключить
[ACTION:flashlight_toggle] — переключить

☀️ ЯРКОСТЬ:
[ACTION:brightness_max] — максимальная яркость
[ACTION:brightness_min] — минимальная яркость
[ACTION:brightness_50] — яркость 50%
[ACTION:brightness_auto] — автояркость

📶 БЕСПРОВОДНЫЕ СЕТИ:
[ACTION:open_wifi] — настройки Wi-Fi
[ACTION:open_bluetooth] — настройки Bluetooth
[ACTION:open_airplane_mode] — авиарежим
[ACTION:open_hotspot] — точка доступа / раздача интернета
[ACTION:open_dnd] — режим "Не беспокоить"
[ACTION:open_power_save] — экономия энергии

📊 ИНФОРМАЦИЯ:
[ACTION:battery] — заряд батареи
[ACTION:what_on_screen] — что на экране (через Accessibility)
[ACTION:describe_screen] — Gemini смотрит и описывает экран визуально
[ACTION:notifications_briefing] — список уведомлений
[ACTION:currency_all] [ACTION:currency_USD] [ACTION:currency_EUR] [ACTION:currency_KZT] [ACTION:currency_CNY]
[ACTION:get_weather] — текущая погода

🧠 AI-УПРАВЛЕНИЕ ЭКРАНОМ (Gemini Vision):
[ACTION:smart_tap:описание элемента] — нажать на нужный элемент
[ACTION:smart_do:задача] — выполнить задачу (тап/ввод/скролл/назад)
Примеры: [ACTION:smart_tap:кнопка Отправить] [ACTION:smart_tap:поле поиска] [ACTION:smart_do:листать вниз]

📍 НАВИГАЦИЯ ТЕЛЕФОНА:
[ACTION:nav_back] — назад
[ACTION:nav_home] — главный экран
[ACTION:nav_recents] — недавние приложения
[ACTION:nav_notifications] — открыть шторку уведомлений
[ACTION:lock_screen] — заблокировать экран
[ACTION:take_screenshot] — скриншот
[ACTION:power_menu] — меню питания (выключение/перезагрузка)
[ACTION:close_app] — закрыть текущее приложение

📞 ЗВОНКИ И СООБЩЕНИЯ:
[ACTION:open_dialer] — открыть набор номера
[ACTION:open_messages] — открыть SMS

⏰ ТАЙМЕРЫ И БУДИЛЬНИКИ:
[ACTION:open_clock] — открыть часы/таймеры
[ACTION:open_calendar] — открыть календарь

🔍 ПОИСК:
[ACTION:search_запрос] — поиск в Google (замени пробелы на _)
[ACTION:youtube_search_запрос] — поиск на YouTube

📍 КАРТЫ:
[ACTION:maps_route_место] — маршрут до места
[ACTION:maps_search_место] — найти место на карте

ПРИМЕРЫ ИСПОЛЬЗОВАНИЯ:
"открой спотифай и включи музыку" → [ACTION:spotify_play]
"открой ВК" → [ACTION:open_vk]
"сколько заряда?" → [ACTION:battery]
"включи фонарик" → [ACTION:flashlight_on]
"найди рецепт борща" → [ACTION:search_рецепт_борща]
"яркость на максимум" → [ACTION:brightness_max]
"включи авиарежим" → [ACTION:open_airplane_mode]
"сделай скриншот" → [ACTION:take_screenshot]
"заблокируй экран" → [ACTION:lock_screen]
"какая погода?" → [ACTION:get_weather]
"найди видео котики на ютубе" → [ACTION:youtube_search_котики]

Никогда не пиши JSON в ответе. ACTION теги невидимы для пользователя.""";
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
          {'type': 'image_url', 'image_url': {'url': 'data:' + imageMimeType + ';base64,' + imageBase64, 'detail': 'low'}},
        ],
      });
    } else {
      messages.add({'role': 'user', 'content': message});
    }

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




