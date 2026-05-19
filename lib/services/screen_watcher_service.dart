import 'dart:async';
import 'package:flutter/services.dart';

class ScreenWatcherService {
  static const _channel = MethodChannel('com.aika.assistant/screen');
  static const _eventChannel = EventChannel('com.aika.assistant/screen_events');

  static String _currentPackage = '';
  static String _currentLabel = '';
  static StreamSubscription? _sub;

  static Map<String, String>? getCurrentAppInfo() {
    if (_currentPackage.isEmpty) return null;
    return {'package': _currentPackage, 'label': _currentLabel};
  }

  static String get currentPackage => _currentPackage;
  static String get currentLabel => _currentLabel;

  /// Запустить прослушивание событий экрана
  static void startWatching({void Function(String pkg, String label)? onChanged}) {
    _sub?.cancel();
    _sub = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        _currentPackage = event['package'] ?? '';
        _currentLabel   = event['label'] ?? '';
        onChanged?.call(_currentPackage, _currentLabel);
      }
    }, onError: (_) {});
  }

  static void stopWatching() {
    _sub?.cancel();
    _sub = null;
  }

  /// Проверить включён ли Accessibility Service
  static Future<bool> isAccessibilityEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Открыть настройки доступности
  static Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }
}
