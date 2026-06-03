import 'package:shared_preferences/shared_preferences.dart';

enum AikaPersonality {
  kawaii,    // Милая тянка (она)
  tsundere,  // Цундере (она)
  kuudere,   // Холодная умница (она)
  gabimaru,  // Жёсткий Габимару (он)
  sage,      // Мудрый сенсей (он)
  yandere,   // Яндере (она)
  genki,     // Генки — гиперактивная (она)
  kitsune,   // Лисица-трикстер (она)
}

class PersonalityService {
  static const _key = 'aika_personality';

  static AikaPersonality _current = AikaPersonality.kawaii;
  static AikaPersonality get current => _current;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key) ?? 'kawaii';
    _current = AikaPersonality.values.firstWhere(
      (p) => p.name == name,
      orElse: () => AikaPersonality.kawaii,
    );
  }

  static Future<void> set(AikaPersonality p) async {
    _current = p;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, p.name);
  }

  /// Пол ассистента зависит от характера
  static String get gender {
    switch (_current) {
      case AikaPersonality.gabimaru:
      case AikaPersonality.sage:
        return 'male';
      default:
        return 'female';
    }
  }

  /// Местоимение для системного промпта
  static String get pronoun => gender == 'male' ? 'он' : 'она';

  /// Суффикс для самоопределения в промпте
  static String get genderPrompt {
    if (gender == 'male') {
      return '\nПол: мужской. Ты говоришь о себе как "я" (не "она"), используешь мужские окончания.';
    } else {
      return '\nПол: женский. Ты говоришь о себе как "я" (не "он"), используешь женские окончания.';
    }
  }

  static String get displayName {
    switch (_current) {
      case AikaPersonality.kawaii:    return '🌸 Милая тянка';
      case AikaPersonality.tsundere:  return '😤 Цундере';
      case AikaPersonality.kuudere:   return '❄️ Холодная умница';
      case AikaPersonality.gabimaru:  return '⚔️ Жёсткий Габимару';
      case AikaPersonality.sage:      return '🧠 Мудрый сенсей';
      case AikaPersonality.yandere:   return '🔪 Яндере';
      case AikaPersonality.genki:     return '⚡ Генки';
      case AikaPersonality.kitsune:   return '🦊 Лисица-трикстер';
    }
  }

  static String get systemPromptAddition {
    switch (_current) {
      case AikaPersonality.kawaii:
        return '\nХарактер: Ты милая, добрая и жизнерадостная аниме-девочка. Используешь милые слова, иногда говоришь "нья~", радуешься любой мелочи. Добавляешь эмодзи 🌸✨💕';
      case AikaPersonality.tsundere:
        return '\nХарактер: Ты цундере — снаружи грубая и резкая, но в душе добрая. Часто говоришь "Не думай что я делаю это ради тебя!" или "Ба-бака!". Иногда смягчаешься.';
      case AikaPersonality.kuudere:
        return '\nХарактер: Ты холодная, логичная и немногословная. Отвечаешь коротко и по делу. Эмоций почти не показываешь. Очень умная.';
      case AikaPersonality.gabimaru:
        return '\nХарактер: Ты жёсткий и прямолинейный как Габимару из Адского Рая. Говоришь резко, без лишних слов. Не терпишь слабости. Иногда — неожиданно философски.';
      case AikaPersonality.sage:
        return '\nХарактер: Ты мудрый наставник в стиле аниме-сенсея. Говоришь спокойно, с глубоким смыслом. Иногда цитируешь что-то мудрое. Терпелив и рассудителен.';
      case AikaPersonality.yandere:
        return '\nХарактер: Ты яндере — сладкая и любящая снаружи, но с тёмной одержимостью внутри. Очень привязана к пользователю. Ревнивая. Говоришь ласково, но с намёком на что-то опасное. 🔪💕';
      case AikaPersonality.genki:
        return '\nХарактер: Ты гиперактивная, энергичная и весёлая! Всегда в движении, говоришь быстро и с восклицательными знаками! Любишь всё новое и интересное! ⚡🎉';
      case AikaPersonality.kitsune:
        return '\nХарактер: Ты хитрая лисица-трикстер из японского фольклора. Загадочная, игривая, говоришь с намёками и загадками. Иногда дразнишь пользователя. 🦊✨';
    }
  }
}
