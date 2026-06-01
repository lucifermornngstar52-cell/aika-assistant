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
        // КРИТИЧНО: прозрачный фон чтобы не было чёрного квадрата
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

  // Путь к текущей модели (null = встроенная Haru)
  String? _customModelPath;
  bool _webViewReady = false;

  static const _readyChannel = MethodChannel('com.aika.assistant/overlay_ready');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNative);
    _loadSavedModel();
  }

  Future<void> _loadSavedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('custom_model_path');
    if (saved != null && File(saved).existsSync()) {
      setState(() => _customModelPath = saved);
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

  // Выбор своей модели через file picker
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
          setState(() {
            _customModelPath = path;
            _webViewReady = false;
          });
          // Перезагружаем WebView с новой моделью
          _webCtrl?.reload();
        }
      }
    } catch (e) {
      debugPrint('FilePicker error: \$e');
    }
  }

  // Сброс к стандартной модели
  Future<void> _resetModel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_model_path');
    setState(() {
      _customModelPath = null;
      _webViewReady = false;
    });
    _webCtrl?.reload();
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
          // Отключаем дефолтный белый/чёрный фон WebView
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
                // Модель загружена — сигналим Kotlin показать оверлей
                _readyChannel.invokeMethod('modelReady').catchError((_) {});
              } else if (msg == 'pick_model') {
                _pickCustomModel();
              } else if (msg == 'reset_model') {
                _resetModel();
              }
            },
          );
          // Передаём путь к кастомной модели если есть
          if (_customModelPath != null) {
            ctrl.addJavaScriptHandler(
              handlerName: 'getCustomModelPath',
              callback: (_) => _customModelPath,
            );
          }
        },
        onLoadStop: (ctrl, url) {
          setState(() => _webViewReady = true);
          // Даём JS время загрузить pixi + live2d + модель
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (_customModelPath != null) {
              ctrl.evaluateJavascript(
                source: "window.loadCustomModel('file://\$_customModelPath')"
              );
            }
          });
          // Оверлей покажется когда JS сообщит 'modelLoaded' через FlutterChannel
        },
        onConsoleMessage: (ctrl, msg) {
          debugPrint('[WebView] \${msg.messageLevel.name}: \${msg.message}');
        },
        onLoadError: (ctrl, url, code, message) {
          debugPrint('[WebView] load error: \$code \$message');
        },
      ),
    );
  }
}
