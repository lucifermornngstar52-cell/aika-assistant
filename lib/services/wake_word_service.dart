import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// WakeWordService — использует ОБЩИЙ экземпляр SpeechToText из SpeechService
/// чтобы не конфликтовать за микрофон.
class WakeWordService {
  static WakeWordService? _instance;
  factory WakeWordService() => _instance ??= WakeWordService._();
  WakeWordService._();

  SpeechToText? _stt;

  bool _isListening  = false;
  bool _paused       = false;
  bool _musicPlaying = false;
  List<String> _triggers = ['айка', 'aika'];
  Function()? _onWakeWord;

  static const String wakeWord = 'айка';

  // ─── Инициализация ──────────────────────────────────────────────────────────

  Future<void> initWithSharedStt(SpeechToText stt) async {
    _stt = stt;
    debugPrint('[WakeWord] инициализирован с shared STT');
  }

  /// Устаревший — для совместимости
  Future<void> initialize() async {
    debugPrint('[WakeWord] initialize() вызван — ждём shared STT');
  }

  // ─── Запуск ────────────────────────────────────────────────────────────────

  Future<void> startListening(Function() onWakeWordDetected) async {
    _onWakeWord = onWakeWordDetected;
    if (_isListening) return;
    if (_stt == null) {
      debugPrint('[WakeWord] ❌ STT не передан');
      return;
    }
    _isListening = true;
    _paused = false;
    _listen(onWakeWordDetected);
  }

  void _listen(Function() callback) {
    if (!_isListening || _paused || _musicPlaying) return;
    final stt = _stt;
    if (stt == null || !stt.isAvailable) return;

    // Если STT уже слушает (активный диалог) — ждём освобождения
    if (stt.isListening) {
      Future.delayed(const Duration(milliseconds: 500), () => _listen(callback));
      return;
    }

    stt.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase();
        debugPrint('[WakeWord] услышал: $text');
        if (_paused || _musicPlaying) return;
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
          _isListening && !_paused && !_musicPlaying) {
        Future.delayed(const Duration(milliseconds: 300), () => _listen(callback));
      }
    };
  }

  // ─── Пауза / Возобновление ─────────────────────────────────────────────────

  /// Пауза во время речи ассистента.
  /// ⚡ Реально останавливает STT чтобы не записывать звук TTS в микрофон.
  Future<void> pause() async {
    if (_paused) return;
    _paused = true;
    debugPrint('[WakeWord] пауза');
    final stt = _stt;
    // Останавливаем STT только если WakeWord им владеет (не активный диалог)
    if (stt != null && stt.isListening) {
      try {
        await stt.stop();
      } catch (e) {
        debugPrint('[WakeWord] pause stop error: $e');
      }
    }
  }

  Future<void> resume() async {
    if (!_isListening || !_paused) return;
    _paused = false;
    debugPrint('[WakeWord] возобновление');
    if (_onWakeWord != null && !_musicPlaying) {
      // Задержка чтобы TTS/EdgeTTS успел завершить воспроизведение
      await Future.delayed(const Duration(milliseconds: 500));
      _listen(_onWakeWord!);
    }
  }

  // ─── Музыка / Видео ────────────────────────────────────────────────────────

  /// Вызывается когда начинается/заканчивается воспроизведение медиа.
  /// ⚡ При playing=true — полностью останавливает STT пока играет медиа.
  void setMusicPlaying(bool playing) {
    final wasPlaying = _musicPlaying;
    _musicPlaying = playing;

    if (playing && !wasPlaying) {
      debugPrint('[WakeWord] 🎵 медиа играет — отключаем микрофон');
      _paused = true;
      final stt = _stt;
      if (stt != null && stt.isListening) {
        stt.stop().catchError((e) {
          debugPrint('[WakeWord] music stop error: $e');
        });
      }
    } else if (!playing && wasPlaying) {
      debugPrint('[WakeWord] 🎵 медиа остановлена — включаем микрофон');
      _paused = false;
      if (_isListening && _onWakeWord != null) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!_musicPlaying && !_paused) _listen(_onWakeWord!);
        });
      }
    }
  }

  // ─── Прочее ────────────────────────────────────────────────────────────────

  Future<void> updateTriggers([List<String>? triggers]) async {
    if (triggers != null && triggers.isNotEmpty) {
      _triggers = triggers;
    } else {
      _triggers = ['айка', 'aika'];
    }
  }

  bool get isListening => _isListening && !_paused && !_musicPlaying;
  bool get isMusicPlaying => _musicPlaying;

  Future<void> stop() async {
    _isListening = false;
    _paused = false;
    debugPrint('[WakeWord] остановлен');
    // НЕ останавливаем shared STT — он нужен SpeechService
  }
}
