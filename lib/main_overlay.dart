import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'dart:async';

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
      home: _ModelOverlayPage(),
    );
  }
}

class _ModelOverlayPage extends StatefulWidget {
  const _ModelOverlayPage();

  @override
  State<_ModelOverlayPage> createState() => _ModelOverlayPageState();
}

class _ModelOverlayPageState extends State<_ModelOverlayPage>
    with SingleTickerProviderStateMixin {
  static const _channel = MethodChannel('com.aika.assistant/live2d_overlay');

  String _state    = 'idle';
  double _opacity  = 1.0;
  double _size     = 170.0; // dp
  bool   _mirror   = false;
  bool   _modelLoaded = false;
  bool   _musicPlaying = false;

  // Имя текущей анимации для model-viewer
  String _currentAnim = 'idle';
  bool   _animAutoPlay = true;

  // Анимация пульса когда думает
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Маппинг состояний → анимации модели
  // Названия должны совпадать с именами анимаций в GLB
  static const _stateToAnim = {
    'idle':      'idle',
    'listening': 'agree',
    'thinking':  'headShake',
    'talking':   'agree',
    'greeting':  'agree',
    'dance':     'SambaDance',
    'walk':      'walk',
    'run':       'run',
    'wave':      'agree',
    'sad':       'sad_pose',
    'music':     'SambaDance',  // включилась музыка → танцует
  };

  // Таймер для возврата в idle
  Timer? _returnTimer;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNative);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _returnTimer?.cancel();
    super.dispose();
  }

  Future<dynamic> _handleNative(MethodCall call) async {
    switch (call.method) {

      // Изменить состояние (idle/listening/thinking/dance/etc.)
      case 'setState':
        final s = call.arguments as String? ?? 'idle';
        _applyState(s);
        break;

      // Музыка включилась/выключилась
      case 'setMusicPlaying':
        final playing = call.arguments as bool? ?? false;
        if (mounted) setState(() => _musicPlaying = playing);
        if (playing) {
          _applyState('music');
        } else if (_state == 'music') {
          _applyState('idle');
        }
        break;

      // Конфиг: размер, прозрачность, зеркало
      case 'setConfig':
        final args = call.arguments as Map? ?? {};
        if (mounted) {
          setState(() {
            _size    = (args['size']    as num?)?.toDouble() ?? _size;
            _opacity = (args['opacity'] as num?)?.toDouble() ?? _opacity;
            _mirror  = args['mirror']  as bool? ?? _mirror;
          });
        }
        break;

      // Тап на модель → реакция
      case 'onTap':
        _applyState('greeting');
        _scheduleReturn(3);
        break;

      // Принудительно установить анимацию по имени
      case 'playAnimation':
        final animName = call.arguments as String? ?? 'idle';
        if (mounted) setState(() => _currentAnim = animName);
        break;

      // Получить список доступных анимаций
      case 'getAnimations':
        return _stateToAnim.keys.toList();
    }
  }

  void _applyState(String state) {
    _returnTimer?.cancel();
    final anim = _stateToAnim[state] ?? 'idle';
    if (mounted) {
      setState(() {
        _state       = state;
        _currentAnim = anim;
      });
    }
  }

  // Через N секунд возвращаемся в idle
  void _scheduleReturn(int seconds) {
    _returnTimer = Timer(Duration(seconds: seconds), () {
      if (mounted && _state != 'idle' && !_musicPlaying) {
        _applyState('idle');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 400),
        child: _buildModel(),
      ),
    );
  }

  Widget _buildModel() {
    // Пульс когда думает
    if (_state == 'thinking') {
      return AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, child) => Transform.scale(
          scale: _pulseAnim.value,
          child: child,
        ),
        child: _modelViewer(),
      );
    }

    return Transform(
      alignment: Alignment.center,
      transform: _mirror
          ? (Matrix4.identity()..scale(-1.0, 1.0))
          : Matrix4.identity(),
      child: _modelViewer(),
    );
  }

  Widget _modelViewer() {
    return ModelViewer(
      src: 'asset://assets/models/aika_model.glb',
      alt: 'Aika 3D Model',
      autoPlay: _animAutoPlay,
      animationName: _currentAnim,
      autoRotate: false,
      cameraControls: false,
      backgroundColor: Colors.transparent,
      // Размер управляется из overlay service через WindowManager
    );
  }
}
