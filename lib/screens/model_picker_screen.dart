import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/live2d_widget.dart';
import '../services/overlay_service.dart';

class BuiltinModel {
  final String id;
  final String name;
  final String assetPath;
  final String emoji;
  BuiltinModel({required this.id, required this.name, required this.assetPath, required this.emoji});
}

final _builtinLive2D = [
  BuiltinModel(id: 'natori', name: 'Natori', assetPath: 'models/Natori/Natori.model3.json', emoji: '🌟'),
  BuiltinModel(id: 'hiyori', name: 'Hiyori', assetPath: 'models/Hiyori/Hiyori.model3.json', emoji: '🌸'),
  BuiltinModel(id: 'haru',   name: 'Haru',   assetPath: 'models/Haru/Haru.model3.json',     emoji: '⚡'),
  BuiltinModel(id: 'mao',    name: 'Mao',    assetPath: 'models/Mao/Mao.model3.json',       emoji: '🍵'),
  BuiltinModel(id: 'rice',   name: 'Rice',   assetPath: 'models/Rice/Rice.model3.json',     emoji: '🌾'),
  BuiltinModel(id: 'wanko',  name: 'Wanko',  assetPath: 'models/Wanko/Wanko.model3.json',  emoji: '🐶'),
];

class ModelPickerScreen extends StatefulWidget {
  const ModelPickerScreen({super.key});
  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  String _selectedId = 'natori';
  String _previewState = 'idle';
  final _overlaySvc = OverlayService();

  final _states = ['idle', 'listening', 'thinking', 'greeting', 'dance'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedId = prefs.getString('live2d_model_id') ?? 'natori';
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('overlay_mode', 'live2d');
    await prefs.setString('live2d_model_id', _selectedId);
  }

  Future<void> _applyAndClose() async {
    await _save();
    final model = _builtinLive2D.firstWhere(
      (m) => m.id == _selectedId,
      orElse: () => _builtinLive2D.first,
    );
    final path = model.assetPath;
    await _overlaySvc.switchModel(path);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: AikaTheme.surface,
        title: Text('МОДЕЛЬ ПЕРСОНАЖА',
            style: TextStyle(color: AikaTheme.accent, fontWeight: FontWeight.bold, letterSpacing: 2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white54),
            onPressed: _showHelpDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 260,
            color: Colors.black,
            child: _buildPreview(),
          ),
          Container(
            color: AikaTheme.surface.withOpacity(0.5),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _states.map((s) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s, style: const TextStyle(fontSize: 12)),
                    selected: _previewState == s,
                    onSelected: (_) => setState(() => _previewState = s),
                    selectedColor: AikaTheme.accent.withOpacity(0.3),
                    backgroundColor: AikaTheme.surface,
                    labelStyle: TextStyle(
                      color: _previewState == s ? AikaTheme.accent : Colors.white70,
                    ),
                    side: BorderSide(
                      color: _previewState == s ? AikaTheme.accent : Colors.white24,
                    ),
                  ),
                )).toList(),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: _buildLive2DList(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _applyAndClose,
        backgroundColor: AikaTheme.accent.withOpacity(0.2),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.check_rounded),
        label: const Text('Применить'),
      ),
    );
  }

  Widget _buildPreview() {
    final path = _builtinLive2D.firstWhere(
      (m) => m.id == _selectedId,
      orElse: () => _builtinLive2D.first,
    ).assetPath;
    return Live2DWidget(
      width: double.infinity,
      height: 260,
      state: _previewState,
      builtinModelAsset: path,
    );
  }

  List<Widget> _buildLive2DList() {
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('LIVE2D МОДЕЛИ',
            style: TextStyle(color: AikaTheme.accent, fontSize: 12,
                fontWeight: FontWeight.bold, letterSpacing: 2)),
      ),
      ..._builtinLive2D.map((m) => _buildModelCard(
        id: m.id, name: m.name, emoji: m.emoji, desc: 'Live2D • встроенная',
        onTap: () async { setState(() => _selectedId = m.id); await _save(); },
      )),
      const SizedBox(height: 80),
    ];
  }

  Widget _buildModelCard({
    required String id, required String name, required String emoji,
    required String desc, required VoidCallback onTap, Color accentColor = const Color(0xFFB0B0B0),
  }) {
    final isSelected = _selectedId == id;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withOpacity(0.1) : AikaTheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accentColor : Colors.white12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(desc, style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            Icon(isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? accentColor : Colors.white24, size: 24),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AikaTheme.surface,
        title: Text('Справка', style: TextStyle(color: AikaTheme.accent)),
        content: const Text(
          'Live2D — 2D аниме-модели с мимикой и физикой.\n\n'
          'Доступны только встроенные модели, для которых полностью настроен просмотр.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: AikaTheme.accent)),
          ),
        ],
      ),
    );
  }
}
