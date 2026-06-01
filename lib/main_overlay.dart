import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Entry point для оверлея — запускается отдельным Flutter Engine
/// внутри AikaOverlayService (FlutterView поверх всех приложений).
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
  static const _ch = MethodChannel('com.aika.assistant/live2d_overlay');

  String _state = 'idle';
  double _opacity = 1.0;

  // Анимация плавания
  late AnimationController _floatCtrl;
  late Animation<double> _floatAnim;

  // Анимация glow пульсации
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  // Анимация dance покачивания
  late AnimationController _danceCtrl;
  late Animation<double> _danceSwing;

  // Спрайт-анимации
  int _danceFrame = 0;
  int _stretchFrame = 0;
  Timer? _danceTimer;
  Timer? _stretchTimer;

  static const _danceSprites = [
    'assets/images/aika_dance1.png', 'assets/images/aika_dance2.png',
    'assets/images/aika_dance3.png', 'assets/images/aika_dance4.png',
    'assets/images/aika_dance5.png', 'assets/images/aika_dance6.png',
    'assets/images/aika_dance7.png', 'assets/images/aika_dance8.png',
    'assets/images/aika_dance9.png', 'assets/images/aika_dance10.png',
    'assets/images/aika_dance11.png', 'assets/images/aika_dance12.png',
    'assets/images/aika_dance13.png', 'assets/images/aika_dance14.png',
    'assets/images/aika_dance15.png',
  ];

  static const _stretchSprites = [
    'assets/images/aika_stretch1.png', 'assets/images/aika_stretch2.png',
    'assets/images/aika_stretch3.png', 'assets/images/aika_stretch4.png',
    'assets/images/aika_stretch5.png', 'assets/images/aika_stretch6.png',
    'assets/images/aika_stretch7.png', 'assets/images/aika_stretch8.png',
    'assets/images/aika_stretch9.png', 'assets/images/aika_stretch10.png',
    'assets/images/aika_stretch11.png', 'assets/images/aika_stretch12.png',
    'assets/images/aika_stretch13.png', 'assets/images/aika_stretch14.png',
    'assets/images/aika_stretch15.png',
  ];

  String get _currentSprite {
    switch (_state) {
      case 'listening': return 'assets/images/aika_listen.png';
      case 'thinking':  return 'assets/images/aika_think.png';
      case 'greeting':  return 'assets/images/aika_wave.png';
      case 'dance':     return _danceSprites[_danceFrame];
      case 'stretch':   return _stretchSprites[_stretchFrame];
      default:          return 'assets/images/aika_idle.png';
    }
  }

  Color get _glowColor {
    switch (_state) {
      case 'listening': return const Color(0xFF9C27B0);
      case 'thinking':  return const Color(0xFF2196F3);
      case 'greeting':  return const Color(0xFF4CAF50);
      case 'dance':     return const Color(0xFFE91E63);
      case 'stretch':   return const Color(0xFF7B1FA2);
      default:          return const Color(0xFF00B4D8);
    }
  }

  @override
  void initState() {
    super.initState();

    _ch.setMethodCallHandler(_handleNative);

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    _danceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..repeat(reverse: true);
    _danceSwing = Tween<double>(begin: -15, end: 15).animate(
      CurvedAnimation(parent: _danceCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _glowCtrl.dispose();
    _danceCtrl.dispose();
    _danceTimer?.cancel();
    _stretchTimer?.cancel();
    super.dispose();
  }

  void _startDance() {
    _danceTimer?.cancel();
    _danceTimer = Timer.periodic(const Duration(milliseconds: 280), (_) {
      if (mounted && _state == 'dance') {
        setState(() => _danceFrame = (_danceFrame + 1) % _danceSprites.length);
      }
    });
  }

  void _startStretch() {
    _stretchTimer?.cancel();
    _stretchFrame = 0;
    _stretchTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || _state != 'stretch') return;
      setState(() {
        _stretchFrame = (_stretchFrame + 1) % _stretchSprites.length;
      });
    });
  }

  void _stopAnimTimers() {
    _danceTimer?.cancel();
    _stretchTimer?.cancel();
    _danceTimer = null;
    _stretchTimer = null;
    _danceFrame = 0;
    _stretchFrame = 0;
  }

  Future<dynamic> _handleNative(MethodCall call) async {
    switch (call.method) {
      case 'setState':
        final newState = call.arguments as String? ?? 'idle';
        if (!mounted) return;
        _stopAnimTimers();
        setState(() => _state = newState);
        if (newState == 'dance') _startDance();
        if (newState == 'stretch') _startStretch();
        break;
      case 'onTap':
        // Тап по оверлею — пиниг/bounce эффект
        if (mounted) setState(() {});
        break;
      case 'setConfig':
        final args = call.arguments as Map?;
        if (args == null) break;
        if (mounted) setState(() {
          _opacity = (args['opacity'] as num?)?.toDouble() ?? _opacity;
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDancing = _state == 'dance';
    final isListening = _state == 'listening';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Opacity(
        opacity: _opacity,
        child: AnimatedBuilder(
          animation: Listenable.merge([_floatAnim, _glowAnim,
            if (isDancing) _danceSwing]),
          builder: (ctx, child) {
            final dy = isDancing ? 0.0 : _floatAnim.value;
            final rotation = isDancing
                ? (_danceSwing.value * 3.14159 / 180)
                : 0.0;

            return Transform.translate(
              offset: Offset(0, dy),
              child: Transform.rotate(
                angle: rotation,
                child: child,
              ),
            );
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Glow круг
              AnimatedBuilder(
                animation: _glowAnim,
                builder: (_, __) => Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _glowColor.withOpacity(
                            (isListening ? 0.65 : isDancing ? 0.55 : 0.3) *
                                _glowAnim.value),
                        blurRadius: isListening ? 55 : isDancing ? 60 : 30,
                        spreadRadius: isListening ? 14 : isDancing ? 18 : 6,
                      ),
                    ],
                  ),
                ),
              ),

              // Спрайт
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Image.asset(
                  _currentSprite,
                  key: ValueKey('$_state-$_danceFrame-$_stretchFrame'),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),

              // Маленький бейдж статуса внизу
              Positioned(
                bottom: 4,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildBadge(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge() {
    String label = '';
    Color color = _glowColor;
    switch (_state) {
      case 'listening': label = '🎤'; break;
      case 'thinking':  label = '💭'; break;
      case 'dance':     label = '🎵'; break;
      case 'stretch':   label = '🧘'; break;
      default: return const SizedBox.shrink(key: ValueKey('none'));
    }
    return Container(
      key: ValueKey(_state),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.7), width: 1),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}
