import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_theme.dart';
import '../widgets/live2d_widget.dart';

/// Встроенные модели из assets/models/
class BuiltinModel {
  final String id;
  final String name;
  final String assetPath; // путь к model3.json внутри assets
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
  String _selectedId = 'hiyori';
  String? _customModelPath;
  String _previewState = 'idle';
  bool _loading = false;

  final _previewKey = GlobalKey<_Live2DWidgetState2>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedId = prefs.getString('live2d_model_id') ?? 'natori';
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
          setState(() {
            _customModelPath = path;
            _selectedId = 'custom';
          });
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
    } catch (e) {
      debugPrint('FilePicker error: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _pickModelFolder() async {
    // Инструкция как установить кастомную модель
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: const Text('Как установить модель?',
          style: TextStyle(color: Colors.white, fontSize: 16)),
      content: const SingleChildScrollView(
        child: Text(
          '1. Скачай модель с VRoid Hub / Booth / другого сайта\n\n'
          '2. Распакуй архив в папку на телефоне\n\n'
          '3. Нажми "Загрузить модель (.json)"\n\n'
          '4. Выбери файл .model3.json из папки с моделью\n\n'
          'Важно: папка с моделью должна содержать все файлы '
          '(.moc3, текстуры, motions и т.д.) рядом с .model3.json',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Понял', style: TextStyle(color: AikaTheme.neonBlue)),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('МОДЕЛЬ ПЕРСОНАЖА', style: TextStyle(
          color: AikaTheme.neonBlue, fontSize: 15,
          fontWeight: FontWeight.bold, letterSpacing: 3,
        )),
        centerTitle: true,
        iconTheme: IconThemeData(color: AikaTheme.neonBlue),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white54),
            onPressed: _pickModelFolder,
          ),
        ],
      ),
      body: Column(
        children: [
          // Превью модели
          Container(
            height: 280,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black26,
              border: Border(bottom: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.2))),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                _buildPreviewLive2D(),
                // Кнопки анимации
                Positioned(
                  bottom: 8,
                  child: Row(
                    children: ['idle','listening','thinking','greeting','dance'].map((s) =>
                      GestureDetector(
                        onTap: () => setState(() => _previewState = s),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _previewState == s
                                ? AikaTheme.neonBlue.withOpacity(0.3)
                                : Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _previewState == s ? AikaTheme.neonBlue : Colors.white24,
                            ),
                          ),
                          child: Text(s, style: TextStyle(
                            color: _previewState == s ? AikaTheme.neonBlue : Colors.white54,
                            fontSize: 10,
                          )),
                        ),
                      )
                    ).toList(),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Встроенные модели
                  Text('ВСТРОЕННЫЕ МОДЕЛИ',
                    style: TextStyle(color: AikaTheme.neonBlue, fontSize: 11,
                        letterSpacing: 2, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ..._builtinModels.map((m) => _buildModelCard(
                    id: m.id,
                    emoji: m.emoji,
                    name: m.name,
                    desc: 'Live2D • встроенная',
                    onTap: () async {
                      setState(() => _selectedId = m.id);
                      await _save(m.id);
                    },
                  )),

                  const SizedBox(height: 20),

                  // Кастомная модель
                  Text('СВОЯ МОДЕЛЬ',
                    style: TextStyle(color: AikaTheme.neonBlue, fontSize: 11,
                        letterSpacing: 2, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),

                  if (_customModelPath != null)
                    _buildModelCard(
                      id: 'custom',
                      emoji: '📦',
                      name: _customModelPath!.split('/').last.replaceAll('.model3.json', ''),
                      desc: 'Кастомная • ${_customModelPath!.split('/').last}',
                      onTap: () async {
                        setState(() => _selectedId = 'custom');
                        await _save('custom', customPath: _customModelPath);
                      },
                    ),

                  const SizedBox(height: 12),

                  // Кнопка загрузки
                  GestureDetector(
                    onTap: _loading ? null : _pickCustomModel,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: AikaTheme.neonBlue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AikaTheme.neonBlue.withOpacity(0.4), style: BorderStyle.solid),
                      ),
                      child: Column(children: [
                        _loading
                            ? SizedBox(width: 24, height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AikaTheme.neonBlue))
                            : Icon(Icons.upload_file, color: AikaTheme.neonBlue, size: 28),
                        const SizedBox(height: 6),
                        Text('Загрузить модель (.json)',
                          style: TextStyle(color: AikaTheme.neonBlue, fontSize: 13,
                              fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        const Text('Выбери .model3.json из папки модели',
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Ссылка на сайты с моделями
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🔗 Где найти модели:',
                          style: TextStyle(color: Colors.white70, fontSize: 12,
                              fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        const Text(
                          '• VRoid Hub — vroid.com/hub\n'
                          '• Booth — booth.pm\n'
                          '• Niconi Commons — commons.nicovideo.jp\n\n'
                          'Ищи файлы с расширением .model3.json',
                          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewLive2D() {
    if (_selectedId == 'custom' && _customModelPath != null) {
      return Live2DWidget(
        width: double.infinity,
        height: 260,
        state: _previewState,
        customModelPath: _customModelPath,
      );
    }
    final model = _builtinModels.firstWhere(
      (m) => m.id == _selectedId,
      orElse: () => _builtinModels.first,
    );
    return Live2DWidget(
      width: double.infinity,
      height: 260,
      state: _previewState,
      builtinModelAsset: model.assetPath,
    );
  }

  Widget _buildModelCard({
    required String id,
    required String emoji,
    required String name,
    required String desc,
    required VoidCallback onTap,
  }) {
    final isSelected = _selectedId == id;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AikaTheme.neonBlue.withOpacity(0.12)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AikaTheme.neonBlue : Colors.white12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          )),
          if (isSelected)
            Icon(Icons.check_circle, color: AikaTheme.neonBlue, size: 22),
        ]),
      ),
    );
  }
}

// Заглушка для ключа — не используется напрямую
class _Live2DWidgetState2 {}
