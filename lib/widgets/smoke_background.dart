import 'dart:math';
import 'package:flutter/material.dart';

/// ════════════════════════════════════════════════════════════════════════════
/// SmokeBackground фиолетовый переливающийся дым, как на сайте HikariOS.
/// Чёрный фон → тёмно-фиолетовые клубы → светлые фиолетовые вспышки.
/// Медленная анимация (30 сек цикл), GPU-блюр, поверх затемнение,
/// чтобы контент читался. Используется через MaterialApp.builder 
/// единая атмосфера во всём приложении, включая все экраны настроек.
/// ════════════════════════════════════════════════════════════════════════════
class SmokeBackground extends StatefulWidget {
 final Widget child;
 const SmokeBackground({super.key, required this.child});

 @override
 State<SmokeBackground> createState() => _SmokeBackgroundState();
}

class _SmokeBackgroundState extends State<SmokeBackground>
 with SingleTickerProviderStateMixin {
 late final AnimationController _c =
 AnimationController(vsync: this, duration: const Duration(seconds: 30))
..repeat();

 @override
 void dispose() {
 _c.dispose();
 super.dispose();
 }

 @override
 Widget build(BuildContext context) {
 return RepaintBoundary(
 child: Stack(
 fit: StackFit.passthrough,
 children: [
 // ── Дым: клубы на почти чёрном фоне ──
 Positioned.fill(
 child: AnimatedBuilder(
 animation: _c,
 builder: (_, __) => CustomPaint(
 painter: _SmokePainter(_c.value),
 child: const SizedBox.expand(),
),
),
),
 // Контент поверх
 widget.child,
 ],
),
);
 }
}

class _SmokePainter extends CustomPainter {
 final double t; // 0..1 цикл
 _SmokePainter(this.t);

 @override
 void paint(Canvas canvas, Size size) {
 final w = size.width;
 final h = size.height;

 // База: чёрный с лёгким фиолетовым уклоном
 final base = Paint()
..shader = LinearGradient(
 begin: Alignment.topLeft,
 end: Alignment.bottomRight,
 colors: const [Color(0xFF07060D), Color(0xFF0A0812), Color(0xFF0D0A16)],
).createShader(Offset.zero & size);
 canvas.drawRect(Offset.zero & size, base);

 // Клубы дыма: радиальные градиенты, дрейфуют по синусам
 final rng = Random(7);
 for (var i = 0; i < 6; i++) {
 final phase = rng.nextDouble();
 final cx = (0.15 + rng.nextDouble() * 0.7) * w +
 sin((t * 2 * pi) + phase * 6.28) * w * 0.12;
 final cy = (0.1 + rng.nextDouble() * 0.8) * h +
 cos((t * 2 * pi * 0.8) + phase * 9.42) * h * 0.10;
 final r = (0.28 + rng.nextDouble() * 0.25) *
 (w > h? h: w) *
 (0.85 + 0.15 * sin(t * 2 * pi + phase * 12.56));

 // От почти чёрного фиолетового к светлому разные клубы
 final shade = rng.nextDouble();
 final Color color;
 if (shade < 0.35) {
 color = const Color(0xFF241436); // тёмный фиолет
 } else if (shade < 0.7) {
 color = const Color(0xFF3A2260); // средний
 } else {
 color = const Color(0xFF5B3A9E); // светлее, акцентный
 }
 final paint = Paint()
..shader = RadialGradient(
 colors: [color.withOpacity(0.55), color.withOpacity(0.0)],
 radius: 1.0,
).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r))
..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
 canvas.drawCircle(Offset(cx, cy), r, paint);
 }
 }

 @override
 bool shouldRepaint(_SmokePainter old) => old.t!= t;
}
