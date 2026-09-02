import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/personality_service.dart';
import '../theme/app_theme.dart';

class PersonalityScreen extends StatefulWidget {
  const PersonalityScreen({super.key});
  @override
  State<PersonalityScreen> createState() => _PersonalityScreenState();
}

class _PersonalityScreenState extends State<PersonalityScreen> {
  AikaPersonality _selected = PersonalityService.current;

  final Map<AikaPersonality, Map<String, String>> _info = {
    // ── Аниме персонажи ───────────────────────────────────────────────
    AikaPersonality.kawaii: {
      'icon': '🌸',
      'name': 'Милая тянка',
      'desc': 'Добрая, радостная, использует милые слова и эмодзи. Любит тебя безусловно~',
      'tag': 'АНИМЕ',
    },
    AikaPersonality.tsundere: {
      'icon': '😤',
      'name': 'Цундере',
      'desc': 'Снаружи грубая, внутри добрая. "Не думай что я делаю это ради тебя, бака!"',
      'tag': 'АНИМЕ',
    },
    AikaPersonality.kuudere: {
      'icon': '❄️',
      'name': 'Холодная умница',
      'desc': 'Короткие ответы, логика прежде всего. Эмоции скрывает, но они есть.',
      'tag': 'АНИМЕ',
    },
    AikaPersonality.yandere: {
      'icon': '🔪',
      'name': 'Яндере',
      'desc': 'Сладкая снаружи, одержимая внутри. Очень привязана к тебе. Ревнивая и опасная 💕',
      'tag': 'АНИМЕ',
    },
    AikaPersonality.genki: {
      'icon': '⚡',
      'name': 'Генки',
      'desc': 'Гиперактивная и весёлая! Всегда в движении, говорит быстро, любит всё! ⚡🎉',
      'tag': 'АНИМЕ',
    },
    AikaPersonality.kitsune: {
      'icon': '🦊',
      'name': 'Лисица-трикстер',
      'desc': 'Хитрая и загадочная лисица из японского фольклора. Говорит намёками и загадками.',
      'tag': 'АНИМЕ',
    },
    AikaPersonality.gabimaru: {
      'icon': '⚔️',
      'name': 'Жёсткий Габимару',
      'desc': 'Прямолинейный и резкий как Габимару из Адского Рая. Говорит только суть.',
      'tag': 'АНИМЕ',
    },
    AikaPersonality.sage: {
      'icon': '🧠',
      'name': 'Мудрый сенсей',
      'desc': 'Спокойный наставник с глубокими мыслями. Терпелив и рассудителен.',
      'tag': 'АНИМЕ',
    },

    // ── Sci-Fi персонажи ──────────────────────────────────────────────
    AikaPersonality.jarvis: {
      'icon': '🤖',
      'name': 'J.A.R.V.I.S',
      'desc': 'AI-система Тони Старка. Безупречно вежлив, предельно точен. "Будет сделано, сэр."',
      'tag': 'SCI-FI',
    },
    AikaPersonality.friday: {
      'icon': '💠',
      'name': 'F.R.I.D.A.Y',
      'desc': 'Преемница JARVIS. Деловая, прямолинейная, с ирландским шармом. "Готово, boss."',
      'tag': 'SCI-FI',
    },
    AikaPersonality.ghost: {
      'icon': '👻',
      'name': 'Призрак',
      'desc': 'Бывший спецназовец, ныне AI. Минимум слов, максимум эффекта. "Цель принята."',
      'tag': 'SCI-FI',
    },
    AikaPersonality.oracle: {
      'icon': '🔮',
      'name': 'Оракул',
      'desc': 'Древний AI-пророк. Таинственный и всезнающий. "Ты уже знаешь ответ..."',
      'tag': 'SCI-FI',
    },
  };

