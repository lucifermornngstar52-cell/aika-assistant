import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_theme.dart';
import '../widgets/live2d_widget.dart';
import '../widgets/model3d_widget.dart';
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
  BuiltinModel(id: 'mark',   name: 'Mark',   assetPath: 'models/Mark/Mark.model3.json',     emoji: '🧑'),
  BuiltinModel(id: 'rice',   name: 'Rice',   assetPath: 'models/Rice/Rice.model3.json',     emoji: '🌾'),
  BuiltinModel(id: 'wanko',  name: 'Wanko',  assetPath: 'models/Wanko/Wanko.model3.json',  emoji: '🐶'),
];

/// Встроенные 3D модели
class Builtin3DModel {
  final String id;
  final String name;
  final String assetPath;
  final String emoji;
  final int animCount;
  Builtin3DModel({required this.id, required this.name, required this.assetPath, required this.emoji, this.animCount = 0});
}

final _builtin3D = [
  Builtin3DModel(id: 'tsumire', name: 'Tsumire', assetPath: 'models/tsumire.glb', emoji: '🎀', animCount: 9),
  Builtin3DModel(id: 'aika_model', name: 'Aika', assetPath: 'models/aika_model.glb', emoji: '🤖', animCount: 9),
  Builtin3DModel(id: 'michelle', name: 'Michelle', assetPath: 'models/michelle.glb', emoji: '💃', animCount: 2),
  Builtin3DModel(id: 'anime_girl', name: 'Anime Girl', assetPath: 'models/anime_girl.glb', emoji: '👧', animCount: 0),
  Builtin3DModel(id: 'robot', name: 'Robot', assetPath: 'models/robot.glb', emoji: '🦾', animCount: 0),
  Builtin3DModel(id: 'soldier', name: 'Soldier', assetPath: 'models/soldier.glb', emoji: '🪖', animCount: 0),
];

class ModelPickerScreen extends StatefulWidget {
  const ModelPickerScreen({super.key});
  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  String _mode = 'live2d'; // 'live2d' or '3d'
  String _selectedId = 'natori';
  String _selected3DId = 'tsumire';
  String? _customModelPath;
  String? _custom3DPath;
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
      _selected3DId = prefs.getString('model3d_id') ?? 'tsumire';
      _customModelPath = prefs.getString('custom_model_path');
      _custom3DPath = prefs.getString('custom_3d_path');
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('overlay_mode', _mode);
    if (_mode == 'live2d') {
      await prefs.setString('live2d_model_id', _selectedId);
      if (_customModelPath != null && _selectedId == 'custom') {
        await prefs.setString('custom_model_path', _customModelPath!);
      }
    } else {
      await prefs.setString('model3d_id', _selected3DId);
      if (_custom3DPath != null && _selected3DId == 'custom') {
        await prefs.setString('custom_3d_path', _custom3DPath!);
      }
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
              content: Text('Модель загружена: \${path.split('/').last}'),
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
    } catch (e) { debugPrint('FilePicker error: \$e'); }
    setState(() => _loading = false);
  }

  Future<void> _pickCustom3D() async {
    setState(() => _loading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['glb', 'gltf'],
        dialogTitle: 'Выбери .glb файл',
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        setState(() { _custom3DPath = path; _selected3DId = 'custom'; });
        await _save();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('3D модель загружена: ${path.split('/').last}'),
            backgroundColor: Colors.cyan.withOpacity(0.8),
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) { debugPrint('FilePicker 3D error: $e'); }
    setState(() => _loading = false);
  }

  Future<void> _applyAndClose() async {
    await _save();
    if (_mode == '3d') {
      final model = _builtin3D.firstWhere(
        (m) => m.id == _selected3DId,
        orElse: () => _builtin3D.first,
      );
      final path = _selected3DId == 'custom' && _custom3DPath != null
          ? _custom3DPath! : model.assetPath;
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
          // ── Toggle: Live2D / 3D ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AikaTheme.surface,
            child: Row(
              children: [
                _buildModeToggle('Live2D', 'live2d', Icons.face_retouching_natural),
                const SizedBox(width: 10),
                _buildModeToggle('3D', '3d', Icons.view_in_ar),
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
              children: _mode == 'live2d' ? _buildLive2DList() : _build3DList(),
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

  Widget _buildModeToggle(String label, String mode, IconData icon) {
    final isSelected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AikaTheme.neonBlue.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AikaTheme.neonBlue : Colors.white12,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18,
                color: isSelected ? AikaTheme.neonBlue : Colors.white54),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                color: isSelected ? AikaTheme.neonBlue : Colors.white54,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              )),
            ],
          ),
        ),
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

  List<Widget> _build3DList() {
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('3D МОДЕЛИ (GLB)',
            style: TextStyle(color: Colors.cyan, fontSize: 12,
                fontWeight: FontWeight.bold, letterSpacing: 2)),
      ),
      ..._builtin3D.map((m) => _buildModelCard(
        id: m.id, name: m.name, emoji: m.emoji,
        desc: m.animCount > 0 ? '3D • ${m.animCount} анимаций' : '3D • без анимаций',
        accentColor: Colors.cyan,
        onTap: () async { setState(() => _selected3DId = m.id); await _save(); },
      )),
      const SizedBox(height: 8),
      Divider(color: Colors.white12),
      const SizedBox(height: 8),
      _buildAddCard('Добавить .glb файл', Icons.view_in_ar, _pickCustom3D),
      if (_custom3DPath != null) ...[
        const SizedBox(height: 8),
        _buildModelCard(
          id: 'custom',
          name: _custom3DPath!.split('/').last,
          emoji: '📦', desc: '3D • пользовательская',
          accentColor: Colors.cyan,
          onTap: () async { setState(() => _selected3DId = 'custom'); await _save(); },
        ),
      ],
      const SizedBox(height: 80),
    ];
  }

  Widget _buildModelCard({
    required String id, required String name, required String emoji,
    required String desc, required VoidCallback onTap, Color accentColor = Colors.blue,
  }) {
    final isSelected = _mode == 'live2d'
        ? _selectedId == id : _selected3DId == id;
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
          'Live2D — 2D аниме-модели с мимикой и физикой.\n\n'
          '3D (GLB) — полноценные 3D-модели со скелетной анимацией.\n'
          'Tsumire: 24k полигонов, 9 анимаций (idle, walk, run, dance, agree, headShake, sad, sneak, TPose).\n\n'
          'Можно загружать свои модели (.model3.json для Live2D, .glb для 3D).',
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
