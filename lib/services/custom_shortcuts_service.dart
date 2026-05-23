import 'app_launcher_service.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CustomShortcutsService {
  static const _key = 'custom_shortcuts';

  Future<Map<String, String>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    // Load text-action shortcuts
    final raw = prefs.getString(_key) ?? '{}';
    final textShortcuts = Map<String, String>.from(json.decode(raw));
    // Also load app-launch commands from AppLauncher storage (unified)
    final appRaw = prefs.getString('custom_app_commands') ?? '{}';
    final appCommands = Map<String, String>.from(json.decode(appRaw));
    // Merge: text shortcuts + app commands, text shortcuts take priority
    return {...appCommands, ...textShortcuts};
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
    final hasAddKeyword = RegExp(
      r'(?:добавь|создай|запомни)\s+команд',
      caseSensitive: false,
    ).hasMatch(text);

    if (!hasAddKeyword) return null;

    // Find trigger in single or double quotes
    final triggerMatch = RegExp(r'"([^"]+)"|' + "'([^']+)'").firstMatch(text);
    if (triggerMatch == null) return null;

    final trigger = (triggerMatch.group(1) ?? triggerMatch.group(2) ?? '').trim();
    if (trigger.isEmpty) return null;

    // Find action after dash
    final dashIndex = text.lastIndexOf('—');
    final altDash = text.lastIndexOf(' - ');
    final idx = dashIndex >= 0 ? dashIndex : altDash;
    if (idx < 0) return null;

    final action = text.substring(idx + 1).trim();
    if (action.isEmpty) return null;

    await save(trigger, action);
    return 'Команда добавлена!\n\nФраза: "$trigger"\nДействие: $action\n\nПросто скажи "$trigger" когда нужно!';
  }

  Future<String> listShortcuts() async {
    final all = await getAll();
    if (all.isEmpty) {
      return 'Пока нет кастомных команд.\n\nДобавь так:\n"Добавь команду: скажу "домой" — открой карты"';
    }
    final buf = StringBuffer('Твои команды:\n\n');
    all.forEach((trigger, action) {
      buf.writeln('"$trigger" — $action');
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
      final raw = delMatch.group(1)!.trim();
      final trigger = raw.replaceAll('"', '').replaceAll("'", '').toLowerCase();
      await remove(trigger);
      return 'Команда "$trigger" удалена.';
    }

    // Match existing shortcuts
    final all = await getAll();
    final lower = text.toLowerCase().trim();
    for (final entry in all.entries) {
      if (lower == entry.key || lower.contains(entry.key)) {
        final action = entry.value;
        // If action looks like an app package name — launch it
        if (action.contains('.') && !action.contains(' ') && action.length > 5) {
          final result = await AppLauncherService.launchPackage(action);
          return result;
        }
        return 'Выполняю: $action';
      }
    }

    return null;
  }
}
