import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ConversationHistoryService — история диалога с навигацией стрелками.
/// Вдохновлено Google Assistant Desktop Client (history/historyHead паттерн).
/// 
/// Фичи:
///   - Показывает последние 100 сообщений из единого chat_history
///   - navigatePrev/navigateNext — листать историю как в терминале (↑↓)
///   - getContext(n) — возвращает последние N пар user+assistant для промпта
///   - forceNewConversation — флаг сброса контекста (как в GA Client)
class ConversationHistoryService {
  static final ConversationHistoryService _i = ConversationHistoryService._();
  factory ConversationHistoryService() => _i;
  ConversationHistoryService._();

  static const _key = 'chat_history';
  static const _maxItems = 100;

  List<Map<String, String>> _history = []; // [{role: 'user'|'assistant', text: '...'}]
  int _head = -1; // текущая позиция в истории (для ↑↓)
  String _currentDraft = ''; // черновик текущего ввода

  bool forceNewConversation = false; // сбросить контекст при след. запросе

  // ──────────────── ИНИЦИАЛИЗАЦИЯ ────────────────

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _history = [];
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final records = jsonDecode(raw);
        if (records is List) {
          for (final record in records.whereType<Map>()) {
            final role = record['role'];
            final text = record['content'];
            if (text is! String || text.isEmpty) continue;
            if (role == 'user' || role == 'aika' || role == 'assistant') {
              _history.add({'role': role == 'user' ? 'user' : 'assistant',
                'text': text});
            }
          }
          _trim();
        }
      } catch (_) { _history = []; }
    }
    // Старый независимый кэш навигации больше не используется.
    await prefs.remove('aivora_conv_history_v1');
    _head = -1;
    debugPrint('[ConvHistory] загружено ${_history.length} сообщений');
  }

  // ──────────────── ДОБАВЛЕНИЕ ────────────────

  void addUser(String text) {
    _history.add({'role': 'user', 'text': text});
    _trim();
    _head = -1; // сбрасываем навигацию
  }

  void addAssistant(String text) {
    _history.add({'role': 'assistant', 'text': text});
    _trim();
  }

  // ──────────────── НАВИГАЦИЯ ↑↓ (как в терминале) ────────────────

  /// Переход к предыдущему запросу пользователя (↑)
  String? navigatePrev(String currentDraft) {
    final userMsgs = _history
        .where((m) => m['role'] == 'user')
        .map((m) => m['text']!)
        .toList();

    if (userMsgs.isEmpty) return null;

    if (_head == -1) {
      _currentDraft = currentDraft; // сохраняем черновик
      _head = userMsgs.length - 1;
    } else if (_head > 0) {
      _head--;
    }

    return userMsgs[_head];
  }

  /// Переход к следующему запросу (↓)
  String? navigateNext() {
    final userMsgs = _history
        .where((m) => m['role'] == 'user')
        .map((m) => m['text']!)
        .toList();

    if (_head == -1) return null;

    _head++;
    if (_head >= userMsgs.length) {
      _head = -1;
      return _currentDraft; // возвращаем черновик
    }

    return userMsgs[_head];
  }

  // ──────────────── КОНТЕКСТ ДЛЯ AI ────────────────

  /// Возвращает последние [pairs] пар user+assistant для промпта
  List<Map<String, String>> getContext({int pairs = 5}) {
    if (forceNewConversation) return [];

    final result = <Map<String, String>>[];
    int count = 0;

    for (int i = _history.length - 1; i >= 0 && count < pairs * 2; i--) {
      result.insert(0, _history[i]);
      count++;
    }

    return result;
  }

  /// Форматирует контекст в строку для вставки в системный промпт
  String formatContextForPrompt({int pairs = 4}) {
    final ctx = getContext(pairs: pairs);
    if (ctx.isEmpty) return '';

    final sb = StringBuffer('История диалога:\n');
    for (final msg in ctx) {
      final role = msg['role'] == 'user' ? 'Пользователь' : 'Ты';
      sb.writeln('$role: ${msg['text']}');
    }
    return sb.toString();
  }

  // ──────────────── УТИЛИТЫ ────────────────

  void clear() {
    _history.clear();
    _head = -1;
  }

  int get length => _history.length;

  void _trim() {
    if (_history.length > _maxItems) {
      _history.removeRange(0, _history.length - _maxItems);
    }
  }

}
