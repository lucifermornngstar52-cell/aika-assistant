import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// SpeechService — владелец единственного экземпляра SpeechToText.
/// WakeWordService получает shared доступ через sharedStt.
class SpeechService extends ChangeNotifier {
  // Синглтон — один STT на всё приложение
  static SpeechService? _instance;
  factory SpeechService() => _instance ??= SpeechService._internal();
  SpeechService._internal();

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isAvailable = false;
  String _lastWords = '';
  double _soundLevel = 0.0;
  static const String _ruLocaleId = 'ru_RU';

  bool get isListening => _isListening;
  bool get isSpeaking  => _isSpeaking;
  bool get isAvailable => _isAvailable;
  String get lastWords => _lastWords;
  double get soundLevel => _soundLevel;

  /// Shared STT для WakeWordService — не создавать второй экземпляр!
  SpeechToText get sharedStt => _stt;

  Future<void> initialize() async {
    // ── STT ──────────────────────────────────────────────────────────────
    _isAvailable = await _stt.initialize(
      onError: (error) {
        debugPrint('[STT] error: $error');
        // При ошибке — сбрасываем флаг чтобы можно было начать снова
        if (_isListening) {
          _isListening = false;
          notifyListeners();
        }
      },
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
      final ruLocales = locales.where((l) => l.localeId.startsWith('ru')).toList();
      debugPrint('[STT] Russian locales: ${ruLocales.map((l) => l.localeId).join(", ")}');
      if (ruLocales.isEmpty) {
        debugPrint('[STT] ⚠️ Русский языковой пакет НЕ установлен на устройстве!');
      }
    }
    debugPrint('[STT] Available: $_isAvailable');

    // ── TTS (системный fallback) ─────────────────────────────────────────
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
              return name.contains('female') || name.contains('alena') ||
                  name.contains('svetlana') || name.contains('katya') ||
                  name.contains('marina') || name.contains('dariya');
            },
            orElse: () => ruVoices.first,
          );
          await _tts.setVoice({
            'name': femaleVoice['name']?.toString() ?? '',
            'locale': femaleVoice['locale']?.toString() ?? 'ru-RU',
          });
        }
      }
    } catch (e) {
      debugPrint('[TTS] voices error: $e');
    }
  }

  Future<void> startListening(
    Function(String text) onResult, {
    Function()? onListeningStart,
  }) async {
    if (!_isAvailable) {
      debugPrint('[STT] недоступен');
      return;
    }
    // Если уже слушаем — останавливаем сначала
    if (_stt.isListening) {
      await _stt.stop();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _isListening = true;
    _lastWords = '';
    notifyListeners();
    onListeningStart?.call();

    _stt.listen(
      onResult: (result) {
        _lastWords = result.recognizedWords;
        _soundLevel = 0;
        notifyListeners();
        if (result.finalResult && _lastWords.isNotEmpty) {
          debugPrint('[STT] финал: $_lastWords');
          onResult(_lastWords);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      localeId: _ruLocaleId,
      onSoundLevelChange: (level) {
        _soundLevel = level;
        notifyListeners();
      },
      cancelOnError: false,
      partialResults: true,
    );
  }

  Future<void> stopListening() async {
    _isListening = false;
    await _stt.stop();
    notifyListeners();
  }

  Future<void> speak(String text) async {
    _isSpeaking = true;
    notifyListeners();
    final done = Completer<void>();
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      notifyListeners();
      if (!done.isCompleted) done.complete();
    });
    _tts.setErrorHandler((_) {
      _isSpeaking = false;
      notifyListeners();
      if (!done.isCompleted) done.complete();
    });
    await _tts.speak(text);
    await done.future.timeout(
      Duration(seconds: (text.length / 6).ceil() + 5),
      onTimeout: () { _isSpeaking = false; notifyListeners(); },
    );
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    _isSpeaking = false;
    notifyListeners();
  }
}
