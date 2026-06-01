import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Entry point для overlay — запускается отдельным Flutter Engine
/// поверх всех приложений через AikaOverlayService.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _OverlayApp());
}

class _OverlayApp extends StatelessWidget {
  const _OverlayApp();
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _AikaOverlayPage(),
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

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNative);
  }

  Future<dynamic> _handleNative(MethodCall call) async {
    switch (call.method) {
      case 'setState':
        final s = call.arguments as String? ?? 'idle';
        if (mounted) setState(() => _state = s);
        _webCtrl?.evaluateJavascript(source: "window.setAikaState('$s')");
        break;
      case 'setMusicPlaying':
        final playing = call.arguments as bool? ?? false;
        final s = playing ? 'dance' : 'idle';
        if (mounted) setState(() => _state = s);
        _webCtrl?.evaluateJavascript(source: "window.setAikaState('$s')");
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
        _webCtrl?.evaluateJavascript(source: "window.setAikaState('greeting')");
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _state = 'idle');
          _webCtrl?.evaluateJavascript(source: "window.setAikaState('idle')");
        });
        break;
      case 'playAnimation':
        final anim = call.arguments as String? ?? 'idle';
        final mapped = _animToState(anim);
        if (mounted) setState(() => _state = mapped);
        _webCtrl?.evaluateJavascript(source: "window.setAikaState('$mapped')");
        break;
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
    return SizedBox(
      width: _size,
      height: _size * 1.5,
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
          _webCtrl = ctrl;
          ctrl.addJavaScriptHandler(
            handlerName: 'FlutterChannel',
            callback: (args) {
              final msg = args.isNotEmpty ? args[0].toString() : '';
              if (msg == 'tap') {
                _channel.invokeMethod('onTap');
              }
            },
          );
        },
        onLoadStop: (ctrl, url) {
          Future.delayed(const Duration(milliseconds: 800), () {
            ctrl.evaluateJavascript(source: "window.setAikaState('${_state}')");
          });
        },
      ),
    );
  }
}
