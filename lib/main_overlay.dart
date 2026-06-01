import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

/// Entry point для 3D overlay — запускается отдельным Flutter Engine
/// внутри AikaOverlayService (FlutterView поверх всех приложений).
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _OverlayApp());
}

class _OverlayApp extends StatelessWidget {
  const _OverlayApp();
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _AikaOverlayPage(),
    );
  }
}

class _AikaOverlayPage extends StatefulWidget {
  const _AikaOverlayPage();
  @override
  State<_AikaOverlayPage> createState() => _AikaOverlayPageState();
}

class _AikaOverlayPageState extends State<_AikaOverlayPage>
    with TickerProviderStateMixin {
  static const _channel = MethodChannel('com.aika.assistant/overlay_flutter');

  String _state = 'idle';
  double _opacity = 1.0;

  // Glow animation
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  // Bounce animation for listening/thinking
  late AnimationController _bounceCtrl;
  late Animation<double> _bounceAnim;

  // Анимации модели по состоянию
  static const _animMap = {
    'idle':      'TPose',
    'listening': 'SambaDance',   // лёгкое движение
    'thinking':  'TPose',
    'talking':   'SambaDance',
    'greeting':  'SambaDance',
    'dance':     'SambaDance',
    'stretch':   'TPose',
  };

  // Цвет glow по состоянию
  Color get _glowColor {
    switch (_state) {
      case 'listening': return const Color(0xFF9C27B0);
      case 'thinking':  return const Color(0xFF00BCD4);
      case 'talking':   return const Color(0xFF4CAF50);
      case 'greeting':  return const Color(0xFFFF9800);
      case 'dance':     return const Color(0xFFE91E63);
      case 'stretch':   return const Color(0xFF673AB7);
      default:          return const Color(0xFF2196F3);
    }
  }

  @override
  void initState() {
    super.initState();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.25, end: 0.75)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _bounceAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _bounceCtrl, curve: Curves.elasticInOut));

    _channel.setMethodCallHandler(_handleNative);
  }

  Future<dynamic> _handleNative(MethodCall call) async {
    switch (call.method) {
      case 'setState':
        final s = call.arguments as String? ?? 'idle';
        if (mounted) setState(() => _state = s);
        break;
      case 'setConfig':
        final args = call.arguments as Map?;
        if (args == null) break;
        final newOpacity = (args['opacity'] as num?)?.toDouble() ?? _opacity;
        if (mounted) setState(() => _opacity = newOpacity);
        break;
      case 'onTap':
        if (mounted) setState(() => _state = 'greeting');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _state = 'idle');
        });
        break;
    }
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _bounceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animName = _animMap[_state] ?? 'TPose';
    final isActive = _state != 'idle' && _state != 'thinking';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Opacity(
        opacity: _opacity,
        child: AnimatedBuilder(
          animation: _glowAnim,
          builder: (_, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // Glow ring
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _glowColor.withOpacity(_glowAnim.value * 0.6),
                        blurRadius: isActive ? 32 : 16,
                        spreadRadius: isActive ? 8 : 2,
                      ),
                    ],
                  ),
                ),
                // 3D Model
                child!,
                // State label
                Positioned(
                  bottom: 4,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      key: ValueKey(_state),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _glowColor.withOpacity(0.5), width: 1),
                      ),
                      child: Text(
                        _stateLabel(_state),
                        style: TextStyle(
                            color: _glowColor, fontSize: 9, letterSpacing: 0.4),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          child: ModelViewer(
            src: 'assets/models/aika_model.glb',
            alt: 'Aika',
            autoPlay: true,
            autoRotate: false,
            cameraControls: false,
            disableZoom: true,
            backgroundColor: const Color(0x00000000),
            animationName: animName,
          ),
        ),
      ),
    );
  }

  String _stateLabel(String state) {
    switch (state) {
      case 'idle':      return 'Aika 💤';
      case 'listening': return 'Слушаю... 👂';
      case 'thinking':  return 'Думаю... 🤔';
      case 'talking':   return 'Говорю 💬';
      case 'greeting':  return 'Привет! 👋';
      case 'dance':     return 'Танцую 💃';
      case 'stretch':   return 'Растяжка 🧘';
      default:          return 'Aika';
    }
  }
}
