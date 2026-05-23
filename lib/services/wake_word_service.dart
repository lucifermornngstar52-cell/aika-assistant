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
    // Русские варианты (Google STT может возвращать по-разному)
    'айка', 'ай-ка', 'ай ка', 'аика', 'айко', 'айк',
    'эйка', 'эй-ка', 'эй ка',
    // Латинские транслиты
    'aika', 'aica', 'ayka', 'eika', 'aica',
    // Частичные совпадения (STT иногда добавляет окончания)
    'айкa', 'ayка',
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

    // Основное имя ассистента
    final name = (prefs.getString('assistant_name') ?? 'Aika').trim();
    final variants = _generateVariants(name);

    // Кастомный wake word (если задан отдельно)
    final customWord = (prefs.getString('custom_wake_word') ?? '').trim().toLowerCase();
    final customVariants = customWord.isNotEmpty ? _generateVariants(customWord) : <String>[];

    _currentTriggers = <String>{
      ...variants,
      ..._defaultTriggers,
      ...customVariants,
      if (customWord.isNotEmpty) customWord,
    }.toList();

    debugPrint('[WakeWord] триггеры: \$_currentTriggers');
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
        pauseFor: const Duration(milliseconds: 500), // 500ms пауза для wake word
        partialResults: true,
        listenMode: ListenMode.search,
        cancelOnError: false,
        onResult: (result) {
          if (!_isRunning || _isPaused) return;
          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;
          debugPrint('[WakeWord] STT слышу: "$words"');

          // Проверяем и partial и final — что придёт первым
          final matched = _currentTriggers.any((t) => words.contains(t));
          if (matched) {
            debugPrint('[WakeWord] ✅ WAKE WORD! "$words" (final=\${result.finalResult})');
            _stt.stop();
            _sttListening = false;
            onWakeWord?.call();
            return;
          }
          if (result.finalResult) {
            _sttListening = false;
            debugPrint('[WakeWord] финал без wake word: "$words"');
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
      // type=command — микрофон остаётся открытым, просто игнорируем результаты
      await _vadMethod.invokeMethod('pause', {'type': 'command'});
    } catch (_) {}

    debugPrint('[WakeWord] ⏸ пауза команда (микрофон открыт)');
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
    if (_musicPlaying == playing) return; // нет изменений
    _musicPlaying = playing;

    if (playing) {
      // Медиа играет — полностью выключаем микрофон
      debugPrint('[WakeWord] 🎵 медиа играет — микрофон ВЫКЛЮЧЕН');
      _sttStopTimer?.cancel();
      if (_sttListening) {
        _stt.stop();
        _sttListening = false;
      }
      try { _vadMethod.invokeMethod('pause', {'type': 'media'}); } catch (_) {}
    } else {
      // Медиа остановилась — включаем микрофон обратно
      debugPrint('[WakeWord] 🎵 медиа остановилась — микрофон ВКЛЮЧЁН');
      try { _vadMethod.invokeMethod('resume'); } catch (_) {}
    }
  }

  Future<void> pauseForMusic() async => setMusicPlaying(true);
  Future<void> resumeAfterMusic() async => setMusicPlaying(false);

  // ── Watchdog ──────────────────────────────────────────────────────────

  void _startWatchdog() {
    _watchdog?.cancel();
    // Watchdog запускается раз в 60 сек — только проверяет что VAD жив
    // НЕ вызывает resume() без необходимости (это сбрасывало состояние VAD)
    _watchdog = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (!_isRunning || _isPaused) return;
      try {
        // Вместо blindly resume — просто проверяем статус
        final ok = await _vadMethod.invokeMethod<bool>('isRunning') ?? false;
        if (!ok) {
          debugPrint('[WakeWord] watchdog: VAD не запущен, перезапуск...');
          try { await _vadMethod.invokeMethod('start'); } catch (_) {}
        }
      } catch (e) {
        // VAD недоступен совсем — переходим на fallback
        if (_isRunning && !_isPaused && !_fallbackActive) {
          debugPrint('[WakeWord] watchdog: VAD недоступен → fallback STT');
          _startFallbackLoop();
        }
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
        pauseFor: const Duration(seconds: 2),
        listenMode: ListenMode.dictation,
        partialResults: true,
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
