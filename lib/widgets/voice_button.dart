import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

class VoiceButton extends StatefulWidget {
  final bool isListening;
  final bool isSpeaking;
  final double soundLevel;
  final VoidCallback onTap;

  const VoiceButton({
    super.key,
    required this.isListening,
    required this.isSpeaking,
    required this.onTap,
    this.soundLevel = 0.0,
  });

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isListening
        ? AikaTheme.neonPink
        : widget.isSpeaking
            ? AikaTheme.neonPurple
            : AikaTheme.neonBlue;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (_, child) {
          final pulse = widget.isListening
              ? 1.0 + _pulseController.value * 0.2
              : 1.0;
          return Transform.scale(
            scale: pulse,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer pulse ring
                if (widget.isListening)
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                  ),

                // Main button
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        color.withOpacity(0.8),
                        color.withOpacity(0.4),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.6),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.isListening
                        ? Icons.mic
                        : widget.isSpeaking
                            ? Icons.volume_up
                            : Icons.mic_none,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
