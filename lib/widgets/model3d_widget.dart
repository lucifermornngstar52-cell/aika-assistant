import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 3D-виджет аватара через InAppWebView + Three.js.
/// Загружает GLB модели с анимациями.
/// Копирует GLB во временный файл и грузит через file:// URL.
class Model3DWidget extends StatefulWidget {
  final double width;
  final double height;
  final String state; // idle, talking, dance, thinking, etc.
  final String? modelAsset;

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

  /// Копирует GLB asset во временный файл и грузит через file:// URL.
  /// Это обходит ограничения fetch() на android_asset:// scheme.
  Future<void> _loadModelFromFile(InAppWebViewController ctrl) async {
    final assetPath = widget.modelAsset ??
        _builtin3DPaths[_modelId] ??
        _builtin3DPaths['tsumire']!;

    try {
      // Copy asset to temp file
      final byteData = await rootBundle.load('assets/$assetPath');
      final bytes = byteData.buffer.asUint8List();

      // Get temp directory
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/aika_model.glb';
      final file = File(tempPath);
      await file.writeAsBytes(bytes);
      debugPrint('[Model3DWidget] Copied ${bytes.length} bytes to $tempPath');

      // Load via file:// URL - this works with fetch() on real filesystem
      final fileUrl = 'file://$tempPath';
      await ctrl.evaluateJavascript(
          source: "window.model3D && window.model3D.loadModel('$fileUrl');");
    } catch (e) {
      debugPrint('[Model3DWidget] Error: $e');
      // Fallback: try direct asset path
      final assetPath2 = widget.modelAsset ??
          _builtin3DPaths[_modelId] ??
          _builtin3DPaths['tsumire']!;
      await ctrl.evaluateJavascript(
          source: "window.model3D && window.model3D.loadModel('$assetPath2');");
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
                if (mounted) _loadModelFromFile(ctrl);
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
