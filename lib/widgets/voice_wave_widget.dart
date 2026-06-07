import 'dart:math' as math;
import 'package:flutter/material.dart';

/// VoiceWaveWidget — анимированная звуковая волна в реальном времени.
/// Похожа на Gemini Live / Google Assistant.
/// Показывает 5 полос с разными частотами анимации.
class VoiceWaveWidget extends StatefulWidget {
  final bool isActive;
  final double soundLevel; // -2.0 .. 10.0 (из STT onSoundLevelChange)
  final Color color;
  final double height;
  final int barCount;

  const VoiceWaveWidget({
    super.key,
    required this.isActive,
    this.soundLevel = 0.0,
    this.color = const Color(0xFF7B61FF),
    this.height = 48.0,
    this.barCount = 5,
  });

  @override
  State<VoiceWaveWidget> createState() => _VoiceWaveWidgetState();
}

class _VoiceWaveWidgetState extends State<VoiceWaveWidget>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;
  final _rng = math.Random();

  // Разные скорости для каждой полосы — выглядит органично
  static const _speeds = [700, 500, 900, 600, 800];
  static const _phases = [0.0, 0.3, 0.6, 0.15, 0.45];

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.barCount, (i) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _speeds[i % _speeds.length]),
      )..repeat(reverse: true);
    });

    _animations = List.generate(widget.barCount, (i) {
      return Tween<double>(begin: 0.15, end: 1.0).animate(
        CurvedAnimation(
          parent: _controllers[i],
          curve: Curves.easeInOut,
        ),
      );
    });

    // Запускаем с фазовым сдвигом для органичного вида
    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(
        Duration(milliseconds: ((_phases[i % _phases.length]) * 500).round()),
        () {
          if (mounted) _controllers[i].repeat(reverse: true);
        },
      );
    }
  }

  @override
  void didUpdateWidget(VoiceWaveWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      for (final c in _controllers) {
        if (!c.isAnimating) c.repeat(reverse: true);
      }
    } else if (!widget.isActive && oldWidget.isActive) {
      for (final c in _controllers) {
        c.animateTo(0.15, duration: const Duration(milliseconds: 300));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  double _barHeight(int index, double animValue) {
    if (!widget.isActive) return 0.12;
    // Нормализуем soundLevel: -2..10 → 0..1
    final level = ((widget.soundLevel + 2.0) / 12.0).clamp(0.0, 1.0);
    final base = animValue * (0.4 + level * 0.6);
    // Центральные полосы выше
    final centerBoost = index == widget.barCount ~/ 2 ? 1.3 : 1.0;
    return (base * centerBoost).clamp(0.08, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(widget.barCount, (i) {
          return AnimatedBuilder(
            animation: _animations[i],
            builder: (_, __) {
              final h = _barHeight(i, _animations[i].value);
              return Container(
                width: 4,
                height: widget.height * h,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: widget.isActive
                      ? [
                          BoxShadow(
                            color: widget.color.withOpacity(0.4),
                            blurRadius: 6,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

/// WakeWordIndicator — маленький индикатор фонового прослушивания.
/// Показывается в углу как у Gemini — пульсирующая точка.
class WakeWordIndicator extends StatefulWidget {
  final bool isListening;
  final Color color;

  const WakeWordIndicator({
    super.key,
    required this.isListening,
    this.color = const Color(0xFF7B61FF),
  });

  @override
  State<WakeWordIndicator> createState() => _WakeWordIndicatorState();
}

class _WakeWordIndicatorState extends State<WakeWordIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isListening) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white24,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 16 * _pulse.value,
              height: 16 * _pulse.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withOpacity(0.2 * _pulse.value),
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.5),
                    blurRadius: 4,
                    spreadRadius: 1,
                  )
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
