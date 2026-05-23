import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Умные уведомления: анализирует важность входящих сообщений.
/// Важные — читает вслух сразу. Остальные — копит в буфер для брифинга.
class SmartNotificationsService {
  static const _bufferKey = 'smart_notif_buffer';
  static const _enabledKey = 'smart_notif_enabled';

  // Ключевые слова высокой важности
  static const _highPriorityWords = [
    'срочно', 'urgent', 'важно', 'помогите', 'help', 'emergency',
    'встреча', 'звонок', 'перезвони', 'callback', 'asap',
    'дедлайн', 'deadline', 'опоздаешь', 'не забудь',
    'авария', 'сломалось', 'не работает', 'упало',
    'деньги', 'оплата', 'счёт', 'долг',
  ];

  // Приложения которые всегда важны
  static const _alwaysImportantApps = [
    'com.whatsapp', 'org.telegram.messenger',
    'com.vkontakte.android', 'com.discord',
  ];

  /// Анализирует уведомление и решает — важное или нет.
  /// Возвращает true если нужно читать вслух немедленно.
  static bool isImportant({
    required String packageName,
    required String title,
    required String text,
  }) {
    final combined = '${title.toLowerCase()} ${text.toLowerCase()}';

    // Всегда важно если есть ключевые слова
    if (_highPriorityWords.any((w) => combined.contains(w))) return true;

    // Важно если от приоритетного приложения и текст не пустой
    if (_alwaysImportantApps.contains(packageName) && text.trim().length > 3) {
      return true;
    }

    return false;
  }

  /// Добавляет неважное уведомление в буфер для позднего брифинга
  static Future<void> addToBuffer({
    required String appName,
    required String title,
    required String text,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_bufferKey) ?? '[]';
    final List<dynamic> buffer = jsonDecode(raw);
    buffer.add({
      'app': appName,
      'title': title,
      'text': text,
      'time': DateTime.now().toIso8601String(),
    });
    // Храним не больше 50 уведомлений
    if (buffer.length > 50) buffer.removeRange(0, buffer.length - 50);
    await prefs.setString(_bufferKey, jsonEncode(buffer));
  }

  /// Возвращает брифинг по накопленным уведомлениям и очищает буфер
  static Future<String?> getBufferBriefing() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_bufferKey) ?? '[]';
    final List<dynamic> buffer = jsonDecode(raw);
    if (buffer.isEmpty) return null;

    // Группируем по приложениям
    final Map<String, List<String>> byApp = {};
    for (final item in buffer) {
      final app = item['app'] as String? ?? 'Приложение';
      final text = item['text'] as String? ?? '';
      byApp.putIfAbsent(app, () => []).add(text);
    }

    final sb = StringBuffer('Пока тебя не было, пришло несколько сообщений. ');
    for (final entry in byApp.entries) {
      final count = entry.value.length;
      sb.write('Из ${entry.key}: $count ${_plural(count)}. ');
    }

    // Очищаем буфер
    await prefs.remove(_bufferKey);
    return sb.toString().trim();
  }

  /// Возвращает количество накопленных уведомлений
  static Future<int> getBufferCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_bufferKey) ?? '[]';
    final List<dynamic> buffer = jsonDecode(raw);
    return buffer.length;
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  static String _plural(int n) {
    if (n == 1) return 'сообщение';
    if (n >= 2 && n <= 4) return 'сообщения';
    return 'сообщений';
  }
}
