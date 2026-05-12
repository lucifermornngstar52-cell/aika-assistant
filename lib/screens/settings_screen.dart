import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/ai_service.dart';
import '../services/memory_service.dart';
import '../services/speech_service.dart';

class SettingsScreen extends StatefulWidget {
  final AIService aiService;

  const SettingsScreen({super.key, required this.aiService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final MemoryService _memoryService = MemoryService();
  final SpeechService _speechService = SpeechService();

  AIProvider _selectedProvider = AIProvider.gemini;
  double _speechRate = 0.85;
  double _speechPitch = 1.1;
  String? _userName;

  @override
  void initState() {
    super.initState();
    _selectedProvider = widget.aiService.currentProvider;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final name = await _memoryService.getUserName();
    setState(() => _userName = name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: AikaTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AikaTheme.neonBlue),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [AikaTheme.neonBlue, AikaTheme.neonPurple],
          ).createShader(b),
          child: const Text(
            'Настройки',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('🤖 AI Модель', [
            _buildProviderTile(
              'Gemini 2.0 Flash',
              'Google · Быстрый и умный',
              AIProvider.gemini,
              Icons.auto_awesome,
              AikaTheme.neonBlue,
            ),
            _buildProviderTile(
              'GPT-4o',
              'OpenAI · Мощный и точный',
              AIProvider.openai,
              Icons.psychology,
              AikaTheme.neonPurple,
            ),
          ]),

          const SizedBox(height: 16),

          _buildSection('🎤 Голос', [
            _buildSliderTile(
              'Скорость речи',
              _speechRate,
              0.5,
              1.5,
              Icons.speed,
              (v) {
                setState(() => _speechRate = v);
                _speechService.setVoiceSettings(rate: v);
              },
            ),
            _buildSliderTile(
              'Высота голоса',
              _speechPitch,
              0.5,
              2.0,
              Icons.graphic_eq,
              (v) {
                setState(() => _speechPitch = v);
                _speechService.setVoiceSettings(pitch: v);
              },
            ),
          ]),

          const SizedBox(height: 16),

          _buildSection('👤 Профиль', [
            _buildNameTile(),
          ]),

          const SizedBox(height: 16),

          _buildSection('🗂 Данные', [
            _buildActionTile(
              'Очистить историю чата',
              Icons.delete_outline,
              AikaTheme.neonPink,
              () async {
                await _memoryService.clearHistory();
                widget.aiService.clearHistory();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('История очищена'),
                      backgroundColor: AikaTheme.surface,
                    ),
                  );
                }
              },
            ),
          ]),

          const SizedBox(height: 32),

          // Version info
          Center(
            child: Text(
              'Айка v1.0.0 · Made with ❤️',
              style: const TextStyle(
                color: AikaTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: AikaTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
        Container(
          decoration: AikaTheme.glassCard(opacity: 0.05),
          child: Column(children: children),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildProviderTile(
    String name,
    String subtitle,
    AIProvider provider,
    IconData icon,
    Color color,
  ) {
    final selected = _selectedProvider == provider;
    return ListTile(
      onTap: () async {
        setState(() => _selectedProvider = provider);
        await widget.aiService.setProvider(provider);
      },
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.15),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(name, style: const TextStyle(color: AikaTheme.textPrimary, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(color: AikaTheme.textSecondary, fontSize: 12)),
      trailing: selected
          ? Icon(Icons.check_circle, color: color, size: 20)
          : Icon(Icons.radio_button_unchecked, color: AikaTheme.textSecondary, size: 20),
    );
  }

  Widget _buildSliderTile(
    String label,
    double value,
    double min,
    double max,
    IconData icon,
    Function(double) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AikaTheme.neonBlue, size: 16),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: AikaTheme.textPrimary, fontSize: 14)),
              const Spacer(),
              Text(
                value.toStringAsFixed(1),
                style: const TextStyle(color: AikaTheme.neonBlue, fontSize: 12),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AikaTheme.neonBlue,
              inactiveTrackColor: AikaTheme.neonBlue.withOpacity(0.2),
              thumbColor: AikaTheme.neonBlue,
              overlayColor: AikaTheme.neonBlue.withOpacity(0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  Widget _buildNameTile() {
    return ListTile(
      leading: const Icon(Icons.person_outline, color: AikaTheme.neonPurple, size: 20),
      title: const Text('Твоё имя', style: TextStyle(color: AikaTheme.textPrimary, fontSize: 14)),
      subtitle: Text(
        _userName ?? 'Не указано',
        style: const TextStyle(color: AikaTheme.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(Icons.edit, color: AikaTheme.textSecondary, size: 16),
      onTap: () => _showNameDialog(),
    );
  }

  Widget _buildActionTile(String label, IconData icon, Color color, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color, size: 20),
      title: Text(label, style: TextStyle(color: color, fontSize: 14)),
    );
  }

  void _showNameDialog() {
    final ctrl = TextEditingController(text: _userName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AikaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Как тебя зовут?', style: TextStyle(color: AikaTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: AikaTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Введи своё имя',
            hintStyle: const TextStyle(color: AikaTheme.textSecondary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.5)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AikaTheme.neonBlue),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: AikaTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              await _memoryService.setUserName(ctrl.text);
              setState(() => _userName = ctrl.text);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Сохранить', style: TextStyle(color: AikaTheme.neonBlue)),
          ),
        ],
      ),
    );
  }
}
