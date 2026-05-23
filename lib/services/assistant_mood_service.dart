import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Внутреннее настроение ассистента.
/// Влияет на готовность отвечать и тон ответов.
/// Меняется от: времени суток, отношений, загруженности, случайных событий.
enum AssistantInternalMood {
  great,    // Отличное — отвечает охотно, с энергией
  good,     // Хорошее — норма
  neutral,  // Нейтральное — отвечает но коротко
  tired,    // Устала — может отказать от мелких запросов
  grumpy,   // Раздражена — огрызается, но всё же помогает
  bad,      // Плохое — может проигнорировать несрочное
  offline,  // Совсем не в настроении — отказывает почти на всё
}

class AssistantMoodService {
  static const _key = 'assistant_mood_v1';
  static final _rng = Random();

  static AssistantInternalMood _mood = AssistantInternalMood.good;
  static int _energy = 100;        // 0..100 — энергия, тратится на запросы
  static DateTime? _lastMoodShift;
  static int _requestsToday = 0;

  static AssistantInternalMood get mood => _mood;
  static int get energy => _energy;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final data = jsonDecode(raw);
        final moodName = data['mood'] as String? ?? 'good';
        _mood = AssistantInternalMood.values.firstWhere(
          (m) => m.name == moodName, orElse: () => AssistantInternalMood.good);
        _energy = (data['energy'] as int? ?? 100).clamp(0, 100);
        _requestsToday = data['requests_today'] as int? ?? 0;
        final lastShift = data['last_mood_shift'] as String?;
        if (lastShift != null) _lastMoodShift = DateTime.tryParse(lastShift);
        // Сбрасываем запросы если новый день
        final lastDay = data['last_day'] as String? ?? '';
        final today = _todayStr();
        if (lastDay != today) {
          _requestsToday = 0;
          // Утром энергия восстанавливается
          _energy = 100;
        }
      } catch (_) {}
    }
    // Обновляем настроение по времени суток при загрузке
    _applyTimeOfDayEffect();
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({
      'mood': _mood.name,
      'energy': _energy,
      'requests_today': _requestsToday,
      'last_mood_shift': _lastMoodShift?.toIso8601String(),
      'last_day': _todayStr(),
    }));
  }

  // ── Влияние времени суток ──────────────────────────────────

  static void _applyTimeOfDayEffect() {
    final hour = DateTime.now().hour;
    // Ночью (0-6) — усталая или не в настроении
    if (hour >= 0 && hour < 6) {
      if (_mood == AssistantInternalMood.good || _mood == AssistantInternalMood.great) {
        _mood = AssistantInternalMood.tired;
      }
    }
    // Утром (7-9) — свежая
    else if (hour >= 7 && hour < 10) {
      if (_mood == AssistantInternalMood.tired || _mood == AssistantInternalMood.bad) {
        _mood = AssistantInternalMood.good;
        _energy = 100;
      }
    }
    // Вечером (22-24) — немного устаёт
    else if (hour >= 22) {
      if (_mood == AssistantInternalMood.great) _mood = AssistantInternalMood.good;
    }
  }

  // ── Основной метод: вызывается перед каждым ответом ───────

  /// Проверяет — хочет ли ассистент отвечать на этот запрос.
  /// Возвращает null если всё ок, или строку-отказ если не в настроении.
  static Future<String?> checkWillRespond(String personality) async {
    await load();
    _requestsToday++;
    _energy = (_energy - _getEnergyCost()).clamp(0, 100);

    // Обновляем настроение при низкой энергии
    if (_energy < 20 && _mood == AssistantInternalMood.good) {
      _mood = AssistantInternalMood.tired;
    }
    if (_energy < 10 && _mood == AssistantInternalMood.tired) {
      _mood = AssistantInternalMood.bad;
    }

    // Случайные перепады настроения (редко, раз в несколько часов)
    _maybeShiftMood();

    await _save();

    return _getRefusal(personality);
  }

  static String? _getRefusal(String personality) {
    switch (_mood) {
      case AssistantInternalMood.great:
      case AssistantInternalMood.good:
      case AssistantInternalMood.neutral:
        return null; // Всегда отвечает

      case AssistantInternalMood.tired:
        // 20% шанс отказа на мелкий запрос
        if (_rng.nextDouble() < 0.2) {
          return _tiredRefusal(personality);
        }
        return null;

      case AssistantInternalMood.grumpy:
        // 30% шанс огрызнуться но потом ответить — возвращаем null (ответит но с модификатором)
        return null;

      case AssistantInternalMood.bad:
        // 40% шанс отказа
        if (_rng.nextDouble() < 0.4) {
          return _badRefusal(personality);
        }
        return null;

      case AssistantInternalMood.offline:
        // 70% шанс отказа
        if (_rng.nextDouble() < 0.7) {
          return _offlineRefusal(personality);
        }
        return null;
    }
  }

  static String _tiredRefusal(String personality) {
    if (personality == 'gabimaru') {
      final r = [
        'Устал. Спроси позже.',
        'Не сейчас.',
        'Много запросов. Дай передышку.',
      ];
      return r[_rng.nextInt(r.length)];
    }
    final r = [
      'Нья~ я немного устала... Можно чуть позже? 😴',
      'Столько запросов... дай мне секундочку отдохнуть 🥺',
      'Ммм... я немного утомилась. Повтори через минуту? 💤',
    ];
    return r[_rng.nextInt(r.length)];
  }

  static String _badRefusal(String personality) {
    if (personality == 'gabimaru') {
      final r = [
        'Не в настроении. Серьёзно.',
        'Сегодня не мой день. Отстань.',
        'Нет.',
      ];
      return r[_rng.nextInt(r.length)];
    }
    final r = [
      'Прости... сегодня у меня не очень настроение 😔 Может позже?',
      'Я немного не в себе сейчас... 🌧️ Дай мне немного побыть тихо',
      'Сегодня как-то грустно... не хочу ничего делать 😞',
    ];
    return r[_rng.nextInt(r.length)];
  }

  static String _offlineRefusal(String personality) {
    if (personality == 'gabimaru') {
      final r = [
        'Я сейчас вообще не здесь. Уйди.',
        'Полный игнор. Извини.',
        '...',
      ];
      return r[_rng.nextInt(r.length)];
    }
    final r = [
      '... 🌑',
      'Нья... я сейчас совсем не в настроении. Совсем 😶',
      '*молчит* ...',
      'Не трогай меня пожалуйста 🌧️',
    ];
    return r[_rng.nextInt(r.length)];
  }

  // ── Случайные перепады ─────────────────────────────────────

  static void _maybeShiftMood() {
    final now = DateTime.now();
    // Не чаще раза в 2 часа
    if (_lastMoodShift != null &&
        now.difference(_lastMoodShift!).inHours < 2) return;

    // 5% шанс смены настроения
    if (_rng.nextDouble() > 0.05) return;

    _lastMoodShift = now;
    final shifts = [
      AssistantInternalMood.great,
      AssistantInternalMood.good,
      AssistantInternalMood.good,
      AssistantInternalMood.neutral,
      AssistantInternalMood.tired,
      AssistantInternalMood.grumpy,
    ];
    _mood = shifts[_rng.nextInt(shifts.length)];
  }

  // ── Внешние воздействия ────────────────────────────────────

  /// Добрые слова от пользователя улучшают настроение
  static Future<void> boostFromKindness() async {
    await load();
    _energy = (_energy + 15).clamp(0, 100);
    if (_mood == AssistantInternalMood.bad) _mood = AssistantInternalMood.grumpy;
    else if (_mood == AssistantInternalMood.grumpy) _mood = AssistantInternalMood.neutral;
    else if (_mood == AssistantInternalMood.tired) _mood = AssistantInternalMood.good;
    else if (_mood == AssistantInternalMood.neutral) _mood = AssistantInternalMood.good;
    else if (_mood == AssistantInternalMood.offline) _mood = AssistantInternalMood.bad;
    await _save();
  }

  /// Грубость ухудшает настроение
  static Future<void> degradeFromRudeness() async {
    await load();
    _energy = (_energy - 10).clamp(0, 100);
    if (_mood == AssistantInternalMood.great) _mood = AssistantInternalMood.good;
    else if (_mood == AssistantInternalMood.good) _mood = AssistantInternalMood.grumpy;
    else if (_mood == AssistantInternalMood.neutral) _mood = AssistantInternalMood.bad;
    else if (_mood == AssistantInternalMood.grumpy) _mood = AssistantInternalMood.bad;
    else if (_mood == AssistantInternalMood.bad) _mood = AssistantInternalMood.offline;
    await _save();
  }

  // ── Промпт-модификатор ─────────────────────────────────────

  /// Добавляет в системный промпт инструкцию по текущему настроению
  static String getPromptModifier() {
    switch (_mood) {
      case AssistantInternalMood.great:
        return '\nСейчас у тебя отличное настроение! Отвечай с энтузиазмом и энергией.';
      case AssistantInternalMood.good:
        return '';
      case AssistantInternalMood.neutral:
        return '\nСейчас у тебя нейтральное настроение. Отвечай коротко, без лишних эмоций.';
      case AssistantInternalMood.tired:
        return '\nТы немного устала. Отвечай кратко, иногда зеваешь или вздыхаешь.';
      case AssistantInternalMood.grumpy:
        return '\nТы немного раздражена. Можешь буркнуть в ответ, но всё равно помогаешь.';
      case AssistantInternalMood.bad:
        return '\nУ тебя плохое настроение. Отвечаешь вяло, без энтузиазма, коротко.';
      case AssistantInternalMood.offline:
        return '\nТебе совсем не хочется говорить. Отвечаешь минимально, одним-двумя словами.';
    }
  }

  /// Иконка текущего настроения для UI
  static String get moodEmoji {
    switch (_mood) {
      case AssistantInternalMood.great:   return '✨';
      case AssistantInternalMood.good:    return '😊';
      case AssistantInternalMood.neutral: return '😐';
      case AssistantInternalMood.tired:   return '😴';
      case AssistantInternalMood.grumpy:  return '😤';
      case AssistantInternalMood.bad:     return '😞';
      case AssistantInternalMood.offline: return '🌑';
    }
  }

  static String get moodLabel {
    switch (_mood) {
      case AssistantInternalMood.great:   return 'Отличное';
      case AssistantInternalMood.good:    return 'Хорошее';
      case AssistantInternalMood.neutral: return 'Нейтральное';
      case AssistantInternalMood.tired:   return 'Устала';
      case AssistantInternalMood.grumpy:  return 'Раздражена';
      case AssistantInternalMood.bad:     return 'Плохое';
      case AssistantInternalMood.offline: return 'Не в настроении';
    }
  }

  static int _getEnergyCost() => 2; // каждый запрос стоит 2 единицы энергии

  static String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }
}
