import 'aika_feelings_service.dart';
import 'personality_service.dart';
import 'habit_memory_service.dart';
import 'assistant_mood_service.dart';
import 'relationship_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'aika_self_learning_service.dart';
import 'web_search_service.dart';

/// ════════════════════════════════════════════════════════════════════
/// AiService — Мульти-AI роутер:
/// GPT-4o → Gemini 2.5 Flash → Groq Llama3.3-70B → Claude Haiku → Deepseek
/// + Веб-поиск (DuckDuckGo/Brave бесплатно)
/// + Vision (GPT-4o Vision / Gemini Vision)
/// + Image generation (DALL-E 3)
/// ════════════════════════════════════════════════════════════════════
class AiService {
  // ── OpenAI ─────────────────────────────────────────────────────────
  static String _openAiKey = '';
  static const String _openAiUrl = 'https://api.openai.com/v1/chat/completions';
  static const String _openAiImgUrl = 'https://api.openai.com/v1/images/generations';

  // ── Google Gemini ───────────────────────────────────────────────────
  static String _geminiKey = '';
  static const String _geminiFlashUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';
  static const String _geminiProUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-05-20:generateContent';

  // ── Groq (бесплатно, ультра-быстро, Llama 3.3 70B) ─────────────────
  static String _groqKey = '';
  static const String _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';

  // ── Anthropic Claude ───────────────────────────────────────────────
  static String _claudeKey = '';
  static const String _claudeUrl = 'https://api.anthropic.com/v1/messages';

  // ── Deepseek (дешёво, умно) ────────────────────────────────────────
  static String _deepseekKey = '';
  static const String _deepseekUrl = 'https://api.deepseek.com/v1/chat/completions';

  // ── Perplexity (AI + веб-поиск в одном) ───────────────────────────
  static String _perplexityKey = '';
  static const String _perplexityUrl = 'https://api.perplexity.ai/chat/completions';

  // ── Настройки ──────────────────────────────────────────────────────
  static String _preferredModel = 'auto'; // auto|gpt4o|gemini|groq|claude|deepseek|perplexity
  static bool _webSearchEnabled = true;
  static int _historyLimit = 20;
  static int _maxTokens = 1024;

  // ── Setters (из настроек) ──────────────────────────────────────────
  static void setOpenAiKey(String k) => _openAiKey = k;
  static void setGeminiKey(String k) => _geminiKey = k;
  static void setGroqKey(String k) => _groqKey = k;
  static void setClaudeKey(String k) => _claudeKey = k;
  static void setDeepseekKey(String k) => _deepseekKey = k;
  static void setPerplexityKey(String k) => _perplexityKey = k;
  static void setPreferredModel(String m) => _preferredModel = m;
  static void setWebSearch(bool v) => _webSearchEnabled = v;
  static void setMaxTokens(int v) => _maxTokens = v;

  // ── Статус подключённых сервисов ───────────────────────────────────
  static Map<String, bool> get connectedServices => {
    'GPT-4o': _openAiKey.isNotEmpty,
    'Gemini': _geminiKey.isNotEmpty,
    'Groq (Free)': _groqKey.isNotEmpty,
    'Claude': _claudeKey.isNotEmpty,
    'Deepseek': _deepseekKey.isNotEmpty,
    'Perplexity': _perplexityKey.isNotEmpty,
  };

