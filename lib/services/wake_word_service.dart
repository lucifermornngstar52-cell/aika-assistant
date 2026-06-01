import 'package:speech_to_text/speech_to_text.dart';

class WakeWordService {
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  bool _paused = false;
  bool _musicPlaying = false;
  List<String> _triggers = ['айка'];
  static const String wakeWord = 'айка';
  Function()? _onWakeWord;

  Future<void> initialize() async {
    await _speech.initialize();
  }

  Future<void> startListening(Function() onWakeWordDetected) async {
    _onWakeWord = onWakeWordDetected;
    if (_isListening) return;
    _isListening = true;
    _listen(onWakeWordDetected);
  }

  void _listen(Function() onWakeWordDetected) {
    if (!_isListening || _paused) return;
    _speech.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase();
        for (final t in _triggers) {
          if (text.contains(t)) {
            onWakeWordDetected();
            break;
          }
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      localeId: 'ru_RU',
      onSoundLevelChange: null,
    );
    _speech.statusListener = (status) {
      if (status == 'done' && _isListening && !_paused) {
        Future.delayed(const Duration(milliseconds: 500), () => _listen(onWakeWordDetected));
      }
    };
  }

  /// Временно остановить распознавание (например во время активного диалога)
  Future<void> pause() async {
    _paused = true;
    await _speech.stop();
  }

  /// Возобновить прослушивание после паузы
  Future<void> resume() async {
    if (!_isListening || !_paused) return;
    _paused = false;
    if (_onWakeWord != null) _listen(_onWakeWord!);
  }

  /// Уведомить о состоянии музыки (влияет на чувствительность)
  void setMusicPlaying(bool playing) {
    _musicPlaying = playing;
  }

  /// Обновить список триггерных слов
  void updateTriggers(List<String> triggers) {
    _triggers = triggers.isEmpty ? ['айка'] : triggers;
  }

  Future<void> stop() async {
    _isListening = false;
    _paused = false;
    await _speech.stop();
  }
}
