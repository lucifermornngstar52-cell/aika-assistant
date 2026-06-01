import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AikaAvatar extends StatefulWidget {
  final bool isThinking;
  final bool isListening;

  const AikaAvatar({
    Key? key,
    this.isThinking = false,
    this.isListening = false,
  }) : super(key: key);

  @override
  State<AikaAvatar> createState() => _AikaAvatarState();
}

class _AikaAvatarState extends State<AikaAvatar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
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
    final color = widget.isListening
        ? AikaTheme.neonBlue
        : widget.isThinking
            ? AikaTheme.neonPurple
            : AikaTheme.neonBlue;

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (_, __) => Container(
        width: 120,
        height: 120,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AikaTheme.surface,
          border: Border.all(color: color.withOpacity(0.6), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(_glowAnimation.value * 0.5),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Icon(
          widget.isListening
              ? Icons.mic
              : widget.isThinking
                  ? Icons.psychology
                  : Icons.auto_awesome,
          color: color,
          size: 48,
        ),
      ),
    );
  }
}
