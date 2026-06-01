import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls the floating Live2D overlay that appears over ALL other apps.
/// Uses MethodChannel → native Android WindowManager + FlutterView.
class OverlayService {
  static const MethodChannel _channel =
      MethodChannel('com.aika.assistant/overlay');

  // Дополнительный канал для управления Live2D из overlay engine
  static const MethodChannel _live2dChannel =
      MethodChannel('com.aika.assistant/live2d_overlay');

  static Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (e) {
      debugPrint('[Overlay] hasPermission error: $e');
      return false;
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (e) {
      debugPrint('[Overlay] requestPermission error: $e');
    }
  }

  /// Show Live2D overlay. [state]: idle | listening | thinking | greeting
  static Future<void> showOverlay({String state = 'idle'}) async {
    try {
      await _channel.invokeMethod('showOverlay', {'state': state});
    } catch (e) {
      debugPrint('[Overlay] showOverlay error: $e');
    }
  }

  /// Update avatar state (motion + expression)
  static Future<void> updateState(String state) async {
    try {
      await _channel.invokeMethod('updateOverlay', {'state': state});
    } catch (e) {
      debugPrint('[Overlay] updateState error: $e');
    }
  }

  static Future<void> hideOverlay() async {
    try {
      await _channel.invokeMethod('hideOverlay');
    } catch (e) {
      debugPrint('[Overlay] hideOverlay error: $e');
    }
  }

  /// Обновить параметры Live2D модели (размер, прозрачность, скорость, отражение, сторона).
  /// Применяется мгновенно без перезапуска overlay.
  static Future<void> updateLive2DConfig({
    double size    = 170,
    double opacity = 1.0,
    double speed   = 1.0,
    bool   mirror  = false,
    String side    = 'left',
  }) async {
    try {
      // 1. Говорим нативной стороне изменить размер окна и положение
      await _channel.invokeMethod('updateLive2DConfig', {
        'size':    size,
        'opacity': opacity,
        'side':    side,
      });
      // 2. Говорим Flutter-overlay engine применить скорость и зеркало
      await _live2dChannel.invokeMethod('setConfig', {
        'speed':   speed,
        'mirror':  mirror,
        'opacity': opacity,
      });
    } catch (e) {
      debugPrint('[Overlay] updateLive2DConfig error: $e');
    }
  }
}
