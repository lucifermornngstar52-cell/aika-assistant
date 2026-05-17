import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Постоянное фоновое прослушивание — как Google Assistant / Gemini.
/// Использует общий SpeechToText из SpeechService, непрерывно слушает
/// без принудительных перезапусков каждые N секунд.
class WakeWordService {
  bool _isRunning = false;
  SpeechToText? _sharedStt;
  Timer? _watchdogTimer;
  Function()? onWakeWord;

  static const List<String> _triggers = [
    'айка', 'aika', 'aica', 'эйка', 'ика', 'ayka',
  ];

  Future<void> initialize() async {
    debugPrint('[WakeWord] ready — ждёт shared STT');
  }

  void initWithSharedStt(SpeechToText stt) {
    _sharedStt = stt;
    debugPrint('[WakeWord] shared STT подключён');
  }

  Future<void> startListening(Function() callback) async {
    if (_sharedStt == null || !_sharedStt!.isAvailable || _isRunning) return;
    onWakeWord = callback;
    _isRunning = true;
    debugPrint('[WakeWord] фоновое прослушивание запущено');
    await _startContinuousListen();
    _startWatchdog();
  }

  /// Запускает непрерывное прослушивание с длинным окном.
  /// По завершению сессии сразу перезапускается — без пауз.
  Future<void> _startContinuousListen() async {
    if (!_isRunning || _sharedStt == null) return;
    if (!_sharedStt!.isAvailable) return;
    // Если уже слушаем (пользователь говорит в микрофон) — не мешаем
    if (_sharedStt!.isListening) return;

    try {
      await _sharedStt!.listen(
        localeId: 'ru_RU',
        // Длинное окно — постоянно открытое, как фоновый детектор
        listenFor: const Duration(minutes: 5),
        // Пауза после молчания — не обрываем сразу
        pauseFor: const Duration(seconds: 30),
        onResult: (result) {
          if (!_isRunning) return;
          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;
          debugPrint('[WakeWord] слышу: $words');
          if (_triggers.any((t) => words.contains(t))) {
            debugPrint('[WakeWord] ✅ Wake word!');
            onWakeWord?.call();
          }
        },
        listenMode: ListenMode.dictation, // dictation = непрерывно, не ждёт финала
      );
    } catch (e) {
      debugPrint('[WakeWord] ошибка listen: $e');
    }

    // После завершения сессии — сразу перезапуск (через 300ms буфер)
    if (_isRunning) {
      await Future.delayed(const Duration(milliseconds: 300));
      _startContinuousListen();
    }
  }

  /// Watchdog — проверяет каждые 15 секунд что STT живой.
  /// Если вдруг завис — перезапускает. Не трогает активную сессию.
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_isRunning) return;
      if (_sharedStt == null || !_sharedStt!.isAvailable) return;
      // Если не слушаем — значит сессия упала, перезапускаем
      if (!_sharedStt!.isListening) {
        debugPrint('[WakeWord] watchdog: перезапуск...');
        _startContinuousListen();
      }
    });
  }

  Future<void> stop() async {
    _isRunning = false;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    // Не останавливаем _sharedStt — им управляет SpeechService
    debugPrint('[WakeWord] остановлено');
  }

  bool get isRunning => _isRunning;
}
