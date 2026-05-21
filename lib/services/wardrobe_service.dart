import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OutfitItem {
  final String id;
  final String name;
  final String category; // 'top', 'bottom', 'dress', 'accessory', 'hair'
  final String assetPath;
  final bool isPremium;
  final int priceKzt;

  const OutfitItem({
    required this.id,
    required this.name,
    required this.category,
    required this.assetPath,
    this.isPremium = false,
    this.priceKzt = 0,
  });

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'category': category, 'assetPath': assetPath};
  factory OutfitItem.fromJson(Map<String, dynamic> j) => OutfitItem(
    id: j['id'], name: j['name'], category: j['category'], assetPath: j['assetPath'],
  );
}

class WardrobeService {
  static const _keyOwned    = 'wardrobe_owned';
  static const _keyEquipped = 'wardrobe_equipped';

  // Все доступные предметы гардероба
  static const List<OutfitItem> allItems = [
    // Бесплатные
    OutfitItem(id: 'school_uniform', name: 'Школьная форма', category: 'dress', assetPath: 'assets/wardrobe/school_uniform.png'),
    OutfitItem(id: 'casual_blue',    name: 'Повседневный синий', category: 'top', assetPath: 'assets/wardrobe/casual_blue.png'),
    // Премиум
    OutfitItem(id: 'kimono_sakura',  name: 'Кимоно Сакура', category: 'dress', assetPath: 'assets/wardrobe/kimono_sakura.png', isPremium: true, priceKzt: 500),
    OutfitItem(id: 'battle_armor',   name: 'Боевая броня', category: 'dress', assetPath: 'assets/wardrobe/battle_armor.png', isPremium: true, priceKzt: 800),
    OutfitItem(id: 'maid_outfit',    name: 'Костюм горничной', category: 'dress', assetPath: 'assets/wardrobe/maid_outfit.png', isPremium: true, priceKzt: 600),
    OutfitItem(id: 'cat_ears',       name: 'Кошачьи ушки', category: 'accessory', assetPath: 'assets/wardrobe/cat_ears.png', isPremium: true, priceKzt: 300),
    OutfitItem(id: 'demon_horns',    name: 'Рожки демона', category: 'accessory', assetPath: 'assets/wardrobe/demon_horns.png', isPremium: true, priceKzt: 300),
  ];

  static Set<String> _ownedIds = {'school_uniform', 'casual_blue'};
  static Map<String, String> _equipped = {}; // category -> itemId

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final ownedRaw = prefs.getStringList(_keyOwned);
    if (ownedRaw != null) _ownedIds = ownedRaw.toSet();

    final equippedRaw = prefs.getString(_keyEquipped);
    if (equippedRaw != null) {
      _equipped = Map<String, String>.from(jsonDecode(equippedRaw));
    } else {
      _equipped = {'dress': 'school_uniform'};
    }
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyOwned, _ownedIds.toList());
    await prefs.setString(_keyEquipped, jsonEncode(_equipped));
  }

  static bool isOwned(String id) => _ownedIds.contains(id);

  static String? getEquipped(String category) => _equipped[category];

  static Future<void> equip(String itemId) async {
    final item = allItems.firstWhere((i) => i.id == itemId, orElse: () => throw Exception('Item not found'));
    if (!isOwned(itemId)) return;
    _equipped[item.category] = itemId;
    await save();
  }

  static Future<void> unlock(String itemId) async {
    _ownedIds.add(itemId);
    await save();
  }

  static List<OutfitItem> getByCategory(String category) =>
      allItems.where((i) => i.category == category).toList();

  static List<OutfitItem> get owned =>
      allItems.where((i) => isOwned(i.id)).toList();
}
