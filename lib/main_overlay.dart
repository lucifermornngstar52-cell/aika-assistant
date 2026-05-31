import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_live2d/flutter_live2d.dart';

/// Entry point для Live2D overlay — запускается отдельным Flutter Engine
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
      home: _Live2DOverlayPage(),
    );
  }
}

class _Live2DOverlayPage extends StatefulWidget {
  const _Live2DOverlayPage();

  @override
  State<_Live2DOverlayPage> createState() => _Live2DOverlayPageState();
}

class _Live2DOverlayPageState extends State<_Live2DOverlayPage> {
  static const _channel = MethodChannel('com.aika.assistant/live2d_overlay');

  final _ctrl = Live2DViewController();
  bool _loaded = false;
  String _state = 'idle';

  // Маппинг состояний → motion group
  static const _groups = {
    'idle':      'Idle',
    'listening': 'TapBody',
    'thinking':  'Idle',
    'talking':   'TapBody',
    'greeting':  'TapBody',
    'dance':     'TapBody',
  };

  static const _expressions = {
    'idle': 0, 'listening': 1, 'thinking': 2,
    'talking': 0, 'greeting': 3, 'dance': 4,
  };

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNative);
    _ctrl.whenAttached.then((_) => _loadModel());
  }

  Future<void> _loadModel() async {
    final ok = await _ctrl.loadModel(
      modelDir: 'assets/models/Haru/',
      modelFileName: 'Haru.model3.json',
    );
    if (!ok || !mounted) return;
    setState(() => _loaded = true);
    _applyState(_state);
  }

  Future<dynamic> _handleNative(MethodCall call) async {
    switch (call.method) {
      case 'setState':
        final s = call.arguments as String? ?? 'idle';
        setState(() => _state = s);
        _applyState(s);
        break;
      case 'onTap':
        if (_loaded) {
          _ctrl.startMotion(group: 'TapBody', priority: 3);
          _ctrl.setExpression(4);
        }
        break;
    }
  }

  void _applyState(String state) {
    if (!_loaded) return;
    final group = _groups[state] ?? 'Idle';
    final expr  = _expressions[state] ?? 0;
    final prio  = (state == 'greeting' || state == 'dance') ? 3 : 2;
    _ctrl.setExpression(expr);
    _ctrl.startMotion(group: group, priority: prio);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Полностью прозрачный фон — видно приложение под оверлеем
      backgroundColor: Colors.transparent,
      body: _loaded
          ? Live2DView(controller: _ctrl)
          : const SizedBox.shrink(),
    );
  }
}
