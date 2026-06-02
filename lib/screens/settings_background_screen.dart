import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_theme.dart';

/// Предустановленные фоны
class _BgPreset {
  final String id;
  final String name;
  final Color color1;
  final Color color2;
  const _BgPreset({required this.id, required this.name, required this.color1, required this.color2});
}

const _presets = [
  _BgPreset(id: 'none',    name: 'Без фона',   color1: Color(0xFF0F0F0F),  color2: Color(0xFF0F0F0F)),
  _BgPreset(id: 'night',   name: 'Ночь',       color1: Color(0xFF0D0D2B),  color2: Color(0xFF1A0533)),
  _BgPreset(id: 'aurora',  name: 'Аврора',     color1: Color(0xFF001F3F),  color2: Color(0xFF00A86B)),
  _BgPreset(id: 'sunset',  name: 'Закат',      color1: Color(0xFF1A0533),  color2: Color(0xFFFF6B35)),
  _BgPreset(id: 'ocean',   name: 'Океан',      color1: Color(0xFF001B4A),  color2: Color(0xFF00B4D8)),
  _BgPreset(id: 'cherry',  name: 'Сакура',     color1: Color(0xFF1A0020),  color2: Color(0xFFFF69B4)),
  _BgPreset(id: 'cyber',   name: 'Киберпанк',  color1: Color(0xFF0A0014),  color2: Color(0xFF7B00FF)),
];

class SettingsBackgroundScreen extends StatefulWidget {
  const SettingsBackgroundScreen({Key? key}) : super(key: key);
  @override
  State<SettingsBackgroundScreen> createState() => _SettingsBackgroundScreenState();
}

class _SettingsBackgroundScreenState extends State<SettingsBackgroundScreen> {
  String _selectedId = 'none';
  String? _customImagePath;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedId = prefs.getString('bg_preset_id') ?? 'none';
      _customImagePath = prefs.getString('bg_custom_image');
    });
  }

  Future<void> _save(String id, {String? customPath}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bg_preset_id', id);
    if (customPath != null) {
      await prefs.setString('bg_custom_image', customPath);
    } else if (id != 'custom') {
      await prefs.remove('bg_custom_image');
    }
    setState(() {
      _selectedId = id;
      if (customPath != null) _customImagePath = customPath;
    });
  }

  Future<void> _pickImage() async {
    setState(() => _loading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        dialogTitle: 'Выбери фон',
      );
      if (result != null && result.files.single.path != null) {
        await _save('custom', customPath: result.files.single.path!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Фон установлен'),
            backgroundColor: Colors.green.withOpacity(0.8),
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      debugPrint('FilePicker error: $e');
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Фон', style: TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Превью текущего фона
          Container(
            height: 140,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: _selectedId != 'custom'
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _presets.firstWhere((p) => p.id == _selectedId,
                            orElse: () => _presets.first).color1,
                        _presets.firstWhere((p) => p.id == _selectedId,
                            orElse: () => _presets.first).color2,
                      ],
                    )
                  : null,
              image: _selectedId == 'custom' && _customImagePath != null
                  ? DecorationImage(
                      image: FileImage(File(_customImagePath!)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Center(
              child: Text('Предпросмотр',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 12,
                      letterSpacing: 1)),
            ),
          ),

          // Предустановленные фоны
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('ПРЕДУСТАНОВЛЕННЫЕ',
                style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
          ),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.3,
            children: _presets.map((p) {
              final isSelected = _selectedId == p.id;
              return GestureDetector(
                onTap: () => _save(p.id),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [p.color1, p.color2],
                    ),
                    border: Border.all(
                      color: isSelected ? AikaTheme.neonBlue : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                          ),
                          child: Text(p.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                      ),
                      if (isSelected)
                        const Positioned(
                          top: 6, right: 6,
                          child: Icon(Icons.check_circle, color: Colors.white, size: 16),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Своя картинка
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('СВОЯ КАРТИНКА',
                style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
          ),
          GestureDetector(
            onTap: _loading ? null : _pickImage,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: _selectedId == 'custom'
                    ? AikaTheme.neonBlue.withOpacity(0.1)
                    : const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _selectedId == 'custom' ? AikaTheme.neonBlue : Colors.white12,
                ),
              ),
              child: Column(children: [
                _loading
                    ? SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AikaTheme.neonBlue))
                    : Icon(Icons.add_photo_alternate_outlined,
                        color: _selectedId == 'custom' ? AikaTheme.neonBlue : Colors.white38,
                        size: 32),
                const SizedBox(height: 6),
                Text(
                  _customImagePath != null
                      ? _customImagePath!.split('/').last
                      : 'Выбрать из галереи',
                  style: TextStyle(
                    color: _selectedId == 'custom' ? AikaTheme.neonBlue : Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
