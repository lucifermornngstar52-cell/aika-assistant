import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'personality_service.dart';

/// WakeWordService — вейкворд на собственном STT.
///
/// Ключевые механизмы:
/// 1. _processing флаг — когда команда обрабатывается (от вейкворда до rearm),
///    watchdog НЕ перезапускает цикл, чтобы не конфликтовать с SpeechService STT
/// 2. onStatus "done"/"notListening" — мгновенно завершает completer
/// 3. Watchdog-таймер (каждые 2с) — перезапускает цикл если он умер
///    (но только если _processing == false)
/// 4. После 10 сессий — реинициализация STT
class WakeWordService {
  static WakeWordService? _instance;
  factory WakeWordService() => _instance ??= WakeWordService._();
  WakeWordService._();

  static const _phoneChannel = EventChannel('com.aika.assistant/phone_state');

  SpeechToText _stt = SpeechToText();  // non-final — заменяем при ре-инициализации
  bool _sttReady = false;

  bool _active       = false;
  bool _loopRunning  = false;
  bool _suppressed   = false;
  bool _processing   = false;  // ← НОВОЕ: команда в обработке, watchdog молчит
  Timer? _suppressTimer;
  Timer? _watchdog;
  int _sessionCount  = 0;
  int _consecutiveErrors = 0;  // подряд ошибок → полный сброс

  List<String> _triggers = ['айка', 'aika'];
  Function()? _onWakeWord;
  Completer<bool>? _currentCompleter;

