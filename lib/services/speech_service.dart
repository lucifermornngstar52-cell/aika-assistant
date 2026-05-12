import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SpeechService extends ChangeNotifier {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isAvailable = false;
  String _lastWords = '';
  double _soundLevel = 0.0;

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get isAvailable => _isAvailable;
  String get lastWords => _lastWords;
  double get soundLevel => _soundLevel;

  Future<void> initialize() async {
    _isAvailable = await _stt.initialize(
      onError: (error) => debugPrint('STT error: $error'),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          notifyListeners();
        }
      },
    );

    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.85);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.1);

    // Select a good female voice if available
    final voices = await _tts.getVoices;
    if (voices != null) {
      final ruVoices = (voices as List)
          .where((v) => v['locale']?.toString().startsWith('ru') ?? false)
          .toList();
      if (ruVoices.isNotEmpty) {
        await _tts.setVoice({
          'name': ruVoices.first['name'],
          'locale': ruVoices.first['locale'],
        });
      }
    }

    _tts.setStartHandler(() {
      _isSpeaking = true;
      notifyListeners();
    });

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      notifyListeners();
    });

    notifyListeners();
  }

  Future<void> startListening({
    required Function(String) onResult,
    required Function() onDone,
  }) async {
    if (!_isAvailable) return;
    _lastWords = '';
    _isListening = true;
    notifyListeners();

    await _stt.listen(
      localeId: 'ru_RU',
      onResult: (result) {
        _lastWords = result.recognizedWords;
        notifyListeners();
        if (result.finalResult) {
          onResult(result.recognizedWords);
          _isListening = false;
          notifyListeners();
          onDone();
        }
      },
      onSoundLevelChange: (level) {
        _soundLevel = level;
        notifyListeners();
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 2),
    );
  }

  Future<void> stopListening() async {
    await _stt.stop();
    _isListening = false;
    notifyListeners();
  }

  Future<void> speak(String text) async {
    // Remove action tags before speaking
    final cleanText = text.replaceAll(RegExp(r'\[ACTION:[^\]]*\]'), '').trim();
    if (cleanText.isEmpty) return;
    await _tts.stop();
    await _tts.speak(cleanText);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    _isSpeaking = false;
    notifyListeners();
  }

  Future<void> setVoiceSettings({
    double? rate,
    double? pitch,
    double? volume,
  }) async {
    if (rate != null) await _tts.setSpeechRate(rate);
    if (pitch != null) await _tts.setPitch(pitch);
    if (volume != null) await _tts.setVolume(volume);
  }
}
