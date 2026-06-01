import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/edge_tts_service.dart';
import '../theme/app_theme.dart';
import '../services/wake_word_service.dart';
import 'commands_screen.dart';
import 'personality_screen.dart';
import 'wardrobe_screen.dart';
import '../services/overlay_service.dart';

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

  // Live2D model settings
  double _live2dSize    = 170.0;  // px, 80..280
  double _live2dOpacity = 1.0;    // 0.3..1.0
  double _live2dSpeed   = 1.0;    // 0.5..2.0
  bool   _live2dMirror  = false;  // flip horizontal
  String _live2dSide    = 'left'; // left / right

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
      _live2dSize    = prefs.getDouble('live2d_size')    ?? 170.0;
      _live2dOpacity = prefs.getDouble('live2d_opacity') ?? 1.0;
      _live2dSpeed   = prefs.getDouble('live2d_speed')   ?? 1.0;
      _live2dMirror  = prefs.getBool('live2d_mirror')    ?? false;
      _live2dSide    = prefs.getString('live2d_side')    ?? 'left';
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
    await prefs.setDouble('live2d_size',    _live2dSize);
    await prefs.setDouble('live2d_opacity', _live2dOpacity);
    await prefs.setDouble('live2d_speed',   _live2dSpeed);
    await prefs.setBool('live2d_mirror',    _live2dMirror);
    await prefs.setString('live2d_side',    _live2dSide);
    // Apply Live2D settings to running overlay
    await OverlayService.updateLive2DConfig(
      size: _live2dSize,
      opacity: _live2dOpacity,
      speed: _live2dSpeed,
      mirror: _live2dMirror,
      side: _live2dSide,
    );

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
                onChanged(v); // setState вызывается снаружи
                // Live preview: передаём v напрямую, не ждём setState
                final svc = EdgeTtsService();
                svc.setVoice(_selectedEdgeVoice);
                // определяем что именно меняется по label
                // (rate/pitch/volume — передаём актуальное v)
                svc.setRate(label.contains('Скорость') ? v : _edgeTtsRate);
                svc.setPitch(label.contains('Высота') ? v : _edgeTtsPitch);
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

            ]),

            // ── Voice ────────────────────────────────────────────────
            _buildSectionTitle('ГОЛОС'),
            _buildVoiceCard(),


            // ── Live2D Avatar ─────────────────────────────────────────
            _buildSectionTitle('АВАТАР LIVE2D'),
            _buildLive2DCard(),

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
  // ── Live2D card ───────────────────────────────────────────────────────────

  Widget _buildLive2DCard() {
    return _buildCard([
      // Header
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AikaTheme.neonPink.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.face_retouching_natural, color: AikaTheme.neonPink, size: 20),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Live2D Haru', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                Text('Анимированный 3D аватар', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
      const Divider(color: Colors.white10, height: 1),

      // Размер
      _buildSlider(
        label: 'Размер модели',
        unit: 'px',
        value: _live2dSize,
        min: 80,
        max: 280,
        divisions: 20,
        onChanged: (v) => setState(() => _live2dSize = v),
      ),

      // Прозрачность
      _buildOpacitySlider(),

      // Скорость анимации
      _buildSpeedSlider(),

      // Сторона экрана
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Сторона', style: TextStyle(color: Colors.white70, fontSize: 13)),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'left',  label: Text('Лево')),
                ButtonSegment(value: 'right', label: Text('Право')),
              ],
              selected: {_live2dSide},
              onSelectionChanged: (s) => setState(() => _live2dSide = s.first),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                    ? AikaTheme.neonPink.withOpacity(0.25)
                    : Colors.transparent,
                ),
                foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected) ? AikaTheme.neonPink : Colors.white54,
                ),
                side: WidgetStatePropertyAll(BorderSide(color: AikaTheme.neonPink.withOpacity(0.3))),
              ),
            ),
          ],
        ),
      ),

      // Зеркало
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: const Text('Зеркальное отражение', style: TextStyle(color: Colors.white70, fontSize: 13)),
        value: _live2dMirror,
        activeColor: AikaTheme.neonPink,
        onChanged: (v) => setState(() => _live2dMirror = v),
      ),

      // Кнопка применить
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.preview_rounded, size: 18),
            label: const Text('Применить сейчас'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AikaTheme.neonPink.withOpacity(0.2),
              foregroundColor: AikaTheme.neonPink,
              side: BorderSide(color: AikaTheme.neonPink.withOpacity(0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () async {
              await OverlayService.updateLive2DConfig(
                size: _live2dSize,
                opacity: _live2dOpacity,
                speed: _live2dSpeed,
                mirror: _live2dMirror,
                side: _live2dSide,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Аватар обновлён ✓'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 1),
                ));
              }
            },
          ),
        ),
      ),
    ]);
  }

  Widget _buildOpacitySlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Прозрачность', style: TextStyle(color: Colors.white70, fontSize: 13)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AikaTheme.neonPink.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(_live2dOpacity * 100).round()}%',
                  style: TextStyle(color: AikaTheme.neonPink, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AikaTheme.neonPink,
              inactiveTrackColor: AikaTheme.neonPink.withOpacity(0.15),
              thumbColor: AikaTheme.neonPink,
              overlayColor: AikaTheme.neonPink.withOpacity(0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: _live2dOpacity,
              min: 0.2, max: 1.0, divisions: 16,
              onChanged: (v) => setState(() => _live2dOpacity = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedSlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Скорость анимации', style: TextStyle(color: Colors.white70, fontSize: 13)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AikaTheme.neonPink.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_live2dSpeed.toStringAsFixed(1)}×',
                  style: TextStyle(color: AikaTheme.neonPink, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AikaTheme.neonPink,
              inactiveTrackColor: AikaTheme.neonPink.withOpacity(0.15),
              thumbColor: AikaTheme.neonPink,
              overlayColor: AikaTheme.neonPink.withOpacity(0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: _live2dSpeed,
              min: 0.5, max: 2.0, divisions: 15,
              onChanged: (v) => setState(() => _live2dSpeed = v),
            ),
          ),
        ],
      ),
    );
  }


}