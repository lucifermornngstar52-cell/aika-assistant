import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/edge_tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// Фиксированный список голосов Google TTS. EdgeTTS мёртв (Microsoft закрыл
/// бесплатный доступ), поэтому только системные голоса Android.
/// Только эти шесть, имя карточки — чистое имя голоса.
const _curatedVoices = <Map<String, String>>[
  {'name': 'ru-ru-xruf-local',    'label': 'Дмитрий', 'locale': 'ru-RU'},
  {'name': 'en-gb-x-gbs-network', 'label': 'Ella',    'locale': 'en-GB'},
  {'name': 'ru-ru-x-ruf-network', 'label': 'Piter',   'locale': 'ru-RU'},
  {'name': 'en-au-x-auc-network', 'label': 'Stella',  'locale': 'en-AU'},
  {'name': 'ru-ru-x-rud-local',   'label': 'Tim',     'locale': 'ru-RU'},
  {'name': 'ru-ru-x-ruc-local',   'label': 'Astra',   'locale': 'ru-RU'},
];

class SettingsVoiceScreen extends StatefulWidget {
  const SettingsVoiceScreen({Key? key}) : super(key: key);
  @override
  State<SettingsVoiceScreen> createState() => _SettingsVoiceScreenState();
}

class _SettingsVoiceScreenState extends State<SettingsVoiceScreen> {
  final FlutterTts _tts = FlutterTts();
  double _rate = 0.5, _pitch = 1.0, _volume = 1.0;
  String? _selectedVoice;
  bool _loading = true;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // EdgeTTS больше не используется: движок всегда системный Google TTS.
    await prefs.setString('tts_engine', 'system');
    EdgeTtsService().setTtsEngine('system');
    try { await _tts.setEngine('com.google.android.tts'); } catch (_) {}
    final savedVoice = prefs.getString('tts_voice');
    if (savedVoice != null && savedVoice.isNotEmpty) {
      _selectedVoice = savedVoice;
      final locale = _curatedVoices
          .firstWhere((v) => v['name'] == savedVoice,
              orElse: () => const {'locale': 'ru-RU'})['locale'];
      await _tts.setVoice({'name': savedVoice, 'locale': locale ?? 'ru-RU'});
    }
    if (mounted) {
      setState(() {
        _rate = prefs.getDouble('tts_rate') ?? 0.5;
        _pitch = prefs.getDouble('tts_pitch') ?? 1.0;
        _volume = prefs.getDouble('tts_volume') ?? 1.0;
        if (_selectedVoice == null) {
          _selectedVoice = _curatedVoices.first['name'];
        }
        _loading = false;
      });
    }
  }

  Future<void> _preview() async {
    if (_previewing) return;
    setState(() => _previewing = true);
    const sample = 'Привет! Вот так будет звучать мой голос.';
    try {
      await _tts.setSpeechRate(_rate);
      await _tts.setPitch(_pitch);
      await _tts.setVolume(_volume);
      final v = _curatedVoices.firstWhere(
          (x) => x['name'] == _selectedVoice,
          orElse: () => _curatedVoices.first);
      await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
      await _tts.speak(sample);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_engine', 'system');
    await prefs.setDouble('tts_rate', _rate);
    await prefs.setDouble('tts_pitch', _pitch);
    await prefs.setDouble('tts_volume', _volume);
    EdgeTtsService().setTtsEngine('system');
    if (_selectedVoice != null) {
      await prefs.setString('tts_voice', _selectedVoice!);
      final v = _curatedVoices.firstWhere(
          (x) => x['name'] == _selectedVoice,
          orElse: () => _curatedVoices.first);
      await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
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
          _label('ГОЛОСА'),
          _card(Column(children: _curatedVoices.map(_voiceTile).toList())),
          const SizedBox(height: 20),
          _label('ПАРАМЕТРЫ ГОЛОСА'),
          _card(Column(children: [
            _slider('Скорость речи', _rate, 0.25, 1.5, (v) => setState(() => _rate = v)),
            _slider('Высота голоса', _pitch, 0.5, 2.0, (v) => setState(() => _pitch = v)),
            _slider('Громкость', _volume, 0.0, 1.0, (v) => setState(() => _volume = v)),
          ])),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _preview,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AikaTheme.neonBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.4)),
              ),
              child: _previewing
                  ? SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AikaTheme.neonBlue))
                  : Text('🔊  Проверить голос', style: TextStyle(color: AikaTheme.neonBlue, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _voiceTile(Map<String, String> v) => GestureDetector(
        onTap: () async {
          setState(() => _selectedVoice = v['name']);
          await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('tts_voice', v['name']!);
        },
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
            Expanded(child: Text(v['label']!,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
            if (_selectedVoice == v['name'])
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
