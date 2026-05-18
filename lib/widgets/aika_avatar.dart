import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum AikaState { idle, greeting, listening, thinking }

class AikaAvatar extends StatefulWidget {
  final bool isThinking;
  final bool isListening;
  final bool draggable;

  const AikaAvatar({
    Key? key,
    this.isThinking = false,
    this.isListening = false,
    this.draggable = false,
  }) : super(key: key);

  @override
  State<AikaAvatar> createState() => _AikaAvatarState();
}

class _AikaAvatarState extends State<AikaAvatar> with TickerProviderStateMixin {
  late AnimationController _floatCtrl;
  late Animation<double> _floatAnim;
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;
  late AnimationController _waveCtrl;

  // Моргание
  late AnimationController _blinkCtrl;
  late Animation<double> _blinkAnim;
  bool _isBlinking = false;

  AikaState _currentState = AikaState.idle;

  double _x = 20;
  double _y = 120;
  static const double _size = 110.0;

  final _random = Random();

  @override
  void initState() {
    super.initState();

    _floatCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -7, end: 7).animate(
        CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));

    _scaleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
        CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut));

    _waveCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));

    // Контроллер моргания — быстрое закрытие/открытие
    _blinkCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _blinkAnim = Tween<double>(begin: 1.0, end: 0.04)
        .animate(CurvedAnimation(parent: _blinkCtrl, curve: Curves.easeIn));

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _playGreeting();
    });

    // Запускаем цикл моргания
    _scheduleBlink();
  }

  /// Рандомное моргание каждые 3–6 секунд (только в idle)
  void _scheduleBlink() {
    final delay = 3000 + _random.nextInt(3000); // 3–6 сек
    Future.delayed(Duration(milliseconds: delay), () {
      if (!mounted) return;
      if (_currentState == AikaState.idle) {
        _doBlink();
      }
      _scheduleBlink();
    });
  }

  Future<void> _doBlink() async {
    if (_isBlinking || !mounted) return;
    _isBlinking = true;
    // Закрыть
    await _blinkCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 40));
    // Открыть
    await _blinkCtrl.reverse();
    // Иногда двойное моргание
    if (_random.nextDouble() < 0.25) {
      await Future.delayed(const Duration(milliseconds: 80));
      await _blinkCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 40));
      await _blinkCtrl.reverse();
    }
    _isBlinking = false;
  }

  Future<void> _playGreeting() async {
    setState(() => _currentState = AikaState.greeting);
    _scaleCtrl.forward(from: 0);
    for (int i = 0; i < 4; i++) {
      await _waveCtrl.forward();
      await _waveCtrl.reverse();
    }
    if (mounted) setState(() => _currentState = AikaState.idle);
  }

  @override
  void didUpdateWidget(AikaAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !oldWidget.isListening) {
      _switchState(AikaState.listening);
    } else if (widget.isThinking && !oldWidget.isThinking) {
      _switchState(AikaState.thinking);
    } else if (!widget.isListening &&
        !widget.isThinking &&
        (oldWidget.isListening || oldWidget.isThinking)) {
      _switchState(AikaState.idle);
    }
  }

  void _switchState(AikaState next) {
    if (_currentState == next) return;
    _scaleCtrl.forward(from: 0);
    setState(() => _currentState = next);
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _scaleCtrl.dispose();
    _waveCtrl.dispose();
    _blinkCtrl.dispose();
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
      default:
        return 'assets/images/aika_idle.png';
    }
  }

  Widget _buildSprite() {
    return AnimatedBuilder(
      animation: Listenable.merge([_floatAnim, _scaleAnim]),
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _floatAnim.value),
        child: Transform.scale(scale: _scaleAnim.value, child: child),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: _size * 1.5,
            height: _size * 1.5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _currentState == AikaState.listening
                      ? AikaTheme.neonPurple.withOpacity(0.55)
                      : AikaTheme.neonBlue.withOpacity(0.25),
                  blurRadius: _currentState == AikaState.listening ? 50 : 28,
                  spreadRadius: _currentState == AikaState.listening ? 12 : 4,
                ),
              ],
            ),
          ),
          // Sprite + blink overlay
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Stack(
              key: ValueKey(_currentState),
              alignment: Alignment.center,
              children: [
                // Основной спрайт
                Image.asset(
                  _currentImage,
                  width: _size,
                  height: _size * 1.4,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
                // Моргание — только в idle, тонкая чёрная полоска поверх глаз
                if (_currentState == AikaState.idle)
                  AnimatedBuilder(
                    animation: _blinkAnim,
                    builder: (_, __) => Positioned(
                      top: _size * 0.28, // примерно уровень глаз
                      child: Transform.scale(
                        scaleY: 1.0 - _blinkAnim.value, // 0 = глаза открыты, 1 = закрыты
                        alignment: Alignment.center,
                        child: Container(
                          width: _size * 0.55,
                          height: _size * 0.18,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1a0a2e), // цвет кожи/фона под глазами
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Status badge
          Positioned(
            bottom: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: (_currentState == AikaState.listening ||
                      _currentState == AikaState.thinking)
                  ? Container(
                      key: ValueKey(_currentState),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AikaTheme.surface.withOpacity(0.9),
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
                          const SizedBox(width: 5),
                          Text(
                            _currentState == AikaState.listening
                                ? 'Слушаю...'
                                : 'Думаю...',
                            style: TextStyle(
                              color: _currentState == AikaState.listening
                                  ? AikaTheme.neonPurple
                                  : AikaTheme.neonBlue,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
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

  @override
  Widget build(BuildContext context) {
    if (!widget.draggable) {
      return SizedBox(height: 240, child: _buildSprite());
    }
    return Positioned(
      left: _x,
      top: _y,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _x += d.delta.dx;
            _y += d.delta.dy;
            final s = MediaQuery.of(context).size;
            _x = _x.clamp(0.0, s.width - _size);
            _y = _y.clamp(0.0, s.height - _size * 1.6);
          });
        },
        onPanEnd: (_) => _scaleCtrl.forward(from: 0),
        child: _buildSprite(),
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

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _anim,
        child: Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: widget.color, shape: BoxShape.circle)),
      );
}
