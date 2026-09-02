import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AboutProjectScreen extends StatelessWidget {
  const AboutProjectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('О проекте',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card("Айка", "AI-ассистент для Android",
            "AI: Groq gpt-oss-120b → Gemini → Claude → Deepseek (авто-fallback)\n"
            "Голос: speech_to_text + EdgeTTS / ElevenLabs / System TTS\n"
            "Модели: Live2D (Hiyori, Natori, Haru, Mao, Rice, Wanko + свои .model3.json)\n"
            "Оверлей поверх всех приложений, wake word — непрерывное слушание\n"
            "Управление телефоном через Accessibility Service\n"
            "Geolocation: IP-based · Уведомления: NotificationListenerService",
          ),
          const SizedBox(height: 12),
          _card("Персонажи",
            "12 личностей",
            "JARVIS, FRIDAY, Kawaii, Tsundere, Kuudere,\n"
            "Yandere, Genki, Kitsune, Gabimaru, Sage,\n"
            "Ghost, Oracle",
          ),
          const SizedBox(height: 12),
          _card("Управление телефоном",
            "Accessibility + нативные bridge",
            "• Навигация: назад, домой, недавние\n"
            "• Запуск приложений по имени, управление музыкой\n"
            "• Скриншоты, фонарик, яркость\n"
            "• Smart alarm с брифингом",
          ),
          const SizedBox(height: 12),
          _card("Telegram бот",
            "Регистрация и управление",
            "• Регистрация через Telegram\n"
            "• Approve/Reject через inline кнопки",
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              "Aika v2 · 2026",
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _card(String title, String subtitle, String body) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AikaTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(
            color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 12),
          Text(body, style: const TextStyle(
            color: Colors.white70, fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }
}