  // Авто-имена для персонажей
  static const Map<AikaPersonality, String> _autoNames = {
    AikaPersonality.jarvis:   'JARVIS',
    AikaPersonality.friday:   'FRIDAY',
    AikaPersonality.ghost:    'Призрак',
    AikaPersonality.oracle:   'Оракул',
    AikaPersonality.gabimaru: 'Габимару',
    AikaPersonality.kitsune:  'Китсунэ',
    AikaPersonality.sage:     'Сенсей',
    AikaPersonality.kawaii:   'Айка',
    AikaPersonality.tsundere: 'Айка',
    AikaPersonality.kuudere:  'Айка',
    AikaPersonality.yandere:  'Айка',
    AikaPersonality.genki:    'Айка',
  };

  @override
  Widget build(BuildContext context) {
    // Группируем по тегам
    final anime  = AikaPersonality.values.where((p) => _info[p]!['tag'] == 'АНИМЕ').toList();
    final scifi  = AikaPersonality.values.where((p) => _info[p]!['tag'] == 'SCI-FI').toList();

    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('ХАРАКТЕР', style: TextStyle(
          color: AikaTheme.neonBlue, fontSize: 16,
          fontWeight: FontWeight.bold, letterSpacing: 3,
        )),
        centerTitle: true,
        iconTheme: IconThemeData(color: AikaTheme.neonBlue),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Характер меняет стиль общения, голос и wake-word.',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),

          _sectionHeader('🌸 АНИМЕ'),
          ...anime.map((p) => _buildCard(p)),

          const SizedBox(height: 8),
          _sectionHeader('🤖 SCI-FI'),
          ...scifi.map((p) => _buildCard(p)),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(title, style: TextStyle(
      color: AikaTheme.neonBlue.withOpacity(0.7),
      fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2,
    )),
  );

  Widget _buildCard(AikaPersonality p) {
    final info = _info[p]!;
    final isSelected = _selected == p;

    // Цвет для SCI-FI карточек
    final isSci = info['tag'] == 'SCI-FI';
    final accent = isSci
        ? (p == AikaPersonality.jarvis ? const Color(0xFFB0B0B0)
           : p == AikaPersonality.friday ? const Color(0xFF9B9B9B)
           : p == AikaPersonality.ghost ? const Color(0xFF708090)
           : const Color(0xFFA0A0A0))
        : AikaTheme.neonBlue;

    return GestureDetector(
      onTap: () async {
        await PersonalityService.set(p);
        setState(() => _selected = p);

        // Обновляем wake-word с учётом персонажа
        final prefs = await SharedPreferences.getInstance();

        // Ставим авто-имя если текущее имя — дефолтное
        final currentName = prefs.getString('assistant_name') ?? '';
        final defaultNames = {'Айка', 'Aika', 'Aivora', 'JARVIS', 'FRIDAY',
          'Призрак', 'Оракул', 'Габимару', 'Китсунэ', 'Сенсей', ''};
        if (defaultNames.contains(currentName)) {
          await prefs.setString('assistant_name', _autoNames[p] ?? 'Айка');
        }

        // Добавляем wake-words персонажа
        final charWords = PersonalityService.characterWakeWords;
        if (charWords.isNotEmpty) {
          final existing = prefs.getString('custom_wake_word') ?? '';
          final allWords = <String>{...existing.split(',').map((e) => e.trim()), ...charWords}
            ..removeWhere((e) => e.isEmpty);
          await prefs.setString('custom_wake_word', allWords.join(','));
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Характер: ${info['name']} — применён'),
            backgroundColor: accent.withOpacity(0.85),
            behavior: SnackBarBehavior.floating,
          ));
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? accent.withOpacity(0.12) : AikaTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accent : accent.withOpacity(0.15),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(info['icon']!, style: const TextStyle(fontSize: 34)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(info['name']!, style: TextStyle(
                        color: isSelected ? accent : Colors.white,
                        fontSize: 15, fontWeight: FontWeight.bold,
                      )),
                      const SizedBox(width: 6),
                      if (isSci)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('NEW', style: TextStyle(
                            color: accent, fontSize: 9, fontWeight: FontWeight.bold,
                          )),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(info['desc']!, style: const TextStyle(
                    color: Colors.white54, fontSize: 11, height: 1.4,
                  )),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: accent, size: 22)
            else
              Icon(Icons.radio_button_unchecked, color: Colors.white12, size: 20),
          ],
        ),
      ),
    );
  }
}
