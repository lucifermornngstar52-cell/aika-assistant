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
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _assistantNameController = TextEditingController();

  List<dynamic> _voices = [];
  String? _selectedVoice;
  double _speechRate = 0.5;
  double _pitch = 1.0;
  double _volume = 1.0;
  bool _showAvatar = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadVoices();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('user_name') ?? '';
      _assistantNameController.text = prefs.getString('assistant_name') ?? 'Aika';
      _speechRate = prefs.getDouble('tts_rate') ?? 0.5;
      _pitch = prefs.getDouble('tts_pitch') ?? 1.0;
      _volume = prefs.getDouble('tts_volume') ?? 1.0;
      _selectedVoice = prefs.getString('tts_voice');
      _showAvatar = prefs.getBool('show_avatar') ?? true;
      _isLoading = false;
    });
  }

  Future<void> _loadVoices() async {
    final voices = await _tts.getVoices;
    if (voices != null) {
      setState(() {
        _voices = (voices as List).where((v) {
          final locale = v['locale']?.toString() ?? '';
          return locale.startsWith('ru') || locale.startsWith('en');
        }).toList();
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameController.text.trim());
    await prefs.setString('assistant_name', _assistantNameController.text.trim().isEmpty
        ? 'Aika' : _assistantNameController.text.trim());
    await prefs.setDouble('tts_rate', _speechRate);
    await prefs.setDouble('tts_pitch', _pitch);
    await prefs.setDouble('tts_volume', _volume);
    await prefs.setBool('show_avatar', _showAvatar);
    if (_selectedVoice != null) {
      await prefs.setString('tts_voice', _selectedVoice!);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Настройки сохранены ✓'),
          backgroundColor: AppTheme.neonBlue.withOpacity(0.8),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _testVoice() async {
    final name = _assistantNameController.text.trim().isEmpty
        ? 'Aika' : _assistantNameController.text.trim();
    await _tts.setVolume(_volume);
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    if (_selectedVoice != null) {
      await _tts.setVoice({'name': _selectedVoice!, 'locale': 'ru-RU'});
    }
    await _tts.speak('Привет! Я $name, ваш личный ассистент.');
  }

  @override
  void dispose() {
    _tts.stop();
    _nameController.dispose();
    _assistantNameController.dispose();
    super.dispose();
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: AppTheme.neonBlue,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.neonBlue.withOpacity(0.15)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, String hint) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: AppTheme.neonBlue.withOpacity(0.8)),
          hintStyle: TextStyle(color: Colors.white30),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.neonBlue.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.neonBlue),
          ),
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max,
      int divisions, Function(double) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: AppTheme.neonBlue,
                inactiveTrackColor: AppTheme.neonBlue.withOpacity(0.2),
                thumbColor: AppTheme.neonBlue,
                overlayColor: AppTheme.neonBlue.withOpacity(0.2),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              value.toStringAsFixed(1),
              style: TextStyle(color: AppTheme.neonBlue, fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: Center(child: CircularProgressIndicator(color: AppTheme.neonBlue)),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'НАСТРОЙКИ',
          style: TextStyle(
            color: AppTheme.neonBlue,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: AppTheme.neonBlue),
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: Text('СОХРАНИТЬ',
                style: TextStyle(color: AppTheme.neonBlue, fontSize: 12, letterSpacing: 1)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- ПРОФИЛЬ ---
            _buildSectionTitle('ПРОФИЛЬ'),
            _buildCard([
              _buildTextField(_nameController, 'Ваше имя', 'Как вас зовут?'),
            ]),

            // --- АССИСТЕНТ ---
            _buildSectionTitle('АССИСТЕНТ'),
            _buildCard([
              _buildTextField(_assistantNameController, 'Имя ассистента', 'Aika'),
              const Divider(color: Colors.white10, height: 1),
              SwitchListTile(
                title: const Text('Показывать аватар', style: TextStyle(color: Colors.white)),
                subtitle: Text('3D аватар на главном экране',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                value: _showAvatar,
                activeColor: AppTheme.neonBlue,
                onChanged: (v) => setState(() => _showAvatar = v),
              ),
            ]),

            // --- ГОЛОС ---
            _buildSectionTitle('ГОЛОС АССИСТЕНТА'),
            _buildCard([
              if (_voices.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: DropdownButtonFormField<String>(
                    value: _selectedVoice,
                    dropdownColor: AppTheme.surfaceColor,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Голос',
                      labelStyle: TextStyle(color: AppTheme.neonBlue.withOpacity(0.8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.neonBlue.withOpacity(0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.neonBlue),
                      ),
                    ),
                    hint: const Text('Выберите голос', style: TextStyle(color: Colors.white38)),
                    items: _voices.map<DropdownMenuItem<String>>((v) {
                      final name = v['name']?.toString() ?? '';
                      final locale = v['locale']?.toString() ?? '';
                      return DropdownMenuItem(
                        value: name,
                        child: Text('$name ($locale)',
                            style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedVoice = v),
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),
              ],
              const SizedBox(height: 8),
              _buildSlider('Скорость', _speechRate, 0.1, 1.0, 9,
                  (v) => setState(() => _speechRate = v)),
              _buildSlider('Высота', _pitch, 0.5, 2.0, 15,
                  (v) => setState(() => _pitch = v)),
              _buildSlider('Громкость', _volume, 0.0, 1.0, 10,
                  (v) => setState(() => _volume = v)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _testVoice,
                    icon: Icon(Icons.play_arrow, color: AppTheme.neonBlue),
                    label: Text('Тест голоса',
                        style: TextStyle(color: AppTheme.neonBlue)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.neonBlue.withOpacity(0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
