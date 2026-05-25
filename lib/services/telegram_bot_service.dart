import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Telegram Bot интеграция для Айки.
class TelegramBotService {
  static const _keyToken   = 'telegram_bot_token';
  static const _keyEnabled = 'telegram_bot_enabled';
  static const _keyOffset  = 'telegram_bot_offset';

  static String? _token;
  static bool _isRunning = false;
  static Timer? _pollTimer;
  static int _offset = 0;

  /// Callback: вызывается когда пришло сообщение от пользователя.
  static Future<String> Function(String message, String from)? onMessage;

  /// Callback: обработчик команд безопасности.
  static Future<bool> Function(String text, String chatId)? onSecurityCommand;

  /// Callback: обработчик inline кнопок (callback_query).
  /// Принимает: callbackData, chatId, messageId, fromName
  /// Возвращает текст ответа (или null чтобы не отвечать)
  static Future<String?> Function(String data, String chatId, int messageId, String from)? onCallbackQuery;

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
      // Получаем и message и callback_query
      final url = 'https://api.telegram.org/bot$_token/getUpdates'
          '?offset=$_offset&timeout=3'
          '&allowed_updates=%5B%22message%22%2C%22callback_query%22%5D';
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      final data = json.decode(resp.body);
      if (data['ok'] != true) return;

      for (final update in data['result']) {
        final updateId = update['update_id'] as int;
        _offset = updateId + 1;

        // ── Обработка inline кнопок ──────────────────────────────────
        final cbq = update['callback_query'];
        if (cbq != null) {
          final cbId     = cbq['id'] as String;
          final cbData   = cbq['data'] as String? ?? '';
          final cbMsg    = cbq['message'];
          final cbChatId = cbMsg?['chat']?['id']?.toString() ?? '';
          final cbMsgId  = cbMsg?['message_id'] as int? ?? 0;
          final cbFrom   = cbq['from'];
          final cbName   = '${cbFrom?['first_name'] ?? ''} ${cbFrom?['last_name'] ?? ''}'.trim();

          // Обязательно отвечаем на callback чтобы кнопка не крутилась
          await _answerCallbackQuery(cbId);

          // Вызываем пользовательский обработчик
          if (onCallbackQuery != null) {
            try {
              final reply = await onCallbackQuery!(cbData, cbChatId, cbMsgId, cbName);
              if (reply != null && reply.isNotEmpty) {
                await _sendMessage(int.tryParse(cbChatId) ?? cbChatId, reply);
              }
            } catch (e) {
              await _sendMessage(int.tryParse(cbChatId) ?? cbChatId, 'Ошибка: $e');
            }
          } else {
            // Базовая обработка если нет кастомного обработчика
            if (onMessage != null) {
              try {
                final reply = await onMessage!(cbData, cbName);
                await _sendMessage(int.tryParse(cbChatId) ?? cbChatId, reply);
              } catch (_) {}
            }
          }
          continue;
        }

        // ── Обработка текстовых сообщений ────────────────────────────
        final message = update['message'];
        if (message == null) continue;

        final text = message['text'] as String?;
        if (text == null) continue;

        final from     = message['from'];
        final fromName = '${from?['first_name'] ?? ''} ${from?['last_name'] ?? ''}'.trim();
        final chatId   = message['chat']['id'];

        // Сохраняем chat_id владельца
        final prefs2 = await SharedPreferences.getInstance();
        if (prefs2.getString('telegram_owner_chat_id') == null) {
          await prefs2.setString('telegram_owner_chat_id', chatId.toString());
        }

        // Команды безопасности
        try {
          if (onSecurityCommand != null) {
            final handled = await onSecurityCommand!(text, chatId.toString());
            if (handled) continue;
          }
        } catch (_) {}

        // AI ответ
        if (onMessage != null) {
          try {
            final reply = await onMessage!(text, fromName);
            await _sendMessage(chatId, reply);
          } catch (_) {
            await _sendMessage(chatId, 'Момент, я думаю... 🤔');
          }
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyOffset, _offset);
    } catch (_) {}
  }

  /// Ответить на callback_query (убирает "часики" с кнопки)
  static Future<void> _answerCallbackQuery(String callbackQueryId, {String? text}) async {
    if (_token == null) return;
    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot$_token/answerCallbackQuery'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'callback_query_id': callbackQueryId,
          if (text != null) 'text': text,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
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

  /// Отправить сообщение с inline кнопками
  static Future<void> sendWithButtons(dynamic chatId, String text,
      List<List<Map<String, String>>> keyboard) async {
    if (_token == null) {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_keyToken);
    }
    if (_token == null) return;
    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot$_token/sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'chat_id': chatId,
          'text': text,
          'parse_mode': 'HTML',
          'reply_markup': {
            'inline_keyboard': keyboard.map((row) =>
              row.map((btn) => {
                'text': btn['text']!,
                'callback_data': btn['data']!,
              }).toList()
            ).toList(),
          },
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Редактировать сообщение (например убрать кнопки после нажатия)
  static Future<void> editMessageText(dynamic chatId, int messageId, String text) async {
    if (_token == null) return;
    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot$_token/editMessageText'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'chat_id': chatId,
          'message_id': messageId,
          'text': text,
          'parse_mode': 'HTML',
          'reply_markup': {'inline_keyboard': []},
        }),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  static Future<void> sendToChatId(dynamic chatId, String text) async {
    if (_token == null) {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_keyToken);
    }
    if (_token == null) return;
    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot$_token/sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'chat_id': chatId is String ? int.tryParse(chatId) ?? chatId : chatId,
          'text': text,
          'parse_mode': 'HTML',
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

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
