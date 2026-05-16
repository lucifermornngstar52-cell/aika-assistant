import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Listens for wake word using a SHARED SpeechToText instance passed from outside.
/// This avoids the conflict of two concurrent STT sessions on Android.
class WakeWordService {
  bool _isRunning = false;
  SpeechToText? _sharedStt;
  Timer? _restartTimer;
  Function()? onWakeWord;

  static const List<String> _triggers = [
    'айка', 'aika', 'aica', 'эйка', 'ика', 'ayka',
  ];

  /// Initialize with a shared SpeechToText instance from SpeechService.
  void initWithSharedStt(SpeechToText stt) {
    _sharedStt = stt;
    debugPrint('[WakeWord] Initialized with shared STT');
  }

  Future<void> startListening(Function() callback) async {
    if (_sharedStt == null || !_sharedStt!.isAvailable || _isRunning) return;
    onWakeWord = callback;
    _isRunning = true;
    _listen();
  }

  void _listen() {
    if (!_isRunning || _sharedStt == null || !_sharedStt!.isAvailable) return;
    // Don't start if STT is already active (user is speaking)
    if (_sharedStt!.isListening) {
      _restartTimer = Timer(const Duration(milliseconds: 800), _listen);
      return;
    }
    _sharedStt!.listen(
      localeId: 'ru_RU',
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase();
        debugPrint('[WakeWord] Heard: \$words');
        if (_triggers.any((t) => words.contains(t))) {
          debugPrint('[WakeWord] Wake word detected!');
          onWakeWord?.call();
        }
      },
      listenMode: ListenMode.confirmation,
    ).then((_) {
      if (_isRunning) {
        _restartTimer = Timer(const Duration(milliseconds: 500), _listen);
      }
    });
  }

  Future<void> stop() async {
    _isRunning = false;
    _restartTimer?.cancel();
    // Don't stop shared STT here — SpeechService manages it
  }

  bool get isRunning => _isRunning;
}
