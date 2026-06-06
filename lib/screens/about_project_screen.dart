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
        title: const Text(
          'ПРОЕКТ',
          style: TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildSection(
            icon: '⚡',
            title: 'О ПРОЕКТЕ',
            children: [
              _buildText(
                'Aika Assistant — персональный голосовой AI-ассистент нового поколения. '
                'Не просто чат-бот — живая аниме-личность с характером, эмоциями и реальным контролем над устройством.',
              ),
              const SizedBox(height: 8),
              _buildText(
                'Работает на базе Gemini Flash и GPT-4o с автоматическим переключением '
                'при перегрузке. Голос — Microsoft Neural через EdgeTTS. '
                '2D-персонаж — Live2D Cubism с анимациями в реальном времени.',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            icon: '🎯',
            title: 'ВОЗМОЖНОСТИ',
            children: [
              _buildFeature('🧠', 'AI-диалог', 'Gemini Flash + GPT-4o fallback, долгая память, 8 персонажей'),
              _buildFeature('🎤', 'Wake-word', 'Бесконечное фоновое прослушивание по имени ассистента'),
              _buildFeature('📱', 'Управление телефоном', 'Запуск приложений, жесты, ввод текста через AccessibilityService'),
              _buildFeature('🎵', 'Медиа-контроль', 'Управление музыкой без переключения из игр'),
              _buildFeature('🔔', 'Уведомления', 'Чтение и ответ на входящие сообщения голосом'),
              _buildFeature('📅', 'Расписание', 'Расписание дня, будильники, умный утренний брифинг'),
              _buildFeature('🌤', 'Погода и курсы', 'IP-геолокация, актуальные данные в реальном времени'),
              _buildFeature('🎭', '8 персонажей', 'Милая тянка, цундере, яндере, мудрый сенсей и другие'),
              _buildFeature('🪟', 'Оверлей поверх всего', 'Live2D-персонаж поверх любого приложения'),
              _buildFeature('📊', 'Журнал настроения', 'AI-анализ настроения и дневник эмоций'),
              _buildFeature('🤖', 'Telegram-бот', 'Дистанционное управление и push-уведомления'),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            icon: '🎨',
            title: '2D ПЕРСОНАЖИ',
            children: [
              _buildText(
                'Модели Haru, Hiyori, Mao, Mark, Natori, Ren, Rice, Wanko — '
                'официальные образцы Live2D Inc.',
              ),
              const SizedBox(height: 4),
              _buildText('Сайт: cubism.live2d.com'),
              const SizedBox(height: 4),
              _buildText('Движок: Live2D Cubism SDK + PixiJS + pixi-live2d-display.'),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            icon: '👥',
            title: 'КОМАНДА',
            children: [
              _buildCredit('🏆', 'HikariOS', 'Идея, архитектура, вся разработка', isBoss: true),
              _buildCredit('🎨', 'Live2D Inc.', '2D персонажи (cubism.live2d.com)'),
              _buildCredit('🤖', 'Base44 AI', 'Автоматические исправления и рефакторинг кода'),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            icon: '🛠',
            title: 'СТЕК',
            children: [
              _buildChips([
                'Flutter', 'Kotlin', 'Gemini Flash', 'GPT-4o',
                'EdgeTTS', 'Live2D SDK', 'PixiJS', 'AccessibilityService',
                'SharedPreferences', 'Telegram Bot API', 'WebView',
              ]),
            ],
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              '© 2025–2026 HikariOS',
              style: const TextStyle(
                color: Colors.white24,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A001F), Color(0xFF001040)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1),
      ),
      child: Column(
        children: [
          const Text('AIKA', style: TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 40,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
          )),
          const SizedBox(height: 4),
          const Text('ASSISTANT', style: TextStyle(
            color: Colors.white54,
            fontSize: 14,
            letterSpacing: 6,
          )),
          const SizedBox(height: 12),
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, const Color(0xFF00E5FF).withOpacity(0.5), Colors.transparent],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('v1.0.0 — Alpha', style: TextStyle(
            color: Colors.white38, fontSize: 12, letterSpacing: 2,
          )),
        ],
      ),
    );
  }

  Widget _buildSection({required String icon, required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            )),
          ]),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildText(String text) => Text(
    text,
    style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
  );

  Widget _buildFeature(String icon, String name, String desc) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.4)),
          ],
        )),
      ],
    ),
  );

  Widget _buildCredit(String icon, String name, String role, {bool isBoss = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isBoss
              ? const Color(0xFF00E5FF).withOpacity(0.15)
              : const Color(0xFF0A0A2A),
            border: Border.all(
              color: isBoss ? const Color(0xFF00E5FF) : const Color(0xFF00E5FF).withOpacity(0.2),
              width: isBoss ? 2 : 1,
            ),
          ),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: TextStyle(
              color: isBoss ? const Color(0xFF00E5FF) : Colors.white,
              fontSize: 14,
              fontWeight: isBoss ? FontWeight.bold : FontWeight.normal,
            )),
            Text(role, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        )),
      ],
    ),
  );

  Widget _buildChips(List<String> chips) => Wrap(
    spacing: 8, runSpacing: 8,
    children: chips.map((c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF00E5FF).withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1),
      ),
      child: Text(c, style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11)),
    )).toList(),
  );
}
