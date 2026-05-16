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
    // FIXED: initialize STT — locale forced to ru_RU
    _isAvailable = await _stt.initialize(
      onError: (error) => debugPrint('[STT] error: $error'),
      onStatus: (status) {
        debugPrint('[STT] status: $status');
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          notifyListeners();
        }
      },
    );

    debugPrint('[STT] Available: $_isAvailable');

    // FIXED: TTS — force Russian language
    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.85);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.1);

    // FIXED: Select Russian female voice explicitly
    final voices = await _tts.getVoices;
    if (voices != null) {
      final allVoices = voices as List;
      debugPrint('[TTS] Available voices: ${allVoices.length}');

      // Priority: ru-RU female > ru-RU any > ru any
      final ruVoices = allVoices
          .where((v) => v['locale']?.toString().startsWith('ru') ?? false)
          .toList();

      if (ruVoices.isNotEmpty) {
        // Prefer female voice
        final femaleVoice = ruVoices.firstWhere(
          (v) =>
              v['name']?.toString().toLowerCase().contains('female') == true ||
              v['name']?.toString().toLowerCase().contains('alena') == true ||
              v['name']?.toString().toLowerCase().contains('svetlana') == true ||
              v['name']?.toString().toLowerCase().contains('katya') == true,
          orElse: () => ruVoices.first,
        );
        await _tts.setVoice({
          'name': femaleVoice['name'],
          'locale': 'ru-RU',
        });
        debugPrint('[TTS] Voice set: ${femaleVoice['name']}');
      } else {
        // Fallback: just set language, Android will pick default ru voice
        await _tts.setLanguage('ru-RU');
        debugPrint('[TTS] No ru voices found, using language fallback');
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

    _tts.setErrorHandler((msg) {
      debugPrint('[TTS] error: $msg');
      _isSpeaking = false;
      notifyListeners();
    });

    notifyListeners();
  }

  Future<void> startListening({
    required Function(String) onResult,
    required Function() onDone,
  }) async {
    if (!_isAvailable || _isListening) return;
    _lastWords = '';
    _isListening = true;
    notifyListeners();

    await _stt.listen(
      // FIXED: force Russian locale for speech recognition
      localeId: 'ru_RU',
      onResult: (result) {
        _lastWords = result.recognizedWords;
        notifyListeners();
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
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
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 2),
      // FIXED: use dictation mode for better Russian recognition
      listenMode: ListenMode.dictation,
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
    // FIXED: ensure Russian language is set before each speak call
    await _tts.setLanguage('ru-RU');
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
    String? voiceName,
  }) async {
    if (rate != null) await _tts.setSpeechRate(rate);
    if (pitch != null) await _tts.setPitch(pitch);
    if (volume != null) await _tts.setVolume(volume);
    if (voiceName != null) {
      await _tts.setVoice({'name': voiceName, 'locale': 'ru-RU'});
    }
  }

  /// Returns list of available Russian voices
  Future<List<Map<String, String>>> getRussianVoices() async {
    final voices = await _tts.getVoices;
    if (voices == null) return [];
    return (voices as List)
        .where((v) => v['locale']?.toString().startsWith('ru') ?? false)
        .map((v) => {
              'name': v['name']?.toString() ?? '',
              'locale': v['locale']?.toString() ?? '',
            })
        .toList();
  }
}
