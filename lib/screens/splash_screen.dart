import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const MainScreen(),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Glowing orb
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AikaTheme.neonBlue.withOpacity(0.8),
                    AikaTheme.neonPurple.withOpacity(0.4),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AikaTheme.neonBlue.withOpacity(0.6),
                    blurRadius: 60,
                    spreadRadius: 20,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 60,
              ),
            )
                .animate(onPlay: (ctrl) => ctrl.repeat(reverse: true))
                .scale(
                  begin: const Offset(0.9, 0.9),
                  end: const Offset(1.1, 1.1),
                  duration: 1500.ms,
                ),

            const SizedBox(height: 32),

            // Name
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AikaTheme.neonBlue, AikaTheme.neonPurple],
              ).createShader(bounds),
              child: const Text(
                'АЙКА',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 12,
                ),
              ),
            )
                .animate()
                .fadeIn(delay: 500.ms, duration: 800.ms)
                .slideY(begin: 0.3, end: 0),

            const SizedBox(height: 8),

            Text(
              'AI · Ассистент',
              style: TextStyle(
                color: AikaTheme.textSecondary,
                fontSize: 14,
                letterSpacing: 4,
              ),
            )
                .animate()
                .fadeIn(delay: 800.ms, duration: 600.ms),

            const SizedBox(height: 60),

            // Loading dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AikaTheme.neonBlue,
                  ),
                )
                    .animate(delay: Duration(milliseconds: 1000 + i * 200))
                    .fadeIn(duration: 400.ms)
                    .then()
                    .animate(onPlay: (ctrl) => ctrl.repeat(reverse: true))
                    .scaleXY(begin: 0.5, end: 1.5, duration: 600.ms),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
