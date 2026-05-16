import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Listens continuously in background for wake word "айка" or "aika".
/// When detected, calls [onWakeWord].
class WakeWordService {
  final SpeechToText _stt = SpeechToText();
  bool _isRunning = false;
  bool _isAvailable = false;
  Timer? _restartTimer;
  Function()? onWakeWord;

  static const List<String> _triggers = [
    'айка', 'aika', 'aica', 'эйка', 'ика', 'ayka',
  ];

  Future<void> initialize() async {
    _isAvailable = await _stt.initialize(
      onError: (e) => debugPrint('[WakeWord] STT error: $e'),
    );
    debugPrint('[WakeWord] Available: $_isAvailable');
  }

  Future<void> startListening(Function() callback) async {
    if (!_isAvailable || _isRunning) return;
    onWakeWord = callback;
    _isRunning = true;
    _listen();
  }

  void _listen() {
    if (!_isRunning || !_isAvailable) return;
    _stt.listen(
      localeId: 'ru_RU',
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase();
        debugPrint('[WakeWord] Heard: $words');
        if (_triggers.any((t) => words.contains(t))) {
          debugPrint('[WakeWord] 🔥 Wake word detected!');
          onWakeWord?.call();
        }
      },
      listenMode: ListenMode.confirmation,
    ).then((_) {
      // Restart after session ends
      if (_isRunning) {
        _restartTimer = Timer(const Duration(milliseconds: 500), _listen);
      }
    });
  }

  Future<void> stop() async {
    _isRunning = false;
    _restartTimer?.cancel();
    await _stt.stop();
  }

  bool get isRunning => _isRunning;
}
