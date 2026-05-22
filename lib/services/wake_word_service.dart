import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Непрерывный детектор wake-word на базе нативного AudioRecord VAD.
///
/// Архитектура:
///   ┌─────────────────────────────────────────────────┐
///   │  AudioRecord (Kotlin) — микрофон ВСЕГДА открыт  │
///   │  VAD → speech_start / speech_end события        │
///   └──────────────┬──────────────────────────────────┘
///                  │ EventChannel
///   ┌──────────────▼──────────────────────────────────┐
///   │  speech_to_text.listen() — только когда нужно   │
///   │  Запускается на speech_start (есть голос)        │
///   │  Останавливается и проверяет wake-word           │
///   └─────────────────────────────────────────────────┘
///
/// Преимущества:
///  • Нет "мёртвых зон" — VAD слушает непрерывно
///  • STT запускается только когда есть речь → экономия батареи
///  • Нет циклических перезапусков STT
class WakeWordService {
  WakeWordService._internal();
  static final WakeWordService instance = WakeWordService._internal();
  factory WakeWordService() => instance;

  static const _vadEvent  = EventChannel('com.aika.assistant/vad_events');
  static const _vadMethod = MethodChannel('com.aika.assistant/vad');

  final SpeechToText _stt = SpeechToText();

  bool _sttInitialized = false;
  bool _isRunning = false;
  bool _isPaused = false;
  bool _musicPlaying = false;
  bool _sttListening = false;

  StreamSubscription? _vadSub;
  Timer? _sttStopTimer;
  Timer? _watchdog;

  Function()? onWakeWord;

  static const List<String> _defaultTriggers = [
    'айка', 'aika', 'aica', 'эйка', 'ayka', 'ай ка', 'ай-ка',
  ];
  List<String> _currentTriggers = List.from(_defaultTriggers);

  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;

  // ── Генерация вариантов имени ──────────────────────────────────────────

  static List<String> _generateVariants(String name) {
    final n = name.toLowerCase().trim();
    if (n.isEmpty) return [];
    final variants = <String>{n};
    const ruToEn = {
      'а':'a','б':'b','в':'v','г':'g','д':'d','е':'e','ё':'yo','ж':'zh',
      'з':'z','и':'i','й':'y','к':'k','л':'l','м':'m','н':'n','о':'o',
      'п':'p','р':'r','с':'s','т':'t','у':'u','ф':'f','х':'kh','ц':'ts',
      'ч':'ch','ш':'sh','щ':'sch','ъ':'','ы':'y','ь':'','э':'e','ю':'yu','я':'ya',
    };
    String translit = '';
    for (final ch in n.split('')) translit += ruToEn[ch] ?? ch;
    if (translit != n) variants.add(translit);
    if (n == 'айка' || translit == 'aika') variants.addAll(_defaultTriggers);
    return variants.toList();
  }

  Future<void> updateTriggers() async {
    final prefs = await SharedPreferences.getInstance();
    final name = (prefs.getString('assistant_name') ?? 'Aika').trim();
    final variants = _generateVariants(name);
    _currentTriggers = <String>{...variants, ..._defaultTriggers}.toList();
    debugPrint('[WakeWord] триггеры: $_currentTriggers');
  }

  void initWithSharedStt(SpeechToText stt) {}

  // ── Инициализация ──────────────────────────────────────────────────────

  Future<void> initialize() async {
    await updateTriggers();
    _sttInitialized = await _stt.initialize(
      onError: (e) => debugPrint('[WakeWord] STT error: $e'),
      onStatus: (s) {
        debugPrint('[WakeWord] STT status: $s');
        if (s == 'done' || s == 'notListening') {
          _sttListening = false;
        }
      },
    );
    debugPrint('[WakeWord] STT initialized: $_sttInitialized');
  }

  // ── Запуск ─────────────────────────────────────────────────────────────

  Future<void> startListening(Function() callback) async {
    if (_isRunning) return;
    onWakeWord = callback;
    _isRunning = true;
    _isPaused = false;

    if (!_sttInitialized) await initialize();

    // Запускаем нативный VAD
    try {
      await _vadMethod.invokeMethod('start');
      debugPrint('[WakeWord] ▶ нативный VAD запущен');
    } catch (e) {
      debugPrint('[WakeWord] VAD недоступен — fallback STT loop: $e');
      _startFallbackLoop();
      return;
    }

    // Подписываемся на события VAD
    _vadSub?.cancel();
    _vadSub = _vadEvent.receiveBroadcastStream().listen(
      _onVadEvent,
      onError: (e) {
        debugPrint('[WakeWord] VAD stream error: $e');
        _startFallbackLoop();
      },
    );

    _startWatchdog();
  }

  // ── Обработка VAD событий ──────────────────────────────────────────────

  void _onVadEvent(dynamic event) {
    if (!_isRunning || _isPaused) return;
    final type = event['type'] as String? ?? '';
    final data = event['data'] as String? ?? '';

    switch (type) {
      case 'speech_start':
        debugPrint('[WakeWord] 🎤 VAD: голос обнаружен (RMS=$data)');
        // Если STT уже слушает — ничего не делаем
        if (_sttListening) return;
        // Запускаем STT распознавание
        _startSttRecognition();
        break;

      case 'speech_end':
        // VAD сообщает что тишина — STT сам завершится по pauseFor
        debugPrint('[WakeWord] 🔇 VAD: тишина');
        break;

      case 'status':
        debugPrint('[WakeWord] VAD status: $data');
        break;

      case 'error':
        debugPrint('[WakeWord] VAD ошибка: $data');
        // Fallback на старый STT loop
        if (_isRunning && !_isPaused) _startFallbackLoop();
        break;
    }
  }

