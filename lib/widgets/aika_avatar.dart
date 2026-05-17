import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum AikaState { idle, greeting, listening, thinking }

class AikaAvatar extends StatefulWidget {
  final bool isThinking;
  final bool isListening;
  final bool use3DModel; // kept for API compat, ignored

  const AikaAvatar({
    Key? key,
    this.isThinking = false,
    this.isListening = false,
    this.use3DModel = true,
  }) : super(key: key);

  @override
  State<AikaAvatar> createState() => _AikaAvatarState();
}

class _AikaAvatarState extends State<AikaAvatar> with TickerProviderStateMixin {
  // Float animation (idle bounce)
  late AnimationController _floatCtrl;
  late Animation<double> _floatAnim;

  // Greeting wave animation (arm up/down)
  late AnimationController _waveCtrl;
  late Animation<double> _waveAnim;

  // State switch animation (crossfade)
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // Scale bounce when state changes
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;

  AikaState _currentState = AikaState.idle;
  bool _showGreeting = true; // play greeting on first load

  @override
  void initState() {
    super.initState();

    _floatCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -7, end: 7).animate(
        CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));

    _waveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _waveAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _waveCtrl, curve: Curves.easeInOut));

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(_fadeCtrl);

    _scaleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
        CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut));

    // Play greeting animation on startup
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _playGreeting();
    });
  }

  Future<void> _playGreeting() async {
    setState(() => _currentState = AikaState.greeting);
    _scaleCtrl.forward(from: 0);
    // Wave for 2.5 seconds
    for (int i = 0; i < 4; i++) {
      await _waveCtrl.forward();
      await _waveCtrl.reverse();
    }
    if (mounted) setState(() => _currentState = AikaState.idle);
  }

  void _switchState(AikaState next) {
    if (_currentState == next) return;
    _fadeCtrl.forward(from: 0);
    _scaleCtrl.forward(from: 0);
    setState(() => _currentState = next);
  }

  @override
  void didUpdateWidget(AikaAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !oldWidget.isListening) {
      _switchState(AikaState.listening);
    } else if (widget.isThinking && !oldWidget.isThinking) {
      _switchState(AikaState.thinking);
    } else if (!widget.isListening && !widget.isThinking &&
        (oldWidget.isListening || oldWidget.isThinking)) {
      _switchState(AikaState.idle);
    }
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _waveCtrl.dispose();
    _fadeCtrl.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  String get _currentImage {
    switch (_currentState) {
      case AikaState.greeting:
        return 'assets/images/aika_wave.png';
      case AikaState.listening:
        return 'assets/images/aika_listen.png';
      case AikaState.thinking:
        return 'assets/images/aika_think.png';
      case AikaState.idle:
      default:
        return 'assets/images/aika_idle.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: AnimatedBuilder(
        animation: Listenable.merge([_floatAnim, _scaleAnim]),
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _floatAnim.value),
            child: Transform.scale(
              scale: _scaleAnim.value,
              child: child,
            ),
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
                    color: _currentState == AikaState.listening
                        ? AikaTheme.neonPurple.withOpacity(0.6)
                        : _currentState == AikaState.thinking
                            ? AikaTheme.neonBlue.withOpacity(0.45)
                            : AikaTheme.neonBlue.withOpacity(0.22),
                    blurRadius: _currentState == AikaState.listening ? 55 : 32,
                    spreadRadius: _currentState == AikaState.listening ? 14 : 6,
                  ),
                ],
              ),
            ),

            // Chibi sprite — crossfade between states
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Image.asset(
                _currentImage,
                key: ValueKey(_currentState),
                height: 195,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),

            // Status label
            Positioned(
              bottom: 6,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: (_currentState == AikaState.listening ||
                        _currentState == AikaState.thinking)
                    ? Container(
                        key: ValueKey(_currentState),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: AikaTheme.surface.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _currentState == AikaState.listening
                                ? AikaTheme.neonPurple.withOpacity(0.8)
                                : AikaTheme.neonBlue.withOpacity(0.8),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PulsingDot(
                              color: _currentState == AikaState.listening
                                  ? AikaTheme.neonPurple
                                  : AikaTheme.neonBlue,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _currentState == AikaState.listening
                                  ? 'Слушаю...'
                                  : 'Думаю...',
                              style: TextStyle(
                                color: _currentState == AikaState.listening
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
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      width: 7, height: 7,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
}
