import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Виджет аватара через InAppWebView.
/// Только Live2D (.model3.json).
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
  String? _savedCustomPath;
  bool _prefsLoaded = false;

  static const _builtinLive2DPaths = {
    'natori': 'models/Natori/Natori.model3.json',
    'hiyori': 'models/Hiyori/Hiyori.model3.json',
    'haru':   'models/Haru/Haru.model3.json',
    'mao':    'models/Mao/Mao.model3.json',
    'mark':   'models/Mark/Mark.model3.json',
    'rice':   'models/Rice/Rice.model3.json',
    'wanko':  'models/Wanko/Wanko.model3.json',
  };

  @override
  void initState() {
    super.initState();
    _loadSavedModel();
  }

  Future<void> _loadSavedModel() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _modelId         = prefs.getString('live2d_model_id') ?? 'natori';
      _savedCustomPath = prefs.getString('custom_model_path');
      _prefsLoaded     = true;
      _ready           = false;
    });
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

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.purpleAccent),
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
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
          allowContentAccess: true,
        ),
        onWebViewCreated: (ctrl) {
          _ctrl = ctrl;
          _ready = false;
          ctrl.addJavaScriptHandler(
            handlerName: 'FlutterChannel',
            callback: (args) {
              final msg = args.isNotEmpty ? args[0].toString() : '';
              if (msg == 'modelLoaded') {
                if (mounted) setState(() => _ready = true);
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) _sendState(widget.state);
                });
              }
            },
          );
        },
        onLoadStop: (ctrl, url) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) ctrl.evaluateJavascript(source: _buildInitJS());
          });
        },
        onReceivedError: (ctrl, req, err) {
          debugPrint('[Live2DWidget] WebView error: \${err.description}');
        },
      ),
    );
  }
}
