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
            "Flutter + Kotlin\n"
            "Live2D модели (Cubism SDK)\n"
            "Голосовой ввод: speech_to_text\n"
            "TTS: EdgeTTS / ElevenLabs / System\n"
            "AI: Groq gpt-oss-120b (основной)\n"
            "Fallback: Gemini → Claude → Deepseek\n"
            "Оверлей поверх всех приложений\n"
            "Wake word: непрерывное слушание\n"
            "Управление телефоном: Accessibility Service\n"
            "Geolocation: IP-based\n"
            "Уведомления: NotificationListenerService\n"
            "Тема: тёмная, серые/белые/стекло",
          ),
          const SizedBox(height: 12),
          _card("AI Двигатели",
            "Подключённые сервисы",
            "• Groq gpt-oss-120b — основной (бесплатно)\n"
            "• Google Gemini — fallback\n"
            "• Claude Haiku — творческие задачи\n"
            "• Deepseek — дешёвый fallback\n"
            "• Переключение автоматически при 429\n"
            "• Веб-поиск: DuckDuckGo + Brave\n"
            "• 12 персонажей с уникальными промптами",
          ),
          const SizedBox(height: 12),
          _card("Голос",
            "TTS и распознавание",
            "• Wake word: speech_to_text, 300с сессии\n"
            "• TTS: EdgeTTS (WebSocket), ElevenLabs, System\n"
            "• Распознавание: Google Speech API\n"
            "• VAD: RMS-энергия + порог тишины\n"
            "• Фоновое слушание: foreground service\n"
            "• Mute во время звонков",
          ),
          const SizedBox(height: 12),
          _card("Управление телефоном",
            "Accessibility + нативные bridge",
            "• Навигация: назад, домой, рекents\n"
            "• Запуск приложений по имени\n"
            "• Управление музыкой (media broadcast)\n"
            "• Уведомления: чтение через TTS\n"
            "• Скриншоты, фонарик, яркость\n"
            "• MethodChannel / EventChannel bridge\n"
            "• Smart alarm с брифингом",
          ),
          const SizedBox(height: 12),
          _card("Персонажи",
            "12 личностей",
            "JARVIS, FRIDAY, Kawaii, Tsundere, Kuudere,\n"
            "Yandere, Genki, Kitsune, Gabimaru, Sage,\n"
            "Ghost, Oracle",
          ),
          const SizedBox(height: 12),
          _card("Модели",
            "Live2D только",
            "Hiyori, Natori, Haru, Mao, Rice, Wanko\n"
            "Кастомные .model3.json файлы\n"
            "3D модели удалены",
          ),
          const SizedBox(height: 12),
          _card("Telegram бот",
            "Регистрация и управление",
            "• Регистрация через Telegram\n"
            "• Approve/Reject через inline кнопки\n"
            "• License requests → server endpoint",
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
