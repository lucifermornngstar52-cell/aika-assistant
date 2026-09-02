import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'personality_service.dart';

/// WakeWordService — нативный AudioRecord + VAD + короткий STT.
///
/// Архитектура:
/// 1. AikaMicrophoneService (Kotlin) держит AudioRecord 16kHz PCM в foreground service
/// 2. VAD (RMS energy) детектит речь → EventChannel → Flutter
/// 3. Flutter запускает speech_to_text на 5-10 сек для распознавания
/// 4. Если слово совпало → onWakeWord callback → чат-STT
/// 5. Если не совпало → sttDone → нативный сервис пересоздаёт AudioRecord
/// 6. Watchdog: если STT не вернулся за 15 сек → нативный сервис сам рестартит
/// 7. Battery optimization: запрашиваем exemption при старте
class WakeWordService {
  static WakeWordService? _instance;
  factory WakeWordService() => _instance ??= WakeWordService._();
  WakeWordService._();

  // Нативные каналы
  static const _micChannel = MethodChannel('com.aika.assistant/microphone');
  static const _audioEvents = EventChannel('com.aika.assistant/audio_events');
  static const _phoneChannel = EventChannel('com.aika.assistant/phone_state');

  // Короткий STT для распознавания wake word (5-10 сек)
  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false;

  bool _active = false;
  bool _suppressed = false;
  Timer? _suppressTimer;
  StreamSubscription? _audioEventSub;
  bool _sttSessionActive = false; // защита от двойного срабатывания

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

    // Battery optimization — критично для foreground service
    try {
      final isOptimized = await _micChannel.invokeMethod('isBatteryOptimized');
      if (isOptimized == false) {
        debugPrint('[WakeWord] ⚠️ Battery optimization NOT disabled — requesting exemption');
        await _micChannel.invokeMethod('requestBatteryOptimization');
      }
    } catch (e) {
      debugPrint('[WakeWord] Battery check failed: $e');
    }

    // EventChannel ПЕРВЫМ — чтобы не пропустить первое событие
    _audioEventSub = _audioEvents.receiveBroadcastStream().listen(
      (event) {
        debugPrint('[WakeWord] ← Native event: $event');
        if (event == 'speech_detected' && _active && !_suppressed && !_sttSessionActive) {
          _onNativeSpeechDetected();
        }
      },
      onError: (e) => debugPrint('[WakeWord] EventChannel error: $e'),
    );

    // Запускаем нативный AudioRecord + VAD
    try {
      await _micChannel.invokeMethod('start');
      debugPrint('[WakeWord] 🎤 Native AudioRecord + VAD started');
    } catch (e) {
      debugPrint('[WakeWord] ⚠ Native service failed: $e');
    }
  }

  Future<void> stop() async {
    _active = false;
    _sttSessionActive = false;
    _audioEventSub?.cancel();
    _audioEventSub = null;
    _suppressTimer?.cancel();
    _suppressed = false;
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }
    try { await _micChannel.invokeMethod('stop'); } catch (_) {}
    debugPrint('[WakeWord] stopped');
  }

  /// Перезапуск после того как чат-STT отработал.
  Future<void> rearm() async {
    if (!_active) return;
    debugPrint('[WakeWord] rearm — restarting native AudioRecord');
    try {
      // sttDone возвращает нативный сервис к AudioRecord
      await _micChannel.invokeMethod('sttDone');
    } catch (e) {
      // Если sttDone не сработал — пробуем start
      debugPrint('[WakeWord] sttDone failed, trying start: $e');
      try { await _micChannel.invokeMethod('start'); } catch (_) {}
    }
  }

  /// Остановка перед ручным вводом через микрофон.
  Future<void> disarm() async {
    debugPrint('[WakeWord] disarmed — pausing native AudioRecord');
    try { await _micChannel.invokeMethod('stop'); } catch (_) {}
  }

  /// Временное подавление триггеров (на время речи Айки).
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
  Future<void> pause() async => await disarm();
  Future<void> resume() async => await rearm();
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

  // ── ОСНОВНОЙ ПОТОК: Native VAD → короткий STT → проверка ──────────

  /// Нативный VAD обнаружил речь. Запускаем короткую сессию STT (5-10 сек)
  /// чтобы распознать слова и проверить на совпадение с wake word триггерами.
  Future<void> _onNativeSpeechDetected() async {
    _sttSessionActive = true;
    debugPrint('[WakeWord] Native VAD → starting short STT session (10s)');

    if (!_sttReady) {
      debugPrint('[WakeWord] STT not ready — skipping, resuming AudioRecord');
      await _notifySttDone();
      _sttSessionActive = false;
      return;
    }

    final completer = Completer<void>();
    bool triggered = false;

    try {
      await _stt.listen(
        onResult: (result) {
          final text = result.recognizedWords.toLowerCase();
          if (text.isNotEmpty) {
            debugPrint('[WakeWord] heard "$text"');
          }

          if (!_suppressed && _active) {
            for (final t in _triggers) {
              if (t.isNotEmpty && text.contains(t)) {
                if (!triggered) {
                  triggered = true;
                  if (!completer.isCompleted) completer.complete();
                }
                return;
              }
            }
          }

          // finalResult без совпадения — завершаем сессию
          if (result.finalResult && !completer.isCompleted) {
            completer.complete();
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        localeId: 'ru_RU',
        partialResults: true,
        cancelOnError: true,
      );

      // Ждём: триггер, final result, или таймаут 12 сек
      await completer.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => debugPrint('[WakeWord] STT session timeout (12s)'),
      );

    } catch (e) {
      debugPrint('[WakeWord] STT session error: $e');
    }

    // Останавливаем STT
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }

    _sttSessionActive = false;

    if (triggered && _active) {
      debugPrint('[WakeWord] 🎯 TRIGGERED! — calling onWakeWord');
      _onWakeWord?.call();
      // НЕ отправляем sttDone — чат-STT займёт микрофон.
      // main_screen вызовет rearm() после обработки команды.
    } else {
      debugPrint('[WakeWord] No wake word matched — resuming AudioRecord');
      await _notifySttDone();
    }
  }

  Future<void> _notifySttDone() async {
    try {
      await _micChannel.invokeMethod('sttDone');
    } catch (e) {
      debugPrint('[WakeWord] sttDone failed: $e');
    }
  }

  // ── Геттеры ───────────────────────────────────────────────────────
  bool get isListening => _active;
  bool get isReady => _sttReady;
  bool get isMusicPlaying => false;
  List<String> get currentTriggers => List.unmodifiable(_triggers);
}
