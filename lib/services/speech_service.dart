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

  /// Expose shared STT instance for WakeWordService
  SpeechToText get sharedStt => _stt;

  Future<void> initialize() async {
    _isAvailable = await _stt.initialize(
      onError: (error) => debugPrint('[STT] error: \$error'),
      onStatus: (status) {
        debugPrint('[STT] status: \$status');
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          notifyListeners();
        }
      },
    );

    debugPrint('[STT] Available: \$_isAvailable');

    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.85);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.1);

    final voices = await _tts.getVoices;
    if (voices != null) {
      final allVoices = voices as List;
      debugPrint('[TTS] Available voices: \${allVoices.length}');

      final ruVoices = allVoices
          .where((v) => v['locale']?.toString().startsWith('ru') ?? false)
          .toList();

      if (ruVoices.isNotEmpty) {
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
        debugPrint('[TTS] Voice set: \${femaleVoice['name']}');
      } else {
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
      debugPrint('[TTS] error: \$msg');
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
      localeId: 'ru_RU',
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        _lastWords = result.recognizedWords;
        _soundLevel = 0;
        notifyListeners();
        if (result.finalResult) {
          _isListening = false;
          notifyListeners();
          onResult(_lastWords);
          onDone();
        }
      },
      onSoundLevelChange: (level) {
        _soundLevel = level;
        notifyListeners();
      },
    );
  }

  Future<void> stopListening() async {
    if (_isListening) {
      await _stt.stop();
      _isListening = false;
      notifyListeners();
    }
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  @override
  void dispose() {
    _stt.stop();
    _tts.stop();
    super.dispose();
  }
}
