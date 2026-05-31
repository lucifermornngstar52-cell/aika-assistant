import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_live2d/flutter_live2d.dart';

/// Сервис управления Live2D оверлеем поверх всех приложений.
/// Использует flutter_overlay_window + Live2DViewController.
class Live2DOverlayService {
  static Live2DViewController? _controller;
  static bool _isShowing = false;

  static const MethodChannel _channel =
      MethodChannel('com.aika.assistant/overlay');

  static Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (_) {}
  }

  static Future<void> show({String state = 'idle'}) async {
    try {
      await _channel.invokeMethod('showOverlay', {
        'state': state,
        'mode': 'live2d', // сигнал нативной стороне что используем live2d
      });
      _isShowing = true;
    } catch (_) {}
  }

  static Future<void> updateState(String state) async {
    if (!_isShowing) return;
    _controller?.startMotion(
      group: _stateToGroup(state),
      priority: 2,
    );
    try {
      await _channel.invokeMethod('updateOverlay', {'state': state});
    } catch (_) {}
  }

  static Future<void> hide() async {
    try {
      await _channel.invokeMethod('hideOverlay');
      _isShowing = false;
    } catch (_) {}
  }

  static String _stateToGroup(String state) {
    switch (state) {
      case 'listening': return 'TapBody';
      case 'thinking':  return 'Idle';
      case 'talking':   return 'TapBody';
      case 'greeting':  return 'TapBody';
      default:          return 'Idle';
    }
  }

  static bool get isShowing => _isShowing;
}

/// Flutter виджет оверлея — рендерит Live2D модель поверх всего.
/// Используется через flutter_overlay_window Entry Point.
class Live2DOverlayWidget extends StatefulWidget {
  final String initialState;
  const Live2DOverlayWidget({Key? key, this.initialState = 'idle'}) : super(key: key);

  @override
  State<Live2DOverlayWidget> createState() => _Live2DOverlayWidgetState();
}

class _Live2DOverlayWidgetState extends State<Live2DOverlayWidget> {
  final _ctrl = Live2DViewController();
  bool _loaded = false;
  double _x = 20;
  double _y = 120;
  static const double _size = 160;

  @override
  void initState() {
    super.initState();
    _ctrl.whenAttached.then((_) async {
      final ok = await _ctrl.loadModel(
        modelDir: 'assets/models/Haru/',
        modelFileName: 'Haru.model3.json',
      );
      if (ok && mounted) {
        setState(() => _loaded = true);
        _ctrl.startMotion(group: 'Idle', priority: 1);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned(
              left: _x,
              top: _y,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() {
                  _x += d.delta.dx;
                  _y += d.delta.dy;
                }),
                onTap: () => _ctrl.startMotion(group: 'TapBody', priority: 3),
                child: SizedBox(
                  width: _size,
                  height: _size * 1.5,
                  child: _loaded
                      ? Live2DView(controller: _ctrl)
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
