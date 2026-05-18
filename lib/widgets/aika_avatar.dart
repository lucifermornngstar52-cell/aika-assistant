import 'package:flutter/material.dart';

enum AikaState { idle, listening, thinking, greeting, dance }

class AikaAvatar extends StatefulWidget {
  final AikaState state;
  final double size;

  const AikaAvatar({Key? key, required this.state, this.size = 200}) : super(key: key);

  @override
  State<AikaAvatar> createState() => _AikaAvatarState();
}

class _AikaAvatarState extends State<AikaAvatar> with TickerProviderStateMixin {
  // Контроллер для float (idle/listen/think)
  late AnimationController _floatCtrl;
  late Animation<double> _floatAnim;

  // Контроллер для dance — быстрый свинг
  late AnimationController _danceCtrl;
  late Animation<double> _danceSwing;
  late Animation<double> _danceScale;

  // Контроллер для pop при смене состояния
  late AnimationController _popCtrl;
  late Animation<double> _popAnim;

  // Текущий фрейм танца (переключается между спрайтами)
  int _danceFrame = 0;

  static const _sprites = {
    AikaState.idle:      'assets/images/aika_idle.png',
    AikaState.listening: 'assets/images/aika_listen.png',
    AikaState.thinking:  'assets/images/aika_think.png',
    AikaState.greeting:  'assets/images/aika_wave.png',
    AikaState.dance:     'assets/images/aika_wave.png', // базовый — меняется через фреймы
  };

  // Для танца чередуем wave / idle / listen спрайты
  static const _danceSprites = [
    'assets/images/aika_wave.png',
    'assets/images/aika_idle.png',
    'assets/images/aika_listen.png',
    'assets/images/aika_wave.png',
  ];

  @override
  void initState() {
    super.initState();

    // Float — медленное покачивание вверх-вниз
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -7, end: 7).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );

    // Dance swing — ритмичный наклон
    _danceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _danceSwing = Tween<double>(begin: -18, end: 18).animate(
      CurvedAnimation(parent: _danceCtrl, curve: Curves.easeInOut),
    );
    _danceScale = TweenSequence([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.08), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: 1.08, end: 1.0), weight: 1),
    ]).animate(_danceCtrl);

    _danceCtrl.addStatusListener((status) {
      if (widget.state == AikaState.dance) {
        if (status == AnimationStatus.completed) {
          _danceCtrl.reverse();
          setState(() => _danceFrame = (_danceFrame + 1) % _danceSprites.length);
        } else if (status == AnimationStatus.dismissed) {
          _danceCtrl.forward();
          setState(() => _danceFrame = (_danceFrame + 1) % _danceSprites.length);
        }
      }
    });

    // Pop — при смене состояния
    _popCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _popAnim = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _popCtrl, curve: Curves.elasticOut),
    );

    _updateAnimations();
  }

  @override
  void didUpdateWidget(AikaAvatar old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _popCtrl.forward(from: 0);
      _updateAnimations();
    }
  }

  void _updateAnimations() {
    if (widget.state == AikaState.dance) {
      _floatCtrl.stop();
      _danceFrame = 0;
      _danceCtrl.forward(from: 0);
    } else {
      _danceCtrl.stop();
      _floatCtrl.repeat(reverse: true);
    }
  }

  String get _currentSprite {
    if (widget.state == AikaState.dance) {
      return _danceSprites[_danceFrame];
    }
    return _sprites[widget.state] ?? _sprites[AikaState.idle]!;
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _danceCtrl.dispose();
    _popCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDance = widget.state == AikaState.dance;

    return ScaleTransition(
      scale: _popAnim,
      child: AnimatedBuilder(
        animation: Listenable.merge([_floatCtrl, _danceCtrl]),
        builder: (context, child) {
          final translateY = isDance ? 0.0 : _floatAnim.value;
          final rotate = isDance ? _danceSwing.value * 3.14159 / 180 : 0.0;
          final scale = isDance ? _danceScale.value : 1.0;

          return Transform.translate(
            offset: Offset(0, translateY),
            child: Transform.rotate(
              angle: rotate,
              child: Transform.scale(
                scale: scale,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Image.asset(
                    _currentSprite,
                    key: ValueKey(_currentSprite + widget.state.name),
                    width: widget.size,
                    height: widget.size,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
