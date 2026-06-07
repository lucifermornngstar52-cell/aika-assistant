import 'package:flutter/material.dart';
import '../services/license_service.dart';
import 'license_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'main_screen.dart';
import 'onboarding_screen.dart';
import 'permissions_onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..forward();

    Future.delayed(const Duration(milliseconds: 2500), _navigate);
  }

  Future<void> _navigate() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name');
    final savedEmail = await LicenseService.getSavedEmail();
    if (!mounted) return;

    // Проверяем лицензию если email уже есть
    if (savedEmail != null) {
      final status = await LicenseService.checkLicenseByEmail(savedEmail);
      if (!mounted) return;
      if (!status.valid) {
        Navigator.of(context).pushReplacement(PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LicenseScreen(),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 600),
        ));
        return;
      }
    } else if (savedEmail == null) {
      // Первый запуск — идём на экран лицензии
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LicenseScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ));
      return;
    }

    Widget nextScreen;
    if (name == null) {
      nextScreen = const OnboardingScreen();
    } else {
      final permsDone = prefs.getBool('permissions_done') ?? false;
      nextScreen = permsDone ? const MainScreen() : const PermissionsOnboardingScreen();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => nextScreen,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Glow orb — без PNG
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [AikaTheme.neonBlue, AikaTheme.neonPurple, Colors.transparent],
                  stops: [0.0, 0.6, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AikaTheme.neonBlue.withOpacity(0.6),
                    blurRadius: 60,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 52),
            )
                .animate()
                .scale(duration: 800.ms, curve: Curves.elasticOut)
                .fadeIn(duration: 600.ms),

            const SizedBox(height: 32),

            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AikaTheme.neonBlue, AikaTheme.neonPurple],
              ).createShader(bounds),
              child: const Text(
                'А И В О Р А',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 12,
                ),
              ),
            )
                .animate()
                .fadeIn(delay: 400.ms, duration: 600.ms)
                .slideY(begin: 0.3, end: 0),

            const SizedBox(height: 12),

            const Text(
              'Твой AI-ассистент',
              style: TextStyle(
                color: AikaTheme.textSecondary,
                fontSize: 14,
                letterSpacing: 2,
              ),
            )
                .animate()
                .fadeIn(delay: 700.ms, duration: 600.ms),

            const SizedBox(height: 60),

            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AikaTheme.neonBlue.withOpacity(0.6),
              ),
            )
                .animate()
                .fadeIn(delay: 1000.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }
}
