import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Состояния Айки
enum AikaState { idle, listening, thinking, greeting, dance }

class AikaAvatar extends StatefulWidget {
  final AikaState state;
  final double size;

  const AikaAvatar({Key? key, required this.state, this.size = 140}) : super(key: key);

  @override
  State<AikaAvatar> createState() => _AikaAvatarState();
}

class _AikaAvatarState extends State<AikaAvatar> with TickerProviderStateMixin {
  late AnimationController _lottieCtrl;
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;
  AikaState _prevState = AikaState.idle;

  static const _assets = {
    AikaState.idle:      'assets/animations/aika_idle.json',
    AikaState.listening: 'assets/animations/aika_listen.json',
    AikaState.thinking:  'assets/animations/aika_think.json',
    AikaState.greeting:  'assets/animations/aika_wave.json',
    AikaState.dance:     'assets/animations/aika_dance.json',
  };

  @override
  void initState() {
    super.initState();
    _lottieCtrl = AnimationController(vsync: this);

    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut),
    );
  }

  @override
  void didUpdateWidget(AikaAvatar old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _onStateChange(widget.state);
    }
  }

  void _onStateChange(AikaState next) {
    // pop scale effect on state change
    _scaleAnim = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut),
    );
    _scaleCtrl.forward(from: 0);
    _prevState = next;
    setState(() {});
  }

  String get _currentAsset => _assets[widget.state]!;

  @override
  void dispose() {
    _lottieCtrl.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(anim), child: child),
        ),
        child: Lottie.asset(
          _currentAsset,
          key: ValueKey(widget.state),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          controller: _lottieCtrl,
          onLoaded: (comp) {
            _lottieCtrl
              ..duration = comp.duration
              ..repeat();
          },
        ),
      ),
    );
  }
}
