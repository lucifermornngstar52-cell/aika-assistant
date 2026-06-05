import 'dart:async';
import 'package:flutter/services.dart';

class MessageSenderService {
  static const _channel = MethodChannel('com.aika.assistant/messenger');

  static Future<String> sendMessage({
    required String app,
    required String contact,
    required String message,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('sendMessage', {
        'app': app,
        'contact': contact,
        'message': message,
      });
      final r = result ?? '';
      if (r.startsWith('NO_ACCESSIBILITY')) {
        return 'Включи Accessibility Service для Aika в настройках Android, чтобы отправлять сообщения';
      }
      if (r.startsWith('ERROR')) return 'Не удалось отправить: проверь имя контакта';
      return r.isEmpty ? 'Отправила!' : r;
    } on PlatformException catch (e) {
      final code = e.code;
      if (code == 'NO_SERVICE') return 'Accessibility Service не активен - включи в настройках';
      return 'Ошибка отправки: \${e.message ?? code}';
    } catch (_) {
      return 'Не удалось отправить сообщение';
    }
  }
}
