import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 3D GLB модель через InAppWebView + Three.js (локальный bundle).
/// Используем assets/3d_viewer.html с локальными three.module.min.js + GLTFLoader.js
class Aika3DAvatar extends StatefulWidget {
  final String? state;
  final double width;
  final double height;

  const Aika3DAvatar({
    Key? key,
    this.state,
    this.width = double.infinity,
    this.height = 300,
  }) : super(key: key);

  @override
  State<Aika3DAvatar> createState() => _Aika3DAvatarState();
}

class _Aika3DAvatarState extends State<Aika3DAvatar> {
  InAppWebViewController? _webCtrl;
  bool _loaded = false;
  String _modelId = 'anime_girl';

  static const _modelPaths = {
    'anime_girl': 'models/anime_girl.glb',
    'aika_glb':   'models/aika_model.glb',
    'xbot_glb':   'models/xbot.glb',
  };

  String get _glbPath => _modelPaths[_modelId] ?? 'models/anime_girl.glb';

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('model_3d_id') ?? 'anime_girl';
    if (_modelPaths.containsKey(saved) && mounted) {
      setState(() => _modelId = saved);
    }
  }

  @override
  void didUpdateWidget(Aika3DAvatar old) {
    super.didUpdateWidget(old);
    if (_loaded && widget.state != old.state) {
      _sendState(widget.state ?? 'idle');
    }
  }

  void _sendState(String state) {
    _webCtrl?.evaluateJavascript(source: "window.setAikaState('$state')");
  }

  void _switchModel(String glbPath) {
    _webCtrl?.evaluateJavascript(source: "window.switchModel('./$glbPath')");
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: InAppWebView(
          initialFile: 'assets/3d_viewer.html',
          initialSettings: InAppWebViewSettings(
            transparentBackground: true,
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            useShouldOverrideUrlLoading: false,
            disableHorizontalScroll: true,
            disableVerticalScroll: true,
          ),
          onWebViewCreated: (ctrl) {
            _webCtrl = ctrl;
            ctrl.addJavaScriptHandler(
              handlerName: 'FlutterChannel',
              callback: (args) {
                final msg = args.isNotEmpty ? args[0].toString() : '';
                if (msg == 'modelLoaded' && mounted) {
                  setState(() => _loaded = true);
                  _sendState(widget.state ?? 'idle');
                  // Загружаем нужную модель если не дефолтная
                  if (_glbPath != 'models/anime_girl.glb') {
                    _switchModel(_glbPath);
                  }
                }
              },
            );
          },
          onLoadStop: (ctrl, url) async {
            // Запасной таймер на случай если modelLoaded не придёт
            await Future.delayed(const Duration(seconds: 3));
            if (!_loaded && mounted) {
              setState(() => _loaded = true);
              _sendState(widget.state ?? 'idle');
            }
          },
          onReceivedError: (ctrl, req, err) {
            debugPrint('[Aika3DAvatar] WebView error: \${err.description}');
          },
        ),
      ),
    );
  }
}
