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
  String? _edgeVoiceId;
  String? _elevenLabsVoice;
  /// Живые голоса из библиотеки ElevenLabs аккаунта (API /v1/voices)
  List<Map<String, dynamic>> _elLiveVoices = [];
  bool _elVoicesLoading = false;
  final _elKeyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _ttsEngine = prefs.getString('tts_engine') ?? 'edge';
    if (_ttsEngine != 'edge' && _ttsEngine != 'elevenlabs' && _ttsEngine != 'system') {
      _ttsEngine = 'edge';
    }
    _edgeVoiceId = prefs.getString('edge_voice') ?? 'ru-RU-DariyaNeural';
    _elevenLabsVoice = prefs.getString('elevenlabs_voice');
    _elKeyCtrl.text = prefs.getString('elevenlabs_key') ?? '';
    if (_ttsEngine == 'elevenlabs') {
      await _loadElevenVoices();
    }
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


  /// Тянет голоса прямо из библиотеки ElevenLabs аккаунта —
  /// если юзер добавлял/менял голоса на сайте, приложение увидит их сразу.
  Future<void> _loadElevenVoices() async {
    if (_elVoicesLoading) return;
    // Ключ из поля должен попасть в prefs ДО запроса — сервис читает его оттуда
    final prefs = await SharedPreferences.getInstance();
    final key = _elKeyCtrl.text.trim();
    if (key.isNotEmpty) await prefs.setString('elevenlabs_key', key);
    setState(() => _elVoicesLoading = true);
    try {
      final svc = ElevenLabsTtsService();
      await svc.initialize();
      final live = await svc.fetchVoices();
      if (live.isNotEmpty && mounted) {
        setState(() => _elLiveVoices = live);
      }
    } catch (_) {}
    if (mounted) setState(() => _elVoicesLoading = false);
  }

  /// UI-слайдер 0.25..1.5 (норма=0.5) → проценты EdgeTTS SSML (-50%..+150%, норма=0%)
  double _toEdgeRate(double r) => (((r - 0.5) / 0.5) * 100).clamp(-50.0, 150.0);
  /// UI-слайдер 0.5..2.0 (норма=1.0) → сдвиг в Hz для EdgeTTS SSML (-50..+50Hz)
  double _toEdgePitch(double p) => ((p - 1.0) * 50).clamp(-50.0, 50.0);

  bool _previewing = false;

  Future<void> _preview() async {
    if (_previewing) return;
    setState(() => _previewing = true);
    const sample = 'Привет! Вот так будет звучать мой голос.';
    try {
      if (_ttsEngine == 'system') {
        await _tts.setSpeechRate(_rate);
        await _tts.setPitch(_pitch);
        await _tts.setVolume(_volume);
        if (_selectedVoice != null) {
          await _tts.setVoice({'name': _selectedVoice!, 'locale': 'ru-RU'});
        }
        await _tts.speak(sample);
      } else if (_ttsEngine == 'elevenlabs') {
        if (_elevenLabsVoice != null) ElevenLabsTtsService().setVoice(_elevenLabsVoice!);
        await ElevenLabsTtsService().speak(sample);
      } else {
        await EdgeTtsService().previewSpeak(
          sample,
          rate: _toEdgeRate(_rate),
          pitch: _toEdgePitch(_pitch),
          volume: _volume,
          voice: _edgeVoiceId ?? 'ru-RU-DariyaNeural',
        );
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_engine', _ttsEngine);
    await prefs.setDouble('tts_rate', _rate);
    await prefs.setDouble('tts_pitch', _pitch);
    await prefs.setDouble('tts_volume', _volume);

    // ФИКС: раньше EdgeTTS (основной движок) читал edge_tts_rate/edge_tts_pitch,
    // которые здесь никогда не записывались — ползунки не влияли на голос.
    final edgeRate = _toEdgeRate(_rate);
    final edgePitch = _toEdgePitch(_pitch);
    await prefs.setDouble('edge_tts_rate', edgeRate);
    await prefs.setDouble('edge_tts_pitch', edgePitch);
    await prefs.setDouble('edge_tts_volume', _volume);
    EdgeTtsService().setRate(edgeRate);
    EdgeTtsService().setPitch(edgePitch);
    EdgeTtsService().setVolume(_volume);
    if (_ttsEngine == 'edge') {
      final voice = _edgeVoiceId ?? 'ru-RU-DariyaNeural';
      await prefs.setString('edge_voice', voice);
      EdgeTtsService().setVoice(voice);
    }
    if (_ttsEngine == 'system' && _selectedVoice != null) {
      await prefs.setString('tts_voice', _selectedVoice!);
    }
    if (_ttsEngine == 'elevenlabs') {
      await prefs.setString('elevenlabs_key', _elKeyCtrl.text.trim());
      if (_elevenLabsVoice != null) {
        await prefs.setString('elevenlabs_voice', _elevenLabsVoice!);
        ElevenLabsTtsService().setVoice(_elevenLabsVoice!);
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
            _label(_elLiveVoices.isNotEmpty
                ? 'ГОЛОСА ELEVENLABS — ИЗ ТВОЕЙ БИБЛИОТЕКИ'
                : 'ГОЛОСА ELEVENLABS'),
            if (_elVoicesLoading)
              Padding(padding: const EdgeInsets.only(bottom: 8),
                child: Text('Загружаю голоса из библиотеки...',
                    style: TextStyle(color: Colors.white54, fontSize: 12))),
            if (_elLiveVoices.isEmpty && !_elVoicesLoading)
              ...ElevenLabsTtsService.voices.map((v) => _elVoiceTile(
                  v['id']!, v['label']!)),
            if (_elLiveVoices.isNotEmpty)
              ..._elLiveVoices.map((v) => _elVoiceTile(
                  v['id'] as String,
                  (v['name'] as String? ?? 'Голос') +
                      ((v['category'] as String?)?.isNotEmpty == true
                          ? ' (${v['category']})' : ''))),
            const SizedBox(height: 12),
            TextField(
              controller: _elKeyCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'xi-api-key (ключ ElevenLabs)',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF1C1C1E),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _loadElevenVoices(),
            ),
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Text('Ключ можно вставить один раз — голоса подтянутся из твоей библиотеки. Оставь пустым, если ключ уже зашит в сборку.',
                  style: TextStyle(color: Colors.white38, fontSize: 11))),
            const SizedBox(height: 20),
          ],

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
          const SizedBox(height: 20),
          if (_ttsEngine == 'edge') ...[
            const SizedBox(height: 20),
            _label('НЕЙРОННЫЙ ГОЛОС (EdgeTTS)'),
            ...EdgeTtsService.voices.map((v) => GestureDetector(
              onTap: () async {
                final id = v['id']!;
                setState(() => _edgeVoiceId = id);
                EdgeTtsService().setVoice(id);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('edge_voice', id);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _edgeVoiceId == v['id']
                      ? AikaTheme.neonBlue.withOpacity(0.15)
                      : const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _edgeVoiceId == v['id'] ? AikaTheme.neonBlue : Colors.transparent,
                  ),
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v['label']!, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(v['description'] ?? 'Бесплатный нейронный голос', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ])),
                  if (_edgeVoiceId == v['id'])
                    Icon(Icons.check_circle, color: AikaTheme.neonBlue, size: 18),
                ]),
              ),
            )),
          ] else if (_voices.isNotEmpty && _ttsEngine == 'system') ...[
            const SizedBox(height: 20),
            _label('СИСТЕМНЫЙ ГОЛОС'),
            ..._voices.map((v) => GestureDetector(
              onTap: () async {
                final name = v['name'];
                if (name == null) return;
                setState(() => _selectedVoice = name);
                await _tts.setVoice({'name': name, 'locale': v['locale'] ?? 'ru-RU'});
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('tts_voice', name);
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
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                    Text(v['locale'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ])),
                  if (_selectedVoice == v['name'])
                    Icon(Icons.check_circle, color: AikaTheme.neonBlue, size: 18),
                ]),
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _elVoiceTile(String id, String label) => GestureDetector(
    onTap: () => setState(() => _elevenLabsVoice = id),
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _elevenLabsVoice == id
            ? AikaTheme.neonBlue.withOpacity(0.15)
            : const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _elevenLabsVoice == id ? AikaTheme.neonBlue : Colors.transparent,
        ),
      ),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13))),
        if (_elevenLabsVoice == id)
          Icon(Icons.check_circle, color: AikaTheme.neonBlue, size: 18),
      ]),
    ),
  );

  Widget _engineTile(String title, String engine, String emoji, String subtitle) =>
      GestureDetector(
        onTap: () async {
          setState(() => _ttsEngine = engine);
          EdgeTtsService().setTtsEngine(engine);
          if (engine == 'elevenlabs' && _elLiveVoices.isEmpty) {
            _loadElevenVoices();
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('tts_engine', engine);
        },
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
