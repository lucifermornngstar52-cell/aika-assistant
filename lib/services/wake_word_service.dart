import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'personality_service.dart';

/// WakeWordService — бесконечный вейкворд на собственном STT.
///
/// Никаких таймаутов, перерывов, циклов.
/// Просто: слушает → Android закончил сессию → 500мс → слушает снова.
/// Отдаёт микрофон ТОЛЬКО при срабатывании wake word.
/// rearm() — снова слушает.
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

  Completer<bool>? _currentCompleter;

  List<String> _triggers = ['айка', 'aika'];
  Function()? _onWakeWord;

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
            _currentCompleter != null &&
            !_currentCompleter!.isCompleted) {
          _currentCompleter!.complete(false);
        }
      },
    );
    await updateTriggers();
    _listenPhoneState();
    debugPrint('[WakeWord] init, ready: $_sttReady, triggers: $_triggers');
  }

  Future<void> initWithSharedStt(SpeechToText stt) async {
    debugPrint('[WakeWord] initWithSharedStt deprecated');
    await initialize();
  }

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

  Future<void> startListening(Function() onWakeWordDetected) async {
    if (_active) return;
    _onWakeWord = onWakeWordDetected;
    _active = true;
    debugPrint('[WakeWord] started');
    _startLoop();
  }

  Future<void> stop() async {
    _active = false;
    _loopRunning = false;
    _suppressTimer?.cancel();
    _suppressed = false;
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }
    debugPrint('[WakeWord] stopped');
  }

  Future<void> rearm() async {
    if (!_active) return;
    debugPrint('[WakeWord] rearm');
    if (!_loopRunning) _startLoop();
  }

  Future<void> disarm() async {
    _loopRunning = false;
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }
    debugPrint('[WakeWord] disarmed');
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
    debugPrint('[WakeWord] triggers: $_triggers');
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

      if (_stt.isListening) {
        await Future.delayed(const Duration(milliseconds: 30));
        continue;
      }

      try {
        final detected = await _listenOnce();
        if (detected && _active && _loopRunning) {
          debugPrint('[WakeWord] TRIGGERED!');
          _loopRunning = false;
          if (_stt.isListening) {
            try { await _stt.stop(); } catch (_) {}
          }
          _onWakeWord?.call();
          return;
        }
        // Сессия закончилась — сразу новую, 500мс
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('[WakeWord] loop error: $e');
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    _loopRunning = false;
    debugPrint('[WakeWord] loop ended');
  }

  /// Одна сессия. Completer завершается при:
  /// 1. Wake word → true
  /// 2. onStatus "done"/"notListening" → false (Android закончил сессию)
  /// 3. onError → false
  /// 4. 2с проверка: listen() не стартанул → false (страховка от зависания)
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

    // Страховка: если listen() не запустился через 2с — завершаем, цикл пойдёт заново
    Future.delayed(const Duration(seconds: 2), () {
      if (!_stt.isListening && !completer.isCompleted && !triggered) {
        debugPrint('[WakeWord] listen did not start — retry');
        completer.complete(false);
      }
    });

    try {
      return await completer.future
          .timeout(const Duration(seconds: 310), onTimeout: () => false);
    } finally {
      _currentCompleter = null;
      if (triggered && _stt.isListening) {
        try { await _stt.stop(); } catch (_) {}
      }
    }
  }

  bool get isListening => _active && _loopRunning;
  bool get isMusicPlaying => false;
  List<String> get currentTriggers => List.unmodifiable(_triggers);
}
