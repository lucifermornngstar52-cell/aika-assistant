import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/edge_tts_service.dart';
import '../theme/app_theme.dart';
import '../services/wake_word_service.dart';
import 'commands_screen.dart';
import 'personality_screen.dart';
import 'wardrobe_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _assistantNameController = TextEditingController();

  // Edge TTS settings only
  String _selectedEdgeVoice = 'ru-RU-DariyaNeural';
  double _edgeTtsRate  = 0.0;   // -50 .. +50 %
  double _edgeTtsPitch  = 0.0;   // -50 .. +50 Hz
  double _edgeTtsVolume = 0.0;  // -50 .. +50 %
  // volume not needed for EdgeTTS

  bool _showAvatar = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text           = prefs.getString('user_name') ?? '';
      _assistantNameController.text  = prefs.getString('assistant_name') ?? 'Aika';
      _selectedEdgeVoice             = prefs.getString('edge_voice') ?? 'ru-RU-DariyaNeural';
      _edgeTtsRate                   = prefs.getDouble('edge_tts_rate')   ?? 0.0;
      _edgeTtsPitch                  = prefs.getDouble('edge_tts_pitch')  ?? 0.0;
      _edgeTtsVolume                 = prefs.getDouble('edge_tts_volume') ?? 0.0;
      _showAvatar                    = prefs.getBool('show_avatar') ?? true;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameController.text.trim());
    await prefs.setString('assistant_name',
        _assistantNameController.text.trim().isEmpty
            ? 'Aika'
            : _assistantNameController.text.trim());
    await prefs.setString('edge_voice',       _selectedEdgeVoice);
    await prefs.setBool('use_edge_tts',       true);
    await prefs.setDouble('edge_tts_rate',    _edgeTtsRate);
    await prefs.setDouble('edge_tts_pitch',   _edgeTtsPitch);
    await prefs.setDouble('edge_tts_volume',  _edgeTtsVolume);
    await prefs.setBool('show_avatar', _showAvatar);

    // Apply to running EdgeTTS singleton immediately
    final svc = EdgeTtsService();
    svc.setVoice(_selectedEdgeVoice);
    svc.setRate(_edgeTtsRate);
    svc.setPitch(_edgeTtsPitch);

    await WakeWordService.instance.updateTriggers();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Настройки сохранены ✓'),
          backgroundColor: AikaTheme.neonBlue.withOpacity(0.85),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _testVoice() async {
    final svc = EdgeTtsService();
    svc.setVoice(_selectedEdgeVoice);
    svc.setRate(_edgeTtsRate);
    svc.setPitch(_edgeTtsPitch);
    final name = _assistantNameController.text.trim().isEmpty
        ? 'Айка'
        : _assistantNameController.text.trim();
    await svc.speak('Привет! Я $name. Проверка голоса.');
  }

  // ── UI helpers ──────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3, height: 16,
            decoration: BoxDecoration(
              color: AikaTheme.neonBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: AikaTheme.neonBlue,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AikaTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: AikaTheme.neonBlue.withOpacity(0.04),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
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
          labelStyle: TextStyle(color: AikaTheme.neonBlue.withOpacity(0.8)),
          hintStyle: const TextStyle(color: Colors.white30),
          filled: true,
          fillColor: Colors.white.withOpacity(0.04),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.25)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AikaTheme.neonBlue),
          ),
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required String unit,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Function(double) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AikaTheme.neonBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${value >= 0 ? '+' : ''}${value.round()}$unit',
                  style: TextStyle(
                    color: AikaTheme.neonBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AikaTheme.neonBlue,
              inactiveTrackColor: AikaTheme.neonBlue.withOpacity(0.15),
              thumbColor: AikaTheme.neonBlue,
              overlayColor: AikaTheme.neonBlue.withOpacity(0.15),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) {
                onChanged(v);
                // Live preview: apply immediately to EdgeTTS singleton
                final svc = EdgeTtsService();
                svc.setVoice(_selectedEdgeVoice);
                svc.setRate(_edgeTtsRate);
                svc.setPitch(_edgeTtsPitch);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Voice card ───────────────────────────────────────────────────────────

  Widget _buildVoiceCard() {
    return _buildCard([
      // Voice selector header
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0078D4).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.graphic_eq, color: Color(0xFF0078D4), size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Microsoft Edge TTS',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                Text('Нейронный голос от Microsoft',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.4)),
              ),
              child: const Text('ACTIVE',
                  style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),

      const Divider(color: Colors.white10, height: 1),

      // Voice dropdown
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Голос', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.25)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  dropdownColor: const Color(0xFF0D1120),
                  value: _selectedEdgeVoice,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  icon: Icon(Icons.expand_more, color: AikaTheme.neonBlue),
                  items: EdgeTtsService.voices.map((v) {
                    return DropdownMenuItem<String>(
                      value: v['id']!,
                      child: Text(v['label']!, style: const TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedEdgeVoice = v);
                      // Preview new voice immediately
                      final svc = EdgeTtsService();
                      svc.setVoice(v);
                      svc.setRate(_edgeTtsRate);
                      svc.setPitch(_edgeTtsPitch);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),

      const Divider(color: Colors.white10, height: 1),

      // Sliders
      const SizedBox(height: 8),
      _buildSlider(
        label: 'Скорость речи',
        unit: '%',
        value: _edgeTtsRate,
        min: -50,
        max: 50,
        divisions: 20,
        onChanged: (v) => setState(() => _edgeTtsRate = v),
      ),
      _buildSlider(
        label: 'Высота тона',
        unit: 'Hz',
        value: _edgeTtsPitch,
        min: -50,
        max: 50,
        divisions: 20,
        onChanged: (v) => setState(() => _edgeTtsPitch = v),
      ),
      _buildSlider(
        label: 'Громкость',
        unit: '%',
        value: _edgeTtsVolume,
        min: -50,
        max: 50,
        divisions: 20,
        onChanged: (v) => setState(() => _edgeTtsVolume = v),
      ),

      const SizedBox(height: 8),

      // Test button
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _testVoice,
            icon: Icon(Icons.play_circle_outline, color: AikaTheme.neonBlue, size: 20),
            label: Text('Проверить голос',
                style: TextStyle(color: AikaTheme.neonBlue, fontSize: 13)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AikaTheme.background,
        body: Center(child: CircularProgressIndicator(color: AikaTheme.neonBlue)),
      );
    }

    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'НАСТРОЙКИ',
          style: TextStyle(
            color: AikaTheme.neonBlue,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: AikaTheme.neonBlue),
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: Text('СОХРАНИТЬ',
                style: TextStyle(
                    color: AikaTheme.neonBlue, fontSize: 12, letterSpacing: 1)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Profile ──────────────────────────────────────────────
            _buildSectionTitle('ПРОФИЛЬ'),
            _buildCard([
              _buildTextField(_nameController, 'Ваше имя', 'Как вас зовут?'),
            ]),

            // ── Assistant ────────────────────────────────────────────
            _buildSectionTitle('АССИСТЕНТ'),
            _buildCard([
              _buildTextField(_assistantNameController, 'Имя ассистента', 'Aika'),
              const Divider(color: Colors.white10, height: 1),
              SwitchListTile(
                title: const Text('Показывать аватар',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('3D аватар на главном экране',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                value: _showAvatar,
                activeColor: AikaTheme.neonBlue,
                onChanged: (v) => setState(() => _showAvatar = v),
              ),
            ]),

            // ── Voice ────────────────────────────────────────────────
            _buildSectionTitle('ГОЛОС'),
            _buildVoiceCard(),

            // ── Navigation ───────────────────────────────────────────
            _buildSectionTitle('РАЗДЕЛЫ'),
            _buildCard([
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Icon(Icons.terminal_rounded, color: AikaTheme.neonBlue),
                title: const Text('Команды', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Голосовые команды и триггеры',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: Icon(Icons.chevron_right, color: Colors.white24),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CommandsScreen())),
              ),
              const Divider(color: Colors.white10, height: 1),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Icon(Icons.face_retouching_natural, color: AikaTheme.neonPurple),
                title: const Text('Личность', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Характер и стиль общения',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: Icon(Icons.chevron_right, color: Colors.white24),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PersonalityScreen())),
              ),
              const Divider(color: Colors.white10, height: 1),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Icon(Icons.checkroom_rounded, color: AikaTheme.neonPink),
                title: const Text('Гардероб', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Внешний вид ассистента',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: Icon(Icons.chevron_right, color: Colors.white24),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WardrobeScreen())),
              ),
            ]),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _assistantNameController.dispose();
    super.dispose();
  }
}
