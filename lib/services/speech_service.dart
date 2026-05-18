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
  String _ruLocaleId = 'ru_RU'; // будет перезаписан при init

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
      debugPrint('[STT] All locales: ${locales.map((l) => l.localeId).join(", ")}');

      // Ищем русскую локаль — пробуем несколько вариантов написания
      LocaleName? ruLocale;
      for (final candidate in ['ru_RU', 'ru-RU', 'ru']) {
        try {
          ruLocale = locales.firstWhere(
            (l) => l.localeId == candidate || l.localeId.startsWith('ru'),
          );
          break;
        } catch (_) {}
      }

      if (ruLocale != null) {
        _ruLocaleId = ruLocale.localeId;
        debugPrint('[STT] Russian locale found: $_ruLocaleId');
      } else {
        // Fallback — используем системную, но логируем предупреждение
        debugPrint('[STT] ⚠️ Russian locale NOT found! Using default. Install Russian STT pack.');
        _ruLocaleId = locales.isNotEmpty ? locales.first.localeId : 'ru_RU';
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
        debugPrint('[TTS] Total voices: ${allVoices.length}');

        final ruVoices = allVoices
            .where((v) => v['locale']?.toString().toLowerCase().startsWith('ru') ?? false)
            .toList();

        debugPrint('[TTS] Russian voices: ${ruVoices.map((v) => v['name']).join(", ")}');

        if (ruVoices.isNotEmpty) {
          // Предпочитаем женский голос
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
          // Нет установленных русских голосов — принудительно ставим язык
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

    await _stt.listen(
      localeId: _ruLocaleId,          // динамически найденный ru locale
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      cancelOnError: false,
      partialResults: true,
      listenMode: ListenMode.dictation, // диктовочный режим — лучше для русского
      onResult: (result) {
        _lastWords = result.recognizedWords;
        _soundLevel = 0;
        notifyListeners();
        if (result.finalResult && _lastWords.isNotEmpty) {
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
