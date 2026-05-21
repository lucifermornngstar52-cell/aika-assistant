import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Telegram Bot интеграция для Айки.
/// Пользователь пишет боту → Айка отвечает через AiService.
/// Настройка: токен бота хранится в SharedPreferences ('telegram_bot_token').
class TelegramBotService {
  static const _keyToken   = 'telegram_bot_token';
  static const _keyEnabled = 'telegram_bot_enabled';
  static const _keyOffset  = 'telegram_bot_offset';

  static String? _token;
  static bool _isRunning = false;
  static Timer? _pollTimer;
  static int _offset = 0;

  /// Callback: вызывается когда пришло сообщение от пользователя.
  /// Возвращает текст ответа который нужно отправить обратно.
  static Future<String> Function(String message, String from)? onMessage;

  static bool get isRunning => _isRunning;

  static Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token.trim());
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
    if (!value) stop();
  }

  /// Проверить токен и вернуть имя бота
  static Future<String?> validateToken(String token) async {
    try {
      final resp = await http.get(
        Uri.parse('https://api.telegram.org/bot$token/getMe'),
      ).timeout(const Duration(seconds: 8));
      final data = json.decode(resp.body);
      if (data['ok'] == true) {
        return '@${data['result']['username']}';
      }
    } catch (_) {}
    return null;
  }

  static Future<void> start() async {
    if (_isRunning) return;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_keyToken);
    if (_token == null || _token!.isEmpty) return;
    _offset = prefs.getInt(_keyOffset) ?? 0;
    _isRunning = true;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  static void stop() {
    _isRunning = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  static Future<void> _poll() async {
    if (_token == null) return;
    try {
      final url = 'https://api.telegram.org/bot$_token/getUpdates'
          '?offset=$_offset&timeout=3&allowed_updates=["message"]';
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      final data = json.decode(resp.body);
      if (data['ok'] != true) return;

      for (final update in data['result']) {
        final updateId = update['update_id'] as int;
        _offset = updateId + 1;

        final message = update['message'];
        if (message == null) continue;

        final text = message['text'] as String?;
        if (text == null) continue;

        final from = message['from'];
        final fromName = '${from?['first_name'] ?? ''} ${from?['last_name'] ?? ''}'.trim();
        final chatId = message['chat']['id'];

        // Получаем ответ от AI
        if (onMessage != null) {
          try {
            final reply = await onMessage!(text, fromName);
            await _sendMessage(chatId, reply);
          } catch (_) {
            await _sendMessage(chatId, 'Момент, я думаю... 🤔');
          }
        }
      }

      // Сохраняем offset
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyOffset, _offset);
    } catch (_) {
      // Игнорируем ошибки сети
    }
  }

  static Future<void> _sendMessage(dynamic chatId, String text) async {
    if (_token == null) return;
    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot$_token/sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'chat_id': chatId,
          'text': text,
          'parse_mode': 'HTML',
        }),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// Отправить уведомление владельцу бота
  static Future<void> notifyOwner(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyToken);
    final chatId = prefs.getString('telegram_owner_chat_id');
    if (token == null || chatId == null) return;
    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'chat_id': int.parse(chatId), 'text': text}),
      );
    } catch (_) {}
  }
}
