import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls the floating 3D overlay that appears over ALL other apps.
/// Uses MethodChannel → native Android WindowManager + FlutterView.
class OverlayService {
  static const MethodChannel _channel =
      MethodChannel('com.aika.assistant/overlay');

  // Канал для управления 3D моделью из overlay engine
  static const MethodChannel _overlayFlutterChannel =
      MethodChannel('com.aika.assistant/overlay_flutter');

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

  /// Show 3D overlay. [state]: idle | listening | thinking | talking | greeting | dance | stretch
  static Future<void> showOverlay({String state = 'idle'}) async {
    try {
      await _channel.invokeMethod('showOverlay', {'state': state});
    } catch (e) {
      debugPrint('[Overlay] showOverlay error: $e');
    }
  }

  /// Update avatar state (animation + glow color)
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

  /// Обновить параметры: размер, прозрачность, сторона (left/right).
  static Future<void> updateConfig({
    double size    = 170,
    double opacity = 1.0,
    String side    = 'left',
  }) async {
    try {
      await _channel.invokeMethod('updateLive2DConfig', {
        'size':    size,
        'opacity': opacity,
        'side':    side,
      });
      await _overlayFlutterChannel.invokeMethod('setConfig', {
        'opacity': opacity,
      });
    } catch (e) {
      debugPrint('[Overlay] updateConfig error: $e');
    }
  }
}
