import 'package:flutter/material.dart';
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
    AikaPersonality.kawaii: {
      'icon': '🌸',
      'name': 'Милая тянка',
      'desc': 'Добрая, радостная, использует милые слова и эмодзи. Любит тебя безусловно~',
    },
    AikaPersonality.tsundere: {
      'icon': '😤',
      'name': 'Цундере',
      'desc': 'Снаружи грубая, внутри добрая. "Не думай что я делаю это ради тебя, бака!"',
    },
    AikaPersonality.kuudere: {
      'icon': '❄️',
      'name': 'Холодная умница',
      'desc': 'Короткие ответы, логика прежде всего. Эмоции скрывает, но они есть.',
    },
    AikaPersonality.gabimaru: {
      'icon': '⚔️',
      'name': 'Жёсткий Габимару',
      'desc': 'Прямолинейный и резкий как Габимару из Адского Рая. Говорит только суть.',
    },
    AikaPersonality.sage: {
      'icon': '🧠',
      'name': 'Мудрый сенсей',
      'desc': 'Спокойный наставник с глубокими мыслями. Терпелив и рассудителен.',
    },
  };

  @override
  Widget build(BuildContext context) {
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Выбери характер ассистента.\nЭто изменит стиль общения Айки.',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: AikaPersonality.values.map((p) {
                final info = _info[p]!;
                final isSelected = _selected == p;
                return GestureDetector(
                  onTap: () async {
                    await PersonalityService.set(p);
                    setState(() => _selected = p);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Характер изменён: ${info['name']}'),
                          backgroundColor: AikaTheme.neonBlue.withOpacity(0.8),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected
                        ? AikaTheme.neonBlue.withOpacity(0.15)
                        : AikaTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                          ? AikaTheme.neonBlue
                          : AikaTheme.neonBlue.withOpacity(0.15),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(info['icon']!, style: const TextStyle(fontSize: 36)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(info['name']!, style: TextStyle(
                                color: isSelected ? AikaTheme.neonBlue : Colors.white,
                                fontSize: 15, fontWeight: FontWeight.bold,
                              )),
                              const SizedBox(height: 4),
                              Text(info['desc']!, style: const TextStyle(
                                color: Colors.white54, fontSize: 12,
                              )),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle_rounded, color: AikaTheme.neonBlue),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
