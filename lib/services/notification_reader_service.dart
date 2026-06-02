import 'package:shared_preferences/shared_preferences.dart';
import 'smart_notifications_service.dart';

/// Сервис чтения уведомлений вслух + умный ответ через AI
class NotificationReaderService {
  static const _keyEnabled     = 'notif_reader_enabled';
  static const _keyApps        = 'notif_reader_apps';
  static const _keyAutoReply   = 'notif_auto_reply_prompt'; // включена ли подсказка ответить

  static Future<String?> Function(String text)? onSpeak;

  // Callback: предложить ответить на сообщение
  // Параметры: appName, senderName, messageText
  // Должен вернуть текст предложенного ответа или null
  static Future<String?> Function(String appName, String sender, String text)? onSuggestReply;

  // Callback: когда получено новое важное уведомление — обновить оверлей
  static void Function(String overlayState)? onOverlayState;

  static DateTime? _lastSpoken;
  static const _minGap = Duration(seconds: 3);

  static const Map<String, String> appNames = {
    'org.telegram.messenger':      'Telegram',
    'org.telegram.messenger.web':  'Telegram',
    'com.whatsapp':                'WhatsApp',
    'com.whatsapp.w4b':            'WhatsApp Business',
    'com.vkontakte.android':       'ВКонтакте',
    'com.instagram.android':       'Instagram',
    'com.facebook.katana':         'Facebook',
    'com.facebook.orca':           'Messenger',
    'com.viber.voip':              'Viber',
    'kik.android':                 'Kik',
    'com.snapchat.android':        'Snapchat',
    'com.discord':                 'Discord',
    'ru.mail.mailru.mymail':       'Mail.ru',
    'com.google.android.gm':       'Gmail',
    'com.microsoft.teams':         'Teams',
    'com.slack':                   'Slack',
    'com.skype.raider':            'Skype',
  };

  static const List<String> defaultApps = [
    'org.telegram.messenger',
    'com.whatsapp',
    'com.vkontakte.android',
    'com.instagram.android',
    'com.discord',
  ];

  // Список приложений из которых предлагаем ответить
  static const List<String> replyApps = [
    'org.telegram.messenger',
    'com.whatsapp',
    'com.vkontakte.android',
    'com.instagram.android',
    'com.viber.voip',
  ];

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
  }

  static Future<List<String>> getEnabledApps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyApps) ?? defaultApps;
  }

  static Future<void> setEnabledApps(List<String> apps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyApps, apps);
  }

  /// Основной обработчик входящего уведомления
  static Future<void> onNotification(Map<String, String> notif) async {
    if (!await isEnabled()) return;

    final pkg   = notif['pkg']   ?? '';
    final title = notif['title'] ?? '';
    final text  = notif['text']  ?? '';

    if (pkg.isEmpty || title.isEmpty || text.isEmpty) return;

    final enabledApps = await getEnabledApps();
    if (!enabledApps.contains(pkg)) return;

    final now = DateTime.now();
    if (_lastSpoken != null && now.difference(_lastSpoken!) < _minGap) return;
    _lastSpoken = now;

    final appName = appNames[pkg] ?? _extractAppName(pkg);

    // Умная фильтрация
    final important = SmartNotificationsService.isImportant(
      packageName: pkg, title: title, text: text);

    if (!important) {
      await SmartNotificationsService.addToBuffer(
        appName: appName, title: title, text: text);
      return;
    }

    // Формируем фразу
    String phrase;
    if (title.isNotEmpty && title != appName) {
      phrase = '$appName: $title — $text';
    } else {
      phrase = '$appName: $text';
    }
    if (phrase.length > 200) phrase = '${phrase.substring(0, 197)}...';

    // Обновляем оверлей → notification
    onOverlayState?.call('notification');

    // Озвучиваем
    await onSpeak?.call(phrase);

    // Предлагаем ответить если это мессенджер
    if (replyApps.contains(pkg) && onSuggestReply != null) {
      // Небольшая пауза перед предложением ответа
      await Future.delayed(const Duration(milliseconds: 500));
      final senderName = title.isNotEmpty ? title : appName;
      await onSuggestReply?.call(appName, senderName, text);
    }
  }

  static String _extractAppName(String pkg) {
    final parts = pkg.split('.');
    if (parts.length >= 2) {
      final name = parts[parts.length - 1];
      return name[0].toUpperCase() + name.substring(1);
    }
    return pkg;
  }

  /// Парсим голосовую команду управления
  static Future<String?> tryParseCommand(String text) async {
    final t = text.toLowerCase();

    if ((t.contains('читай') || t.contains('озвучивай') || t.contains('произноси')) &&
        t.contains('уведомлен')) {
      await setEnabled(true);
      return '🔔 Теперь буду читать уведомления вслух! Telegram, WhatsApp, VK и другие.';
    }

    if ((t.contains('не читай') || t.contains('отключи') || t.contains('выключи')) &&
        t.contains('уведомлен')) {
      await setEnabled(false);
      return '🔕 Перестала читать уведомления вслух.';
    }

    return null;
  }
}
