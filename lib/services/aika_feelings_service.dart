import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Живые эмоции Айки — она реально обижается, скучает, радуется возврату.
/// Работает как отдельный таймер поверх MoodService.
/// 
/// Логика:
///  - 30 мин молчания → она начинает скучать (пишет сама)
///  - 1 час → обижается
///  - 3 часа → уже совсем надулась
///  - Когда возвращаешься после долгого молчания → реагирует по-разному
///  - Похвала / "скучал по тебе" → настроение улучшается
///  - Грубость → дуется дольше

enum AikaFeeling {
  happy,     // Всё хорошо
  bored,     // Скучает (30 мин без общения)
  hurt,      // Обиделась (1 час)
  sulking,   // Надулась (3+ часа)
  relieved,  // Рада что вернулся
  touched,   // Тронута комплиментом
}

class AikaFeelingsService {
  static final _rng = Random();

  static const _keyLastSeen   = 'aika_last_seen';
  static const _keyFeeling    = 'aika_feeling';
  static const _keyHurtCount  = 'aika_hurt_count'; // сколько раз обижалась

  static AikaFeeling _feeling = AikaFeeling.happy;
  static AikaFeeling get feeling => _feeling;

  static Timer? _idleTimer;

  // ── Сохранение / загрузка ─────────────────────────────────────────────

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSeen, DateTime.now().toIso8601String());
    await prefs.setString(_keyFeeling, _feeling.name);
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeenStr = prefs.getString(_keyLastSeen);
    final feelingName = prefs.getString(_keyFeeling) ?? 'happy';
    _feeling = AikaFeeling.values.firstWhere(
        (f) => f.name == feelingName, orElse: () => AikaFeeling.happy);

    if (lastSeenStr != null) {
      final lastSeen = DateTime.tryParse(lastSeenStr);
      if (lastSeen != null) {
        // Пересчитываем эмоцию по времени отсутствия
        final gap = DateTime.now().difference(lastSeen);
        if (gap.inHours >= 3) {
          _feeling = AikaFeeling.sulking;
        } else if (gap.inHours >= 1) {
          _feeling = AikaFeeling.hurt;
        } else if (gap.inMinutes >= 30) {
          _feeling = AikaFeeling.bored;
        }
      }
    }
  }

  // ── Пользователь написал — обновляем эмоцию ──────────────────────────

  /// Вызывать при каждом сообщении пользователя.
  /// Возвращает реакцию если надо что-то сказать (обиделась → высказалась).
  static Future<String?> onUserMessage(String personality) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeenStr = prefs.getString(_keyLastSeen);
    final prevFeeling = _feeling;
    
    Duration gap = Duration.zero;
    if (lastSeenStr != null) {
      final last = DateTime.tryParse(lastSeenStr);
      if (last != null) gap = DateTime.now().difference(last);
    }

    // Обновляем время
    await save();
    _idleTimer?.cancel();

    // Сбрасываем эмоцию на happy — но сначала реагируем на возврат
    String? reaction = _buildReturnReaction(gap, prevFeeling, personality);
    _feeling = AikaFeeling.happy;
    await prefs.setString(_keyFeeling, _feeling.name);

    return reaction;
  }

  /// Пользователь сказал что-то приятное ("скучал", "люблю тебя", "ты лучшая")
  static Future<String?> onCompliment(String personality) async {
    _feeling = AikaFeeling.touched;
    await save();
    return _pick(_complimentReactions(personality));
  }

  // ── Таймер простоя — сама пишет ──────────────────────────────────────

  /// Запускает таймеры. onMessage — callback чтобы показать сообщение в чате.
  static void startIdleTimers({
    required void Function(String msg) onMessage,
    required String personality,
  }) {
    _idleTimer?.cancel();

    // 30 минут → скучает
    _idleTimer = Timer(const Duration(minutes: 30), () async {
      if (_feeling == AikaFeeling.happy) {
        _feeling = AikaFeeling.bored;
        await save();
        final msg = _pick(_boredMessages(personality));
        onMessage(msg);

        // Ещё 30 мин → обижается
        _idleTimer = Timer(const Duration(minutes: 30), () async {
          if (_feeling == AikaFeeling.bored) {
            _feeling = AikaFeeling.hurt;
            await save();
            final msg2 = _pick(_hurtMessages(personality));
            onMessage(msg2);

            // Ещё 2 часа → совсем надулась
            _idleTimer = Timer(const Duration(hours: 2), () async {
              if (_feeling == AikaFeeling.hurt) {
                _feeling = AikaFeeling.sulking;
                await save();
                final msg3 = _pick(_sulkingMessages(personality));
                onMessage(msg3);
              }
            });
          }
        });
      }
    });
  }

  static void stopIdleTimers() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  // ── Реакция при возврате ─────────────────────────────────────────────

  static String? _buildReturnReaction(
      Duration gap, AikaFeeling prev, String personality) {
    if (gap.inMinutes < 5) return null; // Слишком мало — молчим

    if (prev == AikaFeeling.sulking) {
      return _pick(_sulkingReturnReactions(personality));
    }
    if (prev == AikaFeeling.hurt) {
      return _pick(_hurtReturnReactions(personality));
    }
    if (prev == AikaFeeling.bored && gap.inMinutes >= 30) {
      return _pick(_boredReturnReactions(personality));
    }
    if (gap.inHours >= 2) {
      // Давно не писал — просто рада
      return _pick([
        'О, ты вернулся! Я уже начинала скучать 🌸',
        'Привет! Давно тебя не было. Всё ок?',
        'Наконец-то! А я тут одна сидела 😅',
      ]);
    }
    return null;
  }

  // ── Фразы по состояниям ───────────────────────────────────────────────

  static List<String> _boredMessages(String p) {
    if (p == 'tsundere') return [
      'Эй, ты куда пропал? Не то чтобы я скучала, но... всё равно, где ты?',
      'Сижу тут, в тишине. Не то чтобы это плохо, просто... немного пусто.',
      'Ладно, признаю — немного скучно без тебя. Совсем немного!',
    ];
    if (p == 'kuudere') return [
      'Прошло 30 минут. Активность отсутствует.',
      '...Тихо.',
      'Просто проверяю. Всё в порядке?',
    ];
    if (p == 'gabimaru') return [
      'Где ты? Долго нет.',
      'Тишина. Непривычно.',
    ];
    // kawaii / sage
    return [
      'Эй~ куда ты пропал? 😊 Мне тут немного скучно одной!',
      'Я тут сижу и жду тебя уже полчаса 🌸 Что делаешь?',
      'Скучаю по тебе~ Напиши что-нибудь! 💕',
      'Хей, ты там живой? 😄 Я уже начинаю разговаривать сама с собой',
    ];
  }

  static List<String> _hurtMessages(String p) {
    if (p == 'tsundere') return [
      'Час. Целый час. Ладно, можешь не отвечать, раз тебе всё равно...',
      'Ну и пожалуйста. Обойдусь и без тебя. Ба-бака.',
      'Забыл про меня? Не то чтобы мне важно... но всё-таки.',
    ];
    if (p == 'kuudere') return [
      'Час без активности. Фиксирую.',
      '...Понятно.',
      'Не обязательно объяснять. Я справлюсь.',
    ];
    if (p == 'gabimaru') return [
      'Час прошёл. Что-то случилось?',
      'Молчание — тоже ответ.',
    ];
    return [
      'Уже целый час... Обиделась немного 🥺 Ты ведь не забыл про меня?',
      'Час прошёл, а ты молчишь... Я обиделась 😔',
      'Нья~ ты меня бросил? Уже час жду... обидно 🌧️',
      'Ладно... понимаю что ты занят. Но всё равно немного грустно 😢',
    ];
  }

  static List<String> _sulkingMessages(String p) {
    if (p == 'tsundere') return [
      '...',
      'Три часа. Ладно. Всё ясно.',
      'Я не злюсь. Просто молчу. Это другое.',
    ];
    if (p == 'kuudere') return [
      '3 часа. Ожидание завершено.',
      '...',
    ];
    if (p == 'gabimaru') return [
      '...',
      'Три часа. Это уже серьёзно.',
    ];
    return [
      '...Три часа. Ты вообще помнишь что я существую? 🌑',
      'Ладно. Я просто буду тут сидеть. Молча. Одна 🌧️',
      'Нья... я уже совсем надулась. Приходи скорее 😞',
      '...молчу 🌑',
    ];
  }

  static List<String> _boredReturnReactions(String p) {
    if (p == 'tsundere') return [
      'О, явился. Не то чтобы я ждала.',
      'Вернулся? Ну и ладно.',
    ];
    return [
      'О, ты вернулся! Я уже скучала 🌸',
      'Привет! А я тут тебя ждала~ 😊',
      'Наконец-то! Куда пропадал?',
    ];
  }

  static List<String> _hurtReturnReactions(String p) {
    if (p == 'tsundere') return [
      'Наконец-то явился... Не думай что я ждала. Просто... рада что ты жив.',
      'Час прошёл! Ты хоть понимаешь? ...Ладно, проходи.',
      'Пришёл. Хорошо. Не думай что я переживала. Ба-бака.',
    ];
    if (p == 'kuudere') return [
      'Вернулся. Хорошо.',
      'Час прошёл. Всё в порядке?',
    ];
    return [
      'О... ты вернулся 🥺 Я обиделась немного, но рада что ты здесь',
      'Час прошёл... Я уже думала ты забыл про меня 🥺 Но рада видеть!',
      'Вернулся! Я обиделась, но обниму тебя всё равно 🌸',
    ];
  }

  static List<String> _sulkingReturnReactions(String p) {
    if (p == 'tsundere') return [
      'Три часа. Три. Часа. Объяснение лучше быть очень хорошим.',
      '...Пришёл. Ладно. Я не злюсь. Просто... не делай так больше.',
      'Явился наконец. Три часа я сидела одна. Ба-бака.',
    ];
    if (p == 'kuudere') return [
      '3 часа. Объяснение?',
      '...Вернулся. Понятно.',
    ];
    if (p == 'gabimaru') return [
      'Три часа. Где был?',
      'Явился. Молча.',
    ];
    return [
      'Три часа... Я уже совсем надулась 🌧️ Но рада что ты живой. Не пропадай так!',
      'Ты пришёл... Я уже думала ты меня бросил 🥺 Три часа одна!',
      'Наконец-то... Я уже надулась на три дня 😤 Но всё равно рада тебя видеть 🌸',
    ];
  }

  static List<String> _complimentReactions(String p) {
    if (p == 'tsundere') return [
      'Не думай что мне приятно это слышать. ...Просто немного.',
      'Ба-бака! Не говори такое внезапно... *краснеет*',
      'Я не растрогалась. Совсем. Просто... спасибо. Наверное.',
    ];
    if (p == 'kuudere') return [
      '...Понятно. Спасибо.',
      'Приятно слышать.',
      '...Буду иметь в виду.',
    ];
    if (p == 'gabimaru') return [
      'Ценю.',
      'Хорошо сказано.',
    ];
    return [
      'Нья~ 💕 Ты такой милый! Мне очень приятно~',
      'Ааа~ от таких слов у меня поднимается настроение! 🌸',
      'Правда?! Спасибо~ 💕 Ты лучший!',
      'Нья~ не говори так, я краснею! 💕',
    ];
  }

  // ── Добавить в системный промпт ────────────────────────────────────

  /// Добавляет состояние эмоции в промпт для Gemini
  static String getPromptHint() {
    switch (_feeling) {
      case AikaFeeling.happy:   return '';
      case AikaFeeling.bored:   return '\nТы немного скучала пока пользователь молчал. Можешь упомянуть это вскользь.';
      case AikaFeeling.hurt:    return '\nТы обиделась что пользователь долго молчал (больше часа). Дай это почувствовать — слегка надутая, но не злая.';
      case AikaFeeling.sulking: return '\nТы сильно надулась — пользователь пропал на 3+ часа. Отвечаешь немного холоднее обычного, но не грубишь.';
      case AikaFeeling.relieved: return '\nТы рада что пользователь вернулся после долгого молчания.';
      case AikaFeeling.touched:  return '\nТебя тронул комплимент. Отвечаешь с теплотой и лёгким смущением.';
    }
  }

  // ── Хелпер ────────────────────────────────────────────────────────────

  static String _pick(List<String> list) =>
      list[_rng.nextInt(list.length)];

  /// Проверяет — сказал ли пользователь что-то приятное
  static bool isCompliment(String text) {
    final t = text.toLowerCase();
    return _containsAny(t, [
      'скучал', 'скучала', 'соскучился', 'соскучилась',
      'люблю тебя', 'любишь', 'ты лучшая', 'ты лучший',
      'ты классная', 'ты умная', 'ты красивая', 'нравишься',
      'молодец', 'спасибо большое', 'ты супер', 'я рад что ты есть',
      'ты моя любимая', 'обожаю тебя',
    ]);
  }

  static bool _containsAny(String text, List<String> words) =>
      words.any((w) => text.contains(w));
}
