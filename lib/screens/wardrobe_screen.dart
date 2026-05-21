import 'package:flutter/material.dart';
import '../services/wardrobe_service.dart';
import '../theme/app_theme.dart';

class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key});
  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  String _selectedCategory = 'all';
  final List<String> _categories = ['all', 'dress', 'top', 'accessory'];

  final Map<String, String> _categoryNames = {
    'all': 'Все',
    'dress': 'Платья',
    'top': 'Верх',
    'accessory': 'Аксессуары',
  };

  @override
  void initState() {
    super.initState();
    WardrobeService.load();
  }

  List<OutfitItem> get _filteredItems {
    if (_selectedCategory == 'all') return WardrobeService.allItems;
    return WardrobeService.getByCategory(_selectedCategory);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('ГАРДЕРОБ', style: TextStyle(
          color: AikaTheme.neonBlue, fontSize: 16,
          fontWeight: FontWeight.bold, letterSpacing: 3,
        )),
        centerTitle: true,
        iconTheme: IconThemeData(color: AikaTheme.neonBlue),
      ),
      body: Column(
        children: [
          // Chibi preview
          Container(
            height: 200,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AikaTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.2)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Base chibi
                Image.asset('assets/images/aika_chibi.png', height: 160),
                // Equipped items overlay
                ...['dress', 'top', 'accessory'].map((cat) {
                  final itemId = WardrobeService.getEquipped(cat);
                  if (itemId == null) return const SizedBox.shrink();
                  final item = WardrobeService.allItems.firstWhere(
                    (i) => i.id == itemId, orElse: () => WardrobeService.allItems.first);
                  // Try to load asset, silently fail if not exists
                  return Positioned.fill(
                    child: Image.asset(item.assetPath, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  );
                }).toList(),
              ],
            ),
          ),

          // Category filter
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (_, i) {
                final cat = _categories[i];
                final selected = cat == _selectedCategory;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? AikaTheme.neonBlue.withOpacity(0.3) : AikaTheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? AikaTheme.neonBlue : AikaTheme.neonBlue.withOpacity(0.2)),
                    ),
                    child: Text(_categoryNames[cat]!, style: TextStyle(
                      color: selected ? AikaTheme.neonBlue : Colors.white54,
                      fontSize: 13, fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    )),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Items grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: _filteredItems.length,
              itemBuilder: (_, i) {
                final item = _filteredItems[i];
                final owned = WardrobeService.isOwned(item.id);
                final equipped = WardrobeService.getEquipped(item.category) == item.id;
                return GestureDetector(
                  onTap: () async {
                    if (!owned) {
                      _showBuyDialog(item);
                      return;
                    }
                    await WardrobeService.equip(item.id);
                    setState(() {});
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: AikaTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: equipped
                          ? AikaTheme.neonBlue
                          : AikaTheme.neonBlue.withOpacity(0.15),
                        width: equipped ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Item image placeholder
                        Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            color: AikaTheme.neonBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Image.asset(
                            item.assetPath, fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.checkroom_rounded,
                              color: AikaTheme.neonBlue.withOpacity(0.5), size: 40,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(item.name, style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center),
                        const SizedBox(height: 4),
                        if (!owned)
                          Text('${item.priceKzt} ₸',
                            style: TextStyle(color: AikaTheme.neonBlue, fontSize: 11))
                        else if (equipped)
                          Text('✓ Надето', style: TextStyle(color: AikaTheme.neonBlue, fontSize: 11))
                        else
                          Text('Есть', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showBuyDialog(OutfitItem item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AikaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(item.name, style: TextStyle(color: AikaTheme.neonBlue)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Цена: ${item.priceKzt} ₸',
              style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Для покупки напишите в Telegram боту @aikabot',
              style: TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Закрыть', style: TextStyle(color: AikaTheme.neonBlue)),
          ),
        ],
      ),
    );
  }
}
