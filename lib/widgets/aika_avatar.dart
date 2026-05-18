import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum AikaState { idle, listening, thinking, greeting, dance }

class AikaAvatar extends StatefulWidget {
  final AikaState state;
  final double size;

  const AikaAvatar({Key? key, required this.state, this.size = 200}) : super(key: key);

  @override
  State<AikaAvatar> createState() => _AikaAvatarState();
}

class _AikaAvatarState extends State<AikaAvatar> with TickerProviderStateMixin {
  // Float animation
  late AnimationController _floatCtrl;
  late Animation<double> _floatAnim;

  // Dance swing (tilt left/right)
  late AnimationController _danceCtrl;
  late Animation<double> _danceSwing;
  late Animation<double> _danceScale;

  // Pop on state change
  late AnimationController _popCtrl;
  late Animation<double> _popAnim;

  // Dance frame cycling
  int _danceFrame = 0;
  Timer? _danceTimer;

  static const _danceSprites = [
    'assets/images/aika_dance1.png',
    'assets/images/aika_dance2.png',
    'assets/images/aika_dance3.png',
    'assets/images/aika_dance4.png',
  ];

  String get _currentSprite {
    switch (widget.state) {
      case AikaState.idle:      return 'assets/images/aika_idle.png';
      case AikaState.listening: return 'assets/images/aika_listen.png';
      case AikaState.thinking:  return 'assets/images/aika_think.png';
      case AikaState.greeting:  return 'assets/images/aika_wave.png';
      case AikaState.dance:     return _danceSprites[_danceFrame];
    }
  }

  @override
  void initState() {
    super.initState();

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -7, end: 7).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );

    _danceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..repeat(reverse: true);
    _danceSwing = Tween<double>(begin: -20, end: 20).animate(
      CurvedAnimation(parent: _danceCtrl, curve: Curves.easeInOut),
    );
    _danceScale = TweenSequence([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.1), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: 1.1, end: 1.0), weight: 1),
    ]).animate(_danceCtrl);

    _popCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _popAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _popCtrl, curve: Curves.elasticOut),
    );

    if (widget.state == AikaState.dance) _startDanceTimer();
  }

  void _startDanceTimer() {
    _danceTimer?.cancel();
    _danceTimer = Timer.periodic(const Duration(milliseconds: 380), (_) {
      if (mounted && widget.state == AikaState.dance) {
        setState(() => _danceFrame = (_danceFrame + 1) % _danceSprites.length);
      }
    });
  }

  void _stopDanceTimer() {
    _danceTimer?.cancel();
    _danceTimer = null;
    _danceFrame = 0;
  }

  @override
  void didUpdateWidget(AikaAvatar old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _popCtrl.forward(from: 0);
      if (widget.state == AikaState.dance) {
        _startDanceTimer();
      } else {
        _stopDanceTimer();
      }
    }
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _danceCtrl.dispose();
    _popCtrl.dispose();
    _danceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDancing = widget.state == AikaState.dance;

    return SizedBox(
      width: widget.size,
      height: widget.size * 1.35,
      child: AnimatedBuilder(
        animation: Listenable.merge([_floatAnim, _popAnim,
          if (isDancing) _danceSwing]),
        builder: (ctx, child) {
          double rotation = isDancing ? (_danceSwing.value * 3.14159 / 180) : 0;
          double scale = isDancing ? _danceScale.value : _popAnim.value;
          double dy = isDancing ? 0 : _floatAnim.value;

          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(
              scale: scale,
              child: Transform.rotate(
                angle: rotation,
                child: child,
              ),
            ),
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Glow ring
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: widget.size * 1.3,
              height: widget.size * 1.3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: isDancing
                        ? Colors.pinkAccent.withOpacity(0.5)
                        : widget.state == AikaState.listening
                            ? AikaTheme.neonPurple.withOpacity(0.55)
                            : AikaTheme.neonBlue.withOpacity(0.22),
                    blurRadius: isDancing ? 60 :
                        widget.state == AikaState.listening ? 50 : 28,
                    spreadRadius: isDancing ? 16 :
                        widget.state == AikaState.listening ? 12 : 4,
                  ),
                ],
              ),
            ),
            // Sprite
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Image.asset(
                _currentSprite,
                key: ValueKey('${ widget.state}_$_danceFrame'),
                width: widget.size,
                height: widget.size * 1.3,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            // Status badge
            Positioned(
              bottom: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _buildBadge(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge() {
    if (widget.state == AikaState.dance) {
      return Container(
        key: const ValueKey('dance'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.pink.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.pinkAccent.withOpacity(0.8), width: 1.2),
        ),
        child: const Text('🎵 Танцую!',
          style: TextStyle(color: Colors.pinkAccent, fontSize: 11,
              fontWeight: FontWeight.bold)),
      );
    }
    if (widget.state == AikaState.listening || widget.state == AikaState.thinking) {
      final isListen = widget.state == AikaState.listening;
      return Container(
        key: ValueKey(widget.state),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: AikaTheme.surface.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isListen
                ? AikaTheme.neonPurple.withOpacity(0.8)
                : AikaTheme.neonBlue.withOpacity(0.8),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PulsingDot(color: isListen ? AikaTheme.neonPurple : AikaTheme.neonBlue),
            const SizedBox(width: 5),
            Text(
              isListen ? 'Слушаю...' : 'Думаю...',
              style: TextStyle(
                color: isListen ? AikaTheme.neonPurple : AikaTheme.neonBlue,
                fontSize: 10, fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink(key: ValueKey('none'));
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
    child: Container(width: 6, height: 6,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
  );
}
