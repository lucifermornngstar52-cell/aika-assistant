import 'dart:async';
import 'package:flutter/services.dart';

class MessageSenderService {
  static const _channel = MethodChannel('com.aika.assistant/messenger');

  /// Отправить сообщение контакту через WhatsApp или Telegram
  /// [app] — "whatsapp" | "telegram"
  /// [contact] — имя контакта как оно написано в списке
  /// [message] — текст сообщения
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
      return result ?? 'Отправляю...';
    } on PlatformException catch (e) {
      return 'Ошибка: \${e.message}';
    }
  }
}
