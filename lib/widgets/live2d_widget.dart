import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Виджет аватара через InAppWebView.
/// Поддерживает Live2D (.model3.json) и 3D GLB модели.
class Live2DWidget extends StatefulWidget {
  final double width;
  final double height;
  final String state;
  final String? builtinModelAsset;
  final String? customModelPath;

  const Live2DWidget({
    Key? key,
    this.width = 220,
    this.height = 320,
    this.state = 'idle',
    this.builtinModelAsset,
    this.customModelPath,
  }) : super(key: key);

  @override
  State<Live2DWidget> createState() => _Live2DWidgetState();
}

class _Live2DWidgetState extends State<Live2DWidget> {
  InAppWebViewController? _ctrl;
  String _lastState = '';
  bool _ready = false;

  String _modelId = 'natori';
  String _mode = 'live2d'; // 'live2d' | '3d'
  String? _savedCustomPath;

  static const _builtinLive2DPaths = {
    'natori': 'models/Natori/Natori.model3.json',
    'ren':    'models/Ren/Ren.model3.json',
    'hiyori': 'models/Hiyori/Hiyori.model3.json',
    'haru':   'models/Haru/Haru.model3.json',
  };

  static const _builtin3DPaths = {
    'anime_girl':  'models/anime_girl.glb',
    'michelle':    'models/michelle.glb',
    'aika_glb':    'models/aika_model.glb',
    'robot_glb':   'models/robot.glb',
    'xbot_glb':    'models/xbot.glb',
    'soldier_glb': 'models/soldier.glb',
  };

  bool get _is3DModel {
    if (_mode == '3d') return true;
    if (_builtin3DPaths.containsKey(_modelId)) return true;
    final asset = widget.builtinModelAsset ?? '';
    return asset.endsWith('.glb');
  }

  @override
  void initState() {
    super.initState();
    _loadSavedModel();
  }

  Future<void> _loadSavedModel() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _modelId = prefs.getString('live2d_model_id') ?? 'natori';
        _mode = prefs.getString('overlay_mode') ?? 'live2d';
        _savedCustomPath = prefs.getString('custom_model_path');
      });
    }
  }

  @override
  void didUpdateWidget(Live2DWidget old) {
    super.didUpdateWidget(old);
    if (widget.state != _lastState && _ready) {
      _sendState(widget.state);
    }
  }

  void _sendState(String state) {
    _lastState = state;
    _ctrl?.evaluateJavascript(source: "window.setAikaState('$state')");
  }

  String _buildInitJS() {
    if (_is3DModel) {
      // 3D режим — switchModel
      final path = widget.builtinModelAsset
          ?? _builtin3DPaths[_modelId]
          ?? _builtin3DPaths['aika_glb']!;
      return "window.switchModel('$path'); window.setAikaState('${widget.state}');";
    } else {
      // Live2D режим
      final customPath = widget.customModelPath
          ?? (_modelId == 'custom' ? _savedCustomPath : null);
      if (customPath != null) {
        return "window.loadCustomModel('file://$customPath');";
      }
      final assetPath = widget.builtinModelAsset
          ?? _builtinLive2DPaths[_modelId]
          ?? _builtinLive2DPaths['natori']!;
      return "window.switchBuiltinModel('$assetPath');";
    }
  }

  String get _htmlFile =>
      _is3DModel ? 'assets/3d_viewer.html' : 'assets/live2d_viewer.html';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: InAppWebView(
        initialFile: _htmlFile,
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
          ctrl.addJavaScriptHandler(
            handlerName: 'FlutterChannel',
            callback: (args) {
              final msg = args.isNotEmpty ? args[0].toString() : '';
              if (msg == 'modelLoaded') {
                setState(() => _ready = true);
                Future.delayed(const Duration(milliseconds: 300), () {
                  _sendState(widget.state);
                });
              }
            },
          );
        },
        onLoadStop: (ctrl, url) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) {
              ctrl.evaluateJavascript(source: _buildInitJS());
            }
          });
        },
        onReceivedError: (ctrl, req, err) {
          debugPrint('[Live2DWidget] WebView error: ${err.description}');
        },
      ),
    );
  }
}
