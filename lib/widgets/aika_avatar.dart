import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';

class AikaAvatar extends StatefulWidget {
  final AikaEmotion emotion;
  final bool isListening;
  final bool isSpeaking;
  final double soundLevel;

  const AikaAvatar({
    super.key,
    this.emotion = AikaEmotion.idle,
    this.isListening = false,
    this.isSpeaking = false,
    this.soundLevel = 0.0,
  });

  @override
  State<AikaAvatar> createState() => _AikaAvatarState();
}

class _AikaAvatarState extends State<AikaAvatar>
    with TickerProviderStateMixin {
  late AnimationController _blinkController;
  late AnimationController _floatController;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Blink every 3-5 seconds
    _scheduleBlink();
  }

  void _scheduleBlink() async {
    await Future.delayed(Duration(seconds: 3 + (DateTime.now().millisecond % 3)));
    if (mounted) {
      _blinkController.forward().then((_) => _blinkController.reverse());
      _scheduleBlink();
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _floatController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Color get _emotionColor {
    switch (widget.emotion) {
      case AikaEmotion.happy:
        return AikaTheme.neonPurple;
      case AikaEmotion.thinking:
        return Colors.orange;
      case AikaEmotion.surprised:
        return AikaTheme.neonPink;
      case AikaEmotion.listening:
        return AikaTheme.neonBlue;
      default:
        return AikaTheme.neonBlue;
    }
  }

  String get _emotionEmoji {
    switch (widget.emotion) {
      case AikaEmotion.happy:
        return '😊';
      case AikaEmotion.thinking:
        return '🤔';
      case AikaEmotion.surprised:
        return '😲';
      case AikaEmotion.listening:
        return '👂';
      case AikaEmotion.talking:
        return '💬';
      default:
        return '✨';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_floatController, _glowController]),
      builder: (context, child) {
        final floatOffset = _floatController.value * 8 - 4;
        final glowIntensity = 0.4 + _glowController.value * 0.6;
        final listenScale = widget.isListening
            ? 1.0 + (widget.soundLevel.abs() / 100) * 0.1
            : 1.0;

        return Transform.translate(
          offset: Offset(0, floatOffset),
          child: Transform.scale(
            scale: listenScale,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow ring
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _emotionColor.withOpacity(0.2 * glowIntensity),
                        blurRadius: 60,
                        spreadRadius: 20,
                      ),
                    ],
                  ),
                ),

                // Rotating ring when listening
                if (widget.isListening)
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: CircularProgressIndicator(
                      color: AikaTheme.neonBlue.withOpacity(0.6),
                      strokeWidth: 2,
                    ),
                  ),

                // Main avatar circle
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF1A1F3C),
                        AikaTheme.background,
                      ],
                    ),
                    border: Border.all(
                      color: _emotionColor.withOpacity(0.6 * glowIntensity),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _emotionColor.withOpacity(0.4 * glowIntensity),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Stack(
                      children: [
                        // Avatar image
                        Image.asset(
                          'assets/images/aika_avatar.png',
                          fit: BoxFit.cover,
                          width: 150,
                          height: 150,
                          errorBuilder: (_, __, ___) => _buildFallbackAvatar(),
                        ),

                        // Speaking mouth animation overlay
                        if (widget.isSpeaking)
                          Positioned(
                            bottom: 30,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: _SpeakingWave(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // Emotion indicator
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AikaTheme.background,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _emotionColor.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _emotionEmoji,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFallbackAvatar() {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A2744),
            const Color(0xFF0D1F3C),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Hair
          Container(
            width: 90,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFE8E8F0),
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          // Face
          Container(
            width: 70,
            height: 70,
            margin: const EdgeInsets.only(top: -15),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F5),
              borderRadius: BorderRadius.circular(35),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Eyes
                AnimatedBuilder(
                  animation: _blinkController,
                  builder: (_, __) {
                    final blink = _blinkController.value;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildEye(blink),
                        const SizedBox(width: 16),
                        _buildEye(blink),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                // Mouth
                Container(
                  width: widget.isSpeaking ? 20 : 16,
                  height: widget.isSpeaking ? 8 : 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8FAB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEye(double blink) {
    return Container(
      width: 10,
      height: 10 * (1 - blink),
      decoration: BoxDecoration(
        color: AikaTheme.neonBlue,
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: AikaTheme.neonBlue.withOpacity(0.8),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}

class _SpeakingWave extends StatefulWidget {
  @override
  State<_SpeakingWave> createState() => _SpeakingWaveState();
}

class _SpeakingWaveState extends State<_SpeakingWave>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (i) => Container(
            width: 3,
            height: 4 + (i.isEven ? _ctrl.value : 1 - _ctrl.value) * 8,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: AikaTheme.neonBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
