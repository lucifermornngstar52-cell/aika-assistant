import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 3D-виджет аватара через InAppWebView + Three.js.
/// Загружает GLB модели с анимациями.
/// Использует base64 для передачи GLB — обходит ограничения fetch() на file://
class Model3DWidget extends StatefulWidget {
  final double width;
  final double height;
  final String state; // idle, talking, dance, thinking, etc.
  final String? modelAsset; // e.g. 'models/tsumire.glb'

  const Model3DWidget({
    Key? key,
    this.width = 220,
    this.height = 320,
    this.state = 'idle',
    this.modelAsset,
  }) : super(key: key);

  @override
  State<Model3DWidget> createState() => _Model3DWidgetState();
}

class _Model3DWidgetState extends State<Model3DWidget> {
  InAppWebViewController? _ctrl;
  String _lastState = '';
  bool _ready = false;

  // Встроенные 3D модели
  static const _builtin3DPaths = {
    'tsumire': 'models/tsumire.glb',
    'aika_model': 'models/aika_model.glb',
    'anime_girl': 'models/anime_girl.glb',
    'michelle': 'models/michelle.glb',
    'robot': 'models/robot.glb',
    'soldier': 'models/soldier.glb',
  };

  String _modelId = 'tsumire';
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSavedModel();
  }

  Future<void> _loadSavedModel() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _modelId = prefs.getString('model3d_id') ?? 'tsumire';
      _prefsLoaded = true;
      _ready = false;
    });
  }

  @override
  void didUpdateWidget(Model3DWidget old) {
    super.didUpdateWidget(old);
    if (widget.state != _lastState && _ready) {
      _sendState(widget.state);
    }
  }

  void _sendState(String state) {
    _lastState = state;
    _ctrl?.evaluateJavascript(
        source: "window.model3D && window.model3D.setState('$state')");
  }

  /// Загружает GLB как asset bytes и передаёт в JS через base64 data URL.
  /// Это обходит ограничение fetch() на file:// протоколе в Android WebView.
  Future<void> _loadModelViaBase64(InAppWebViewController ctrl) async {
    final assetPath = widget.modelAsset ??
        _builtin3DPaths[_modelId] ??
        _builtin3DPaths['tsumire']!;

    try {
      final byteData = await rootBundle.load('assets/$assetPath');
      final bytes = byteData.buffer.asUint8List();
      final b64 = base64Encode(bytes);
      final dataUrl = 'data:model/gltf-binary;base64,$b64';
      debugPrint('[Model3DWidget] Loaded ${bytes.length} bytes, sending as data URL');
      await ctrl.evaluateJavascript(
          source: "window.model3D && window.model3D.loadModel('$dataUrl');");
    } catch (e) {
      debugPrint('[Model3DWidget] Asset load error: $e');
      // Fallback: try direct path
      await ctrl.evaluateJavascript(
          source: "window.model3D && window.model3D.loadModel('$assetPath');");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: InAppWebView(
        initialFile: 'assets/model3d_viewer.html',
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          useHybridComposition: true,
          disableDefaultErrorPage: true,
          allowContentAccess: true,
        ),
        onWebViewCreated: (ctrl) {
          _ctrl = ctrl;
          _ready = false;
          ctrl.addJavaScriptHandler(
            handlerName: 'onReady',
            callback: (args) {
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) _loadModelViaBase64(ctrl);
              });
            },
          );
          ctrl.addJavaScriptHandler(
            handlerName: 'onModelLoaded',
            callback: (args) {
              if (mounted) setState(() => _ready = true);
              Future.delayed(const Duration(milliseconds: 200), () {
                if (mounted) _sendState(widget.state);
              });
            },
          );
          ctrl.addJavaScriptHandler(
            handlerName: 'onModelError',
            callback: (args) {
              debugPrint('[Model3DWidget] Load error: $args');
            },
          );
        },
        onReceivedError: (ctrl, req, err) {
          debugPrint('[Model3DWidget] WebView error: ${err.description}');
        },
      ),
    );
  }
}
