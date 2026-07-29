import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/edge_tts_service.dart';
import '../services/elevenlabs_tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class SettingsVoiceScreen extends StatefulWidget {
  const SettingsVoiceScreen({Key? key}) : super(key: key);
  @override
  State<SettingsVoiceScreen> createState() => _SettingsVoiceScreenState();
}

class _SettingsVoiceScreenState extends State<SettingsVoiceScreen> {
  final FlutterTts _tts = FlutterTts();
  double _rate = 0.5, _pitch = 1.0, _volume = 1.0;
  List<Map<String, String>> _voices = [];
  String? _selectedVoice;
  bool _loading = true;
  String _ttsEngine = 'edge'; // 'edge' | 'elevenlabs' | 'system'
  String? _elevenLabsVoice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _ttsEngine = prefs.getString('tts_engine') ?? 'edge';
    _elevenLabsVoice = prefs.getString('elevenlabs_voice');
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
      _rate = prefs.getDouble('tts_rate') ?? 0.5;
      _pitch = prefs.getDouble('tts_pitch') ?? 1.0;
      _volume = prefs.getDouble('tts_volume') ?? 1.0;
      _selectedVoice = prefs.getString('tts_voice');
      _voices = voices;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_engine', _ttsEngine);
    if (_elevenLabsVoice != null) await prefs.setString('elevenlabs_voice', _elevenLabsVoice!);
    await prefs.setDouble('tts_rate', _rate);
    await prefs.setDouble('tts_pitch', _pitch);
    await prefs.setDouble('tts_volume', _volume);
    if (_selectedVoice != null) {
      await prefs.setString('tts_voice', _selectedVoice!);
      // Also sync EdgeTTS voice if it matches our neural voice list
      final edgeVoice = EdgeTtsService.voices.firstWhere(
        (v) => _selectedVoice!.toLowerCase().contains(v['id']!.split('-').last.toLowerCase()),
        orElse: () => <String, String>{},
      );
      if (edgeVoice.isNotEmpty) {
        await prefs.setString('edge_voice', edgeVoice['id']!);
        EdgeTtsService().setVoice(edgeVoice['id']!);
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Сохранено'),
        backgroundColor: AikaTheme.neonBlue.withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.pop(context);
    }
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
        title: const Text('Голос', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(onPressed: _save,
              child: Text('Сохранить', style: TextStyle(color: AikaTheme.neonBlue, fontSize: 15))),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AikaTheme.neonBlue))
          : ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _label('ДВИЖОК TTS'),
          _card(Column(children: [
            _engineTile('EdgeTTS (бесплатно)', 'edge', '⚡', 'Microsoft Neural, мгновенный стриминг'),
            _engineTile('ElevenLabs (премиум)', 'elevenlabs', '🎭', 'Лучшее качество, естественные голоса'),
            _engineTile('Системный TTS', 'system', '📱', 'Встроенный Android TTS, офлайн'),
          ])),
          const SizedBox(height: 20),

          if (_ttsEngine == 'elevenlabs') ...[
            _label('ГОЛОСА ELEVENLABS'),
            ...ElevenLabsTtsService.voices.map((v) => GestureDetector(
              onTap: () => setState(() => _elevenLabsVoice = v['id']),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _elevenLabsVoice == v['id']
                      ? AikaTheme.neonBlue.withOpacity(0.15)
                      : const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _elevenLabsVoice == v['id'] ? AikaTheme.neonBlue : Colors.transparent,
                  ),
                ),
                child: Row(children: [
                  Expanded(child: Text(v['label']!, style: const TextStyle(color: Colors.white, fontSize: 13))),
                  if (_elevenLabsVoice == v['id'])
                    Icon(Icons.check_circle, color: AikaTheme.neonBlue, size: 18),
                ]),
              ),
            )),
            const SizedBox(height: 20),
          ],

          _label('ПАРАМЕТРЫ ГОЛОСА'),
          _card(Column(children: [
            _slider('Скорость речи', _rate, 0.25, 1.5, (v) => setState(() => _rate = v)),
            _slider('Высота голоса', _pitch, 0.5, 2.0, (v) => setState(() => _pitch = v)),
            _slider('Громкость', _volume, 0.0, 1.0, (v) => setState(() => _volume = v)),
          ])),
          if (_voices.isNotEmpty && _ttsEngine != 'elevenlabs') ...[
            const SizedBox(height: 20),
            _label('ГОЛОС'),
            ..._voices.map((v) {
              final id = '${v['name']}_${v['locale']}';
              return GestureDetector(
                onTap: () => setState(() => _selectedVoice = v['name']),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _selectedVoice == v['name']
                        ? AikaTheme.neonBlue.withOpacity(0.15)
                        : const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedVoice == v['name'] ? AikaTheme.neonBlue : Colors.transparent,
                    ),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(v['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      Text(v['locale'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ])),
                    if (_selectedVoice == v['name'])
                      Icon(Icons.check_circle, color: AikaTheme.neonBlue, size: 18),
                  ]),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _engineTile(String title, String engine, String emoji, String subtitle) =>
      GestureDetector(
        onTap: () => setState(() => _ttsEngine = engine),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _ttsEngine == engine
                ? AikaTheme.neonBlue.withOpacity(0.15)
                : const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _ttsEngine == engine ? AikaTheme.neonBlue : Colors.transparent,
            ),
          ),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ])),
            if (_ttsEngine == engine)
              Icon(Icons.check_circle, color: AikaTheme.neonBlue, size: 18),
          ]),
        ),
      );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(14)),
    child: child,
  );

  Widget _slider(String label, double val, double min, double max, ValueChanged<double> cb) =>
      Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(val.toStringAsFixed(2), style: TextStyle(color: AikaTheme.neonBlue, fontSize: 13)),
        ]),
        Slider(value: val, min: min, max: max,
            activeColor: AikaTheme.neonBlue,
            inactiveColor: Colors.white12,
            onChanged: cb),
        const SizedBox(height: 4),
      ]);
}
