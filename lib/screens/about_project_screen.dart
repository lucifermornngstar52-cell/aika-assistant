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
          // Название
          _card('Айка', 'AI-ассистент для Android',
            'Flutter + Kotlin
'
            'Live2D модели (Cubism SDK)
'
            'Голосовой ввод: speech_to_text
'
            'TTS: EdgeTTS / ElevenLabs / System
'
            'AI: Groq gpt-oss-120b (основной)
'
            'Fallback: Gemini → Claude → Deepseek
'
            'Оверлей поверх всех приложений
'
            'Wake word: непрерывное слушание
'
            'Управление телефоном: Accessibility Service
'
            'Geolocation: IP-based
'
            'Уведомления: NotificationListenerService
'
            'Тема: тёмная, серые/белые/стекло',
          ),
          const SizedBox(height: 12),

          // AI Двигатели
          _card('AI Двигатели',
            'Подключённые сервисы',
            '• Groq gpt-oss-120b — основной (бесплатно)
'
            '• Google Gemini — fallback
'
            '• Claude Haiku — творческие задачи
'
            '• Deepseek — дешёвый fallback
'
            '• Переключение автоматически при 429
'
            '• Веб-поиск: DuckDuckGo + Brave
'
            '• 12 персонажей с уникальными промптами',
          ),
          const SizedBox(height: 12),

          // Голос
          _card('Голос',
            'TTS и распознавание',
            '• Wake word: speech_to_text, 300с сессии
'
            '• TTS: EdgeTTS (WebSocket), ElevenLabs, System
'
            '• Распознавание: Google Speech API
'
            '• VAD: RMS-энергия + порог тишины
'
            '• Фоновое слушание: foreground service
'
            '• Mute во время звонков',
          ),
          const SizedBox(height: 12),

          // Управление
          _card('Управление телефоном',
            'Accessibility + нативные bridge',
            '• Навигация: назад, домой, рекents
'
            '• Запуск приложений по имени
'
            '• Управление музыкой (media broadcast)
'
            '• Уведомления: чтение через TTS
'
            '• Скриншоты, фонарик, яркость
'
            '• MethodChannel / EventChannel bridge
'
            '• Smart alarm с брифингом',
          ),
          const SizedBox(height: 12),

          // Персонажи
          _card('Персонажи',
            '12 личностей',
            'JARVIS, FRIDAY, Kawaii, Tsundere, Kuudere,
'
            'Yandere, Genki, Kitsune, Gabimaru, Sage,
'
            'Ghost, Oracle',
          ),
          const SizedBox(height: 12),

          // Модели
          _card('Модели',
            'Live2D только',
            'Hiyori, Natori, Haru, Mao, Rice, Wanko
'
            'Кастомные .model3.json файлы
'
            '3D модели удалены',
          ),
          const SizedBox(height: 12),

          // Telegram
          _card('Telegram бот',
            'Регистрация и управление',
            '• Регистрация через Telegram
'
            '• Approve/Reject через inline кнопки
'
            '•license requests → server endpoint',
          ),
          const SizedBox(height: 32),

          // Версия
          Center(
            child: Text(
              'Aika v2 · 2026',
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
