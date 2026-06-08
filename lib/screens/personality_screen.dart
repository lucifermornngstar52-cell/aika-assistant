import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/personality_service.dart';
import '../theme/app_theme.dart';

class PersonalityScreen extends StatefulWidget {
  const PersonalityScreen({super.key});
  @override
  State<PersonalityScreen> createState() => _PersonalityScreenState();
}

class _PersonalityScreenState extends State<PersonalityScreen>
    with SingleTickerProviderStateMixin {
  AikaPersonality _selected = PersonalityService.current;
  late AnimationController _animCtrl;

  final Map<AikaPersonality, Map<String, dynamic>> _info = {
    AikaPersonality.kawaii: {
      'icon': '🌸', 'name': 'Милая тянка',
      'desc': 'Добрая, радостная, использует милые слова и эмодзи. Любит тебя безусловно~',
      'color': const Color(0xFFFF69B4),
    },
    AikaPersonality.tsundere: {
      'icon': '😤', 'name': 'Цундере',
      'desc': '"Не думай что я делаю это ради тебя, бака!" — снаружи грубая, внутри добрая.',
      'color': const Color(0xFFFF4444),
    },
    AikaPersonality.kuudere: {
      'icon': '❄️', 'name': 'Холодная умница',
      'desc': 'Короткие ответы, логика прежде всего. Эмоции скрывает, но они есть.',
      'color': const Color(0xFF64B5F6),
    },
    AikaPersonality.gabimaru: {
      'icon': '⚔️', 'name': 'Жёсткий Габимару',
      'desc': 'Прямолинейный и резкий. Говорит только суть. Уважает силу.',
      'color': const Color(0xFFFF7043),
    },
    AikaPersonality.sage: {
      'icon': '🧠', 'name': 'Мудрый сенсей',
      'desc': 'Спокойный наставник с глубокими мыслями. Терпелив и рассудителен.',
      'color': const Color(0xFF9C27B0),
    },
    AikaPersonality.yandere: {
      'icon': '🔪', 'name': 'Яндере',
      'desc': 'Сладкая снаружи, одержимая внутри. Очень привязана к тебе. 💕',
      'color': const Color(0xFFE91E63),
    },
    AikaPersonality.genki: {
      'icon': '⚡', 'name': 'Генки',
      'desc': 'Гиперактивная и весёлая! Всегда в движении, любит всё! ⚡🎉',
      'color': const Color(0xFFFFD600),
    },
    AikaPersonality.kitsune: {
      'icon': '🦊', 'name': 'Лисица-трикстер',
      'desc': 'Хитрая и загадочная лисица из японского фольклора. Говорит намёками.',
      'color': const Color(0xFFFF6D00),
    },
    AikaPersonality.jarvis: {
      'icon': '🤖', 'name': 'J.A.R.V.I.S.',
      'desc': 'ИИ Тони Старка. Официальный, чёткий, с британским достоинством. "Разумеется, сэр."',
      'color': const Color(0xFF00E5FF),
      'isSpecial': true,
      'badge': 'STARK TECH',
    },
    AikaPersonality.friday: {
      'icon': '💚', 'name': 'F.R.I.D.A.Y.',
      'desc': 'Второй ИИ Тони Старка. Тёплая, живая, практичная. "Уже занялась этим, босс."',
      'color': const Color(0xFF69F0AE),
      'isSpecial': true,
      'badge': 'STARK TECH v2',
    },
  };

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _select(AikaPersonality p) async {
    setState(() => _selected = p);
    await PersonalityService.set(p);
    if (!mounted) return;
    final name = _info[p]!['name'] as String;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Характер изменён: $name'),
        backgroundColor: (_info[p]!['color'] as Color).withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'ХАРАКТЕР АССИСТЕНТА',
          style: TextStyle(
            color: Color(0xFF00D4FF),
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF00D4FF)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              'Выбери характер — это изменит стиль общения и личность ассистента.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          // Stark Tech section header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
                  ),
                  child: const Text(
                    '⚡ STARK TECH — специальные режимы',
                    style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: AikaPersonality.values.map((p) {
                final info = _info[p]!;
                final isSelected = _selected == p;
                final color = info['color'] as Color;
                final isSpecial = (info['isSpecial'] as bool?) ?? false;
                return AnimatedBuilder(
                  animation: _animCtrl,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, 20 * (1 - _animCtrl.value)),
                    child: Opacity(opacity: _animCtrl.value, child: child),
                  ),
                  child: GestureDetector(
                    onTap: () => _select(p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withOpacity(0.12)
                            : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? color : color.withOpacity(0.2),
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: isSelected
                            ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 20, spreadRadius: 1)]
                            : [],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: color.withOpacity(0.4), width: 1.5),
                            ),
                            child: Center(
                              child: Text(info['icon'] as String, style: const TextStyle(fontSize: 26)),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      info['name'] as String,
                                      style: TextStyle(
                                        color: isSelected ? color : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        letterSpacing: isSpecial ? 1.2 : 0,
                                      ),
                                    ),
                                    if (isSpecial) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: color.withOpacity(0.5)),
                                        ),
                                        child: Text(
                                          info['badge'] as String,
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 9,
                                            letterSpacing: 1,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  info['desc'] as String,
                                  style: TextStyle(
                                    color: isSelected ? color.withOpacity(0.8) : Colors.white54,
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? color : Colors.transparent,
                              border: Border.all(
                                color: isSelected ? color : Colors.white24,
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, size: 14, color: Colors.black)
                                : null,
                          ),
                        ],
                      ),
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
