import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'settings_general_screen.dart';
import 'settings_voice_screen.dart';
import 'model_picker_screen.dart';
import 'settings_background_screen.dart';
import 'personality_screen.dart';
import 'chat_history_screen.dart';
import 'settings_overlay_screen.dart';
import 'about_project_screen.dart';
import 'ai_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Настройки',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          const SizedBox(height: 8),

          // ── AI ─────────────────────────────────────────────────────
          _SettingsCard(
            title: '🧠 AI Двигатели',
            subtitle: 'Groq gpt-oss-120b, Gemini, Claude, Deepseek, веб-поиск',
            icon: Icons.auto_awesome,
            accent: const Color(0xFFB0B0B0),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AiSettingsScreen())),
          ),

          // ── Характер ───────────────────────────────────────────────
          _SettingsCard(
            title: 'Персонаж',
            subtitle: 'Айка, JARVIS, FRIDAY, Призрак, Оракул и др.',
            icon: Icons.face_retouching_natural,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PersonalityScreen())),
          ),

          _SettingsCard(
            title: 'Голос',
            subtitle: 'Скорость, тон, Microsoft Neural Voice',
            icon: Icons.graphic_eq,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsVoiceScreen())),
          ),

          _SettingsCard(
            title: 'Оверлей',
            subtitle: 'Размер модели, перетаскивание, прозрачность',
            icon: Icons.picture_in_picture_alt_rounded,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsOverlayScreen())),
          ),

          _SettingsCard(
            title: 'Модели',
            subtitle: 'Live2D, загрузка своих моделей',
            icon: Icons.view_in_ar_rounded,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ModelPickerScreen())),
          ),

          _SettingsCard(
            title: 'Фон',
            subtitle: 'Задний фон, атмосфера',
            icon: Icons.landscape_outlined,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsBackgroundScreen())),
          ),

          _SettingsCard(
            title: 'История чата',
            subtitle: 'Все прошлые сообщения, очистка',
            icon: Icons.history,
            onTap: () async {
              // ФИКС: пробрасываем флаг очистки истории на главный экран,
              // чтобы он сбросил свой список сообщений в памяти.
              final cleared = await Navigator.push<bool>(context,
                  MaterialPageRoute(builder: (_) => const ChatHistoryScreen()));
              if (cleared == true && context.mounted) {
                Navigator.pop(context, true);
              }
            },
          ),

          _SettingsCard(
            title: 'Общие',
            subtitle: 'Имя пользователя, wake word, размер аватара',
            icon: Icons.tune,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsGeneralScreen())),
          ),

          _SettingsCard(
            title: 'О проекте',
            subtitle: 'Технологии, возможности, стек',
            icon: Icons.code_rounded,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AboutProjectScreen())),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? accent;
  final VoidCallback onTap;

  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: color != null
              ? color.withOpacity(0.08)
              : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(18),
          border: color != null
              ? Border.all(color: color.withOpacity(0.3), width: 1)
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color ?? Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(icon,
                color: color != null ? color.withOpacity(0.4) : Colors.white12,
                size: 48),
          ],
        ),
      ),
    );
  }
}
