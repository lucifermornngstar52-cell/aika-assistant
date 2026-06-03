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

final _builtinModels = [
  BuiltinModel(id: 'natori', name: 'Natori',  assetPath: 'models/Natori/Natori.model3.json', emoji: '🌟'),
  BuiltinModel(id: 'ren',    name: 'Ren',     assetPath: 'models/Ren/Ren.model3.json',       emoji: '🔥'),
  BuiltinModel(id: 'hiyori', name: 'Hiyori',  assetPath: 'models/Hiyori/Hiyori.model3.json', emoji: '🌸'),
  BuiltinModel(id: 'haru',   name: 'Haru',    assetPath: 'models/Haru/Haru.model3.json',     emoji: '⚡'),
];

class ModelPickerScreen extends StatefulWidget {
  const ModelPickerScreen({super.key});
  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  String _selectedId    = 'natori';
  String? _customModelPath;
  String _previewState  = 'idle';
  bool _loading         = false;
  final _overlaySvc     = OverlayService();

  final _states = ['idle', 'listening', 'thinking', 'greeting', 'dance'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedId      = prefs.getString('live2d_model_id') ?? 'natori';
      _customModelPath = prefs.getString('custom_model_path');
    });
  }

  Future<void> _save(String id, {String? customPath}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('live2d_model_id', id);
    if (customPath != null) {
      await prefs.setString('custom_model_path', customPath);
    } else if (id != 'custom') {
      await prefs.remove('custom_model_path');
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
          await _save('custom', customPath: path);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Модель загружена: ${path.split('/').last}'),
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
    } catch (e) { debugPrint('FilePicker error: $e'); }
    setState(() => _loading = false);
  }

  Future<void> _applyAndClose() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('overlay_mode'); // всегда live2d
    await prefs.setString('overlay_mode', 'live2d');

    String path;
    if (_selectedId == 'custom' && _customModelPath != null) {
      path = _customModelPath!;
    } else {
      final model = _builtinModels.firstWhere(
        (m) => m.id == _selectedId,
        orElse: () => _builtinModels.first,
      );
      path = model.assetPath;
    }
    await _overlaySvc.switchModel(path);
    if (mounted) Navigator.pop(context);
  }

  String get _currentPreviewPath {
    if (_selectedId == 'custom' && _customModelPath != null) {
      return _customModelPath!;
    }
    final model = _builtinModels.firstWhere(
      (m) => m.id == _selectedId,
      orElse: () => _builtinModels.first,
    );
    return model.assetPath;
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
          // ── Превью Live2D ──────────────────────────────────────────
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
              children: [
                // ── Live2D встроенные ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('LIVE2D МОДЕЛИ',
                      style: TextStyle(color: AikaTheme.neonBlue, fontSize: 12,
                          fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),
                ..._builtinModels.map((m) => _buildModelCard(
                  id: m.id, name: m.name, emoji: m.emoji, desc: 'Live2D • встроенная',
                  onTap: () async {
                    setState(() => _selectedId = m.id);
                    await _save(m.id);
                  },
                )),
                const SizedBox(height: 8),
                Divider(color: Colors.white12),
                const SizedBox(height: 8),
                // ── Кастомная модель ─────────────────────────────
                _buildAddCustomCard(),
                if (_customModelPath != null) ...[
                  const SizedBox(height: 8),
                  _buildModelCard(
                    id: 'custom',
                    name: _customModelPath!.split('/').last.replaceAll('.model3.json', ''),
                    emoji: '📦',
                    desc: 'Live2D • пользовательская',
                    onTap: () async {
                      setState(() => _selectedId = 'custom');
                      await _save('custom', customPath: _customModelPath);
                    },
                  ),
                ],
                const SizedBox(height: 80),
              ],
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
    try {
      return Live2DWidget(
        modelPath: _currentPreviewPath,
        state: _previewState,
        width: double.infinity,
        height: 260,
      );
    } catch (_) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, color: AikaTheme.neonBlue, size: 48),
            const SizedBox(height: 8),
            Text(_selectedId == 'custom' ? 'Кастомная модель' : _selectedId,
                style: TextStyle(color: AikaTheme.neonBlue, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }
  }

  Widget _buildModelCard({
    required String id,
    required String name,
    required String emoji,
    required String desc,
    required VoidCallback onTap,
  }) {
    final isSelected = _selectedId == id;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AikaTheme.neonBlue.withOpacity(0.1) : AikaTheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AikaTheme.neonBlue : Colors.white12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AikaTheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(desc, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: AikaTheme.neonBlue, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildAddCustomCard() {
    return GestureDetector(
      onTap: _loading ? null : _pickCustomModel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AikaTheme.surface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12, style: BorderStyle.solid),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: AikaTheme.surface, borderRadius: BorderRadius.circular(12)),
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: AikaTheme.neonBlue),
                    )
                  : Icon(Icons.add_rounded, color: AikaTheme.neonBlue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Добавить модель', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  Text('Выбери .model3.json файл', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.folder_open_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AikaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Как добавить модель', style: TextStyle(color: AikaTheme.neonBlue, fontWeight: FontWeight.bold)),
        content: const Text(
          '1. Скачай Live2D модель в формате .model3.json\n\n'
          '2. Распакуй все файлы модели в одну папку на телефоне\n\n'
          '3. Нажми "Добавить модель" и выбери .model3.json файл\n\n'
          '4. Нажми "Применить" — модель появится в оверлее',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AikaTheme.neonBlue.withOpacity(0.2),
              side: BorderSide(color: AikaTheme.neonBlue),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