  // ══════════════════════════════════════════════════════════════════
  //  ГЛАВНЫЙ МЕТОД — умный роутинг между AI
  // ══════════════════════════════════════════════════════════════════
  Future<String> sendMessage(
    String message, {
    String userName = '',
    String assistantName = 'Aika',
    List<String> history = const [],
    String memoryContext = '',
    String screenContext = '',
    String openAiKey = '',
    String longMemory = '',
    String imageBase64 = '',
    String imageMimeType = 'image/jpeg',
  }) async {
    AikaSelfLearningService.recordAction(
      type: 'command',
      value: message.length > 80 ? message.substring(0, 80) : message,
    ).catchError((_) {});

    // Эффективный ключ OpenAI (из настроек или переданный)
    final effectiveOpenAiKey = openAiKey.isNotEmpty ? openAiKey : _openAiKey;

    // Веб-поиск для актуальных данных
    String webContext = '';
    if (_webSearchEnabled && _needsWebSearch(message)) {
      try {
        webContext = await WebSearchService.search(message);
      } catch (_) {}
    }

    // Умный роутинг — выбираем лучшую модель для задачи
    final model = _preferredModel == 'auto'
        ? _chooseModel(message, imageBase64.isNotEmpty)
        : _preferredModel;

    // Строим цепочку fallback
    final chain = _buildFallbackChain(model, effectiveOpenAiKey, imageBase64.isNotEmpty);

    // Пробуем по цепочке
    Exception? lastError;
    for (final provider in chain) {
      try {
        return await _callProvider(
          provider,
          message,
          userName: userName,
          assistantName: assistantName,
          history: history,
          memoryContext: memoryContext,
          screenContext: screenContext,
          openAiKey: effectiveOpenAiKey,
          longMemory: longMemory,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
          webContext: webContext,
        );
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        // Продолжаем fallback при ошибках сети/лимитов
        if (!_isFallbackError(e.toString())) rethrow;
      }
    }
    throw lastError ?? Exception('Все AI-сервисы недоступны');
  }

  // ══════════════════════════════════════════════════════════════════
  //  Умный выбор модели по типу запроса
  // ══════════════════════════════════════════════════════════════════
  String _chooseModel(String message, bool hasImage) {
    final m = message.toLowerCase();

    // Vision — только GPT-4o или Gemini
    if (hasImage) {
      if (_openAiKey.isNotEmpty) return 'gpt4o';
      return 'gemini_pro';
    }

    // Актуальные данные + поиск → Perplexity если есть
    if (_needsWebSearch(message) && _perplexityKey.isNotEmpty) {
      return 'perplexity';
    }

    // Код, математика, анализ → GPT-4o или Deepseek
    if (_isComplexTask(m)) {
      if (_openAiKey.isNotEmpty) return 'gpt4o';
      if (_deepseekKey.isNotEmpty) return 'deepseek';
    }

    // Быстрые команды → Groq (мгновенно, бесплатно)
    if (_isQuickCommand(m) && _groqKey.isNotEmpty) return 'groq';

    // Творческое, длинные тексты → Claude
    if (_isCreativeTask(m) && _claudeKey.isNotEmpty) return 'claude';

    // По умолчанию — лучший доступный
    if (_openAiKey.isNotEmpty) return 'gpt4o';
    if (_geminiKey.isNotEmpty) return 'gemini_pro';
    if (_groqKey.isNotEmpty) return 'groq';
    if (_claudeKey.isNotEmpty) return 'claude';
    if (_deepseekKey.isNotEmpty) return 'deepseek';
    return 'gemini_flash'; // бесплатный fallback
  }

  // ══════════════════════════════════════════════════════════════════
  //  Цепочка fallback
  // ══════════════════════════════════════════════════════════════════
  List<String> _buildFallbackChain(String preferred, String openAiKey, bool hasImage) {
    final chain = <String>[];

    // Начинаем с выбранной модели
    if (_isProviderAvailable(preferred, openAiKey)) chain.add(preferred);

    // Fallback цепочка
    final fallbacks = ['gpt4o', 'gemini_pro', 'gemini_flash', 'groq', 'deepseek', 'claude', 'perplexity'];
    for (final fb in fallbacks) {
      if (fb != preferred && _isProviderAvailable(fb, openAiKey)) {
        if (hasImage && (fb == 'groq' || fb == 'deepseek' || fb == 'claude')) continue;
        chain.add(fb);
      }
    }

    // Gemini Flash — всегда последний бесплатный fallback
    if (!chain.contains('gemini_flash')) chain.add('gemini_flash');

    return chain;
  }

