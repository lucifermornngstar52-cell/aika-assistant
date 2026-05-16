import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../theme/app_theme.dart';

class AikaAvatar extends StatefulWidget {
  final bool isThinking;
  final bool isListening;
  final bool use3DModel;

  const AikaAvatar({
    Key? key,
    this.isThinking = false,
    this.isListening = false,
    this.use3DModel = true,
  }) : super(key: key);

  @override
  State<AikaAvatar> createState() => _AikaAvatarState();
}

class _AikaAvatarState extends State<AikaAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;
  bool _modelLoadError = false;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _floatAnimation = Tween<double>(begin: -6.0, end: 6.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: widget.use3DModel && !_modelLoadError
          ? _build3DModel()
          : _buildFallback(),
    );
  }

  Widget _build3DModel() {
    return AnimatedBuilder(
      animation: _floatAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatAnimation.value),
          child: child,
        );
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow ring
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.isListening
                      ? AikaTheme.neonPurple.withOpacity(0.6)
                      : widget.isThinking
                          ? AikaTheme.neonBlue.withOpacity(0.4)
                          : AikaTheme.neonBlue.withOpacity(0.2),
                  blurRadius: widget.isListening ? 50 : 30,
                  spreadRadius: widget.isListening ? 12 : 5,
                ),
              ],
            ),
          ),
          // 3D model container — FIXED: correct asset path, dark bg for transparency
          ClipOval(
            child: Container(
              width: 185,
              height: 185,
              color: Colors.black, // fixes transparent bg rendering
              child: ModelViewer(
                // FIXED: removed '#' prefix — correct Flutter asset path
                src: 'assets/models/aika_model.glb',
                alt: 'Aika 3D Model',
                autoRotate: !widget.isListening && !widget.isThinking,
                autoRotateDelay: 1000,
                cameraControls: false,
                disableZoom: true,
                // FIXED: use solid dark color instead of transparent
                backgroundColor: const Color(0xFF0A0A1A),
                // Auto-play idle animation
                animationName: widget.isListening
                    ? 'listening'
                    : widget.isThinking
                        ? 'thinking'
                        : 'idle',
              ),
            ),
          ),
          // Status label
          Positioned(
            bottom: 10,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: (widget.isListening || widget.isThinking)
                  ? Container(
                      key: ValueKey(widget.isListening),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: AikaTheme.surface.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: widget.isListening
                              ? AikaTheme.neonPurple.withOpacity(0.8)
                              : AikaTheme.neonBlue.withOpacity(0.8),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PulsingDot(
                            color: widget.isListening
                                ? AikaTheme.neonPurple
                                : AikaTheme.neonBlue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.isListening ? 'Слушаю...' : 'Думаю...',
                            style: TextStyle(
                              color: widget.isListening
                                  ? AikaTheme.neonPurple
                                  : AikaTheme.neonBlue,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallback() {
    return AnimatedBuilder(
      animation: _floatAnimation,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _floatAnimation.value),
        child: child,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  widget.isListening
                      ? AikaTheme.neonPurple.withOpacity(0.35)
                      : AikaTheme.neonBlue.withOpacity(0.25),
                  Colors.transparent,
                ],
              ),
              border: Border.all(
                color: widget.isListening
                    ? AikaTheme.neonPurple
                    : AikaTheme.neonBlue,
                width: 2,
              ),
            ),
            child: Icon(
              widget.isListening
                  ? Icons.mic
                  : widget.isThinking
                      ? Icons.psychology
                      : Icons.face_retouching_natural,
              size: 64,
              color: widget.isListening
                  ? AikaTheme.neonPurple
                  : AikaTheme.neonBlue,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny pulsing dot for status indicator
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
