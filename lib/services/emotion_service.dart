import 'dart:math';

enum UserEmotion {
  neutral,
  happy,
  sad,
  angry,
  anxious,
  tired,
  excited,
  stressed,
}

class EmotionService {
  static UserEmotion _lastEmotion = UserEmotion.neutral;
  static int _negativeStreak = 0; // сколько раз подряд негативное

  static UserEmotion get lastEmotion => _lastEmotion;

  /// Определяет эмоцию из текста пользователя
  static UserEmotion detect(String text) {
    final t = text.toLowerCase();

    // Счастье / возбуждение
    if (_matches(t, ['круто', 'ура', 'отлично', 'супер', 'класс', 'вау', 'огонь',
        'кайф', 'топ', 'лол', '🔥', '😍', '🎉', 'наконец', 'ура', 'победа',
        'рад', 'счастлив', 'радуюсь', 'доволен', 'шикарно'])) {
      _lastEmotion = UserEmotion.happy;
      _negativeStreak = 0;
      return UserEmotion.happy;
    }

    // Возбуждение / энтузиазм
    if (_matches(t, ['давай', 'поехали', 'вперёд', 'сделай', 'хочу', 'интересно',
        'покажи', 'расскажи', 'давай добавим', '!!!'])) {
      _lastEmotion = UserEmotion.excited;
      _negativeStreak = 0;
      return UserEmotion.excited;
    }

    // Злость
    if (_matches(t, ['бесит', 'раздражает', 'достал', 'задолбал', 'злой', 'злюсь',
        'ненавижу', 'бесяк', 'тупой', 'идиот', 'дурак', 'что за', 'опять не работает',
        'сломал', 'блин', 'чёрт', 'твою', 'нафиг', 'блять', 'снова'])) {
      _lastEmotion = UserEmotion.angry;
      _negativeStreak++;
      return UserEmotion.angry;
    }

    // Стресс / тревога
    if (_matches(t, ['не успеваю', 'дедлайн', 'срочно', 'помогите', 'паника',
        'тревожно', 'беспокоюсь', 'переживаю', 'волнуюсь', 'страшно',
        'не знаю что делать', 'всё плохо', 'ужас', 'катастрофа', 'помоги'])) {
      _lastEmotion = UserEmotion.anxious;
      _negativeStreak++;
      return UserEmotion.anxious;
    }

    // Грусть
    if (_matches(t, ['грустно', 'плохо', 'устал', 'скучно', 'одиноко', 'грущу',
        'расстроен', 'плачу', 'всё надоело', 'не хочу', 'лень', 'депрессия',
        'тяжело', 'не могу', '😢', '😔', 'обидно', 'никто'])) {
      _lastEmotion = UserEmotion.sad;
      _negativeStreak++;
      return UserEmotion.sad;
    }

    // Усталость
    if (_matches(t, ['устал', 'хочу спать', 'сонный', 'лечь', 'вздремнуть',
        'не могу встать', 'зеваю', 'глаза закрываются', 'ночь', 'утром встал',
        'поздно лёг', 'бессонница'])) {
      _lastEmotion = UserEmotion.tired;
      _negativeStreak++;
      return UserEmotion.tired;
    }

    return UserEmotion.neutral;
  }

  static bool _matches(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  /// Добавляет эмоциональный контекст в system prompt
  static String buildEmotionContext(UserEmotion emotion) {
    switch (emotion) {
      case UserEmotion.happy:
        return '\n\n[ЭМОЦИЯ ПОЛЬЗОВАТЕЛЯ: радостный/в хорошем настроении — поддержи энергию, можно пошутить]';
      case UserEmotion.excited:
        return '\n\n[ЭМОЦИЯ ПОЛЬЗОВАТЕЛЯ: возбуждён/энтузиазм — отвечай с такой же энергией]';
      case UserEmotion.sad:
        return '\n\n[ЭМОЦИЯ ПОЛЬЗОВАТЕЛЯ: грустный — будь мягкой и поддерживающей, не будь слишком бодрой]';
      case UserEmotion.angry:
        return '\n\n[ЭМОЦИЯ ПОЛЬЗОВАТЕЛЯ: раздражён/злится — отвечай спокойно, коротко, не спорь, помоги решить проблему]';
      case UserEmotion.anxious:
        return '\n\n[ЭМОЦИЯ ПОЛЬЗОВАТЕЛЯ: тревожится/в стрессе — успокой, говори уверенно, дай конкретные шаги]';
      case UserEmotion.tired:
        return '\n\n[ЭМОЦИЯ ПОЛЬЗОВАТЕЛЯ: устал — говори мягко, тихо, не перегружай информацией]';
      case UserEmotion.stressed:
        return '\n\n[ЭМОЦИЯ ПОЛЬЗОВАТЕЛЯ: стресс — будь эффективной и краткой, помоги разгрузить]';
      case UserEmotion.neutral:
        return '';
    }
  }

  /// Реакция Айки на обнаруженную эмоцию (показывается один раз)
  static String? getEmotionReaction(UserEmotion emotion) {
    final rng = Random();
    switch (emotion) {
      case UserEmotion.sad:
        final msgs = [
          'Эй, ты в порядке? 🌸 Я здесь если что',
          'Слышу что что-то не так. Расскажи?',
          'Всё нормально? Я рядом 💙',
        ];
        return msgs[rng.nextInt(msgs.length)];
      case UserEmotion.angry:
        final msgs = [
          'Вижу что бесит. Говори — разберёмся 🔧',
          'Спокойно, сейчас починим это',
          'Понимаю, это реально раздражает. Что случилось?',
        ];
        return msgs[rng.nextInt(msgs.length)];
      case UserEmotion.anxious:
        final msgs = [
          'Стоп, дыши. Давай разберём шаг за шагом 🧘',
          'Всё решаемо. С чего начнём?',
          'Я с тобой, не паникуй. Что самое срочное?',
        ];
        return msgs[rng.nextInt(msgs.length)];
      case UserEmotion.tired:
        final msgs = [
          'Ты устал, вижу. Может отдохнёшь? 😴',
          'Может поставить напоминание на сон?',
          'Отдохни немного, я никуда не денусь 🌙',
        ];
        return msgs[rng.nextInt(msgs.length)];
      default:
        return null;
    }
  }

  /// Нужно ли отреагировать на эмоцию отдельным сообщением
  static bool shouldReact(UserEmotion emotion) {
    return emotion == UserEmotion.sad ||
        emotion == UserEmotion.angry ||
        emotion == UserEmotion.anxious ||
        emotion == UserEmotion.tired;
  }

  /// Возвращает настроение Айки соответствующее эмоции пользователя
  static String getAikaMoodForEmotion(UserEmotion emotion) {
    switch (emotion) {
      case UserEmotion.happy:    return 'happy';
      case UserEmotion.excited:  return 'dancing';
      case UserEmotion.sad:      return 'greeting'; // нежный вейв
      case UserEmotion.angry:    return 'thinking'; // думает как помочь
      case UserEmotion.anxious:  return 'thinking';
      case UserEmotion.tired:    return 'idle';
      default:                   return 'idle';
    }
  }
}
