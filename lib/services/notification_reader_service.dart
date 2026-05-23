import 'package:shared_preferences/shared_preferences.dart';
import 'smart_notifications_service.dart';

/// Сервис чтения уведомлений вслух.
/// Когда приходит уведомление — Айка озвучивает кто написал и что.
class NotificationReaderService {
  static const _keyEnabled       = 'notif_reader_enabled';
  static const _keyApps          = 'notif_reader_apps';
  static const _keyMinInterval   = 'notif_reader_interval';

  // Callback: возвращает строку которую нужно озвучить
  static Future<String?> Function(String text)? onSpeak;

  static DateTime? _lastSpoken;
  static const _minGap = Duration(seconds: 3);

  // Человекочитаемые имена приложений
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

  // По умолчанию слушаем эти приложения
  static const List<String> defaultApps = [
    'org.telegram.messenger',
    'com.whatsapp',
    'com.vkontakte.android',
    'com.instagram.android',
    'com.discord',
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
    final saved = prefs.getStringList(_keyApps);
    return saved ?? defaultApps;
  }

  static Future<void> setEnabledApps(List<String> apps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyApps, apps);
  }

  /// Вызывается когда пришло новое уведомление
  static Future<void> onNotification(Map<String, String> notif) async {
    if (!await isEnabled()) return;

    final pkg   = notif['pkg']   ?? '';
    final title = notif['title'] ?? '';
    final text  = notif['text']  ?? '';

    if (pkg.isEmpty || title.isEmpty || text.isEmpty) return;

    // Проверяем включено ли для этого приложения
    final enabledApps = await getEnabledApps();
    if (!enabledApps.contains(pkg)) return;

    // Антиспам — не чаще раза в 3 секунды
    final now = DateTime.now();
    if (_lastSpoken != null && now.difference(_lastSpoken!) < _minGap) return;
    _lastSpoken = now;

    final appName = appNames[pkg] ?? _extractAppName(pkg);

    // ── Умная фильтрация уведомлений ─────────────────────────────────────
    final important = SmartNotificationsService.isImportant(
      packageName: pkg, title: title, text: text);

    if (!important) {
      // Неважное — копим в буфер для брифинга, не читаем вслух
      await SmartNotificationsService.addToBuffer(
        appName: appName, title: title, text: text);
      return;
    }

    // Формируем фразу для озвучки
    String phrase;
    if (title.isNotEmpty && title != appName) {
      phrase = '$appName: $title написал: $text';
    } else {
      phrase = '$appName: $text';
    }

    // Обрезаем длинные сообщения
    if (phrase.length > 200) {
      phrase = '\${phrase.substring(0, 197)}...';
    }

    await onSpeak?.call(phrase);
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
