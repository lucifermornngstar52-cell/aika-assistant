import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OpenAiTtsService — TTS через OpenAI Audio API.
/// Голос "onyx" — самый близкий к JARVIS (Пол Беттани) из доступных.
///
/// Модели: tts-1 (быстрее), tts-1-hd (качественнее)
/// Голоса: alloy, echo, fable, onyx, nova, shimmer
class OpenAiTtsService {
  static OpenAiTtsService? _instance;
  factory OpenAiTtsService() => _instance ??= OpenAiTtsService._internal();
  OpenAiTtsService._internal();

  static const _keyOpenAi = 'openai_tts_key';
  static const _keyVoice = 'openai_tts_voice';
  static const _keyModel = 'openai_tts_model';
  static const _keySpeed = 'openai_tts_speed';

  static const _defaultVoice = 'onyx';   // JARVIS-подобный
  static const _defaultModel = 'tts-1-hd';
  static const _defaultSpeed = 1.0;

  String _apiKey = '';
  String _voice = _defaultVoice;
  String _model = _defaultModel;
  double _speed = _defaultSpeed;
  bool _initialized = false;

  final AudioPlayer _player = AudioPlayer();
  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  /// Голоса, доступные в OpenAI TTS
  static const voices = [
    {'id': 'onyx',   'label': '🤖 Onyx  (JARVIS-стиль, мужской)'},
    {'id': 'echo',   'label': '🎙️ Echo  (мужской, спокойный)'},
    {'id': 'fable',  'label': '📖 Fable (британский, мягкий)'},
    {'id': 'alloy',  'label': '⚙️ Alloy (нейтральный)'},
    {'id': 'nova',   'label': '✨ Nova  (женский)'},
    {'id': 'shimmer', 'label': '💫 Shimmer (женский, тёплый)'},
  ];

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_keyOpenAi) ?? '';
    _voice = prefs.getString(_keyVoice) ?? _defaultVoice;
    _model = prefs.getString(_keyModel) ?? _defaultModel;
    _speed = (prefs.getDouble(_keySpeed) ?? _defaultSpeed);
    _player.onPlayerComplete.listen((_) { _isSpeaking = false; });
    _initialized = true;
  }

  void setApiKey(String k) { _apiKey = k; }
  void setVoice(String v) { _voice = v; }
  void setModel(String m) { _model = m; }
  void setSpeed(double s) { _speed = s; }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOpenAi, _apiKey);
    await prefs.setString(_keyVoice, _voice);
    await prefs.setString(_keyModel, _model);
    await prefs.setDouble(_keySpeed, _speed);
  }

  /// Синтезирует речь и проигрывает её.
  /// [text] — текст для озвучки.
  Future<void> speak(String text) async {
    if (_apiKey.isEmpty) {
      _isSpeaking = false;
      return;
    }
    if (text.trim().isEmpty) return;
    await init();
    _isSpeaking = true;
    try {
      final url = Uri.parse('https://api.openai.com/v1/audio/speech');
      final resp = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'input': text,
          'voice': _voice,
          'response_format': 'mp3',
          'speed': _speed,
        }),
      );
      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/jarvis_tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
        await file.writeAsBytes(bytes);
        await _player.play(file.path);
      } else {
        _isSpeaking = false;
      }
    } catch (_) {
      _isSpeaking = false;
    }
  }

  Future<void> stop() async {
    await _player.stop();
    _isSpeaking = false;
  }
}
