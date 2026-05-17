import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls the floating chibi overlay that appears over ALL other apps.
/// Uses MethodChannel → native Android WindowManager.
class OverlayService {
  static const MethodChannel _channel =
      MethodChannel('com.aika.assistant/overlay');

  static Future<bool> hasPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasPermission');
      return result ?? false;
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

  /// Show chibi over all apps. [state]: idle | listening | thinking | greeting
  static Future<void> showOverlay({String state = 'idle'}) async {
    try {
      await _channel.invokeMethod('showOverlay', {'state': state});
    } catch (e) {
      debugPrint('[Overlay] showOverlay error: $e');
    }
  }

  /// Update chibi state without hiding/showing again
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
}
