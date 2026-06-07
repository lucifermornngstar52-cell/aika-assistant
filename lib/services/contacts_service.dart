import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ContactsService — поиск контактов голосом.
/// Запрашивает READ_CONTACTS разрешение через нативный канал.
/// Адаптировано из openclaw-assistant ContactsHandler (MIT).
///
/// Голосовые команды:
///   "найди контакт Саша", "номер телефона Максим", "позвони Саше" (возвращает номер)
class ContactsService {
  static final ContactsService _i = ContactsService._();
  factory ContactsService() => _i;
  ContactsService._();

  static const _channel = MethodChannel('com.aika.assistant/contacts');

  // ──────────────────────── ПУБЛИЧНЫЙ API ────────────────────────

  /// Ищет контакт по имени, возвращает список {name, phone}
  Future<List<Map<String, String>>> search(String query) async {
    try {
      final result = await _channel.invokeMethod<List>('searchContacts', {'query': query});
      if (result == null) return [];
      return result.map<Map<String, String>>((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return {'name': m['name']?.toString() ?? '', 'phone': m['phone']?.toString() ?? ''};
      }).toList();
    } catch (e) {
      debugPrint('[Contacts] search error: $e');
      return [];
    }
  }

  /// Парсит голосовую команду, возвращает ответ
  Future<String?> parseCommand(String input) async {
    final t = input.toLowerCase().trim();

    String? query;

    for (final trigger in [
      'найди контакт', 'найти контакт', 'контакт',
      'номер телефона', 'номер', 'найди номер',
    ]) {
      if (t.contains(trigger)) {
        query = _extractAfter(input, trigger);
        break;
      }
    }

    if (query == null || query.isEmpty) return null;

    final contacts = await search(query.trim());

    if (contacts.isEmpty) return 'Контакт "$query" не найден.';
    if (contacts.length == 1) {
      final c = contacts.first;
      return '${c['name']}: ${c['phone']}';
    }

    final list = contacts.take(3).map((c) => '${c['name']} — ${c['phone']}').join('\n');
    return 'Нашла ${contacts.length} контактов:\n$list';
  }

  String _extractAfter(String text, String trigger) {
    final idx = text.toLowerCase().indexOf(trigger.toLowerCase());
    if (idx == -1) return '';
    return text.substring(idx + trigger.length).trim();
  }
}
