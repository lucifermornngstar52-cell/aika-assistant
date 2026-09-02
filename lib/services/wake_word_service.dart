import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'personality_service.dart';

/// MethodChannel для управления нативным AikaMicrophoneService
const _micChannel = MethodChannel('com.aika.assistant/microphone');

/// ──────────────────────────────────────────────────────────────────────
/// WakeWordService — архитектура "ring-buffer + watchdog + короткие сессии"
///
/// Вместо одного бесконечного listen() на 300 секунд, который тухнет:
///
/// 1. FOREGROUND SERVICE — живёт постоянно (AikaMicrophoneService.kt)
///    держит WakeLock + foregroundServiceType=microphone.
///    Android не может его заглушить.
///
/// 2. КОРОТКИЕ СЕССИИ (60 сек) — AudioRecord пересоздаётся быстро,
///    не успевает деградировать. После каждой — cancel() + 200мс буфер
///    + мгновенный restart. Это как "дыхание" — вдох-выдох-вдох.
///
/// 3. RING-BUFFER последних слов — AudioRecord → STT → кольцевой буфер
///    на 5 последних результатов. Если в любом из них есть триггер —
///    срабатывает. Покрывает случаи когда STT "разбил" фразу на 2 части.
///
/// 4. WATCHDOG (каждые 3 сек) — проверяет:
///    а) есть ли живые сэмплы (status менялся за последние N сек)
///    б) если тишина дольше порога → ПОЛНОЕ пересоздание AudioRecord
///       (не пытаемся оживить старый — cancel + re-init + новый listen)
///    в) если _stt.isListening == false но loop активен — форс restart
///
/// 5. КАСКАДНЫЙ RECOVERY:
///    Уровень 1: быстрый restart (cancel + listen)        — 90% случаев
///    Уровень 2: полная реинициализация STT (initialize)  — 9% случаев
///    Уровень 3: kill + revive нативного сервиса          — 1% случаев
/// ──────────────────────────────────────────────────────────────────────

class WakeWordService {
  static WakeWordService? _instance;
  factory WakeWordService() => _instance ??= WakeWordService._();
  WakeWordService._();

  static const _phoneChannel = EventChannel('com.aika.assistant/phone_state');

  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false;

  // ── Состояние ──
  bool _active = false;
  bool _loopRunning = false;
  bool _suppressed = false;
  Timer? _suppressTimer;
  Timer? _watchdogTimer;

  Completer<bool>? _currentCompleter;

  // ── Ring-buffer последних результатов STT ──
  final List<String> _recentWords = [];
  static const int _ringBufferSize = 5;

  // ── Watchdog метрики ──
  DateTime _lastStatusChange = DateTime.now();
  DateTime _lastAudioSample = DateTime.now();
  int _sessionCount = 0;
  int _consecutiveSilent = 0;       // сколько сессий подряд без слов
  int _recoveryLevel = 0;           // текущий уровень recovery

  // Ключевые константы
  static const Duration _sessionTimeout = Duration(seconds: 60);
  static const Duration _watchdogInterval = Duration(seconds: 3);
  static const Duration _silenceThreshold = Duration(seconds: 15);
  static const Duration _recreateBuffer = Duration(milliseconds: 200);

  List<String> _triggers = ['айка', 'aika'];
  Function()? _onWakeWord;

  // ════════════════════════════════════════════════════════════════════
  //  STT callbacks
  // ════════════════════════════════════════════════════════════════════

