import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls the floating overlay window that appears over other apps.
/// Uses a MethodChannel to communicate with native Android code.
class OverlayService {
  static const MethodChannel _channel = MethodChannel('com.aika.assistant/overlay');

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

  static Future<void> showOverlay({String message = 'Слушаю...'}) async {
    try {
      await _channel.invokeMethod('showOverlay', {'message': message});
    } catch (e) {
      debugPrint('[Overlay] showOverlay error: $e');
    }
  }

  static Future<void> updateOverlay({required String message}) async {
    try {
      await _channel.invokeMethod('updateOverlay', {'message': message});
    } catch (e) {
      debugPrint('[Overlay] updateOverlay error: $e');
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
