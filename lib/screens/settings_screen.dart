import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'settings_general_screen.dart';
import 'settings_voice_screen.dart';
import 'model_picker_screen.dart';
import 'settings_background_screen.dart';
import 'personality_screen.dart';
import 'chat_history_screen.dart';

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
          _SettingsCard(
            title: 'Персонаж',
            subtitle: 'Имя ассистента, личность и характер',
            icon: Icons.face_retouching_natural,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PersonalityScreen())),
          ),
          _SettingsCard(
            title: 'Голос',
            subtitle: 'Скорость, тон, громкость речи',
            icon: Icons.graphic_eq,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsVoiceScreen())),
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
            subtitle: 'Задний фон за персонажем, атмосфера',
            icon: Icons.landscape_outlined,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsBackgroundScreen())),
          ),
          _SettingsCard(
            title: 'История чата',
            subtitle: 'Все прошлые сообщения, очистка',
            icon: Icons.history,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChatHistoryScreen())),
          ),
          _SettingsCard(
            title: 'Общие',
            subtitle: 'Имя пользователя, размер аватара',
            icon: Icons.tune,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsGeneralScreen())),
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
  final VoidCallback onTap;

  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(icon, color: Colors.white12, size: 52),
          ],
        ),
      ),
    );
  }
}