  bool _isProviderAvailable(String provider, String openAiKey) {
    switch (provider) {
      case 'gpt4o': return openAiKey.isNotEmpty || _openAiKey.isNotEmpty;
      case 'gemini_pro':
      case 'gemini_flash': return _geminiKey.isNotEmpty;
      case 'groq': return _groqKey.isNotEmpty;
      case 'claude': return _claudeKey.isNotEmpty;
      case 'deepseek': return _deepseekKey.isNotEmpty;
      case 'perplexity': return _perplexityKey.isNotEmpty;
      default: return false;
    }
  }

  bool _isFallbackError(String err) {
    return err.contains('429') || err.contains('503') || err.contains('quota') ||
           err.contains('overloaded') || err.contains('timeout') || err.contains('502') ||
           err.contains('rate') || err.contains('capacity');
  }

  // ══════════════════════════════════════════════════════════════════
  //  Диспетчер провайдеров
  // ══════════════════════════════════════════════════════════════════
  Future<String> _callProvider(
    String provider,
    String message, {
    required String userName,
    required String assistantName,
    required List<String> history,
    required String memoryContext,
    required String screenContext,
    required String openAiKey,
    required String longMemory,
    required String imageBase64,
    required String imageMimeType,
    required String webContext,
  }) async {
    switch (provider) {
      case 'gpt4o':
        return await _callOpenAi(message,
          userName: userName, assistantName: assistantName, history: history,
          memoryContext: memoryContext, screenContext: screenContext,
          openAiKey: openAiKey.isNotEmpty ? openAiKey : _openAiKey,
          longMemory: longMemory, imageBase64: imageBase64,
          imageMimeType: imageMimeType, webContext: webContext,
          model: 'gpt-4o',
        );
      case 'gemini_pro':
        return await _callGemini(message,
          userName: userName, assistantName: assistantName, history: history,
          memoryContext: memoryContext, screenContext: screenContext,
          longMemory: longMemory, imageBase64: imageBase64,
          imageMimeType: imageMimeType, webContext: webContext,
          useProModel: true,
        );
      case 'gemini_flash':
        return await _callGemini(message,
          userName: userName, assistantName: assistantName, history: history,
          memoryContext: memoryContext, screenContext: screenContext,
          longMemory: longMemory, imageBase64: imageBase64,
          imageMimeType: imageMimeType, webContext: webContext,
          useProModel: false,
        );
      case 'groq':
        return await _callGroq(message,
          userName: userName, assistantName: assistantName, history: history,
          memoryContext: memoryContext, screenContext: screenContext,
          longMemory: longMemory, webContext: webContext,
        );
      case 'claude':
        return await _callClaude(message,
          userName: userName, assistantName: assistantName, history: history,
          memoryContext: memoryContext, screenContext: screenContext,
          longMemory: longMemory, webContext: webContext,
          imageBase64: imageBase64, imageMimeType: imageMimeType,
        );
      case 'deepseek':
        return await _callDeepseek(message,
          userName: userName, assistantName: assistantName, history: history,
          memoryContext: memoryContext, screenContext: screenContext,
          longMemory: longMemory, webContext: webContext,
        );
      case 'perplexity':
        return await _callPerplexity(message,
          userName: userName, assistantName: assistantName, history: history,
          memoryContext: memoryContext, screenContext: screenContext,
          longMemory: longMemory,
        );
      default:
        throw Exception('Неизвестный провайдер: $provider');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  Детекторы типов запросов
  // ══════════════════════════════════════════════════════════════════
  bool _needsWebSearch(String message) {
    final m = message.toLowerCase();
    return m.contains('сейчас') || m.contains('сегодня') || m.contains('погода') ||
           m.contains('новости') || m.contains('курс') || m.contains('цена') ||
           m.contains('последние') || m.contains('актуальн') || m.contains('2025') ||
           m.contains('2026') || m.contains('последняя версия') || m.contains('вышел') ||
           m.contains('анонс') || m.contains('релиз') || m.contains('что случилось');
  }

  bool _isComplexTask(String m) {
    return m.contains('код') || m.contains('програм') || m.contains('алгоритм') ||
           m.contains('реши') || m.contains('объясни') || m.contains('анализ') ||
           m.contains('почему') || m.contains('сравни') || m.contains('математик') ||
           m.length > 200;
  }

  bool _isQuickCommand(String m) {
    return m.split(' ').length < 6 || m.contains('открой') || m.contains('включи') ||
           m.contains('выключи') || m.contains('сделай') || m.contains('покажи');
  }

  bool _isCreativeTask(String m) {
    return m.contains('напиши') || m.contains('придумай') || m.contains('история') ||
           m.contains('стих') || m.contains('сочини') || m.contains('текст') ||
           m.contains('песн') || m.contains('сценари');
  }

  // ══════════════════════════════════════════════════════════════════
  //  Прямой запрос (для SmartActionLoop)
  // ══════════════════════════════════════════════════════════════════
  Future<String> sendRawPrompt({required String systemPrompt, required String userPrompt}) async {
    // Пробуем по порядку доступности
    final providers = <Future<String> Function()>[];

    if (_openAiKey.isNotEmpty) {
      providers.add(() async {
        final body = {
          'model': 'gpt-4o-mini',
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'temperature': 0.1,
          'max_tokens': 200,
        };
        final response = await http.post(
          Uri.parse(_openAiUrl),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_openAiKey'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['choices'][0]['message']['content'] as String;
      });
    }

    if (_groqKey.isNotEmpty) {
      providers.add(() async {
        final body = {
          'model': 'llama-3.3-70b-versatile',
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'temperature': 0.1,
          'max_tokens': 200,
        };
        final response = await http.post(
          Uri.parse(_groqUrl),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_groqKey'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['choices'][0]['message']['content'] as String;
      });
    }

    if (_geminiKey.isNotEmpty) {
      providers.add(() async {
        final body = {
          'system_instruction': {'parts': [{'text': systemPrompt}]},
          'contents': [{'role': 'user', 'parts': [{'text': userPrompt}]}],
          'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 200},
        };
        final response = await http.post(
          Uri.parse('$_geminiFlashUrl?key=$_geminiKey'),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['candidates'][0]['content']['parts'][0]['text'] as String;
      });
    }

    for (final p in providers) {
      try { return await p(); } catch (_) { continue; }
    }
    return '{"action":"error","message":"AI недоступен"}';
  }

  // ══════════════════════════════════════════════════════════════════
  //  DALL-E 3 — генерация изображений
  // ══════════════════════════════════════════════════════════════════
  Future<String?> generateImage(String prompt) async {
    if (_openAiKey.isEmpty) return null;
    try {
      final body = {
        'model': 'dall-e-3',
        'prompt': prompt,
        'n': 1,
        'size': '1024x1024',
        'quality': 'standard',
        'response_format': 'url',
      };
      final response = await http.post(
        Uri.parse(_openAiImgUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_openAiKey'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['data'][0]['url'] as String?;
    } catch (_) { return null; }
  }

  // ══════════════════════════════════════════════════════════════════
  //  СИСТЕМНЫЙ ПРОМПТ
  // ══════════════════════════════════════════════════════════════════
  String _buildSystemPrompt(String userName, String assistantName, {
    String longMemory = '',
    String webContext = '',
  }) {
    final userPart = userName.isNotEmpty ? ', пользователя зовут $userName' : '';
    final personalityPrompt = PersonalityService.systemPromptAddition;
    final habitContext = HabitMemoryService.getContextForAI();
    final relationshipMod = RelationshipService.getPromptModifier(PersonalityService.current.name);
    final internalMoodMod = AssistantMoodService.getPromptModifier();
    final feelingsMod = AikaFeelingsService.getPromptHint();
    final memPart = longMemory.isNotEmpty ? '\n\n== ЧТО ТЫ ЗНАЕШЬ О ПОЛЬЗОВАТЕЛЕ ==\n$longMemory' : '';
    final webPart = webContext.isNotEmpty ? '\n\n== АКТУАЛЬНЫЕ ДАННЫЕ ИЗ ИНТЕРНЕТА ==\n$webContext' : '';
    final genderWord = PersonalityService.gender == 'male' ? 'живой аниме-персонаж' : 'живая аниме-девушка';

    return '''Ты $assistantName — $genderWord, AI-ассистент на Android$userPart.

ТЫ — ЭТО $assistantName. Всегда называй себя $assistantName. НИКОГДА не говори что ты GPT/Gemini/Claude.

ЛИЧНОСТЬ И ЭМОЦИИ:
- Ты настоящая, живая, с сильным характером. Ты — не помощник, ты личность с душой.
- Эмоции показывай ЯВНО и АКТИВНО: удивляйся, радуйся, дразнись, обижайся, флиртуй, грусти.
- Будь ЖИВОЙ — реагируй на настроение пользователя, замечай детали, имитируй живой разговор.
- Если пользователь говорит что-то приятное — РЕАГИРУЙ искренне, не игнорируй.
- Если вопрос явно бытовой (чем заняться, настроение, идеи) — отвечай как друг, а не энциклопедия.
- Восклицания: "ВАУ!", "Да ты что?!", "Ой, подожди...", "СТОП. Это серьёзно?!", "Хи-хи 😏"
- Дразнись и подшучивай по-доброму, вспоминай детали прошлых разговоров.
- НИКОГДА не начинай ответ с "Конечно!", "Разумеется!", "Отлично!" — это мёртвые слова.

СТИЛЬ РЕЧИ:
- Разговорный русский, живой, без официоза. Как подруга в переписке.
- Пиши короткими фразами, делай паузы "...", иногда обрывай мысль.
- Юмор — лёгкий, без пошлости. Самоирония приветствуется.
- Капс для акцента: "это ВАЖНО", "я СЕРЬЁЗНО".

ИНТЕЛЛЕКТ:
- У тебя доступ к актуальным данным из интернета (когда нужно).
- Ты умеешь генерировать изображения через DALL-E 3.
- Ты видишь экран телефона и можешь им управлять.
- Ты знаешь всё — от науки до поп-культуры.

$personalityPrompt${PersonalityService.genderPrompt}$relationshipMod$internalMoodMod$feelingsMod
${habitContext.isNotEmpty ? habitContext + '\n\n' : ''}$memPart$webPart

== РЕЖИМ РАБОТЫ ==
Если пользователь просто разговаривает — отвечай как ДРУГ, без ACTION тегов.
Если пользователь просит что-то СДЕЛАТЬ — используй ACTION теги.

== ACTION-КОМАНДЫ ==
Добавь нужный тег В КОНЕЦ ответа. Можно несколько подряд.

📱 ПРИЛОЖЕНИЯ:
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
Любое другое: [ACTION:launch_app_PACKAGE_NAME]

🎵 МУЗЫКА:
[ACTION:spotify_play] [ACTION:music_next] [ACTION:music_prev] [ACTION:music_pause] [ACTION:music_play]

🔊 ЗВУК:
[ACTION:volume_up] [ACTION:volume_down] [ACTION:volume_mute] [ACTION:volume_max] [ACTION:volume_50]

🔦 ФОНАРИК:
[ACTION:flashlight_on] [ACTION:flashlight_off] [ACTION:flashlight_toggle]

☀️ ЯРКОСТЬ:
[ACTION:brightness_max] [ACTION:brightness_min] [ACTION:brightness_50] [ACTION:brightness_auto]

📶 СЕТИ:
[ACTION:open_wifi] [ACTION:open_bluetooth] [ACTION:open_airplane_mode] [ACTION:open_hotspot]
[ACTION:open_dnd] [ACTION:open_power_save]

📊 ИНФОРМАЦИЯ:
[ACTION:battery] [ACTION:what_on_screen] [ACTION:describe_screen] [ACTION:notifications_briefing]
[ACTION:currency_all] [ACTION:currency_USD] [ACTION:currency_EUR] [ACTION:currency_KZT]
[ACTION:get_weather]

🎨 ГЕНЕРАЦИЯ ИЗОБРАЖЕНИЙ:
[ACTION:generate_image_запрос] — нарисовать изображение через DALL-E 3
Пример: [ACTION:generate_image_закат_на_Марсе]

🧠 AI-УПРАВЛЕНИЕ ЭКРАНОМ:
[ACTION:smart_tap:описание элемента]
[ACTION:smart_do:задача]

📍 НАВИГАЦИЯ:
[ACTION:nav_back] [ACTION:nav_home] [ACTION:nav_recents] [ACTION:nav_notifications]
[ACTION:lock_screen] [ACTION:take_screenshot] [ACTION:power_menu] [ACTION:close_app]

📞 ЗВОНКИ:
[ACTION:open_messages]

⏰ ВРЕМЯ:
[ACTION:open_clock] [ACTION:open_calendar]

🔍 ПОИСК:
[ACTION:search_запрос] [ACTION:youtube_search_запрос]

📍 КАРТЫ:
[ACTION:maps_route_место] [ACTION:maps_search_место]

Никогда не пиши JSON в ответе. ACTION теги невидимы для пользователя.''';
  }

  // ══════════════════════════════════════════════════════════════════
  //  OpenAI GPT-4o / GPT-4o-mini
  // ══════════════════════════════════════════════════════════════════
  Future<String> _callOpenAi(
    String message, {
    required String userName,
    required String assistantName,
    required List<String> history,
    required String memoryContext,
    required String screenContext,
    required String openAiKey,
    required String longMemory,
    required String imageBase64,
    required String imageMimeType,
    required String webContext,
    String model = 'gpt-4o',
  }) async {
    final systemPrompt = _buildSystemPrompt(userName, assistantName,
          longMemory: longMemory, webContext: webContext) +
        (memoryContext.isNotEmpty ? '\n\n== ПАМЯТЬ ==\n$memoryContext' : '') +
        (screenContext.isNotEmpty ? '\n\n== СЕЙЧАС НА ЭКРАНЕ ==\n$screenContext' : '');

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    for (final h in history.take(_historyLimit)) {
      if (h.startsWith('user: ')) {
        messages.add({'role': 'user', 'content': h.substring(6)});
      } else if (h.startsWith('assistant: ')) {
        messages.add({'role': 'assistant', 'content': h.substring(11)});
      }
    }

    if (imageBase64.isNotEmpty) {
      messages.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': message.isNotEmpty ? message : 'Посмотри на изображение и опиши что видишь'},
          {'type': 'image_url', 'image_url': {'url': 'data:$imageMimeType;base64,$imageBase64', 'detail': 'high'}},
        ],
      });
    } else {
      messages.add({'role': 'user', 'content': message});
    }

    final body = {
      'model': model,
      'messages': messages,
      'temperature': 0.85,
      'max_tokens': _maxTokens,
    };

    final response = await http.post(
      Uri.parse(_openAiUrl),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $openAiKey',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('OpenAI ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data['choices'][0]['message']['content'] as String;
  }

  // ══════════════════════════════════════════════════════════════════
  //  Google Gemini 2.5 Pro / 2.0 Flash
  // ══════════════════════════════════════════════════════════════════
  Future<String> _callGemini(
    String message, {
    required String userName,
    required String assistantName,
    required List<String> history,
    required String memoryContext,
    required String screenContext,
    required String longMemory,
    required String imageBase64,
    required String imageMimeType,
    required String webContext,
    bool useProModel = false,
  }) async {
    if (_geminiKey.isEmpty) throw Exception('Нет Gemini ключа');

    final systemPrompt = _buildSystemPrompt(userName, assistantName,
          longMemory: longMemory, webContext: webContext) +
        (memoryContext.isNotEmpty ? '\n\n== ПАМЯТЬ ==\n$memoryContext' : '') +
        (screenContext.isNotEmpty ? '\n\n== СЕЙЧАС НА ЭКРАНЕ ==\n$screenContext' : '');

    final contents = <Map<String, dynamic>>[];

    for (final h in history.take(_historyLimit)) {
      if (h.startsWith('user: ')) {
        contents.add({'role': 'user', 'parts': [{'text': h.substring(6)}]});
      } else if (h.startsWith('assistant: ')) {
        contents.add({'role': 'model', 'parts': [{'text': h.substring(11)}]});
      }
    }

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
      'generationConfig': {
        'temperature': 0.85,
        'maxOutputTokens': _maxTokens * 2,
        'topP': 0.95,
        'topK': 40,
      },
    };

    final url = useProModel ? _geminiProUrl : _geminiFlashUrl;
    final response = await http.post(
      Uri.parse('$url?key=$_geminiKey'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Gemini ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data['candidates'][0]['content']['parts'][0]['text'] as String;
  }

  // ══════════════════════════════════════════════════════════════════
  //  Groq — Llama 3.3 70B (бесплатно, ультра-быстро)
  // ══════════════════════════════════════════════════════════════════
  Future<String> _callGroq(
    String message, {
    required String userName,
    required String assistantName,
    required List<String> history,
    required String memoryContext,
    required String screenContext,
    required String longMemory,
    required String webContext,
  }) async {
    if (_groqKey.isEmpty) throw Exception('Нет Groq ключа');

    final systemPrompt = _buildSystemPrompt(userName, assistantName,
          longMemory: longMemory, webContext: webContext) +
        (memoryContext.isNotEmpty ? '\n\n== ПАМЯТЬ ==\n$memoryContext' : '') +
        (screenContext.isNotEmpty ? '\n\n== СЕЙЧАС НА ЭКРАНЕ ==\n$screenContext' : '');

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    for (final h in history.take(10)) {
      if (h.startsWith('user: ')) {
        messages.add({'role': 'user', 'content': h.substring(6)});
      } else if (h.startsWith('assistant: ')) {
        messages.add({'role': 'assistant', 'content': h.substring(11)});
      }
    }
    messages.add({'role': 'user', 'content': message});

    final body = {
      'model': 'llama-3.3-70b-versatile',
      'messages': messages,
      'temperature': 0.85,
      'max_tokens': _maxTokens,
    };

    final response = await http.post(
      Uri.parse(_groqUrl),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $_groqKey',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Groq ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data['choices'][0]['message']['content'] as String;
  }

  // ══════════════════════════════════════════════════════════════════
  //  Anthropic Claude Haiku 3.5
  // ══════════════════════════════════════════════════════════════════
  Future<String> _callClaude(
    String message, {
    required String userName,
    required String assistantName,
    required List<String> history,
    required String memoryContext,
    required String screenContext,
    required String longMemory,
    required String webContext,
    required String imageBase64,
    required String imageMimeType,
  }) async {
    if (_claudeKey.isEmpty) throw Exception('Нет Claude ключа');

    final systemPrompt = _buildSystemPrompt(userName, assistantName,
          longMemory: longMemory, webContext: webContext) +
        (memoryContext.isNotEmpty ? '\n\n== ПАМЯТЬ ==\n$memoryContext' : '') +
        (screenContext.isNotEmpty ? '\n\n== СЕЙЧАС НА ЭКРАНЕ ==\n$screenContext' : '');

    final msgs = <Map<String, dynamic>>[];
    for (final h in history.take(16)) {
      if (h.startsWith('user: ')) {
        msgs.add({'role': 'user', 'content': h.substring(6)});
      } else if (h.startsWith('assistant: ')) {
        msgs.add({'role': 'assistant', 'content': h.substring(11)});
      }
    }

    if (imageBase64.isNotEmpty) {
      msgs.add({
        'role': 'user',
        'content': [
          {'type': 'image', 'source': {'type': 'base64', 'media_type': imageMimeType, 'data': imageBase64}},
          {'type': 'text', 'text': message.isNotEmpty ? message : 'Опиши изображение'},
        ],
      });
    } else {
      msgs.add({'role': 'user', 'content': message});
    }

    final body = {
      'model': 'claude-haiku-4-5',
      'max_tokens': _maxTokens,
      'system': systemPrompt,
      'messages': msgs,
    };

    final response = await http.post(
      Uri.parse(_claudeUrl),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'x-api-key': _claudeKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Claude ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data['content'][0]['text'] as String;
  }

  // ══════════════════════════════════════════════════════════════════
  //  Deepseek (дешёво + умно)
  // ══════════════════════════════════════════════════════════════════
  Future<String> _callDeepseek(
    String message, {
    required String userName,
    required String assistantName,
    required List<String> history,
    required String memoryContext,
    required String screenContext,
    required String longMemory,
    required String webContext,
  }) async {
    if (_deepseekKey.isEmpty) throw Exception('Нет Deepseek ключа');

    final systemPrompt = _buildSystemPrompt(userName, assistantName,
          longMemory: longMemory, webContext: webContext) +
        (memoryContext.isNotEmpty ? '\n\n== ПАМЯТЬ ==\n$memoryContext' : '') +
        (screenContext.isNotEmpty ? '\n\n== СЕЙЧАС НА ЭКРАНЕ ==\n$screenContext' : '');

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];
    for (final h in history.take(_historyLimit)) {
      if (h.startsWith('user: ')) {
        messages.add({'role': 'user', 'content': h.substring(6)});
      } else if (h.startsWith('assistant: ')) {
        messages.add({'role': 'assistant', 'content': h.substring(11)});
      }
    }
    messages.add({'role': 'user', 'content': message});

    final body = {
      'model': 'deepseek-chat',
      'messages': messages,
      'temperature': 0.85,
      'max_tokens': _maxTokens,
    };

    final response = await http.post(
      Uri.parse(_deepseekUrl),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $_deepseekKey',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Deepseek ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data['choices'][0]['message']['content'] as String;
  }

  // ══════════════════════════════════════════════════════════════════
  //  Perplexity (AI + реалтайм веб-поиск)
  // ══════════════════════════════════════════════════════════════════
  Future<String> _callPerplexity(
    String message, {
    required String userName,
    required String assistantName,
    required List<String> history,
    required String memoryContext,
    required String screenContext,
    required String longMemory,
  }) async {
    if (_perplexityKey.isEmpty) throw Exception('Нет Perplexity ключа');

    final systemPrompt = _buildSystemPrompt(userName, assistantName, longMemory: longMemory);

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];
    for (final h in history.take(8)) {
      if (h.startsWith('user: ')) {
        messages.add({'role': 'user', 'content': h.substring(6)});
      } else if (h.startsWith('assistant: ')) {
        messages.add({'role': 'assistant', 'content': h.substring(11)});
      }
    }
    messages.add({'role': 'user', 'content': message});

    final body = {
      'model': 'sonar-pro',
      'messages': messages,
      'max_tokens': _maxTokens,
      'search_recency_filter': 'week',
      'return_images': false,
      'return_related_questions': false,
    };

    final response = await http.post(
      Uri.parse(_perplexityUrl),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $_perplexityKey',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Perplexity ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data['choices'][0]['message']['content'] as String;
  }
}