  void _onSttError(dynamic e) {
    debugPrint('[WakeWord] error: $e');
    _lastStatusChange = DateTime.now();
    _bumpRecoveryLevel();
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete(false);
    }
  }

  void _onSttStatus(String s) {
    debugPrint('[WakeWord] status: $s');
    _lastStatusChange = DateTime.now();
    // 'listening' = получили живые сэмплы
    if (s == 'listening') {
      _lastAudioSample = DateTime.now();
      _recoveryLevel = 0;
    }
    if ((s == 'done' || s == 'notListening') &&
        _currentCompleter != null &&
        !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete(false);
    }
  }

  // ════════════════════════════════════════════════════════════════════
  //  Инициализация
  // ════════════════════════════════════════════════════════════════════

  Future<void> initialize() async {
    _sttReady = await _stt.initialize(
      onError: _onSttError,
      onStatus: _onSttStatus,
    );
    _lastStatusChange = DateTime.now();
    _lastAudioSample = DateTime.now();
    await updateTriggers();
    _listenPhoneState();
    _startWatchdog();
    debugPrint('[WakeWord] init, ready: $_sttReady');
  }

  Future<void> initWithSharedStt(SpeechToText stt) async {
    await initialize();
  }

  void _listenPhoneState() {
    _phoneChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          debugPrint('[WakeWord] phone: ${event['state']}');
        }
      },
      onError: (e) => debugPrint('[WakeWord] phone error: $e'),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  WATCHDOG — каждые 3 секунды
  // ════════════════════════════════════════════════════════════════════

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) async {
      if (!_active || !_loopRunning) return;

      final now = DateTime.now();
      final silenceDuration = now.difference(_lastAudioSample);
      final stuckDuration = now.difference(_lastStatusChange);
      final isListening = _stt.isListening;

      // ── Проверка 1: status не менялся > 15 сек → движок завис ──
      if (stuckDuration > _silenceThreshold && !isListening) {
        debugPrint('[WakeWord] 🔴 Watchdog: stuck ${stuckDuration.inSeconds}s, not listening — LEVEL ${_recoveryLevel + 1}');
        await _forceRecovery();
        return;
      }

      // ── Проверка 2: status менялся, но нет живых сэмплов > 15 сек ──
      // Значит AudioRecord "молчит" — система подавила микрофон
      if (silenceDuration > _silenceThreshold && isListening) {
        debugPrint('[WakeWord] 🟡 Watchdog: silence ${silenceDuration.inSeconds}s while "listening" — recreating AudioRecord');
        await _forceRecovery();
        return;
      }

      // ── Проверка 3: loop активен, но STT не слушает ──
      if (!isListening && _loopRunning && _currentCompleter == null) {
        debugPrint('[WakeWord] 🟠 Watchdog: loop running but not listening — nudge');
        await _nudgeRestart();
        return;
      }
    });
  }

  /// Каскадное восстановление
  Future<void> _forceRecovery() async {
    _recoveryLevel++;

    switch (_recoveryLevel) {
      case 1:
        // Уровень 1: быстрый restart — cancel + слушать заново
        debugPrint('[WakeWord] Recovery L1: quick restart');
        await _quickRestart();
        break;

      case 2:
        // Уровень 2: полная реинициализация STT
        debugPrint('[WakeWord] Recovery L2: full STT re-init');
        await _fullReinit();
        break;

      default:
        // Уровень 3: kill + revive нативного сервиса
        debugPrint('[WakeWord] Recovery L3: kill + revive native service');
        await _reviveNativeService();
        _recoveryLevel = 0;
        break;
    }

    // Завершаем текущую сессию — loop подхватит
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete(false);
    }
    _lastStatusChange = DateTime.now();
    _lastAudioSample = DateTime.now();
  }

  /// Лёгкий пуш — просто прервать текущую сессию, loop сделает новый listen
  Future<void> _nudgeRestart() async {
    try { await _stt.cancel(); } catch (_) {}
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete(false);
    }
  }

  /// Уровень 1: cancel + очистка + новая сессия
  Future<void> _quickRestart() async {
    try { await _stt.cancel(); } catch (_) {}
    await Future.delayed(_recreateBuffer);
  }

  /// Уровень 2: полная реинициализация STT engine
  Future<void> _fullReinit() async {
    try { await _stt.cancel(); } catch (_) {}
    await Future.delayed(_recreateBuffer);
    try {
      _sttReady = await _stt.initialize(
        onError: _onSttError,
        onStatus: _onSttStatus,
      );
      debugPrint('[WakeWord] L2: STT re-init result: $_sttReady');
    } catch (e) {
      debugPrint('[WakeWord] L2: STT re-init failed: $e');
    }
    _sessionCount = 0;
  }

  /// Уровень 3: перезапуск нативного Foreground Service
  Future<void> _reviveNativeService() async {
    try {
      await _micChannel.invokeMethod('stop');
      await Future.delayed(const Duration(milliseconds: 500));
      await _micChannel.invokeMethod('start');
      debugPrint('[WakeWord] L3: native service revived');
    } catch (e) {
      debugPrint('[WakeWord] L3: native revive failed: $e');
    }
    // Также реинициализируем STT
    await _fullReinit();
  }

  void _bumpRecoveryLevel() {
    if (_recoveryLevel < 3) _recoveryLevel++;
  }

  // ════════════════════════════════════════════════════════════════════
  //  Ring-buffer проверки
  // ════════════════════════════════════════════════════════════════════

  void _pushToRingBuffer(String words) {
    _recentWords.add(words.toLowerCase().trim());
    if (_recentWords.length > _ringBufferSize) {
      _recentWords.removeAt(0);
    }
    _lastAudioSample = DateTime.now();
    _consecutiveSilent = 0;
    _recoveryLevel = 0;
  }

  bool _checkTriggers() {
    // Проверяем весь ring-buffer — триггер может быть в любом из последних
    // результатов (STT иногда разбивает фразу на части)
    for (final words in _recentWords) {
      for (final trigger in _triggers) {
        if (words.contains(trigger)) {
          _recentWords.clear();
          return true;
        }
      }
    }
    // Очищаем buffer если не нашли — оставляем только последнее слово
    if (_recentWords.length >= _ringBufferSize) {
      _recentWords.removeRange(0, _recentWords.length - 1);
    }
    return false;
  }

  // ════════════════════════════════════════════════════════════════════
  //  Управление
  // ════════════════════════════════════════════════════════════════════

  Future<void> startListening(Function() onWakeWordDetected) async {
    if (_active) return;
    _onWakeWord = onWakeWordDetected;
    _active = true;
    _recoveryLevel = 0;
    _consecutiveSilent = 0;
    _recentWords.clear();

    // Запрашиваем exemption от battery optimization
    try {
      final isOptimized = await _micChannel.invokeMethod<bool>('isBatteryOptimized') ?? false;
      if (isOptimized) {
        debugPrint('[WakeWord] 🔋 Requesting battery optimization exemption');
        await _micChannel.invokeMethod('requestBatteryOptimization');
      }
    } catch (e) {
      debugPrint('[WakeWord] ⚠ Battery opt check failed: $e');
    }
    // Запускаем нативный Foreground Service
    try {
      await _micChannel.invokeMethod('start');
      debugPrint('[WakeWord] 🎤 AikaMicrophoneService started');
    } catch (e) {
      debugPrint('[WakeWord] ⚠ AikaMicrophoneService failed: $e');
    }
    _startLoop();
  }

  Future<void> stop() async {
    _active = false;
    _loopRunning = false;
    _suppressTimer?.cancel();
    _watchdogTimer?.cancel();
    _suppressed = false;
    _recentWords.clear();
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }
    try {
      await _micChannel.invokeMethod('stop');
      debugPrint('[WakeWord] 🎤 AikaMicrophoneService stopped');
    } catch (_) {}
  }

  Future<void> rearm() async {
    if (!_active) return;
    _recoveryLevel = 0;
    if (!_loopRunning) _startLoop();
  }

  Future<void> disarm() async {
    _loopRunning = false;
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }
  }

  void suppress([int seconds = 3]) {
    _suppressed = true;
    _suppressTimer?.cancel();
    _suppressTimer = Timer(Duration(seconds: seconds), () {
      _suppressed = false;
    });
  }

  Future<void> pause() async {}
  Future<void> resume() async { await rearm(); }
  void setDialogOpen(bool open) { if (!open) rearm(); }
  void setMusicPlaying(bool playing) {}

  Future<void> updateTriggers([List<String>? triggers]) async {
    if (triggers != null && triggers.isNotEmpty) {
      _triggers = triggers;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final assistantName = (prefs.getString('assistant_name') ?? 'Айка').toLowerCase().trim();
    final customRaw = prefs.getString('custom_wake_word') ?? '';

    final Set<String> result = {'айка', 'aika', assistantName};

    if (assistantName.isNotEmpty) {
      result.add(assistantName);
      final translit = assistantName
        .replaceAll('а','a').replaceAll('б','b').replaceAll('в','v')
        .replaceAll('г','g').replaceAll('д','d').replaceAll('е','e')
        .replaceAll('ё','yo').replaceAll('ж','zh').replaceAll('з','z')
        .replaceAll('и','i').replaceAll('й','j').replaceAll('к','k')
        .replaceAll('л','l').replaceAll('м','m').replaceAll('н','n')
        .replaceAll('о','o').replaceAll('п','p').replaceAll('р','r')
        .replaceAll('с','s').replaceAll('т','t').replaceAll('у','u')
        .replaceAll('ф','f').replaceAll('х','h').replaceAll('ц','ts')
        .replaceAll('ч','ch').replaceAll('ш','sh').replaceAll('щ','sch')
        .replaceAll('ъ','').replaceAll('ы','y').replaceAll('ь','')
        .replaceAll('э','e').replaceAll('ю','yu').replaceAll('я','ya');
      if (translit != assistantName) result.add(translit);
    }

    result.addAll(PersonalityService.characterWakeWords);

    if (customRaw.isNotEmpty) {
      for (final w in customRaw.split(',')) {
        final clean = w.trim().toLowerCase();
        if (clean.isNotEmpty) result.add(clean);
      }
    }

    _triggers = result.toList();
  }

  // ════════════════════════════════════════════════════════════════════
  //  ЦИКЛ — короткие сессии по 60 сек с быстрым пересозданием
  // ════════════════════════════════════════════════════════════════════

  void _startLoop() {
    if (_loopRunning) return;
    _loopRunning = true;
    _runLoop();
  }

  Future<void> _runLoop() async {
    debugPrint('[WakeWord] loop started (60s sessions, ring-buffer, watchdog)');

    while (_active && _loopRunning) {
      if (!_sttReady) {
        debugPrint('[WakeWord] STT not ready — waiting 500ms');
        await Future.delayed(const Duration(milliseconds: 500));
        // Пробуем реинициализировать
        try {
          _sttReady = await _stt.initialize(
            onError: _onSttError,
            onStatus: _onSttStatus,
          );
        } catch (_) {}
        continue;
      }

      // cancel() — гарантированно освобождает recognizer перед новой сессией
      try { await _stt.cancel(); } catch (_) {}

      // Короткий буфер — даёт Android время освободить аудио-ресурсы
      await Future.delayed(_recreateBuffer);

      _sessionCount++;

      // Каждые 10 сессий — профилактическая реинициализация
      if (_sessionCount % 10 == 0) {
        debugPrint('[WakeWord] 🔄 periodic re-init (session $_sessionCount)');
        await _fullReinit();
      }

      try {
        final detected = await _listenOnce()
            .timeout(_sessionTimeout, onTimeout: () {
          debugPrint('[WakeWord] ⏱ 60s session timeout — instant restart');
          _consecutiveSilent++;
          return false;
        });

        if (detected && _active && _loopRunning) {
          debugPrint('[WakeWord] 🎯 TRIGGERED!');
          _loopRunning = false;
          _onWakeWord?.call();
          return;
        }

        // Проверяем ring-buffer после каждой сессии
        if (_checkTriggers() && _active && _loopRunning) {
          debugPrint('[WakeWord] 🎯 TRIGGERED (ring-buffer match)!');
          _loopRunning = false;
          _onWakeWord?.call();
          return;
        }

        // Если много сессий подряд без слов — поднимаем recovery level
        if (_consecutiveSilent > 3) {
          debugPrint('[WakeWord] ⚠ $_consecutiveSilent silent sessions — bumping recovery');
          _bumpRecoveryLevel();
        }

        // Без задержки — сразу в новую сессию
      } catch (e) {
        debugPrint('[WakeWord] session error: $e');
        _bumpRecoveryLevel();
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    _loopRunning = false;
    debugPrint('[WakeWord] loop ended');
  }

  Future<bool> _listenOnce() async {
    final completer = Completer<bool>();
    _currentCompleter = completer;

    String lastWords = '';

    try {
      await _stt.listen(
        onResult: (result) {
          lastWords = result.recognizedWords;
          if (result.finalResult) {
            // Push в ring-buffer
            _pushToRingBuffer(lastWords);
            debugPrint('[WakeWord] heard: "$lastWords" (buffer: ${_recentWords.length})');

            // Проверяем триггеры прямо в callback
            final lower = lastWords.toLowerCase();
            for (final trigger in _triggers) {
              if (lower.contains(trigger)) {
                if (completer != null && !completer.isCompleted) {
                  completer.complete(true);
                }
                return;
              }
            }
            // Не триггер — завершаем сессию для быстрого restart
            if (completer != null && !completer.isCompleted) {
              completer.complete(false);
            }
          }
        },
        listenFor: _sessionTimeout,
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        localeId: 'ru_RU',
        onSoundLevelChange: (level) {
          // Звуковая активность = живые сэмплы
          _lastAudioSample = DateTime.now();
          if (level > 0) _recoveryLevel = 0;
        },
        cancelOnError: false,
        listenMode: ListenMode.dictation,
        sampleRate: 44100,
      );
    } catch (e) {
      debugPrint('[WakeWord] listen() error: $e');
      if (completer != null && !completer.isCompleted) {
        completer.complete(false);
      }
    }

    return completer.future;
  }

  List<String> get currentTriggers => List.unmodifiable(_triggers);
  bool get isActive => _active;
  bool get isLoopRunning => _loopRunning;
  int get recoveryLevel => _recoveryLevel;
}
