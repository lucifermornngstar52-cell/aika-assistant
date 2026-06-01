import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Entry point для overlay — запускается отдельным Flutter Engine
/// поверх всех приложений через AikaOverlayService.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _OverlayApp());
}

class _OverlayApp extends StatelessWidget {
  const _OverlayApp();
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _AikaOverlayPage(),
      );
}

class _AikaOverlayPage extends StatefulWidget {
  const _AikaOverlayPage();
  @override
  State<_AikaOverlayPage> createState() => _AikaOverlayPageState();
}

class _AikaOverlayPageState extends State<_AikaOverlayPage>
    with TickerProviderStateMixin {
  static const _channel = MethodChannel('com.aika.assistant/live2d_overlay');

  String _state   = 'idle';
  double _opacity = 1.0;
  double _size    = 170.0;
  bool   _mirror  = false;
  bool   _musicPlaying = false;

  // ── Анимации ──────────────────────────────────────────────────────────────
  late AnimationController _floatCtrl;
  late Animation<double>   _floatAnim;

  late AnimationController _bounceCtrl;
  late Animation<double>   _bounceAnim;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  late AnimationController _shakeCtrl;
  late Animation<double>   _shakeAnim;

  late AnimationController _rotCtrl;
  late Animation<double>   _rotAnim;

  // Спрайты танца
  int _danceFrame = 0;
  Timer? _danceTimer;

  // Маппинг состояний на картинку
  String get _imagePath {
    switch (_state) {
      case 'listening': return 'assets/images/aika_listen.png';
      case 'thinking':  return 'assets/images/aika_think.png';
      case 'greeting':
      case 'talking':   return 'assets/images/aika_wave.png';
      case 'dance':
      case 'music':     return 'assets/images/aika_chibi.png';
      default:          return 'assets/images/aika_chibi.png';
    }
  }

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNative);

    // Плавное покачивание (idle)
    _floatCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -6, end: 6).animate(
        CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));

    // Прыжок
    _bounceCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _bounceAnim = Tween<double>(begin: 0, end: -20).animate(
        CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeOut));

    // Пульс (thinking)
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.93, end: 1.07).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Тряска (listening)
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
    _shakeAnim = Tween<double>(begin: -4, end: 4).animate(
        CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));

    // Вращение (dance)
    _rotCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _rotAnim = Tween<double>(begin: -0.12, end: 0.12).animate(
        CurvedAnimation(parent: _rotCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _bounceCtrl.dispose();
    _pulseCtrl.dispose();
    _shakeCtrl.dispose();
    _rotCtrl.dispose();
    _danceTimer?.cancel();
    super.dispose();
  }

  Future<dynamic> _handleNative(MethodCall call) async {
    switch (call.method) {
      case 'setState':
        final s = call.arguments as String? ?? 'idle';
        _applyState(s);
        break;
      case 'setMusicPlaying':
        final playing = call.arguments as bool? ?? false;
        if (mounted) setState(() => _musicPlaying = playing);
        _applyState(playing ? 'dance' : 'idle');
        break;
      case 'setConfig':
        final args = call.arguments as Map? ?? {};
        if (mounted) setState(() {
          _size    = (args['size']    as num?)?.toDouble() ?? _size;
          _opacity = (args['opacity'] as num?)?.toDouble() ?? _opacity;
          _mirror  = args['mirror']  as bool? ?? _mirror;
        });
        break;
      case 'onTap':
        _bounce();
        _applyState('greeting');
        Future.delayed(const Duration(seconds: 2), () => _applyState('idle'));
        break;
      case 'playAnimation':
        final anim = call.arguments as String? ?? 'idle';
        _applyStateByAnim(anim);
        break;
    }
  }

  void _applyStateByAnim(String anim) {
    switch (anim) {
      case 'SambaDance': _applyState('dance'); break;
      case 'agree':      _applyState('greeting'); break;
      case 'headShake':  _applyState('thinking'); break;
      case 'walk':
      case 'run':        _applyState('idle'); break;
      default:           _applyState('idle');
    }
  }

  void _applyState(String state) {
    _danceTimer?.cancel();
    if (mounted) setState(() => _state = state);

    if (state == 'dance' || state == 'music') {
      _danceTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (mounted) setState(() => _danceFrame = (_danceFrame + 1) % 2);
      });
    }
  }

  void _bounce() {
    _bounceCtrl.forward(from: 0).then((_) => _bounceCtrl.reverse());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 300),
        child: _buildAvatar(),
      ),
    );
  }

  Widget _buildAvatar() {
    Widget img = Image.asset(
      _imagePath,
      width: _size,
      height: _size * 1.4,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _fallbackIcon(),
    );

    // Зеркало
    if (_mirror) {
      img = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(-1.0, 1.0),
        child: img,
      );
    }

    // Анимация по состоянию
    Widget animated;
    switch (_state) {
      case 'thinking':
        animated = AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Transform.scale(scale: _pulseAnim.value, child: child),
          child: img,
        );
        break;
      case 'listening':
        animated = AnimatedBuilder(
          animation: _shakeAnim,
          builder: (_, child) => Transform.translate(
              offset: Offset(_shakeAnim.value, 0), child: child),
          child: img,
        );
        break;
      case 'dance':
      case 'music':
        animated = AnimatedBuilder(
          animation: _rotAnim,
          builder: (_, child) => Transform.rotate(angle: _rotAnim.value, child: child),
          child: img,
        );
        break;
      case 'greeting':
      case 'talking':
        animated = AnimatedBuilder(
          animation: _bounceCtrl,
          builder: (_, child) => Transform.translate(
              offset: Offset(0, _bounceAnim.value), child: child),
          child: img,
        );
        break;
      default: // idle — плавное покачивание
        animated = AnimatedBuilder(
          animation: _floatAnim,
          builder: (_, child) => Transform.translate(
              offset: Offset(0, _floatAnim.value), child: child),
          child: img,
        );
    }

    // Glow вокруг
    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow
        Container(
          width: _size * 0.8,
          height: _size * 0.8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _glowColor().withOpacity(0.25),
                blurRadius: 30,
                spreadRadius: 15,
              ),
            ],
          ),
        ),
        animated,
      ],
    );
  }

  Color _glowColor() {
    switch (_state) {
      case 'listening': return Colors.greenAccent;
      case 'thinking':  return Colors.orangeAccent;
      case 'talking':   return Colors.cyanAccent;
      case 'dance':
      case 'music':     return Colors.pinkAccent;
      default:          return const Color(0xFF00E5FF);
    }
  }

  Widget _fallbackIcon() => Container(
    width: _size, height: _size * 1.4,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFF0D1117),
      border: Border.all(color: const Color(0xFF00E5FF), width: 2),
    ),
    child: const Icon(Icons.face, color: Color(0xFF00E5FF), size: 48),
  );
}
