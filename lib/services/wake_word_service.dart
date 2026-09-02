import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'personality_service.dart';

/// WakeWordService — ПОЛНОСТЬЮ НЕЗАВИСИМЫЙ вейкворд на собственном STT.
///
/// Архитектура:
/// - Свой собственный SpeechToText (не делит с SpeechService)
/// - Работает постоянно, никогда не останавливается (кроме срабатывания)
/// - При срабатывании: останавливает свой STT → сигнал в приложение
/// - После того как чат-STT отработал: rearm() перезапускает прослушивание
/// - Во время речи Айки (TTS): suppress() игнорирует триггеры, но STT не стопит
/// - Звонки / запись ГС / музыка: НЕ останавливают прослушивание
class WakeWordService {
  static WakeWordService? _instance;
  factory WakeWordService() => _instance ??= WakeWordService._();
  WakeWordService._();

  static const _phoneChannel = EventChannel('com.aika.assistant/phone_state');

  // СОБСТВЕННЫЙ STT — независимый от SpeechService
  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false;

  bool _active       = false;   // сервис запущен
  bool _loopRunning  = false;
  bool _suppressed   = false;   // временное подавление триггеров (TTS echo)
  Timer? _suppressTimer;

  List<String> _triggers = ['айка', 'aika'];
  Function()? _onWakeWord;
  Completer<bool>? _currentCompleter; // для onError из initialize()

  // ── Инициализация ─────────────────────────────────────────────────
  Future<void> initialize() async {
    _sttReady = await _stt.initialize(
      onError: (e) {
        debugPrint('[WakeWord] STT error: $e');
        // Завершаем текущущий completer чтобы цикл перезапустился
        if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
          _currentCompleter!.complete(false);
        }
      },
      onStatus: (s) {
        debugPrint('[WakeWord] STT status: $s');
        // Когда STT останавливается сам — перезапускаем цикл
        if (s == 'done' || s == 'notListening') {
          if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
            debugPrint('[WakeWord] status $s — restarting loop');
            _currentCompleter!.complete(false);
          }
        }
      },
    );
    await updateTriggers();
    _listenPhoneState();
    debugPrint('[WakeWord] init, STT ready: $_sttReady, triggers: $_triggers');
  }

  /// Бывший initWithSharedStt — больше не нужен, STT собственный.
  /// Оставлен для обратной совместимости, ничего не делает.
  Future<void> initWithSharedStt(SpeechToText stt) async {
    debugPrint('[WakeWord] initWithSharedStt deprecated — using own STT');
    await initialize();
  }

  // ── Phone state — только лог, не глушим ──────────────────────────
  void _listenPhoneState() {
    _phoneChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final state = event['state'] as String? ?? '';
          debugPrint('[WakeWord] phone state: $state');
        }
      },
      onError: (e) => debugPrint('[WakeWord] phone state error: $e'),
    );
  }

  // ── Запуск / Остановка ────────────────────────────────────────────
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

  /// Перезапуск прослушивания после того как чат-STT отработал.
  /// Вызывается из main_screen после получения результата.
  Future<void> rearm() async {
    if (!_active) return;
    debugPrint('[WakeWord] rearm');
    if (!_loopRunning) _startLoop();
  }

  /// Остановка прослушивания — вызывается при срабатывании wake word
  /// или при ручном вводе через микрофон.
  Future<void> disarm() async {
    _loopRunning = false;
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }
    debugPrint('[WakeWord] disarmed');
  }

  /// Временное подавление триггеров (на время речи Айки).
  /// STT продолжает слушать, но wake word не срабатывает.
  void suppress([int seconds = 3]) {
    _suppressed = true;
    _suppressTimer?.cancel();
    _suppressTimer = Timer(Duration(seconds: seconds), () {
      _suppressed = false;
      debugPrint('[WakeWord] suppress ended');
    });
    debugPrint('[WakeWord] suppress for ${seconds}s');
  }

  // ── Обратная совместимость — no-op методы ─────────────────────────
  // Раньше pause/resume/setDialogOpen управляли общим STT.
  // Теперь wake word независимый — эти методы не делают ничего.
  Future<void> pause() async {}
  Future<void> resume() async { await rearm(); }
  void setDialogOpen(bool open) {
    if (!open) rearm();
  }
  void setMusicPlaying(bool playing) {
    // Музыка не глушит wake word
  }

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

  // ── ОСНОВНОЙ ЦИКЛ — непрерывный, без зазоров ─────────────────────
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
          // Останавливаем свой STT — освобождаем микрофон для чат-STT
          if (_stt.isListening) {
            try { await _stt.stop(); } catch (_) {}
          }
          _onWakeWord?.call();
          return;
        }
      } catch (e) {
        debugPrint('[WakeWord] loop error: $e');
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Небольшая пауза между сессиями — даём STT полностью остановиться
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _loopRunning = false;
  }

  /// Одна непрерывная сессия — БЕЗ перезапусков.
  /// listenFor = pauseFor = 300с — сессия не обрывается.
  /// finalResult без совпадения: НЕ завершаем completer, сессия продолжается.
  /// stt.stop() только при срабатывании.
  Future<bool> _listenOnce() async {
    final completer = Completer<bool>();
    _currentCompleter = completer;
    bool triggered = false;

    // Watchdog: если STT остановилось без finalResult или error — перезапускаем
    final watchdog = Timer(const Duration(seconds: 15), () {
      if (!completer.isCompleted && !_stt.isListening) {
        debugPrint('[WakeWord] watchdog: STT stopped without signal, restarting');
        completer.complete(false);
      }
    });

    _stt.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase();
        if (text.isNotEmpty) {
          debugPrint('[WakeWord] heard "$text"');
        }

        // Подавление триггеров (TTS echo) — STT продолжает работать
        if (_suppressed) {
          // Но если сессия завершилась (finalResult), нужно перезапустить
          if (result.finalResult && !completer.isCompleted) {
            completer.complete(false);
          }
          return;
        }
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

        // finalResult без совпадения — сессия завершилась (Android остановил STT).
        // НЕ остаёмся в ожидании 310с — сразу перезапускаем цикл.
        if (result.finalResult && !completer.isCompleted) {
          debugPrint('[WakeWord] session ended (finalResult), restarting...');
          completer.complete(false);
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
      watchdog.cancel();
      _currentCompleter = null;
      if (triggered && _stt.isListening) {
        try { await _stt.stop(); } catch (_) {}
      }
    }
  }

  bool get isListening => _active && _loopRunning;
  bool get isReady => _sttReady; // added for main_screen checks
  bool get isMusicPlaying => false;
  List<String> get currentTriggers => List.unmodifiable(_triggers);
}
