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
  static const String _ruLocaleId = 'ru-RU';

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get isAvailable => _isAvailable;
  String get lastWords => _lastWords;
  double get soundLevel => _soundLevel;

  /// Expose shared STT instance for WakeWordService
  SpeechToText get sharedStt => _stt;

  Future<void> initialize() async {
    // ── STT ──────────────────────────────────────────────────────────
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

    if (_isAvailable) {
      final locales = await _stt.locales();
      final ruLocale = locales.where(
        (l) => l.localeId.startsWith('ru'),
      ).toList();
      debugPrint('[STT] Russian locales found: ${ruLocale.map((l) => l.localeId).join(", ")}');
      if (ruLocale.isEmpty) {
        debugPrint('[STT] ⚠️ Russian STT pack not installed on device!');
      }
    }

    debugPrint('[STT] Available: $_isAvailable | locale: $_ruLocaleId');

    // ── TTS ──────────────────────────────────────────────────────────
    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.85);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.1);

    try {
      final voices = await _tts.getVoices;
      if (voices != null) {
        final allVoices = voices as List;
        final ruVoices = allVoices
            .where((v) => v['locale']?.toString().toLowerCase().startsWith('ru') ?? false)
            .toList();

        debugPrint('[TTS] Russian voices: ${ruVoices.map((v) => v['name']).join(", ")}');

        if (ruVoices.isNotEmpty) {
          final femaleVoice = ruVoices.firstWhere(
            (v) {
              final name = v['name']?.toString().toLowerCase() ?? '';
              return name.contains('female') ||
                  name.contains('alena') ||
                  name.contains('svetlana') ||
                  name.contains('katya') ||
                  name.contains('marina');
            },
            orElse: () => ruVoices.first,
          );
          final voiceName = femaleVoice['name']?.toString() ?? '';
          final voiceLocale = femaleVoice['locale']?.toString() ?? 'ru-RU';
          await _tts.setVoice({'name': voiceName, 'locale': voiceLocale});
          debugPrint('[TTS] Voice set: $voiceName ($voiceLocale)');
        } else {
          await _tts.setLanguage('ru-RU');
          debugPrint('[TTS] ⚠️ No ru voices, forcing language ru-RU');
        }
      }
    } catch (e) {
      debugPrint('[TTS] getVoices error: $e');
      await _tts.setLanguage('ru-RU');
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

    String _partialText = '';
    await _stt.listen(
      localeId: _ruLocaleId,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(milliseconds: 1800), // 1800ms — достаточно для речи
      cancelOnError: false,
      partialResults: true,
      listenMode: ListenMode.dictation,
      onResult: (result) {
        _lastWords = result.recognizedWords;
        _partialText = _lastWords;
        _soundLevel = 0;
        notifyListeners();
        // Срабатываем на finalResult или если есть текст при остановке
        if (result.finalResult) {
          final words = _lastWords.isNotEmpty ? _lastWords : _partialText;
          if (words.isNotEmpty) {
            _isListening = false;
            notifyListeners();
            onResult(words);
            onDone();
          } else {
            _isListening = false;
            notifyListeners();
            onDone();
          }
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

