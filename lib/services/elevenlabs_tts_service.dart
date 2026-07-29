import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// ElevenLabs TTS — премиум голоса через API
/// Используется как альтернатива EdgeTTS когда выбран в настройках
class ElevenLabsTtsService {
  static ElevenLabsTtsService? _instance;
  factory ElevenLabsTtsService() => _instance ??= ElevenLabsTtsService._internal();
  ElevenLabsTtsService._internal();

  static const String _apiKey = String.fromEnvironment('ELEVENLABS_API_KEY', defaultValue: '');
  static const String _baseUrl = 'https://api.elevenlabs.io/v1';

  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _systemTts = FlutterTts();
  bool _isSpeaking = false;
  String _selectedVoiceId = '';

  bool get isSpeaking => _isSpeaking;
  bool get isAvailable => _apiKey.isNotEmpty;

  /// Популярные голоса ElevenLabs (можно расширить через API)
  static const List<Map<String, String>> voices = [
    {'id': '21m00Tcm4TlvDq8ikWAM', 'label': '🎯 Rachel (женский, естественный)'},
    {'id': 'AZnzlk1XvdvUeBnXmlld', 'label': '🎭 Domi (женский, энергичный)'},
    {'id': 'EXAVITQu4vr4xnSDxMAC', 'label': '🌸 Bella (женский, мягкий)'},
    {'id': 'ErXwobaYiN0zPvpw6OvD', 'label': '👨 Antoni (мужской, глубокий)'},
    {'id': 'VR6AewLTigWG4xSOukaG', 'label': '💼 Josh (мужской, нейтральный)'},
    {'id': 'pNInz6obpgDQ3cQZApym', 'label': '📚 Adam (мужской, рассказчик)'},
    {'id': 'yoZ06aMxZJ28S2JZsmQn', 'label': '🌙 Sam (мужской, спокойный)'},
  ];

  Future<void> initialize() async {
    if (_apiKey.isEmpty) {
      debugPrint('[ElevenLabs] ⚠️ Нет API ключа — сервис неактивен');
      return;
    }
    await _initSystemTts();
    _player.onPlayerComplete.listen((_) { _isSpeaking = false; });
    _loadSettings();
    debugPrint('[ElevenLabs] ✅ Инициализирован');
  }

  Future<void> _initSystemTts() async {
    await _systemTts.setLanguage('ru-RU');
    await _systemTts.setSpeechRate(0.85);
    await _systemTts.setVolume(1.0);
    await _systemTts.setPitch(1.1);
    _systemTts.setCompletionHandler(() { _isSpeaking = false; });
    _systemTts.setErrorHandler((_) { _isSpeaking = false; });
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedVoiceId = prefs.getString('elevenlabs_voice') ?? voices.first['id']!;
      final rate = prefs.getDouble('elevenlabs_rate') ?? 1.0;
      final stability = prefs.getDouble('elevenlabs_stability') ?? 0.5;
      final similarity = prefs.getDouble('elevenlabs_similarity') ?? 0.75;
      debugPrint('[ElevenLabs] Voice: $_selectedVoiceId, Rate: $rate');
    } catch (_) {}
  }

  void setVoice(String voiceId) {
    _selectedVoiceId = voiceId;
    SharedPreferences.getInstance().then((p) => p.setString('elevenlabs_voice', voiceId));
  }

  /// Синтез речи через ElevenLabs API
  /// Возвращает путь к аудиофайлу или null при ошибке
  Future<String?> _synthesize(String text) async {
    if (_apiKey.isEmpty || _selectedVoiceId.isEmpty) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final stability = prefs.getDouble('elevenlabs_stability') ?? 0.5;
      final similarity = prefs.getDouble('elevenlabs_similarity') ?? 0.75;
      final style = prefs.getDouble('elevenlabs_style') ?? 0.0;

      final resp = await http.post(
        Uri.parse('$_baseUrl/text-to-speech/$_selectedVoiceId'),
        headers: {
          'xi-api-key': _apiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        body: jsonEncode({
          'text': text,
          'model_id': 'eleven_multilingual_v2',
          'voice_settings': {
            'stability': stability,
            'similarity_boost': similarity,
            'style': style,
            'use_speaker_boost': true,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        debugPrint('[ElevenLabs] ❌ HTTP ${resp.statusCode}: ${resp.body.substring(0, 200)}');
        return null;
      }

      // Сохраняем аудио во временный файл
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/elevenlabs_tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await file.writeAsBytes(resp.bodyBytes);
      return file.path;
    } catch (e) {
      debugPrint('[ElevenLabs] ❌ Ошибка: $e');
      return null;
    }
  }

  /// Озвучить текст
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;

    if (_apiKey.isEmpty) {
      // Fallback на системный TTS
      debugPrint('[ElevenLabs] Нет ключа → системный TTS');
      _isSpeaking = true;
      await _systemTts.speak(text);
      return;
    }

    _isSpeaking = true;
    final audioPath = await _synthesize(text);

    if (audioPath == null) {
      // Fallback на системный TTS при ошибке API
      debugPrint('[ElevenLabs] API ошибка → системный TTS fallback');
      await _systemTts.speak(text);
      return;
    }

    try {
      await _player.play(DeviceFileSource(audioPath));
    } catch (e) {
      debugPrint('[ElevenLabs] Ошибка воспроизведения: $e');
      await _systemTts.speak(text);
    }
  }

  /// Остановить озвучивание
  Future<void> stop() async {
    _isSpeaking = false;
    await _player.stop();
    await _systemTts.stop();
  }

  /// Получить список голосов через API (если нужно обновить)
  Future<List<Map<String, dynamic>>> fetchVoices() async {
    if (_apiKey.isEmpty) return [];

    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/voices'),
        headers: {'xi-api-key': _apiKey},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return [];

      final data = jsonDecode(resp.body);
      final voices = data['voices'] as List? ?? [];
      return voices.map((v) => {
        'id': v['voice_id'] as String,
        'name': v['name'] as String,
        'category': v['category'] as String? ?? '',
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Очистка старых аудиофайлов (вызывать периодически)
  Future<void> cleanupOldFiles() async {
    try {
      final dir = await getTemporaryDirectory();
      final files = dir.listSync()
          .where((f) => f.path.contains('elevenlabs_tts_'))
          .where((f) => DateTime.now().difference((f.statSync()).modified).inMinutes > 30);
      for (final f in files) {
        await f.delete();
      }
    } catch (_) {}
  }
}
