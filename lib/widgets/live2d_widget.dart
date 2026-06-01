import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Виджет Live2D через InAppWebView.
/// Загружает assets/live2d_viewer.html, который рендерит модель Haru
/// через pixi-live2d-display + Live2D Cubism SDK.
class Live2DWidget extends StatefulWidget {
  final double width;
  final double height;
  final String state; // idle, listening, thinking, talking, greeting, dance

  const Live2DWidget({
    Key? key,
    this.width = 220,
    this.height = 320,
    this.state = 'idle',
  }) : super(key: key);

  @override
  State<Live2DWidget> createState() => _Live2DWidgetState();
}

class _Live2DWidgetState extends State<Live2DWidget> {
  InAppWebViewController? _ctrl;
  String _lastState = '';

  @override
  void didUpdateWidget(Live2DWidget old) {
    super.didUpdateWidget(old);
    if (widget.state != _lastState && _ctrl != null) {
      _setState(widget.state);
    }
  }

  void _setState(String state) {
    _lastState = state;
    _ctrl?.evaluateJavascript(source: "window.setAikaState('$state')");
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
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
          ),
          onWebViewCreated: (ctrl) {
            _ctrl = ctrl;
            // Слушаем тапы по модели из JS
            ctrl.addJavaScriptHandler(
              handlerName: 'FlutterChannel',
              callback: (args) {
                final msg = args.isNotEmpty ? args[0].toString() : '';
                if (msg == 'tap') {
                  // можно добавить реакцию
                }
              },
            );
          },
          onLoadStop: (ctrl, url) {
            // Устанавливаем начальное состояние после загрузки
            Future.delayed(const Duration(milliseconds: 500), () {
              _setState(widget.state);
            });
          },
        ),
      ),
    );
  }
}
