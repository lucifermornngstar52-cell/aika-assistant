import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ShoplistService — голосовой список покупок + список дел.
/// Вдохновлено vasisualy/skills/shoplist.py и todolist.py (MIT).
/// Данные сохраняются в SharedPreferences — переживают перезапуск.
///
/// Команды (шоплист):
///   "добавь в список покупок молоко"
///   "покажи список покупок"
///   "очисти список покупок"
///   "что купить"
///
/// Команды (туду):
///   "добавь в список дел позвонить врачу"
///   "покажи список дел"
///   "очисти список дел"
///   "что нужно сделать"
class ShoplistService {
  static final ShoplistService _i = ShoplistService._();
  factory ShoplistService() => _i;
  ShoplistService._();

  static const _keyShop = 'aivora_shoplist_v1';
  static const _keyTodo = 'aivora_todolist_v1';

  // ─────────────────── SHOPLIST ───────────────────

  Future<List<String>> getShoplist() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyShop) ?? [];
  }

  Future<void> addToShoplist(String item) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyShop) ?? [];
    list.add(item.trim());
    await prefs.setStringList(_keyShop, list);
  }

  Future<void> clearShoplist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyShop);
  }

  // ─────────────────── TODOLIST ───────────────────

  Future<List<String>> getTodolist() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyTodo) ?? [];
  }

  Future<void> addToTodolist(String item) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyTodo) ?? [];
    list.add(item.trim());
    await prefs.setStringList(_keyTodo, list);
  }

  Future<void> clearTodolist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyTodo);
  }

  // ─────────────────── ГОЛОСОВОЙ ПАРСЕР ───────────────────

  Future<String?> parseCommand(String input) async {
    final t = input.toLowerCase().trim();

    // ── ШОПЛИСТ ──
    for (final trigger in [
      'добавь в список покупок ', 'добавить в список покупок ',
      'добавь в мой список покупок ', 'купи ', 'купить '
    ]) {
      if (t.contains(trigger)) {
        final item = _extractAfter(input, trigger);
        if (item.isNotEmpty) {
          await addToShoplist(item);
          return 'Добавила "$item" в список покупок 🛒';
        }
      }
    }

    if (_matches(t, ['покажи список покупок', 'что купить', 'список покупок',
                      'что нужно купить', 'мой список покупок'])) {
      final list = await getShoplist();
      if (list.isEmpty) return 'Список покупок пуст.';
      return 'Список покупок:\n${list.asMap().entries.map((e) => '${e.key+1}. ${e.value}').join('\n')}';
    }

    if (_matches(t, ['очисти список покупок', 'удали список покупок', 'очистить список покупок'])) {
      await clearShoplist();
      return 'Список покупок очищен ✅';
    }

    // ── ТУДУ ──
    for (final trigger in [
      'добавь в список дел ', 'добавить в список дел ',
      'добавь в мой список дел ', 'запиши в дела ', 'нужно сделать '
    ]) {
      if (t.contains(trigger)) {
        final item = _extractAfter(input, trigger);
        if (item.isNotEmpty) {
          await addToTodolist(item);
          return 'Добавила "$item" в список дел ✅';
        }
      }
    }

    if (_matches(t, ['покажи список дел', 'что нужно сделать', 'список дел',
                      'мои дела', 'покажи дела'])) {
      final list = await getTodolist();
      if (list.isEmpty) return 'Список дел пуст.';
      return 'Список дел:\n${list.asMap().entries.map((e) => '${e.key+1}. ${e.value}').join('\n')}';
    }

    if (_matches(t, ['очисти список дел', 'удали список дел', 'очистить список дел'])) {
      await clearTodolist();
      return 'Список дел очищен ✅';
    }

    return null;
  }

  String _extractAfter(String text, String trigger) {
    final idx = text.toLowerCase().indexOf(trigger.toLowerCase().trim());
    if (idx == -1) return '';
    return text.substring(idx + trigger.length).trim();
  }

  bool _matches(String text, List<String> triggers) =>
      triggers.any((tr) => text.contains(tr));
}
