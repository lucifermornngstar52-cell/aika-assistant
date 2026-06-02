import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Entry point для overlay — запускается отдельным Flutter Engine
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _OverlayApp());
}

class _OverlayApp extends StatelessWidget {
  const _OverlayApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: Colors.transparent),
        home: const _AikaOverlayPage(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Маппинг состояний → анимации Live2D
// ─────────────────────────────────────────────────────────────────────────────
const _stateAnimMap = {
  'idle':      'idle',
  'listening': 'listening',
  'thinking':  'thinking',
  'talking':   'talking',
  'greeting':  'greeting',
  'dance':     'dance',
  'happy':     'greeting',
  'sad':       'idle',
  'excited':   'dance',
};

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
  double _size    = 200.0;
  bool   _mirror  = false;

  // Live2D WebView
  InAppWebViewController? _webCtrl;
  bool _webReady = false;
  String _lastSentState = '';

  // Модель
  String _modelId = 'hiyori';
  String? _customModelPath;

  static const _builtinPaths = {
    'natori': 'models/Natori/Natori.model3.json',
    'ren':    'models/Ren/Ren.model3.json',
    'hiyori': 'models/Hiyori/Hiyori.model3.json',
    'haru':   'models/Haru/Haru.model3.json',
  };

  // Pinch scale
  double _baseScale = 1.0;
  double _scale     = 1.0;

  // Idle-грусть таймер: если нет сообщений 30+ сек — sad анимация
  Timer? _idleTimer;
  bool _userInactive = false;

  // Float анимация пузыря
  late AnimationController _floatCtrl;
  late Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNative);
    _loadSavedSettings();
    _startIdleTimer();

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -5, end: 5).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _floatCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _modelId = prefs.getString('live2d_model_id') ?? 'hiyori';
        _size    = prefs.getDouble('overlay_size') ?? 200.0;
        _opacity = prefs.getDouble('overlay_opacity') ?? 1.0;
        final cp = prefs.getString('custom_model_path');
        if (cp != null && File(cp).existsSync()) _customModelPath = cp;
      });
    }
  }

  // ── Idle timer: sad после 30 сек бездействия ──────────────────────────────
  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _state == 'idle') {
        setState(() { _userInactive = true; });
        _sendState('sad');
      }
    });
  }

  void _resetIdleTimer() {
    _userInactive = false;
    _startIdleTimer();
  }

  // ── Нативные вызовы из AikaOverlayService ─────────────────────────────────
  Future<dynamic> _handleNative(MethodCall call) async {
    switch (call.method) {

      case 'setState':
        final s = call.arguments as String? ?? 'idle';
        if (mounted) setState(() => _state = s);
        _sendState(s);
        _resetIdleTimer();
        break;

      case 'setMusicPlaying':
        final playing = call.arguments as bool? ?? false;
        final s = playing ? 'dance' : 'idle';
        if (mounted) setState(() => _state = s);
        _sendState(s);
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
        _onTapped();
        break;

      case 'playAnimation':
        final anim = call.arguments as String? ?? 'idle';
        final mapped = _stateAnimMap[anim] ?? 'idle';
        if (mounted) setState(() => _state = mapped);
        _sendState(mapped);
        _resetIdleTimer();
        break;
    }
  }

  void _onTapped() {
    _resetIdleTimer();
    // Радуется при тапе
    final prev = _state;
    setState(() => _state = 'greeting');
    _sendState('greeting');
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _state == 'greeting') {
        setState(() => _state = prev == 'greeting' ? 'idle' : prev);
        _sendState(_state);
      }
    });
  }

  // ── Live2D JS команды ─────────────────────────────────────────────────────
  void _sendState(String state) {
    if (!_webReady) return;
    if (state == _lastSentState) return;
    _lastSentState = state;
    final anim = _stateAnimMap[state] ?? state;
    _webCtrl?.evaluateJavascript(source: "window.setAikaState('$anim')");
  }

  String _buildSwitchJS() {
    if (_customModelPath != null) {
      return "window.loadCustomModel('file://$_customModelPath');";
    }
    final asset = _builtinPaths[_modelId] ?? _builtinPaths['hiyori']!;
    return "window.switchBuiltinModel('$asset');";
  }

  // ── Pinch gesture ─────────────────────────────────────────────────────────
  void _onScaleStart(ScaleStartDetails d) {
    _baseScale = _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.scale == 1.0) return; // игнорируем одиночный палец
    setState(() {
      _scale = (_baseScale * d.scale).clamp(0.5, 2.5);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: AnimatedBuilder(
          animation: _floatAnim,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, _floatAnim.value),
            child: child,
          ),
          child: Transform.scale(
            scale: _scale,
            child: Opacity(
              opacity: _opacity.clamp(0.0, 1.0),
              child: Transform(
                alignment: Alignment.center,
                transform: _mirror
                    ? (Matrix4.identity()..scale(-1.0, 1.0))
                    : Matrix4.identity(),
                child: _buildLive2DView(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLive2DView() {
    return SizedBox.expand(
      child: InAppWebView(
        initialFile: 'assets/live2d_viewer.html',
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          useHybridComposition: true,
          disableDefaultErrorPage: true,
        ),
        onWebViewCreated: (ctrl) {
          _webCtrl = ctrl;
          ctrl.addJavaScriptHandler(
            handlerName: 'FlutterChannel',
            callback: (args) {
              final msg = args.isNotEmpty ? args[0].toString() : '';
              if (msg == 'tap') {
                _onTapped();
              } else if (msg == 'modelLoaded') {
                Future.delayed(const Duration(milliseconds: 500), () {
                  _sendState(_state);
                });
              }
            },
          );
        },
        onLoadStop: (ctrl, url) {
          setState(() => _webReady = true);
          // Переключаем модель через 1.5 сек после загрузки страницы
          Future.delayed(const Duration(milliseconds: 1500), () {
            ctrl.evaluateJavascript(source: _buildSwitchJS());
          });
        },
        onConsoleMessage: (_, msg) {
          debugPrint('[OverlayWebView] ${msg.message}');
        },
      ),
    );
  }
}
