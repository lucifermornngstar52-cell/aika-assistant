import 'dart:async';
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

class _SmokeBackgroundState extends State<SmokeBackground> {
 // PERF: раньше AnimationController.repeat() гнал 60 fps за КАЖДЫМ экраном,
 // и каждый кадр рисовал 6 полноэкранных кругов с MaskFilter.blur(60) —
 // GPU молотил вечно. Дым дрейфует медленно: 4 fps глазом неотличимо,
 // GPU-нагрузка падает в ~15 раз.
 static const _stepMs = 250;
 Timer? _tick;
 double _t = 0.0;

 @override
 void initState() {
 super.initState();
 _tick = Timer.periodic(const Duration(milliseconds: _stepMs), (_) {
 if (!mounted) return;
 setState(() => _t = (_t + _stepMs / 30000) % 1.0);
 });
 }

 @override
 void dispose() {
 _tick?.cancel();
 super.dispose();
 }

 @override
 Widget build(BuildContext context) {
 return RepaintBoundary(
 child: Stack(
 fit: StackFit.passthrough,
 children: [
 Positioned.fill(
 child: CustomPaint(
 painter: _SmokePainter(_t),
 child: const SizedBox.expand(),
),
),
 widget.child,
 ],
),
);
 }
}


// Параметры клубов дыма — детерминированные (раньше Random(7) на каждый кадр).
const _kPhase = [0.729, 0.838, 0.141, 0.946, 0.276, 0.040];
const _kBaseX = [0.201, 0.830, 0.538, 0.621, 0.419, 0.746];
const _kBaseY = [0.177, 0.536, 0.601, 0.281, 0.837, 0.811];
const _kSize = [0.385, 0.213, 0.492, 0.726, 0.885, 0.915];
const _kShade = [0.126, 0.566, 0.397, 0.257, 0.595, 0.770];

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
 // Параметры клубов захардкожены (было: Random(7) на каждый кадр)
 for (var i = 0; i < 6; i++) {
 final phase = _kPhase[i];
 final cx = (0.15 + _kBaseX[i] * 0.7) * w +
 sin((t * 2 * pi) + phase * 6.28) * w * 0.12;
 final cy = (0.1 + _kBaseY[i] * 0.8) * h +
 cos((t * 2 * pi * 0.8) + phase * 9.42) * h * 0.10;
 final r = (0.28 + _kSize[i] * 0.25) *
 (w > h? h: w) *
 (0.85 + 0.15 * sin(t * 2 * pi + phase * 12.56));

 // От почти чёрного фиолетового к светлому разные клубы
 final shade = _kShade[i];
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
