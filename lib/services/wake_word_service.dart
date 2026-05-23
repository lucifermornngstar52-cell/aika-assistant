import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Фоновое прослушивание wake word — чистый STT без нативного VAD.
/// Синглтон. Триггеры горячо обновляются при смене имени ассистента.
class WakeWordService {
  WakeWordService._internal();
  static final WakeWordService instance = WakeWordService._internal();
  factory WakeWordService() => instance;

  final SpeechToText _stt = SpeechToText();

  bool _initialized = false;
  bool _isRunning = false;
  bool _isPaused = false;
  bool _musicPlaying = false;
  bool _sttActive = false;

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

  static List<String> _generateVariants(String name) {
    final n = name.toLowerCase().trim();
    if (n.isEmpty) return [];
    final variants = <String>{n};
    const ruToEn = {
      'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd',
      'е': 'e', 'ё': 'yo', 'ж': 'zh', 'з': 'z', 'и': 'i',
      'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
      'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't',
      'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch',
      'ш': 'sh', 'щ': 'sch', 'ъ': '', 'ы': 'y', 'ь': '',
      'э': 'e', 'ю': 'yu', 'я': 'ya',
    };
    String translit = '';
    for (final ch in n.split('')) {
      translit += ruToEn[ch] ?? ch;
    }
    if (translit != n) variants.add(translit);
    if (n == 'айка' || translit == 'aika') {
      variants.addAll(_defaultTriggers);
    }
    return variants.toList();
  }

  Future<void> updateTriggers() async {
    final prefs = await SharedPreferences.getInstance();
    final name = (prefs.getString('assistant_name') ?? 'Aika').trim();
    final customWord = (prefs.getString('custom_wake_word') ?? '').trim().toLowerCase();
    final variants = _generateVariants(name);
    _currentTriggers = <String>{
      ...variants,
      ..._defaultTriggers,
      if (customWord.isNotEmpty) customWord,
    }.toList();
    debugPrint('[WakeWord] триггеры: $_currentTriggers');
  }

  // Совместимость со старым кодом
  void initWithSharedStt(SpeechToText stt) {}

  Future<void> initialize() async {
    if (_initialized) return;
    await updateTriggers();
    _initialized = await _stt.initialize(
      onError: (e) {
        debugPrint('[WakeWord] STT ошибка: $e');
        _sttActive = false;
        if (_isRunning && !_isPaused) {
          _scheduleRestart(const Duration(seconds: 2));
        }
      },
      onStatus: (status) {
        debugPrint('[WakeWord] STT статус: $status');
        if (status == 'done' || status == 'notListening') {
          _sttActive = false;
          _sttTimeoutTimer?.cancel();
          if (_isRunning && !_isPaused) {
            _scheduleRestart(const Duration(milliseconds: 600));
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

  Future<void> pause() async {
    if (_isPaused) return;
    _isPaused = true;
    _sttTimeoutTimer?.cancel();
    _restartTimer?.cancel();
    if (_stt.isListening) await _stt.stop();
    _sttActive = false;
    debugPrint('[WakeWord] ⏸ пауза');
  }

  Future<void> resume() async {
    if (!_isPaused) return;
    _isPaused = false;
    debugPrint('[WakeWord] ▶ возобновление');
    await Future.delayed(const Duration(milliseconds: 300));
    if (_isRunning && !_sttActive) await _startSttLoop();
  }

  /// При медиа: просто останавливаем STT — он перезапустится когда музыка стихнет.
  /// Никакого нативного канала — всё через флаг.
  void setMusicPlaying(bool playing) {
    if (_musicPlaying == playing) return;
    _musicPlaying = playing;

    if (playing) {
      debugPrint('[WakeWord] 🎵 медиа — STT остановлен');
      _restartTimer?.cancel();
      _sttTimeoutTimer?.cancel();
      if (_stt.isListening) _stt.stop();
      _sttActive = false;
    } else {
      debugPrint('[WakeWord] 🎵 медиа остановилась — перезапуск STT');
      if (_isRunning && !_isPaused) {
        _scheduleRestart(const Duration(seconds: 1));
      }
    }
  }

  Future<void> pauseForMusic() async => setMusicPlaying(true);
  Future<void> resumeAfterMusic() async => setMusicPlaying(false);

  void _scheduleRestart(Duration delay) {
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () async {
      if (_isRunning && !_isPaused && !_musicPlaying && !_sttActive) {
        await _startSttLoop();
      }
    });
  }

  Future<void> _startSttLoop() async {
    if (!_isRunning || _isPaused || _musicPlaying || !_initialized) return;
    if (_stt.isListening || _sttActive) return;

    try {
      _sttActive = true;
      await _stt.listen(
        localeId: 'ru-RU',
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 3),
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

      _sttTimeoutTimer?.cancel();
      _sttTimeoutTimer = Timer(const Duration(minutes: 6), () {
        if (_sttActive && _stt.isListening) {
          debugPrint('[WakeWord] ⚠️ таймаут — перезапуск');
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
      if (!_isRunning || _isPaused || _musicPlaying) return;
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
    _musicPlaying = false;
    _watchdogTimer?.cancel();
    _restartTimer?.cancel();
    _sttTimeoutTimer?.cancel();
    if (_stt.isListening) await _stt.stop();
    debugPrint('[WakeWord] ⏹ остановлен');
  }
}
