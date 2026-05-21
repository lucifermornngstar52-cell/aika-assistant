import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CustomShortcutsService {
  static const _key = 'custom_shortcuts';

  Future<Map<String, String>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? '{}';
    return Map<String, String>.from(json.decode(raw));
  }

  Future<void> save(String trigger, String action) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAll();
    all[trigger.toLowerCase().trim()] = action;
    await prefs.setString(_key, json.encode(all));
  }

  Future<void> remove(String trigger) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAll();
    all.remove(trigger.toLowerCase().trim());
    await prefs.setString(_key, json.encode(all));
  }

  Future<String?> tryAddShortcut(String text) async {
    // Pattern: "добавь команду: скажу X — сделай Y"
    final addMatch = RegExp(
      r'(?:добавь|создай|запомни)\s+команд[уыа]',
      caseSensitive: false,
    ).hasMatch(text);

    if (!addMatch) return null;

    // Find trigger between quotes
    final triggerMatch = RegExp(r"['\u2018\u2019\u201c\u201d]([^'\"]+)['\u2018\u2019\u201c\u201d]").firstMatch(text);
    if (triggerMatch == null) return null;

    final dashMatch = RegExp(r'[—\-\u2013]\s*(.+)$').firstMatch(text);
    if (dashMatch == null) return null;

    final trigger = triggerMatch.group(1)!.trim();
    final action = dashMatch.group(1)!.trim();

    await save(trigger, action);
    return 'Команда добавлена!\n\nФраза: "$trigger"\nДействие: $action\n\nТеперь просто скажи "$trigger"!';
  }

  Future<String> listShortcuts() async {
    final all = await getAll();
    if (all.isEmpty) {
      return 'У тебя пока нет кастомных команд.\n\nДобавь так:\n"Добавь команду: скажу домой — открой карты"';
    }
    final buf = StringBuffer('Твои команды:\n\n');
    all.forEach((trigger, action) {
      buf.writeln('"$trigger" → $action');
    });
    return buf.toString().trim();
  }

  Future<String?> tryHandle(String text) async {
    final t = text.toLowerCase();

    if (t.contains('мои команды') || t.contains('список команд') || t.contains('все команды')) {
      return await listShortcuts();
    }

    final addResult = await tryAddShortcut(text);
    if (addResult != null) return addResult;

    final delMatch = RegExp(r'удали команду[:\s]+(.+)$', caseSensitive: false).firstMatch(text);
    if (delMatch != null) {
      final trigger = delMatch.group(1)!.trim().toLowerCase()
          .replaceAll(RegExp(r"['\u2018\u2019\u201c\u201d]"), '');
      await remove(trigger);
      return 'Команда "$trigger" удалена.';
    }

    // Match existing shortcuts
    final all = await getAll();
    final lower = text.toLowerCase().trim();
    for (final entry in all.entries) {
      if (lower.contains(entry.key) || lower == entry.key) {
        return 'Выполняю: ${entry.value}';
      }
    }

    return null;
  }
}
