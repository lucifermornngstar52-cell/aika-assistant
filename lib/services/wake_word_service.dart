import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'personality_service.dart';

/// MethodChannel для управления нативным AikaMicrophoneService
/// (Foreground Service с типом microphone + WakeLock + AudioFocus)
const _micChannel = MethodChannel('com.aika.assistant/microphone');

/// WakeWordService — бесконечный вейкворд.
/// Слушает всегда. Отдаёт микрофон только при wake word.
///
/// Устойчивость к "зависанию" recognizer engine:
/// движок Android SpeechRecognizer иногда не восстанавливается сразу
/// после долгой сессии (~5 минут) — требуется явный cancel() + буферная
/// задержка + watchdog, который форсирует полную переинициализацию,
/// если статус не менялся слишком долго.
class WakeWordService {
  static WakeWordService? _instance;
  factory WakeWordService() => _instance ??= WakeWordService._();
  WakeWordService._();

  static const _phoneChannel = EventChannel('com.aika.assistant/phone_state');

  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false;

  bool _active = false;
  bool _loopRunning = false;
  bool _suppressed = false;
  Timer? _suppressTimer;
  Timer? _watchdogTimer;

  Completer<bool>? _currentCompleter;

  DateTime _lastStatusChange = DateTime.now();
  int _sessionCount = 0;

  List<String> _triggers = ['айка', 'aika'];
  Function()? _onWakeWord;

  void _onSttError(dynamic e) {
    debugPrint('[WakeWord] error: $e');
    _lastStatusChange = DateTime.now();
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete(false);
    }
  }

  void _onSttStatus(String s) {
    debugPrint('[WakeWord] status: $s');
    _lastStatusChange = DateTime.now();
    if ((s == 'done' || s == 'notListening') &&
        _currentCompleter != null &&
        !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete(false);
    }
  }

  Future<void> initialize() async {
    _sttReady = await _stt.initialize(
      onError: _onSttError,
      onStatus: _onSttStatus,
    );
    _lastStatusChange = DateTime.now();
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

  /// Watchdog — следит, чтобы recognizer engine не "тух" надолго.
  /// Если статус не менялся дольше 20 секунд, пока мы должны слушать —
  /// значит движок застрял в промежуточном состоянии (частая проблема
  /// после длинных сессий на некоторых версиях Android). Форсируем
  /// cancel() + полную переинициализацию, вместо того чтобы ждать,
  /// когда система "сама очнётся".
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!_active || !_loopRunning) return;
      final stuckFor = DateTime.now().difference(_lastStatusChange);
      final reallyListening = _stt.isListening;
      if (stuckFor.inSeconds >= 20 && !reallyListening) {
        debugPrint('[WakeWord] 🚨 Watchdog: stuck for ${stuckFor.inSeconds}s — forcing full re-init');
        try { await _stt.cancel(); } catch (_) {}
        try {
          _sttReady = await _stt.initialize(
            onError: _onSttError,
            onStatus: _onSttStatus,
          );
        } catch (e) {
          debugPrint('[WakeWord] Watchdog re-init failed: $e');
        }
        _lastStatusChange = DateTime.now();
        if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
          _currentCompleter!.complete(false);
        }
      }
    });
  }

  Future<void> startListening(Function() onWakeWordDetected) async {
    if (_active) return;
    _onWakeWord = onWakeWordDetected;
    _active = true;
    // Запрашиваем exemption от battery optimization (Doze не убьёт микшер)
    try {
      final isOptimized = await _micChannel.invokeMethod<bool>('isBatteryOptimized') ?? false;
      if (isOptimized) {
        debugPrint('[WakeWord] 🔋 Requesting battery optimization exemption');
        await _micChannel.invokeMethod('requestBatteryOptimization');
      }
    } catch (e) {
      debugPrint('[WakeWord] ⚠ Battery opt check failed: $e');
    }
    // Запускаем нативный Foreground Service (microphone + WakeLock)
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
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }
    // Останавливаем нативный Foreground Service
    try {
      await _micChannel.invokeMethod('stop');
      debugPrint('[WakeWord] 🎤 AikaMicrophoneService stopped');
    } catch (_) {}
  }

  Future<void> rearm() async {
    if (!_active) return;
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

  // ── БЕСКОНЕЧНЫЙ ЦИКЛ ─────────────────────────────────────────────
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

      // cancel() надёжнее stop() — гарантированно освобождает recognizer
      // engine перед новой сессией (stop() иногда оставляет "хвост").
      try { await _stt.cancel(); } catch (_) {}
      // Небольшая буферная задержка — даёт Android recognizer service
      // время реально освободить аудио-ресурсы перед новым listen().
      // Без неё возникает гонка: listen() вызывается, но система ещё
      // не закончила teardown предыдущей сессии — микрофон "молчит"
      // неопределённое время, пока система сама не решит его поднять.
      await Future.delayed(const Duration(milliseconds: 300));

      _sessionCount++;
      // Каждые 15 сессий — полная переинициализация STT engine,
      // чтобы избежать постепенной деградации движка распознавания.
      if (_sessionCount % 15 == 0) {
        debugPrint('[WakeWord] 🔄 periodic full re-init (session $_sessionCount)');
        try {
          _sttReady = await _stt.initialize(
            onError: _onSttError,
            onStatus: _onSttStatus,
          );
          _lastStatusChange = DateTime.now();
        } catch (_) {}
      }

      try {
        final detected = await _listenOnce()
            .timeout(const Duration(seconds: 300), onTimeout: () {
          debugPrint('[WakeWord] ⏱ timeout — instant restart');
          return false;
        });

        if (detected && _active && _loopRunning) {
          debugPrint('[WakeWord] TRIGGERED!');
          _loopRunning = false;
          _onWakeWord?.call();
          return;
        }
        // Без задержки — сразу в новую сессию (после буфера выше).
      } catch (e) {
        debugPrint('[WakeWord] error: $e');
        // Минимальная задержка только при ошибке, чтобы не спамить.
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    _loopRunning = false;
    debugPrint('[WakeWord] loop ended');
  }

  Future<bool> _listenOnce() async {
    final completer = Completer<bool>();
    _currentCompleter = completer;
    bool triggered = false;

    try {
      await _stt.listen(
        onResult: (result) {
          final text = result.recognizedWords.toLowerCase();
          if (text.isNotEmpty) debugPrint('[WakeWord] heard "$text"');
          _lastStatusChange = DateTime.now();

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
        onSoundLevelChange: (level) {
          _lastStatusChange = DateTime.now();
          if (level > -5) {
            debugPrint('[WakeWord] 🎵 sound level: $level dB');
          }
        },
      );
      _lastStatusChange = DateTime.now();
    } catch (e) {
      debugPrint('[WakeWord] listen() error: $e');
      if (!completer.isCompleted) completer.complete(false);
    }

    return completer.future;
  }

  bool get isListening => _active && _loopRunning;
  bool get isMusicPlaying => false;
  List<String> get currentTriggers => List.unmodifiable(_triggers);
}
