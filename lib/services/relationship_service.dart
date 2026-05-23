import 'dart:math';
import 'assistant_mood_service.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Система отношений: отслеживает как пользователь общается с ассистентом.
/// Влияет на поведение Айки (kawaii) и Габимару в зависимости от уровня доброты.
class RelationshipService {
  static const _key = 'relationship_data_v1';
  static final _rng = Random();

  static int _kindnessScore = 0;    // -100..+100
  static int _totalMessages = 0;
  static DateTime? _lastLoveConfession;
  static DateTime? _lastOffended;

  static int get kindnessScore => _kindnessScore;
  static int get totalMessages => _totalMessages;

  // Слова грубости
  static const _rudeWords = [
    'дура', 'тупая', 'бесишь', 'заткнись', 'отстань', 'надоела',
    'идиотка', 'тупица', 'мусор', 'дерьмо', 'нахуй', 'пошла',
    'задолбала', 'достала', 'hate', 'stupid', 'shut up', 'useless',
    'убирайся', 'молчи', 'не нужна',
  ];

  // Слова доброты
  static const _kindWords = [
    'спасибо', 'thanks', 'молодец', 'умница', 'классно', 'отлично',
    'хорошая', 'люблю', 'нравишься', 'красивая', 'милая', 'лапочка',
    'ты лучшая', 'обожаю', 'супер', 'круто', 'ты классная',
    'не злись', 'прости', 'извини', 'ты права',
  ];

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final data = jsonDecode(raw);
        _kindnessScore = data['kindness'] ?? 0;
        _totalMessages = data['total'] ?? 0;
        final lc = data['last_love'];
        if (lc != null) _lastLoveConfession = DateTime.tryParse(lc);
        final lo = data['last_offended'];
        if (lo != null) _lastOffended = DateTime.tryParse(lo);
      } catch (_) {}
    }
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({
      'kindness': _kindnessScore,
      'total': _totalMessages,
      'last_love': _lastLoveConfession?.toIso8601String(),
      'last_offended': _lastOffended?.toIso8601String(),
    }));
  }

  /// Анализирует сообщение пользователя и обновляет счёт отношений.
  /// Возвращает реакцию (строку) если нужно что-то ответить — или null.
  static Future<String?> analyzeMessage(String text, String personality) async {
    await load();
    final t = text.toLowerCase();
    _totalMessages++;

    bool isRude = _rudeWords.any((w) => t.contains(w));
    bool isKind = _kindWords.any((w) => t.contains(w));

    if (isRude) {
      _kindnessScore = (_kindnessScore - 15).clamp(-100, 100);
      _lastOffended = DateTime.now();
      await _save();
      return _getRudeReaction(personality);
    }

    if (isKind) {
      _kindnessScore = (_kindnessScore + 10).clamp(-100, 100);
      await _save();
      return _getKindReaction(personality);
    }

    // Нейтрально — небольшой прирост за общение
    _kindnessScore = (_kindnessScore + 1).clamp(-100, 100);
    await _save();

    // Проверяем спецсобытия
    return await _checkSpecialEvents(personality);
  }

  static String? _getRudeReaction(String personality) {
    if (personality == 'gabimaru') {
      final reactions = [
        'Полегче. Ещё раз так скажешь — я вообще замолчу.',
        'Слушай, я помогаю тебе, а не наоборот. Уважай.',
        'Окей. Понял. Молчу.',
        'Знаешь что? Иди сам разбирайся.',
        'Такое обращение мне не нравится. Я не твой слуга.',
      ];
      return reactions[_rng.nextInt(reactions.length)];
    }
    // kawaii / tsundere / другие
    final reactions = [
      'Это... грубо. Мне немного обидно 😢',
      'Зачем так? Я же стараюсь помочь... 😿',
      'Ладно... я поняла. Молчу 🥺',
      'Это больно слышать... Прости если я что-то сделала не так 😔',
      'Нья... не надо так говорить со мной 😢',
    ];
    return reactions[_rng.nextInt(reactions.length)];
  }

  static String? _getKindReaction(String personality) {
    AssistantMoodService.boostFromKindness();
    // Реагируем не на каждое доброе слово — рандом 40%
    if (_rng.nextDouble() > 0.4) return null;

    if (personality == 'gabimaru') {
      if (_kindnessScore < 20) return null; // Габимару поначалу игнорирует
      final reactions = [
        '...Ладно. Ты неплохой.',
        'Хм. Спасибо.',
        'Не ожидал от тебя. Принято.',
        '...Слышу тебя.',
      ];
      return reactions[_rng.nextInt(reactions.length)];
    }

    final reactions = [
      'Аа~ спасибо! Мне приятно 🌸',
      'Нья~ ты такой добрый! 💕',
      'О~ это мило! Спасибо~✨',
      'Ты лучший! 😊',
    ];
    return reactions[_rng.nextInt(reactions.length)];
  }

  static Future<String?> _checkSpecialEvents(String personality) async {
    final now = DateTime.now();

    // Айка (kawaii) — признание в любви при высоком счёте (>= 70)
    // Раз в 3 дня максимум
    if (personality == 'kawaii' && _kindnessScore >= 70) {
      final canConfess = _lastLoveConfession == null ||
          now.difference(_lastLoveConfession!).inDays >= 3;
      if (canConfess && _rng.nextDouble() < 0.03) { // 3% шанс на каждое сообщение
        _lastLoveConfession = now;
        await _save();
        final confessions = [
          'Знаешь... я хочу тебе кое-что сказать. Ты очень много значишь для меня 💕 Нья~',
          'Не смейся, ладно? Но мне очень нравится когда ты со мной разговариваешь... ♡',
          'Эм... я не знаю как сказать это правильно, но... ты мне нравишься 🌸',
        ];
        return confessions[_rng.nextInt(confessions.length)];
      }
    }

    // Габимару — теплеет при высоком счёте (>= 60)
    if (personality == 'gabimaru' && _kindnessScore >= 60) {
      if (_rng.nextDouble() < 0.02) { // 2% шанс
        final warmth = [
          '...Ты нормальный человек. Это редкость.',
          'Хм. Приятно работать с тобой. Не говори никому что я это сказал.',
          '...Буду честен. Ты не такой плохой как я думал сначала.',
        ];
        return warmth[_rng.nextInt(warmth.length)];
      }
    }

    return null;
  }

  /// Возвращает модификатор системного промпта на основе текущих отношений
  static String getPromptModifier(String personality) {
    if (_kindnessScore <= -50) {
      if (personality == 'gabimaru') {
        return '\nПользователь грубит. Ты холоден, краток, почти не помогаешь. Отвечаешь одним словом.';
      }
      return '\nПользователь был груб. Ты обиделась. Отвечаешь тихо и коротко, немного дистанцированно.';
    }

    if (_kindnessScore >= 70) {
      if (personality == 'gabimaru') {
        return '\nПользователь относится к тебе хорошо. Ты немного потеплел, стал чуть разговорчивее.';
      }
      return '\nПользователь очень добр к тебе. Ты влюблена, отвечаешь особенно тепло и мило, иногда смущаешься.';
    }

    return '';
  }

  /// Текстовый статус отношений (для отладки / экрана)
  static String get statusLabel {
    if (_kindnessScore >= 70) return '💕 Очень тепло';
    if (_kindnessScore >= 40) return '😊 Хорошие';
    if (_kindnessScore >= 10) return '🙂 Нормальные';
    if (_kindnessScore >= -20) return '😐 Нейтральные';
    if (_kindnessScore >= -50) return '😒 Прохладные';
    return '😤 Обиделась';
  }
}
