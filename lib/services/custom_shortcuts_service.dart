import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Кастомные голосовые макросы
/// Пример: "если скажу 'домой' — открой 2GIS с маршрутом домой"
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

  Future<void> delete(String trigger) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAll();
    all.remove(trigger.toLowerCase().trim());
    await prefs.setString(_key, json.encode(all));
  }

  /// Попытка создать shortcut из фразы
  /// "добавь команду: скажу 'домой' — открой карты"
  Future<String?> tryAddShortcut(String text) async {
    final addMatch = RegExp(
      r"(?:добавь|создай|запомни)\s+команд[уыа][:\s]+(?:скажу|если скажу|когда скажу)?\s*['\"](.+?)['\"]\s*[—\-–]\s*(.+)",
      caseSensitive: false,
    ).firstMatch(text);

    if (addMatch != null) {
      final trigger = addMatch.group(1)!.trim();
      final action = addMatch.group(2)!.trim();
      await save(trigger, action);
      return '✅ Команда добавлена!\n\n🗣 Фраза: "$trigger"\n⚡ Действие: $action\n\nТеперь просто скажи "$trigger" и я всё сделаю!';
    }
    return null;
  }

  /// Показать все команды
  Future<String> listShortcuts() async {
    final all = await getAll();
    if (all.isEmpty) {
      return '⚡ У тебя пока нет кастомных команд.\n\nДобавь так:\n"Добавь команду: скажу \'домой\' — открой карты"';
    }
    final buf = StringBuffer('⚡ Твои команды:\n\n');
    all.forEach((trigger, action) {
      buf.writeln('🗣 "$trigger" → $action');
    });
    return buf.toString().trim();
  }

  Future<String?> tryHandle(String text) async {
    final t = text.toLowerCase();

    // Показать список
    if (t.contains('мои команды') || t.contains('список команд') || t.contains('все команды')) {
      return await listShortcuts();
    }

    // Добавить команду
    final addResult = await tryAddShortcut(text);
    if (addResult != null) return addResult;

    // Удалить команду
    final delMatch = RegExp(r"удали команду[:\s]+['\"]?(.+?)['\"]?$", caseSensitive: false).firstMatch(text);
    if (delMatch != null) {
      final trigger = delMatch.group(1)!.trim().toLowerCase();
      await delete(trigger);
      return '🗑 Команда "$trigger" удалена.';
    }

    // Проверить совпадение с существующими shortcuts
    final all = await getAll();
    final lower = text.toLowerCase().trim();
    for (final entry in all.entries) {
      if (lower.contains(entry.key) || lower == entry.key) {
        return '⚡ Выполняю: ${entry.value}';
      }
    }

    return null;
  }
}
