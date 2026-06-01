import 'package:speech_to_text/speech_to_text.dart';

class WakeWordService {
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  static const String wakeWord = 'айка';

  Future<void> initialize() async {
    await _speech.initialize();
  }

  Future<void> startListening(Function() onWakeWordDetected) async {
    if (_isListening) return;
    _isListening = true;
    _listen(onWakeWordDetected);
  }

  void _listen(Function() onWakeWordDetected) {
    if (!_isListening) return;
    _speech.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase();
        if (text.contains(wakeWord)) {
          onWakeWordDetected();
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      localeId: 'ru_RU',
      onSoundLevelChange: null,
    );
    _speech.statusListener = (status) {
      if (status == 'done' && _isListening) {
        Future.delayed(const Duration(milliseconds: 500), () => _listen(onWakeWordDetected));
      }
    };
  }

  Future<void> stop() async {
    _isListening = false;
    await _speech.stop();
  }
}
