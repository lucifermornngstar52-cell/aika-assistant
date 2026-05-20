import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Долгосрочная память Айки о людях и фактах.
class PeopleMemoryService {
  static const _keyPeople = 'aika_people_memory';
  static const _keyFacts  = 'aika_facts_memory';

  // ──────────────── ЛЮДИ ────────────────

  Future<void> savePerson(String name, {
    String? relation,
    String? phone,
    String? notes,
  }) async {
    final people = await _loadPeople();
    final key = name.toLowerCase().trim();
    final existing = people[key] ?? {};
    people[key] = {
      ...existing,
      'name': name.trim(),
      if (relation != null) 'relation': relation,
      if (phone    != null) 'phone': phone,
      if (notes    != null) 'notes': notes,
      'updated': DateTime.now().toIso8601String(),
    };
    await _savePeople(people);
  }

  Future<Map<String, dynamic>?> findPerson(String query) async {
    final people = await _loadPeople();
    final q = query.toLowerCase().trim();
    if (people.containsKey(q)) return people[q];
    for (final entry in people.entries) {
      if (entry.key.contains(q) || q.contains(entry.key)) return entry.value;
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

  // ──────────────── ФАКТЫ ────────────────

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

  // ──────────────── КОНТЕКСТ ДЛЯ GPT ────────────────

  Future<String> buildMemoryContext() async {
    final people = await _loadPeople();
    final facts  = await getAllFacts();
    final buf    = StringBuffer();

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

  // ──────────────── ПАРСИНГ КОМАНД ────────────────

  /// Возвращает true + сохраняет если распознал команду памяти
  Future<bool> tryParseMemoryCommand(String text) async {
    final t = text.toLowerCase().trim();

    // "запомни что Богдан это/— мой друг"
    // "Богдан это мой друг", "Маша это моя сестра"
    final personRegexes = [
      RegExp(r'запомни[,:]?\s+(?:что\s+)?([а-яёa-z][а-яёa-z]*)\s+(?:это|—|-|является)\s+мо[йяеёи]\s+(.+)', caseSensitive: false),
      RegExp(r'запомни[,:]?\s+(?:что\s+)?([а-яёa-z][а-яёa-z]*)\s+(?:это|—|-)\s+(.+)', caseSensitive: false),
      RegExp(r'([а-яёa-z][а-яёa-z]*)\s+(?:это|—)\s+мо[йяеёи]\s+(друг|подруга|брат|сестра|мама|папа|коллега|начальник|парень|девушка|муж|жена)', caseSensitive: false),
    ];

    for (final regex in personRegexes) {
      final m = regex.firstMatch(t);
      if (m != null) {
        final name = _capitalize(m.group(1)!.trim());
        final rel  = m.group(2)!.trim();
        await savePerson(name, relation: rel);
        return true;
      }
    }

    // "запомни телефон Маши: +7..."
    final phoneRegex = RegExp(
      r'запомни\s+(?:номер|телефон)\s+([а-яёa-z]+)[:\s]+(\+?[\d\s\-]+)',
      caseSensitive: false,
    );
    final pm = phoneRegex.firstMatch(t);
    if (pm != null) {
      final name  = _capitalize(pm.group(1)!.trim());
      final phone = pm.group(2)!.trim();
      await savePerson(name, phone: phone);
      return true;
    }

    // "запомни заметку про Богдана: встреча в пятницу"
    final noteRegex = RegExp(
      r'запомни\s+(?:заметку\s+)?про\s+([а-яёa-z]+)[:\s]+(.+)',
      caseSensitive: false,
    );
    final nm = noteRegex.firstMatch(t);
    if (nm != null) {
      final name = _capitalize(nm.group(1)!.trim());
      final note = nm.group(2)!.trim();
      await savePerson(name, notes: note);
      return true;
    }

    // "запомни: [произвольный факт]"
    if (t.startsWith('запомни') && !t.contains(RegExp(r'[а-яё]+ (?:это|—|мой|моя|про)'))) {
      final fact = t.replaceFirst(RegExp(r'^запомни[:\s]*'), '').trim();
      if (fact.isNotEmpty && fact.length > 3) {
        await saveFact('факт_${DateTime.now().millisecondsSinceEpoch}', fact);
        return true;
      }
    }

    // Автоизвлечение: "напомни Богдану что встреча в 6" — сохраняем Богдана
    final mentionRegex = RegExp(
      r'напомни\s+([а-яё][а-яё]+у?|[а-яё][а-яё]+е?)\s+что',
      caseSensitive: false,
    );
    final mm = mentionRegex.firstMatch(t);
    if (mm != null) {
      final name = _capitalize(mm.group(1)!.trim()
          .replaceAll(RegExp(r'[уе]$'), '')); // убираем падеж
      final existing = await findPerson(name);
      if (existing == null) {
        await savePerson(name); // просто запоминаем имя
      }
      // Не возвращаем true — пусть дальше обрабатывается как команда
    }

    return false;
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

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
