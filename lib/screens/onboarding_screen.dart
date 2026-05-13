import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'main_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _loading = false;

  Future<void> _confirm() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);

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
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AikaTheme.neonPurple.withOpacity(0.5),
                      blurRadius: 50,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/aika_avatar.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AikaTheme.neonBlue, AikaTheme.neonPurple],
                        ),
                      ),
                      child: const Icon(Icons.star, color: Colors.white, size: 60),
                    ),
                  ),
                ),
              )
                  .animate()
                  .scale(duration: 700.ms, curve: Curves.elasticOut)
                  .fadeIn(duration: 500.ms),

              const SizedBox(height: 32),

              const Text(
                'Привет! Я — Айка ✨',
                style: TextStyle(
                  color: AikaTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

              const SizedBox(height: 12),

              const Text(
                'Твой личный AI-ассистент.\nКак мне тебя называть?',
                style: TextStyle(
                  color: AikaTheme.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

              const SizedBox(height: 40),

              // Name input
              Container(
                decoration: AikaTheme.glassCard(borderColor: AikaTheme.neonBlue),
                child: TextField(
                  controller: _nameController,
                  style: const TextStyle(color: AikaTheme.textPrimary, fontSize: 16),
                  textAlign: TextAlign.center,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _confirm(),
                  decoration: const InputDecoration(
                    hintText: 'Твоё имя...',
                    hintStyle: TextStyle(color: AikaTheme.textSecondary),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                ),
              ).animate().fadeIn(delay: 700.ms, duration: 500.ms).slideY(begin: 0.2, end: 0),

              const SizedBox(height: 24),

              // Confirm button
              GestureDetector(
                onTap: _loading ? null : _confirm,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AikaTheme.neonBlue, AikaTheme.neonPurple],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AikaTheme.neonBlue.withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: _loading
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Начать!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                ),
              ).animate().fadeIn(delay: 900.ms, duration: 500.ms),
            ],
          ),
        ),
      ),
    );
  }
}
