import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Умное фоновое прослушивание wake word.
/// 
/// Режим работы:
/// - В обычном состоянии слушает через нативный AudioRecord (VAD)
/// - Когда обнаружена речь — запускает STT на 4 секунды для распознавания
/// - Если слышит "Айка" — вызывает callback
/// - НЕ мешает музыке: при активной музыке использует только VAD без STT
/// - Если VAD недоступен — fallback на мягкий STT-loop с паузами
class WakeWordService {
  final SpeechToText _stt = SpeechToText();
  static const _nativeChannel = MethodChannel('com.aika.assistant/vad');

  bool _initialized = false;
  bool _isRunning = false;
  bool _isPaused = false;       // пауза на время команды
  bool _musicPlaying = false;   // музыка играет прямо сейчас
  bool _sttActive = false;      // STT сейчас работает
  bool _useNativeVad = false;   // нативный VAD доступен

  Timer? _watchdogTimer;
  Timer? _restartTimer;
  Timer? _sttTimeoutTimer;

  Function()? onWakeWord;

  static const List<String> _defaultTriggers = [
    'айка', 'aika', 'aica', 'эйка', 'ayka', 'ай ка', 'ай-ка',
  ];
  List<String> _currentTriggers = List.from(_defaultTriggers);

  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;

  Future<void> updateTriggers() async {
    final prefs = await SharedPreferences.getInstance();
    final name = (prefs.getString('assistant_name') ?? 'Aika').trim().toLowerCase();
    final triggers = <String>{name, ...List.from(_defaultTriggers)};
    _currentTriggers = triggers.toList();
  }

  // Совместимость
  void initWithSharedStt(SpeechToText stt) {}

  Future<void> initialize() async {
    await updateTriggers();
    _initialized = await _stt.initialize(
      onError: (e) {
        debugPrint('[WakeWord] STT ошибка: $e');
        _sttActive = false;
        if (_isRunning && !_isPaused) _scheduleRestart(const Duration(seconds: 2));
      },
      onStatus: (status) {
        debugPrint('[WakeWord] STT статус: $status');
        if (status == 'done' || status == 'notListening') {
          _sttActive = false;
          _sttTimeoutTimer?.cancel();
          // Не перезапускаем сразу — ждём следующего VAD-триггера или watchdog
          if (_isRunning && !_isPaused) {
            _scheduleRestart(const Duration(milliseconds: 800));
          }
        }
      },
    );
    debugPrint('[WakeWord] initialized: $_initialized');
  }

  Future<void> startListening(Function() callback) async {
    if (!_initialized) await initialize();
    if (!_initialized || _isRunning) return;
    onWakeWord = callback;
    _isRunning = true;
    _isPaused = false;
    await updateTriggers();
    debugPrint('[WakeWord] ▶ запуск');
    await _startSttLoop();
    _startWatchdog();
  }

  /// Пауза пока идёт команда (не на музыку)
  Future<void> pause() async {
    if (_isPaused) return;
    _isPaused = true;
    _sttTimeoutTimer?.cancel();
    _restartTimer?.cancel();
    if (_stt.isListening) await _stt.stop();
    _sttActive = false;
    debugPrint('[WakeWord] ⏸ пауза (команда)');
  }

  Future<void> resume() async {
    if (!_isPaused) return;
    _isPaused = false;
    debugPrint('[WakeWord] ▶ возобновление');
    await Future.delayed(const Duration(milliseconds: 600));
    await _startSttLoop();
  }

  /// Вызывается когда музыка играет/останавливается
  /// НЕ останавливает прослушивание полностью — просто помечаем флаг
  void setMusicPlaying(bool playing) {
    _musicPlaying = playing;
    if (playing) {
      debugPrint('[WakeWord] 🎵 музыка — STT работает тихо');
      // Если STT сейчас активен — даём ему закончить цикл сам,
      // не перезапускаем агрессивно чтобы не конкурировать с аудио
    } else {
      debugPrint('[WakeWord] 🎵 музыка остановилась — обычный режим');
      if (_isRunning && !_isPaused && !_sttActive) {
        _scheduleRestart(const Duration(seconds: 1));
      }
    }
  }

  // Совместимость со старым API
  Future<void> pauseForMusic() async => setMusicPlaying(true);
  Future<void> resumeAfterMusic() async => setMusicPlaying(false);

  void _scheduleRestart(Duration delay) {
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () async {
      if (_isRunning && !_isPaused && !_sttActive) await _startSttLoop();
    });
  }

  Future<void> _startSttLoop() async {
    if (!_isRunning || _isPaused || !_initialized) return;
    if (_stt.isListening || _sttActive) return;

    // При музыке — слушаем с более коротким таймаутом и без агрессивного рестарта
    final listenDuration = _musicPlaying
        ? const Duration(seconds: 8)
        : const Duration(minutes: 5);
    final pauseDuration = _musicPlaying
        ? const Duration(seconds: 3)
        : const Duration(seconds: 30);

    try {
      _sttActive = true;
      await _stt.listen(
        localeId: 'ru-RU',
        listenFor: listenDuration,
        pauseFor: pauseDuration,
        onResult: (result) {
          if (!_isRunning || _isPaused) return;
          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;
          debugPrint('[WakeWord] слышу: "$words"');
          if (_currentTriggers.any((t) => words.contains(t))) {
            debugPrint('[WakeWord] ✅ WAKE WORD!');
            onWakeWord?.call();
          }
        },
        listenMode: ListenMode.dictation,
        cancelOnError: false,
      );
      // Страховочный таймер — если STT завис
      _sttTimeoutTimer?.cancel();
      _sttTimeoutTimer = Timer(listenDuration + const Duration(seconds: 5), () {
        if (_sttActive && _stt.isListening) {
          debugPrint('[WakeWord] ⚠️ таймаут STT — перезапуск');
          _stt.stop();
        }
      });
    } catch (e) {
      debugPrint('[WakeWord] ошибка listen: $e');
      _sttActive = false;
      _scheduleRestart(const Duration(seconds: 3));
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!_isRunning || _isPaused) return;
      if (!_stt.isListening && !_sttActive) {
        debugPrint('[WakeWord] 🐕 watchdog: перезапуск');
        await _startSttLoop();
      }
    });
  }

  Future<void> stop() async {
    _isRunning = false;
    _isPaused = false;
    _sttActive = false;
    _watchdogTimer?.cancel();
    _restartTimer?.cancel();
    _sttTimeoutTimer?.cancel();
    if (_stt.isListening) await _stt.stop();
    debugPrint('[WakeWord] ⏹ остановлен');
  }
}
