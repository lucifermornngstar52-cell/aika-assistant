import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

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
        theme: ThemeData(
          scaffoldBackgroundColor: Colors.transparent,
          colorScheme: const ColorScheme.dark(),
        ),
        home: const _AikaOverlayPage(),
      );
}

class _AikaOverlayPage extends StatefulWidget {
  const _AikaOverlayPage();
  @override
  State<_AikaOverlayPage> createState() => _AikaOverlayPageState();
}

class _AikaOverlayPageState extends State<_AikaOverlayPage> {
  static const _channel = MethodChannel('com.aika.assistant/live2d_overlay');

  String _state   = 'idle';
  double _opacity = 1.0;
  double _size    = 200.0;
  bool   _mirror  = false;

  InAppWebViewController? _webCtrl;
  bool _webViewReady = false;

  // Сохранённые настройки модели
  String _modelId = 'hiyori';
  String? _customModelPath;

  static const _builtinPaths = {
    'natori': 'models/Natori/Natori.model3.json',
    'ren':    'models/Ren/Ren.model3.json',
    'hiyori': 'models/Hiyori/Hiyori.model3.json',
    'haru':   'models/Haru/Haru.model3.json',
  };

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNative);
    _loadSavedModel();
  }

  Future<void> _loadSavedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final modelId = prefs.getString('live2d_model_id') ?? 'hiyori';
    final customPath = prefs.getString('custom_model_path');
    if (mounted) {
      setState(() {
        _modelId = modelId;
        if (customPath != null && File(customPath).existsSync()) {
          _customModelPath = customPath;
        }
      });
    }
  }

  Future<dynamic> _handleNative(MethodCall call) async {
    switch (call.method) {
      case 'setState':
        final s = call.arguments as String? ?? 'idle';
        if (mounted) setState(() => _state = s);
        _sendState(s);
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
        if (mounted) setState(() => _state = 'greeting');
        _sendState('greeting');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _state = 'idle');
          _sendState('idle');
        });
        break;
      case 'playAnimation':
        final anim = call.arguments as String? ?? 'idle';
        final mapped = _animToState(anim);
        if (mounted) setState(() => _state = mapped);
        _sendState(mapped);
        break;
      case 'pickModel':
        await _pickCustomModel();
        break;
    }
  }

  void _sendState(String state) {
    if (_webViewReady) {
      _webCtrl?.evaluateJavascript(source: "window.setAikaState('\$state')");
    }
  }

  String _animToState(String anim) {
    switch (anim) {
      case 'SambaDance': return 'dance';
      case 'agree':      return 'greeting';
      case 'headShake':  return 'thinking';
      default:           return 'idle';
    }
  }

  Future<void> _pickCustomModel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Выбери файл модели (.model3.json)',
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (path.endsWith('model3.json') || path.endsWith('model.json')) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('custom_model_path', path);
          await prefs.setString('live2d_model_id', 'custom');
          setState(() {
            _customModelPath = path;
            _modelId = 'custom';
            _webViewReady = false;
          });
          _webCtrl?.reload();
        }
      }
    } catch (e) {
      debugPrint('FilePicker error: \$e');
    }
  }

  Future<void> _resetModel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_model_path');
    await prefs.setString('live2d_model_id', 'hiyori');
    setState(() {
      _customModelPath = null;
      _modelId = 'hiyori';
      _webViewReady = false;
    });
    _webCtrl?.reload();
  }

  String _buildSwitchJS() {
    if (_customModelPath != null) {
      return "window.loadCustomModel('file://\$_customModelPath');";
    }
    final assetPath = _builtinPaths[_modelId] ?? _builtinPaths['hiyori']!;
    return "window.switchBuiltinModel('\$assetPath');";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 300),
        child: Transform(
          alignment: Alignment.center,
          transform: _mirror
              ? (Matrix4.identity()..scale(-1.0, 1.0))
              : Matrix4.identity(),
          child: _buildLive2D(),
        ),
      ),
    );
  }

  Widget _buildLive2D() {
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
                _channel.invokeMethod('onTap');
              } else if (msg == 'modelLoaded') {
                // Модель загружена — отправляем текущее состояние
                Future.delayed(const Duration(milliseconds: 300), () {
                  _sendState(_state);
                });
              } else if (msg == 'pick_model') {
                _pickCustomModel();
              } else if (msg == 'reset_model') {
                _resetModel();
              }
            },
          );
        },
        onLoadStop: (ctrl, url) {
          setState(() => _webViewReady = true);
          // Переключаем на нужную модель через 1.5 секунды
          // (HTML сначала загрузит Hiyori, потом мы переключим)
          Future.delayed(const Duration(milliseconds: 1500), () {
            final js = _buildSwitchJS();
            ctrl.evaluateJavascript(source: js);
          });
        },
        onConsoleMessage: (ctrl, msg) {
          debugPrint('[Overlay WebView] \${msg.messageLevel.name}: \${msg.message}');
        },
        onLoadError: (ctrl, url, code, message) {
          debugPrint('[Overlay WebView] load error: \$code \$message');
        },
      ),
    );
  }
}