  // ── STT распознавание (только когда VAD слышит речь) ──────────────────

  Future<void> _startSttRecognition() async {
    if (!_sttInitialized || _sttListening) return;
    _sttListening = true;
    _sttStopTimer?.cancel();

    try {
      await _stt.listen(
        localeId: 'ru-RU',
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(milliseconds: 800), // очень короткая пауза
        partialResults: true,
        listenMode: ListenMode.search,
        cancelOnError: false,
        onResult: (result) {
          if (!_isRunning || _isPaused) return;
          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;
          debugPrint('[WakeWord] STT слышу: "$words"');

          // Проверяем wake word сразу на partial results — мгновенная реакция
          if (_currentTriggers.any((t) => words.contains(t))) {
            debugPrint('[WakeWord] ✅ WAKE WORD! "$words"');
            _stt.stop();
            _sttListening = false;
            onWakeWord?.call();
          }
        },
      );

      // Страховочный таймер — 12 секунд максимум
      _sttStopTimer = Timer(const Duration(seconds: 12), () {
        if (_sttListening) {
          _stt.stop();
          _sttListening = false;
        }
      });
    } catch (e) {
      debugPrint('[WakeWord] STT ошибка: $e');
      _sttListening = false;
    }
  }

  // ── Пауза / Возобновление ──────────────────────────────────────────────

  Future<void> pause() async {
    if (_isPaused) return;
    _isPaused = true;
    _sttStopTimer?.cancel();

    // Останавливаем STT но НЕ останавливаем VAD — микрофон остаётся открытым
    if (_sttListening) {
      await _stt.stop();
      _sttListening = false;
    }

    try {
      await _vadMethod.invokeMethod('pause');
    } catch (_) {}

    debugPrint('[WakeWord] ⏸ пауза (микрофон открыт)');
  }

  Future<void> resume() async {
    if (!_isPaused) return;
    _isPaused = false;

    try {
      await _vadMethod.invokeMethod('resume');
    } catch (_) {}

    // Небольшая задержка чтобы TTS успел замолчать
    await Future.delayed(const Duration(milliseconds: 200));
    debugPrint('[WakeWord] ▶ возобновление');
  }

  // ── Музыка ────────────────────────────────────────────────────────────

  void setMusicPlaying(bool playing) {
    _musicPlaying = playing;
    // При музыке можно повысить VAD порог чтобы не реагировал на фон
    if (playing) {
      try { _vadMethod.invokeMethod('setThreshold', {'value': 1500.0}); } catch (_) {}
    } else {
      try { _vadMethod.invokeMethod('setThreshold', {'value': 600.0}); } catch (_) {}
    }
  }

  Future<void> pauseForMusic() async => setMusicPlaying(true);
  Future<void> resumeAfterMusic() async => setMusicPlaying(false);

  // ── Watchdog ──────────────────────────────────────────────────────────

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_isRunning || _isPaused) return;
      // Просто проверяем что VAD жив — если нет, перезапускаем
      try {
        await _vadMethod.invokeMethod('resume');
      } catch (e) {
        debugPrint('[WakeWord] watchdog: VAD недоступен, перезапуск');
        await stop();
        if (onWakeWord != null) await startListening(onWakeWord!);
      }
    });
  }

  // ── Fallback: старый STT цикл (если нет нативного VAD) ────────────────

  bool _fallbackActive = false;
  Timer? _fallbackTimer;

  void _startFallbackLoop() {
    if (_fallbackActive) return;
    _fallbackActive = true;
    debugPrint('[WakeWord] ⚠️ Fallback STT loop активирован');
    _runFallbackCycle();
  }

  Future<void> _runFallbackCycle() async {
    if (!_isRunning || _isPaused || !_fallbackActive) return;
    if (_sttListening || _stt.isListening) return;

    try {
      _sttListening = true;
      await _stt.listen(
        localeId: 'ru-RU',
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 3),
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        onResult: (result) {
          if (!_isRunning || _isPaused) return;
          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;
          debugPrint('[WakeWord/fb] слышу: "$words"');
          if (_currentTriggers.any((t) => words.contains(t))) {
            debugPrint('[WakeWord/fb] ✅ WAKE WORD!');
            onWakeWord?.call();
          }
        },
      );
    } catch (e) {
      debugPrint('[WakeWord/fb] ошибка: $e');
      _sttListening = false;
      _fallbackTimer = Timer(const Duration(seconds: 2), _runFallbackCycle);
    }
  }

  // ── Остановка ─────────────────────────────────────────────────────────

  Future<void> stop() async {
    _isRunning = false;
    _isPaused = false;
    _fallbackActive = false;
    _sttStopTimer?.cancel();
    _watchdog?.cancel();
    _fallbackTimer?.cancel();
    _vadSub?.cancel();
    _vadSub = null;

    if (_sttListening) {
      await _stt.stop();
      _sttListening = false;
    }

    try {
      await _vadMethod.invokeMethod('stop');
    } catch (_) {}

    debugPrint('[WakeWord] ⏹ остановлен');
  }
}
