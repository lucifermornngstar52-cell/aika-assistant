import 'package:flutter/services.dart';

class OverlayService {
  static const _channel = MethodChannel('com.aika.assistant/overlay');

  static Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (_) {}
  }

  static Future<void> showOverlay({String message = '...'}) async {
    try {
      await _channel.invokeMethod('showOverlay', {'message': message});
    } catch (_) {}
  }

  static Future<void> updateOverlay({String message = '...'}) async {
    try {
      await _channel.invokeMethod('updateOverlay', {'message': message});
    } catch (_) {}
  }

  static Future<void> hideOverlay() async {
    try {
      await _channel.invokeMethod('hideOverlay');
    } catch (_) {}
  }
}
