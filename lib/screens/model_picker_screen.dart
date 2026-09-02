import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_theme.dart';
import '../widgets/live2d_widget.dart';
import '../services/overlay_service.dart';

/// Встроенные Live2D модели
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
  String _mode = 'live2d';
  String _selectedId = 'natori';
  String? _customModelPath;
  String _previewState = 'idle';
  bool _loading = false;
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
      _mode = prefs.getString('overlay_mode') ?? 'live2d';
      _selectedId = prefs.getString('live2d_model_id') ?? 'natori';
      _customModelPath = prefs.getString('custom_model_path');
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('overlay_mode', 'live2d');
    await prefs.setString('live2d_model_id', _selectedId);
    if (_customModelPath != null && _selectedId == 'custom') {
      await prefs.setString('custom_model_path', _customModelPath!);
    }
  }

  Future<void> _pickCustomModel() async {
    setState(() => _loading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Выбери .model3.json файл',
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (path.endsWith('model3.json') || path.endsWith('model.json')) {
          setState(() { _customModelPath = path; _selectedId = 'custom'; });
          await _save();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Модель загружена: ${path.split("/").last}"),
              backgroundColor: Colors.green.withOpacity(0.8),
              behavior: SnackBarBehavior.floating,
            ));
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Нужен файл .model3.json'),
              backgroundColor: Colors.red,
            ));
          }
        }
      }
    } catch (e) { debugPrint("FilePicker error: $e"); }
    setState(() => _loading = false);
  }

      }
    } catch (e) { debugPrint('FilePicker 3D error: $e'); }
    setState(() => _loading = false);
  }

  Future<void> _applyAndClose() async {
    await _save();
      await _overlaySvc.switchModel(path);
    } else {
      String path;
      if (_selectedId == 'custom' && _customModelPath != null) {
        path = _customModelPath!;
      } else {
        final model = _builtinLive2D.firstWhere(
          (m) => m.id == _selectedId,
          orElse: () => _builtinLive2D.first,
        );
        path = model.assetPath;
      }
      await _overlaySvc.switchModel(path);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: AikaTheme.surface,
        title: Text('МОДЕЛЬ ПЕРСОНАЖА',
            style: TextStyle(color: AikaTheme.neonBlue, fontWeight: FontWeight.bold, letterSpacing: 2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white54),
            onPressed: _showHelpDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Заголовок ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AikaTheme.surface,
            child: Row(
              children: [
                                const SizedBox(width: 10),
                              ],
            ),
          ),
          // ── Превью ──────────────────────────────────────────────────
          Container(
            height: 260,
            color: Colors.black,
            child: _buildPreview(),
          ),
          // ── Переключатель состояний ───────────────────────────────
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
                    selectedColor: AikaTheme.neonBlue.withOpacity(0.3),
                    backgroundColor: AikaTheme.surface,
                    labelStyle: TextStyle(
                      color: _previewState == s ? AikaTheme.neonBlue : Colors.white70,
                    ),
                    side: BorderSide(
                      color: _previewState == s ? AikaTheme.neonBlue : Colors.white24,
                    ),
                  ),
                )).toList(),
              ),
            ),
          ),
          // ── Список моделей ─────────────────────────────────────────
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
        backgroundColor: AikaTheme.neonBlue.withOpacity(0.2),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.check_rounded),
        label: const Text('Применить'),
      ),
    );
  }


  Widget _buildPreview() {
    if (_mode == '3d') {
      return Model3DWidget(
        width: double.infinity,
        height: 260,
        state: _previewState,
        modelAsset: _selected3DId == 'custom' && _custom3DPath != null
            ? null : (_builtin3D.firstWhere(
                (m) => m.id == _selected3DId,
                orElse: () => _builtin3D.first,
              )).assetPath,
      );
    }
    final path = _selectedId == 'custom' && _customModelPath != null
        ? _customModelPath! : (_builtinLive2D.firstWhere(
            (m) => m.id == _selectedId,
            orElse: () => _builtinLive2D.first,
          )).assetPath;
    return Live2DWidget(
      width: double.infinity,
      height: 260,
      state: _previewState,
      builtinModelAsset: _selectedId == 'custom' ? null : path,
      customModelPath: _selectedId == 'custom' ? path : null,
    );
  }

  List<Widget> _buildLive2DList() {
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('LIVE2D МОДЕЛИ',
            style: TextStyle(color: AikaTheme.neonBlue, fontSize: 12,
                fontWeight: FontWeight.bold, letterSpacing: 2)),
      ),
      ..._builtinLive2D.map((m) => _buildModelCard(
        id: m.id, name: m.name, emoji: m.emoji, desc: 'Live2D • встроенная',
        onTap: () async { setState(() => _selectedId = m.id); await _save(); },
      )),
      const SizedBox(height: 8),
      Divider(color: Colors.white12),
      const SizedBox(height: 8),
      _buildAddCard('Добавить .model3.json', Icons.face, _pickCustomModel),
      if (_customModelPath != null) ...[
        const SizedBox(height: 8),
        _buildModelCard(
          id: 'custom',
          name: _customModelPath!.split('/').last.replaceAll('.model3.json', ''),
          emoji: '📦', desc: 'Live2D • пользовательская',
          onTap: () async { setState(() => _selectedId = 'custom'); await _save(); },
        ),
      ],
      const SizedBox(height: 80),
    ];
  }


  Widget _buildModelCard({
    required String id, required String name, required String emoji,
    required String desc, required VoidCallback onTap, Color accentColor = Colors.blue,
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

  Widget _buildAddCard(String label, IconData icon, VoidCallback onTap) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AikaTheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: const Center(child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyan),
        )),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white54, size: 20),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: Colors.white54, fontSize: 14)),
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
        title: Text('Справка', style: TextStyle(color: AikaTheme.neonBlue)),
        content: const Text(
          'Live2D — 2D аниме-модели с мимикой и физикой.\n'
          'Tsumire: 24k полигонов, 9 анимаций (idle, walk, run, dance, agree, headShake, sad, sneak, TPose).\n\n'
          'Можно загружать свои модели (.model3.json для Live2D).',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: AikaTheme.neonBlue)),
          ),
        ],
      ),
    );
  }
}
