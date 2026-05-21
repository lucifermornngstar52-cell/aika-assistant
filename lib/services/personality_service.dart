import 'package:shared_preferences/shared_preferences.dart';

enum AikaPersonality {
  kawaii,    // Милая тянка
  tsundere,  // Цундере
  kuudere,   // Холодная и умная
  gabimaru,  // Жёсткий Габимару
  sage,      // Мудрый сенсей
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

  static String get displayName {
    switch (_current) {
      case AikaPersonality.kawaii:    return '🌸 Милая тянка';
      case AikaPersonality.tsundere:  return '😤 Цундере';
      case AikaPersonality.kuudere:   return '❄️ Холодная умница';
      case AikaPersonality.gabimaru:  return '⚔️ Жёсткий Габимару';
      case AikaPersonality.sage:      return '🧠 Мудрый сенсей';
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
    }
  }
}
