import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// WakeWordService — использует ОБЩИЙ экземпляр SpeechToText из SpeechService
/// чтобы не конфликтовать за микрофон.
class WakeWordService {
  // Синглтон
  static WakeWordService? _instance;
  factory WakeWordService() => _instance ??= WakeWordService._();
  WakeWordService._();

  /// Shared STT — передаётся из SpeechService при инициализации
  SpeechToText? _stt;

  bool _isListening = false;
  bool _paused = false;
  bool _musicPlaying = false;
  List<String> _triggers = ['айка', 'aika'];
  Function()? _onWakeWord;

  static const String wakeWord = 'айка';

  /// Инициализация с общим STT экземпляром
  Future<void> initWithSharedStt(SpeechToText stt) async {
    _stt = stt;
    // STT уже инициализирован в SpeechService — нам ничего делать не надо
    debugPrint('[WakeWord] инициализирован с shared STT');
  }

  /// Устаревший метод — для совместимости (теперь STT shared)
  Future<void> initialize() async {
    // STT инициализируется в SpeechService — ждём initWithSharedStt
    debugPrint('[WakeWord] initialize() вызван — ждём shared STT');
  }

  Future<void> startListening(Function() onWakeWordDetected) async {
    _onWakeWord = onWakeWordDetected;
    if (_isListening) return;
    if (_stt == null) {
      debugPrint('[WakeWord] ❌ STT не передан — вызови initWithSharedStt()');
      return;
    }
    _isListening = true;
    _paused = false;
    _listen(onWakeWordDetected);
  }

  void _listen(Function() callback) {
    if (!_isListening || _paused) return;
    final stt = _stt;
    if (stt == null || !stt.isAvailable) return;

    // Если STT уже слушает (активный диалог) — не перехватываем
    if (stt.isListening) {
      // Повторим через 500мс
      Future.delayed(const Duration(milliseconds: 500), () => _listen(callback));
      return;
    }

    stt.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase();
        debugPrint('[WakeWord] услышал: $text');
        for (final t in _triggers) {
          if (text.contains(t)) {
            debugPrint('[WakeWord] ✅ триггер: $t');
            callback();
            return;
          }
        }
      },
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 4),
      localeId: 'ru_RU',
      onSoundLevelChange: null,
      cancelOnError: false,
    );

    stt.statusListener = (status) {
      debugPrint('[WakeWord] STT status: $status');
      if ((status == 'done' || status == 'notListening') &&
          _isListening && !_paused) {
        Future.delayed(const Duration(milliseconds: 300), () => _listen(callback));
      }
    };
  }

  Future<void> pause() async {
    _paused = true;
    debugPrint('[WakeWord] пауза');
    // НЕ останавливаем STT — он нужен для SpeechService
  }

  Future<void> resume() async {
    if (!_isListening || !_paused) return;
    _paused = false;
    debugPrint('[WakeWord] возобновление');
    if (_onWakeWord != null) {
      // Небольшая задержка чтобы SpeechService успел освободить STT
      await Future.delayed(const Duration(milliseconds: 400));
      _listen(_onWakeWord!);
    }
  }

  void setMusicPlaying(bool playing) {
    _musicPlaying = playing;
    if (playing) pause();
    // При выключении музыки resume() вызовет main_screen
  }

  void updateTriggers([List<String>? triggers]) {
    if (triggers != null && triggers.isNotEmpty) {
      _triggers = triggers;
    } else {
      _triggers = ['айка', 'aika'];
    }
  }

  bool get isListening => _isListening && !_paused;

  Future<void> stop() async {
    _isListening = false;
    _paused = false;
    debugPrint('[WakeWord] остановлен');
    // НЕ останавливаем shared STT
  }
}
