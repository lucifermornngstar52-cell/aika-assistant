import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'personality_service.dart';

/// WakeWordService — ПРОСТОЙ бесконечный вейкворд.
///
/// Принцип:
/// - while цикл: если STT не слушает → запускаем. Если слушает — ждём.
/// - Срабатывание: _listening=false, стоп STT, колбэк в приложение.
/// - rearm(): перезапуск цикла.
/// - НЕТ completer'ов, таймаутов, session count, re-init, watchdog'ов.
/// - Просто бесконечно работающий вейкворд.
class WakeWordService {
  static WakeWordService? _instance;
  factory WakeWordService() => _instance ??= WakeWordService._();
  WakeWordService._();

  static const _phoneChannel = EventChannel('com.aika.assistant/phone_state');

  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false;

  bool _active = false;
  bool _listening = false;
  bool _suppressed = false;
  Timer? _suppressTimer;

  List<String> _triggers = ['айка', 'aika'];
  Function()? _onWakeWord;

  // ── Инициализация ─────────────────────────────────────────────────
  Future<void> initialize() async {
    _sttReady = await _stt.initialize(
      onError: (e) => debugPrint('[WakeWord] STT error: $e'),
      onStatus: (s) => debugPrint('[WakeWord] STT status: $s'),
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
    _listening = false;
    _suppressTimer?.cancel();
    _suppressed = false;
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }
    debugPrint('[WakeWord] stopped');
  }

  /// Перезапуск после того как чат-STT отработал.
  Future<void> rearm() async {
    if (!_active) return;
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }
    _listening = false;
    debugPrint('[WakeWord] rearm');
    _startLoop();
  }

  /// Остановка перед записью команды (ручной микрофон или вейкворд).
  Future<void> disarm() async {
    _listening = false;
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

  // ── ОСНОВНОЙ ЦИКЛ — простой while ────────────────────────────────
  void _startLoop() {
    if (_listening) return;
    _listening = true;
    _runLoop();
  }

  Future<void> _runLoop() async {
    debugPrint('[WakeWord] loop started');

    while (_active && _listening) {
      // STT не готов — ждём
      if (!_sttReady) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      // STT уже слушает — просто ждём
      if (_stt.isListening) {
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }

      // STT не слушает — запускаем
      try {
        debugPrint('[WakeWord] starting STT...');
        await _stt.listen(
          onResult: (result) {
            final text = result.recognizedWords.toLowerCase();
            if (text.isEmpty) return;
            if (!_active || !_listening || _suppressed) return;

            debugPrint('[WakeWord] heard "$text"');

            for (final t in _triggers) {
              if (t.isNotEmpty && text.contains(t)) {
                debugPrint('[WakeWord] TRIGGERED!');
                _listening = false;
                if (_stt.isListening) {
                  try { _stt.stop(); } catch (_) {}
                }
                _onWakeWord?.call();
                return;
              }
            }
          },
          listenFor: const Duration(seconds: 300),
          pauseFor: const Duration(seconds: 300),
          localeId: 'ru_RU',
          cancelOnError: false,
          partialResults: true,
        );
        // Даём STT время на запуск
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        debugPrint('[WakeWord] listen error: $e');
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    _listening = false;
    debugPrint('[WakeWord] loop ended');

    // Авто-рестарт если сервис ещё активен (защита от вылетов)
    if (_active) {
      await Future.delayed(const Duration(seconds: 1));
      if (_active && !_listening) _startLoop();
    }
  }

  bool get isListening => _active && _listening;
  bool get isMusicPlaying => false;
  List<String> get currentTriggers => List.unmodifiable(_triggers);
}
