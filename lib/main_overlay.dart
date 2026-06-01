import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _Live2DOverlayPage(),
      );
}

class _Live2DOverlayPage extends StatefulWidget {
  const _Live2DOverlayPage();
  @override
  State<_Live2DOverlayPage> createState() => _Live2DOverlayPageState();
}

class _Live2DOverlayPageState extends State<_Live2DOverlayPage> {
  static const _ch = MethodChannel('com.aika.assistant/live2d_overlay');

  final _ctrl = Live2DViewController();
  bool   _loaded  = false;
  String _state   = 'idle';
  double _opacity = 1.0;
  bool   _mirror  = false;
  double _speed   = 1.0;
  int    _retries = 0;

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
    _ch.setMethodCallHandler(_handleNative);

    // ⚡ Ждём первого кадра — гарантирует что Live2DView прикреплён к движку
    SchedulerBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), _loadModel);
    });
  }

  Future<void> _loadModel() async {
    if (!mounted) return;
    try {
      final ok = await _ctrl.loadModel(
        modelDir: 'assets/models/Haru/',
        modelFileName: 'Haru.model3.json',
      );
      if (!mounted) return;
      if (ok) {
        if (mounted) setState(() => _loaded = true);
        _ctrl.setMotionSpeed(_speed);
        _applyState(_state);
      } else {
        _scheduleRetry();
      }
    } catch (e) {
      debugPrint('[Live2DOverlay] loadModel error($e), retry $_retries');
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_retries < 4) {
      _retries++;
      Future.delayed(Duration(milliseconds: 1500 * _retries), _loadModel);
    }
  }

  Future<dynamic> _handleNative(MethodCall call) async {
    switch (call.method) {
      case 'setState':
        final s = call.arguments as String? ?? 'idle';
        if (mounted) setState(() => _state = s);
        _applyState(s);
        break;
      case 'onTap':
        if (_loaded) {
          _ctrl.startMotion(group: 'TapBody', priority: 3);
          _ctrl.setExpression(4);
        }
        break;
      case 'setConfig':
        final args = call.arguments as Map?;
        if (args == null) break;
        if (mounted) setState(() {
          _speed   = (args['speed']   as num?)?.toDouble() ?? _speed;
          _mirror  = args['mirror']   as bool? ?? _mirror;
          _opacity = (args['opacity'] as num?)?.toDouble() ?? _opacity;
        });
        if (_loaded) _ctrl.setMotionSpeed(_speed);
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
      backgroundColor: Colors.transparent,
      body: Opacity(
        opacity: _opacity,
        child: Transform(
          alignment: Alignment.center,
          transform: _mirror
              ? (Matrix4.identity()..scale(-1.0, 1.0))
              : Matrix4.identity(),
          child: Live2DView(controller: _ctrl),
        ),
      ),
    );
  }
}
