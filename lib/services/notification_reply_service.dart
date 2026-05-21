import 'package:flutter/services.dart';

/// Сервис для ответа на входящие уведомления из мессенджеров.
/// Поддерживает: Telegram, WhatsApp, VK, Instagram Direct.
class NotificationReplyService {
  static const _channel = MethodChannel('com.aika.assistant/notifications');

  static const Map<String, String> _pkgToApp = {
    'org.telegram.messenger': 'Telegram',
    'org.telegram.plus': 'Telegram',
    'com.whatsapp': 'WhatsApp',
    'com.whatsapp.w4b': 'WhatsApp Business',
    'com.vkontakte.android': 'VK',
    'com.instagram.android': 'Instagram',
    'com.viber.voip': 'Viber',
  };

  /// Проверяет — можно ли ответить на это уведомление
  static bool canReply(Map<String, String> notif) {
    return _pkgToApp.containsKey(notif['pkg'] ?? '');
  }

  static String appNameFor(Map<String, String> notif) {
    return _pkgToApp[notif['pkg'] ?? ''] ?? 'мессенджер';
  }

  /// Детектирует запрос "ответить на уведомление" в тексте пользователя
  static bool isReplyRequest(String text) {
    final t = text.toLowerCase();
    return (t.contains('ответь') || t.contains('напиши') || t.contains('скажи')) &&
        (t.contains('на уведомление') || t.contains('ему') || t.contains('ей') ||
         t.contains('им') || t.contains('в ответ'));
  }

  /// Детектирует подтверждение ответа ("да", "отправь", "ок")
  static bool isConfirm(String text) {
    final t = text.toLowerCase();
    return t == 'да' || t == 'ок' || t == 'окей' || t == 'отправь' ||
        t == 'отправляй' || t.contains('да, отправь') || t.contains('подтверж');
  }

  /// Детектирует отмену ("нет", "отмена")
  static bool isCancel(String text) {
    final t = text.toLowerCase();
    return t == 'нет' || t == 'отмена' || t.contains('не надо') || t.contains('не отправляй');
  }

  /// Отправить ответ через нативный DirectReply (если доступно) или через accessibility
  static Future<bool> replyToNotification({
    required String packageName,
    required String text,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('replyToNotification', {
        'package': packageName,
        'text': text,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
