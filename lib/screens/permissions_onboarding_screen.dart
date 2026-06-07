import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import 'main_screen.dart';

/// PermissionsOnboardingScreen — пошаговый экран запроса разрешений.
/// Каждое разрешение показывается на своём экране с объяснением.
/// Вдохновлено GA Desktop Client "Before you start..." flow.
///
/// Разрешения:
///   0: Микрофон (RECORD_AUDIO) — основа
///   1: Уведомления (POST_NOTIFICATIONS) — чтение / ответы
///   2: Календарь (READ_CALENDAR / WRITE_CALENDAR) — события
///   3: Контакты (READ_CONTACTS) — поиск людей
///   4: Активность (ACTIVITY_RECOGNITION) — шагомер
///   5: Поверх приложений (SYSTEM_ALERT_WINDOW) — чиби overlay
class PermissionsOnboardingScreen extends StatefulWidget {
  const PermissionsOnboardingScreen({super.key});

  @override
  State<PermissionsOnboardingScreen> createState() =>
      _PermissionsOnboardingScreenState();
}

class _PermEntry {
  final String emoji;
  final String title;
  final String subtitle;
  final String description;
  final String grantText;
  final Permission? permission; // null = специальное (overlay)
  final bool optional;

  const _PermEntry({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.grantText,
    this.permission,
    this.optional = false,
  });
}

class _PermissionsOnboardingScreenState
    extends State<PermissionsOnboardingScreen> {
  int _step = 0;
  bool _granting = false;
  Map<int, bool> _granted = {};

  static const List<_PermEntry> _permissions = [
    _PermEntry(
      emoji: '🎤',
      title: 'Микрофон',
      subtitle: 'Разговаривай со мной голосом',
      description:
          'Чтобы слышать тебя и реагировать на голосовые команды. '
          'Без микрофона голосовое управление недоступно.',
      grantText: 'Разрешить доступ к микрофону',
      permission: Permission.microphone,
    ),
    _PermEntry(
      emoji: '🔔',
      title: 'Уведомления',
      subtitle: 'Буду сообщать о важных событиях',
      description:
          'Чтобы отправлять напоминания, таймеры и уведомления. '
          'Также читаю входящие уведомления и могу отвечать на сообщения.',
      grantText: 'Разрешить уведомления',
      permission: Permission.notification,
    ),
    _PermEntry(
      emoji: '📅',
      title: 'Календарь',
      subtitle: 'Твоё расписание всегда под рукой',
      description:
          'Читаю и создаю события в твоём системном календаре. '
          'Можешь спросить "что у меня сегодня" или "добавь встречу в 15:00".',
      grantText: 'Разрешить доступ к календарю',
      permission: Permission.calendarFullAccess,
      optional: true,
    ),
    _PermEntry(
      emoji: '👥',
      title: 'Контакты',
      subtitle: 'Найду нужного человека за секунду',
      description:
          'Ищу контакты голосом. "Найди контакт Саша" — и я покажу '
          'все варианты с номерами телефонов.',
      grantText: 'Разрешить доступ к контактам',
      permission: Permission.contacts,
      optional: true,
    ),
    _PermEntry(
      emoji: '🏃',
      title: 'Физическая активность',
      subtitle: 'Слежу за твоими шагами',
      description:
          'Считаю шаги через встроенный датчик телефона. '
          '"Сколько я прошёл шагов?" — и я расскажу про расстояние и калории.',
      grantText: 'Разрешить отслеживание активности',
      permission: Permission.activityRecognition,
      optional: true,
    ),
    _PermEntry(
      emoji: '🌟',
      title: 'Наложение поверх приложений',
      subtitle: 'Чиби-аватар будет всегда рядом',
      description:
          'Показываю Live2D аватар поверх других приложений. '
          'Это разрешение нужно выдать вручную в настройках.',
      grantText: 'Открыть настройки и разрешить',
      permission: null, // специальное разрешение
      optional: true,
    ),
  ];

  Future<void> _grantCurrent() async {
    setState(() => _granting = true);
    final entry = _permissions[_step];

    if (entry.permission != null) {
      final status = await entry.permission!.request();
      setState(() {
        _granted[_step] = status.isGranted;
        _granting = false;
      });
    } else {
      // SYSTEM_ALERT_WINDOW — открываем настройки
      await openAppSettings();
      setState(() {
        _granted[_step] = true; // считаем выданным (юзер сам проверит)
        _granting = false;
      });
    }

    // Небольшая пауза чтобы анимация успела показаться
    await Future.delayed(const Duration(milliseconds: 400));
    _next();
  }

  void _skip() {
    setState(() => _granted[_step] = false);
    _next();
  }

  void _next() {
    if (_step < _permissions.length - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MainScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = _permissions[_step];
    final isLast = _step == _permissions.length - 1;
    final progress = (_step + 1) / _permissions.length;

    return Scaffold(
      backgroundColor: AikaTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            children: [
              // ── Прогресс-бар ──────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AikaTheme.neonBlue),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_step + 1}/${_permissions.length}',
                    style: TextStyle(
                      color: AikaTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),

              const Spacer(flex: 2),

              // ── Emoji ─────────────────────────────────────────
              Text(
                entry.emoji,
                style: const TextStyle(fontSize: 80),
              )
                  .animate(key: ValueKey(_step))
                  .scale(duration: 600.ms, curve: Curves.elasticOut)
                  .fadeIn(duration: 400.ms),

              const SizedBox(height: 28),

              // ── Заголовок ─────────────────────────────────────
              Text(
                entry.title,
                style: const TextStyle(
                  color: AikaTheme.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(key: ValueKey('title$_step'))
                  .fadeIn(delay: 100.ms, duration: 400.ms)
                  .slideY(begin: 0.15, end: 0),

              const SizedBox(height: 8),

              // ── Подзаголовок ──────────────────────────────────
              Text(
                entry.subtitle,
                style: TextStyle(
                  color: AikaTheme.neonBlue,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(key: ValueKey('sub$_step'))
                  .fadeIn(delay: 200.ms, duration: 400.ms),

              const SizedBox(height: 24),

              // ── Описание ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Text(
                  entry.description,
                  style: TextStyle(
                    color: AikaTheme.textSecondary,
                    fontSize: 15,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
                  .animate(key: ValueKey('desc$_step'))
                  .fadeIn(delay: 300.ms, duration: 400.ms),

              // Бейдж "необязательно"
              if (entry.optional) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Необязательно — можно пропустить',
                    style: TextStyle(
                      color: AikaTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],

              const Spacer(flex: 3),

              // ── Кнопка "Разрешить" ────────────────────────────
              GestureDetector(
                onTap: _granting ? null : _grantCurrent,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AikaTheme.neonBlue, AikaTheme.neonPurple],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AikaTheme.neonBlue.withOpacity(0.4),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: _granting
                      ? const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          ),
                        )
                      : Text(
                          entry.grantText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Кнопка "Пропустить" ───────────────────────────
              GestureDetector(
                onTap: _granting ? null : _skip,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    isLast ? 'Начать без этого' : 'Пропустить',
                    style: TextStyle(
                      color: AikaTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