  // ── Инициализация ─────────────────────────────────────────────────
  Future<void> initialize() async {
    _sttReady = await _stt.initialize(
      onError: (e) {
        debugPrint('[WakeWord] STT error: $e');
        if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
          _currentCompleter!.complete(false);
        }
      },
      onStatus: (s) {
        debugPrint('[WakeWord] STT status: $s');
        if ((s == 'done' || s == 'notListening') &&
            _currentCompleter != null && !_currentCompleter!.isCompleted) {
          _currentCompleter!.complete(false);
        }
      },
    );
    await updateTriggers();
    _listenPhoneState();
    _startWatchdog();
    _consecutiveErrors = 0;
    debugPrint('[WakeWord] init, STT ready: $_sttReady, triggers: $_triggers');
  }

  Future<void> initWithSharedStt(SpeechToText stt) async {
    debugPrint('[WakeWord] initWithSharedStt deprecated — using own STT');
    await initialize();
  }

  // ── Phone state — только лог ──────────────────────────────────────
  void _listenPhoneState() {
    _phoneChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          debugPrint('[WakeWord] phone state: ${event['state']}');
        }
      },
      onError: (e) => debugPrint('[WakeWord] phone state error: $e'),
    );
  }

  // ── WATCHDOG — бессмертие вейкворда ───────────────────────────────
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_active) return;
      if (_loopRunning) return;
      if (_processing) return;  // ← НОВОЕ: команда в обработке — не лезем

      debugPrint('[WakeWord] WATCHDOG: loop dead, restarting');
      _startLoop();
    });
    debugPrint('[WakeWord] watchdog started');
  }

  // ── Запуск / Остановка ────────────────────────────────────────────
  Future<void> startListening(Function() onWakeWordDetected) async {
    if (_active) return;
    _onWakeWord = onWakeWordDetected;
    _active = true;
    _processing = false;
    debugPrint('[WakeWord] started');
    _startLoop();
  }

  Future<void> stop() async {
    _active = false;
    _loopRunning = false;
    _processing = false;
    _suppressTimer?.cancel();
    _suppressed = false;
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }
    debugPrint('[WakeWord] stopped');
  }

  /// Вызывается после полной обработки команды (включая TTS).
  /// Снимает _processing и перезапускает цикл прослушивания.
  Future<void> rearm() async {
    _processing = false;  // ← НОВОЕ: снимаем блокировку watchdog
    if (!_active) return;
    debugPrint('[WakeWord] rearm — restarting loop');

    // Останавливаем STT на всякий случай — чистое состояние
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }

    _loopRunning = false;  // гарантия чистого старта
    _startLoop();
  }

  /// Блокирует вейкворд пока SpeechService записывает команду.
  Future<void> disarm() async {
    _loopRunning = false;
    _processing = true;  // ← НОВОЕ: watchdog не будет перезапускать
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }
    debugPrint('[WakeWord] disarmed (processing=$_processing)');
  }

  void suppress([int seconds = 3]) {
    _suppressed = true;
    _suppressTimer?.cancel();
    _suppressTimer = Timer(Duration(seconds: seconds), () {
      _suppressed = false;
      debugPrint('[WakeWord] suppress ended');
    });
    debugPrint('[WakeWord] suppress for ${seconds}s');
  }

  // ── Обратная совместимость ────────────────────────────────────────
  Future<void> pause() async {}
  Future<void> resume() async { await rearm(); }
  void setDialogOpen(bool open) { if (!open) rearm(); }
  void setMusicPlaying(bool playing) {}

  // ── Триггеры ──────────────────────────────────────────────────────
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
    debugPrint('[WakeWord] triggers: $_triggers');
  }

  // ── ОСНОВНОЙ ЦИКЛ ────────────────────────────────────────────────
  void _startLoop() {
    if (_loopRunning) return;
    _loopRunning = true;
    _runLoop();
  }

  Future<void> _runLoop() async {
    debugPrint('[WakeWord] loop started');
    while (_active && _loopRunning) {
      if (!_sttReady) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      if (_stt.isListening) {
        await Future.delayed(const Duration(milliseconds: 30));
        continue;
      }

      // Периодическая реинициализация: каждые 8 сессий — НОВЫЙ экземпляр SpeechToText
      // Старый Android SpeechRecognizer накапливает ошибки → полная замена
      if (_sessionCount >= 8) {
        debugPrint('[WakeWord] full re-init after $_sessionCount sessions');
        _sessionCount = 0;
        _consecutiveErrors = 0;
        await _fullReinit();
        continue;
      }

      // Защита: 3+ ошибок подряд → полный сброс с новой задержкой
      if (_consecutiveErrors >= 3) {
        debugPrint('[WakeWord] $_consecutiveErrors errors — full reset with backoff');
        _consecutiveErrors = 0;
        await Future.delayed(const Duration(seconds: 3));
        await _fullReinit();
        continue;
      }

      try {
        final detected = await _listenOnce();
        _sessionCount++;
        if (detected && _active && _loopRunning) {
          debugPrint('[WakeWord] TRIGGERED!');
          _consecutiveErrors = 0;
          _loopRunning = false;
          _processing = true;  // ← НОВОЕ: блокируем watchdog
          if (_stt.isListening) {
            try { await _stt.stop(); } catch (_) {}
          }
          _onWakeWord?.call();
          return;
        }
      } catch (e) {
        debugPrint('[WakeWord] loop error: $e');
        _consecutiveErrors++;
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    _loopRunning = false;
  }

  /// Полная реинициализация: уничтожает старый SpeechToText и создаёт новый.
  /// Это единственный надёжный способ сбросить накопленные ошибки Android SpeechRecognizer.
  Future<void> _fullReinit() async {
    try {
      if (_stt.isListening) {
        try { await _stt.stop(); } catch (_) {}
      }
    } catch (_) {}

    // Создаём НОВЫЙ экземпляр — старый полностью отбрасывается
    _stt = SpeechToText();
    _currentCompleter = null;

    try {
      _sttReady = await _stt.initialize(
        onError: (e) {
          debugPrint('[WakeWord] STT error: $e');
          _consecutiveErrors++;
          if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
            _currentCompleter!.complete(false);
          }
        },
        onStatus: (s) {
          debugPrint('[WakeWord] STT status: $s');
          if ((s == 'done' || s == 'notListening') &&
              _currentCompleter != null && !_currentCompleter!.isCompleted) {
            _currentCompleter!.complete(false);
          }
        },
      );
      debugPrint('[WakeWord] full re-init done, STT ready: $_sttReady');
    } catch (e) {
      debugPrint('[WakeWord] full re-init FAILED: $e');
      _sttReady = false;
      _consecutiveErrors++;
    }
  }

  /// Одна сессия прослушивания.
  Future<bool> _listenOnce() async {
    final completer = Completer<bool>();
    _currentCompleter = completer;
    bool triggered = false;

    _stt.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase();
        if (text.isNotEmpty) {
          debugPrint('[WakeWord] heard "$text"');
        }

        if (_suppressed) return;
        if (!_active || !_loopRunning) return;

        for (final t in _triggers) {
          if (t.isNotEmpty && text.contains(t)) {
            if (!triggered) {
              triggered = true;
              if (!completer.isCompleted) completer.complete(true);
            }
            return;
          }
        }
      },
      listenFor: const Duration(seconds: 300),
      pauseFor: const Duration(seconds: 300),
      localeId: 'ru_RU',
      cancelOnError: false,
      partialResults: true,
      onSoundLevelChange: null,
    );

    try {
      return await completer.future
          .timeout(const Duration(seconds: 310), onTimeout: () => false);
    } finally {
      _currentCompleter = null;
      if (_stt.isListening) {
        try { await _stt.stop(); } catch (_) {}
      }
    }
  }

  bool get isListening => _active && _loopRunning;
  bool get isProcessing => _processing;
  bool get isMusicPlaying => false;
  List<String> get currentTriggers => List.unmodifiable(_triggers);
}
