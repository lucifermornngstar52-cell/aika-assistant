import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Долгосрочная память Айки о людях и фактах.
/// Хранит: имена, отношения, факты, заметки.
class PeopleMemoryService {
  static const _keyPeople  = 'aika_people_memory';
  static const _keyFacts   = 'aika_facts_memory';

  // ──────────────────────── ЛЮДИ ────────────────────────

  /// Добавить или обновить человека
  Future<void> savePerson(String name, {
    String? relation,   // друг, мама, коллега...
    String? phone,
    String? notes,
  }) async {
    final people = await _loadPeople();
    final key = name.toLowerCase().trim();
    people[key] = {
      'name': name.trim(),
      if (relation != null) 'relation': relation,
      if (phone    != null) 'phone': phone,
      if (notes    != null) 'notes': notes,
      'updated': DateTime.now().toIso8601String(),
    };
    await _savePeople(people);
  }

  /// Найти человека по имени (нечёткий поиск)
  Future<Map<String, dynamic>?> findPerson(String query) async {
    final people = await _loadPeople();
    final q = query.toLowerCase().trim();
    // Точное совпадение
    if (people.containsKey(q)) return people[q];
    // Частичное совпадение
    for (final entry in people.entries) {
      if (entry.key.contains(q) || q.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  Future<Map<String, Map<String, dynamic>>> getAllPeople() async =>
      await _loadPeople();

  Future<void> deletePerson(String name) async {
    final people = await _loadPeople();
    people.remove(name.toLowerCase().trim());
    await _savePeople(people);
  }

  // ──────────────────────── ФАКТЫ ────────────────────────

  /// Сохранить произвольный факт о пользователе
  Future<void> saveFact(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFacts) ?? '{}';
    final facts = Map<String, String>.from(jsonDecode(raw));
    facts[key.toLowerCase().trim()] = value.trim();
    await prefs.setString(_keyFacts, jsonEncode(facts));
  }

  Future<String?> getFact(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFacts) ?? '{}';
    final facts = Map<String, String>.from(jsonDecode(raw));
    return facts[key.toLowerCase().trim()];
  }

  Future<Map<String, String>> getAllFacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFacts) ?? '{}';
    return Map<String, String>.from(jsonDecode(raw));
  }

  // ──────────────────────── КОНТЕКСТ ДЛЯ GPT ────────────────────────

  /// Формирует блок памяти для системного промпта
  Future<String> buildMemoryContext() async {
    final people = await _loadPeople();
    final facts  = await getAllFacts();

    final buf = StringBuffer();

    if (facts.isNotEmpty) {
      buf.writeln('== Факты о пользователе ==');
      facts.forEach((k, v) => buf.writeln('• $k: $v'));
    }

    if (people.isNotEmpty) {
      buf.writeln('== Люди которых знает пользователь ==');
      people.forEach((_, p) {
        final rel   = p['relation'] != null ? ' (${p['relation']})' : '';
        final phone = p['phone']    != null ? ', тел: ${p['phone']}' : '';
        final notes = p['notes']    != null ? ', заметка: ${p['notes']}' : '';
        buf.writeln('• ${p['name']}$rel$phone$notes');
      });
    }

    return buf.toString().trim();
  }

  // ──────────────────────── ПАРСИНГ КОМАНД ────────────────────────

  /// Пытается распознать команду "запомни что Богдан — мой друг" и сохранить
  /// Возвращает true если команда распознана
  Future<bool> tryParseMemoryCommand(String text) async {
    final t = text.toLowerCase().trim();

    // "запомни что [имя] это/— [отношение/факт]"
    final personRegex = RegExp(
      r'запомни\s+(?:что\s+)?([а-яёa-z]+)\s+(?:это|—|-|является|мой|моя|мои|мое|мою)\s+(.+)',
      caseSensitive: false,
    );
    final m = personRegex.firstMatch(t);
    if (m != null) {
      final name = _capitalize(m.group(1)!.trim());
      final rel  = m.group(2)!.trim();
      await savePerson(name, relation: rel);
      return true;
    }

    // "запомни: [факт]" или "запомни [факт]"
    if (t.startsWith('запомни') && !t.contains(RegExp(r'[а-яё]+ (?:это|—|мой|моя)'))) {
      final fact = t.replaceFirst(RegExp(r'^запомни[:\s]*'), '').trim();
      if (fact.isNotEmpty) {
        await saveFact('заметка_${DateTime.now().millisecondsSinceEpoch}', fact);
        return true;
      }
    }

    return false;
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ──────────────────────── INTERNAL ────────────────────────

  Future<Map<String, Map<String, dynamic>>> _loadPeople() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPeople) ?? '{}';
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
  }

  Future<void> _savePeople(Map<String, Map<String, dynamic>> people) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPeople, jsonEncode(people));
  }
}
