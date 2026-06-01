import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FlutterTts _tts = FlutterTts();
  final _nameController = TextEditingController();
  final _userNameController = TextEditingController();

  double _ttsRate = 0.5;
  double _ttsPitch = 1.0;
  double _ttsVolume = 1.0;
  double _avatarSize = 160;
  bool _show3DAvatar = true;
  List<Map<String, String>> _voices = [];
  String? _selectedVoice;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final rawVoices = await _tts.getVoices;
    final voices = <Map<String, String>>[];
    if (rawVoices is List) {
      for (final v in rawVoices) {
        if (v is Map) {
          final name = v['name']?.toString() ?? '';
          final locale = v['locale']?.toString() ?? '';
          if (locale.startsWith('ru') || locale.startsWith('en')) {
            voices.add({'name': name, 'locale': locale});
          }
        }
      }
    }
    setState(() {
      _nameController.text = prefs.getString('assistant_name') ?? 'Aika';
      _userNameController.text = prefs.getString('user_name') ?? '';
      _ttsRate = prefs.getDouble('tts_rate') ?? 0.5;
      _ttsPitch = prefs.getDouble('tts_pitch') ?? 1.0;
      _ttsVolume = prefs.getDouble('tts_volume') ?? 1.0;
      _avatarSize = prefs.getDouble('avatar_size') ?? 160;
      _show3DAvatar = prefs.getBool('show_3d_avatar') ?? true;
      _selectedVoice = prefs.getString('tts_voice');
      _voices = voices;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final name = _nameController.text.trim();
    await prefs.setString('assistant_name', name.isEmpty ? 'Aika' : name);
    await prefs.setString('user_name', _userNameController.text.trim());
    await prefs.setDouble('tts_rate', _ttsRate);
    await prefs.setDouble('tts_pitch', _ttsPitch);
    await prefs.setDouble('tts_volume', _ttsVolume);
    await prefs.setDouble('avatar_size', _avatarSize);
    await prefs.setBool('show_3d_avatar', _show3DAvatar);
    if (_selectedVoice != null) await prefs.setString('tts_voice', _selectedVoice!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Настройки сохранены'),
        backgroundColor: AikaTheme.neonBlue.withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.pop(context);
    }
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(title, style: TextStyle(color: AikaTheme.neonBlue, fontSize: 11,
        letterSpacing: 2, fontWeight: FontWeight.bold)),
  );

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged, {int? divisions}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(value.toStringAsFixed(0) == value.toString()
              ? value.toStringAsFixed(0)
              : value.toStringAsFixed(2),
              style: TextStyle(color: AikaTheme.neonBlue, fontSize: 12)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AikaTheme.neonBlue,
            thumbColor: AikaTheme.neonBlue,
            inactiveTrackColor: Colors.white12,
            overlayColor: AikaTheme.neonBlue.withOpacity(0.1),
          ),
          child: Slider(value: value, min: min, max: max,
              divisions: divisions, onChanged: onChanged),
        ),
      ]);

  Widget _buildTextField(TextEditingController ctrl, String hint, IconData icon) =>
      TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: Icon(icon, color: AikaTheme.neonBlue.withOpacity(0.7), size: 20),
          filled: true,
          fillColor: AikaTheme.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.5))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: AikaTheme.surface,
        title: Text('Настройки', style: TextStyle(color: AikaTheme.neonBlue, letterSpacing: 2)),
        iconTheme: const IconThemeData(color: Colors.white54),
        actions: [
          TextButton(onPressed: _save, child: Text('Сохранить', style: TextStyle(color: AikaTheme.neonBlue))),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AikaTheme.neonBlue))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _section('ЛИЧНОЕ'),
                _buildTextField(_nameController, 'Имя ассистента', Icons.auto_awesome),
                const SizedBox(height: 12),
                _buildTextField(_userNameController, 'Ваше имя', Icons.person_outline),

                _section('3D АВАТАР'),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Показывать аватар', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Switch(
                    value: _show3DAvatar,
                    onChanged: (v) => setState(() => _show3DAvatar = v),
                    activeColor: AikaTheme.neonBlue,
                  ),
                ]),
                if (_show3DAvatar)
                  _slider('Размер аватара', _avatarSize, 80, 300,
                      (v) => setState(() => _avatarSize = v), divisions: 22),
                if (_show3DAvatar)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AikaTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Text(
                      '💡 Нажми на аватар в чате — появятся кнопки + / - для изменения размера. Перетаскивай за любое место.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),

                _section('ГОЛОС'),
                _slider('Скорость речи', _ttsRate, 0.1, 1.0,
                    (v) => setState(() => _ttsRate = v)),
                _slider('Тон голоса', _ttsPitch, 0.5, 2.0,
                    (v) => setState(() => _ttsPitch = v)),
                _slider('Громкость', _ttsVolume, 0.0, 1.0,
                    (v) => setState(() => _ttsVolume = v)),

                if (_voices.isNotEmpty) ...[
                  _section('ВЫБОР ГОЛОСА'),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: AikaTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedVoice,
                      isExpanded: true,
                      dropdownColor: AikaTheme.surface,
                      underline: const SizedBox(),
                      hint: const Text('Выберите голос',
                          style: TextStyle(color: Colors.white38)),
                      items: _voices.map((v) => DropdownMenuItem(
                        value: v['name'],
                        child: Text('${v["name"]} (${v["locale"]})',
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      )).toList(),
                      onChanged: (v) => setState(() => _selectedVoice = v),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _userNameController.dispose();
    super.dispose();
  }
}
