import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'personality_service.dart';

/// MethodChannel для управления нативным AikaMicrophoneService
const _micChannel = MethodChannel('com.aika.assistant/microphone');

/// EventChannel — нативный VAD (AudioRecord) → Flutter
const _audioEvents = EventChannel('com.aika.assistant/audio_events');

/// ──────────────────────────────────────────────────────────────────────
/// WakeWordService — нативный AudioRecord + VAD → Flutter STT
///
/// Архитектура:
///
///   Native (AikaMicrophoneService.kt):
///     AudioRecord (16kHz, mono, PCM) → read() loop → VAD (RMS)
///     └── speech detected → EventChannel → Flutter
///
///   Flutter (WakeWordService.dart):
///     EventChannel → speech_detected → STT (speech_to_text) → trigger match
///     └── trigger found → onWakeWord callback
///     └── no trigger → ACTION_STT_DONE → native resumes AudioRecord
///
/// AudioRecord lifecycle управляется нативно:
///   create → startRecording → read loop
///   ├── read <= 0 → release → create → startRecording (не оживляем старый)
///   └── 60 сек → release → create → startRecording (профилактика)
///
/// Подробное логирование на каждом шаге.
/// ──────────────────────────────────────────────────────────────────────

class WakeWordService {
  static WakeWordService? _instance;
  factory WakeWordService() => _instance ??= WakeWordService._();
  WakeWordService._();

  static const _phoneChannel = EventChannel('com.aika.assistant/phone_state');

  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false;

  bool _active = false;
  bool _suppressed = false;
  Timer? _suppressTimer;
  StreamSubscription? _audioEventSub;

  // Ring-buffer последних результатов STT
  final List<String> _recentWords = [];
  static const int _ringBufferSize = 5;

  List<String> _triggers = ['айка', 'aika'];
  Function()? _onWakeWord;

  // ─── STT callbacks ───────────────────────────────────────────────

  void _onSttError(dynamic e) {
    debugPrint('[WakeWord] STT error: $e');
    _notifySttDone();
  }

  void _onSttStatus(String s) {
    debugPrint('[WakeWord] STT status: $s');
  }

  // ─── Инициализация ───────────────────────────────────────────────

  Future<void> initialize() async {
    _sttReady = await _stt.initialize(
      onError: _onSttError,
      onStatus: _onSttStatus,
    );
    debugPrint('[WakeWord] STT init, ready: $_sttReady');
    await updateTriggers();
    _listenPhoneState();
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

  // ─── Запуск/остановка ────────────────────────────────────────────

  Future<void> startListening(Function() onWakeWordDetected) async {
    if (_active) return;
    _onWakeWord = onWakeWordDetected;
    _active = true;
    _recentWords.clear();

    // Battery optimization exemption
    try {
      final isOptimized = await _micChannel.invokeMethod<bool>('isBatteryOptimized') ?? false;
      if (isOptimized) {
        debugPrint('[WakeWord] 🔋 Requesting battery optimization exemption');
        await _micChannel.invokeMethod('requestBatteryOptimization');
      }
    } catch (e) {
      debugPrint('[WakeWord] ⚠ Battery opt check failed: $e');
    }

    // Запускаем нативный AudioRecord + VAD
    try {
      await _micChannel.invokeMethod('start');
      debugPrint('[WakeWord] 🎤 Native AudioRecord + VAD started');
    } catch (e) {
      debugPrint('[WakeWord] ⚠ Native service failed: $e');
    }

    // Слушаем EventChannel — нативный VAD присылает "speech_detected"
    _audioEventSub = _audioEvents.receiveBroadcastStream().listen(
      (event) {
        debugPrint('[WakeWord] ← Native event: $event');
        if (event == 'speech_detected' && _active && !_suppressed) {
          _onSpeechDetected();
        }
      },
      onError: (e) => debugPrint('[WakeWord] EventChannel error: $e'),
    );
  }

  Future<void> stop() async {
    _active = false;
    _suppressed = false;
    _suppressTimer?.cancel();
    _audioEventSub?.cancel();
    _audioEventSub = null;
    _recentWords.clear();

    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }
    try {
      await _micChannel.invokeMethod('stop');
      debugPrint('[WakeWord] 🎤 Native service stopped');
    } catch (_) {}
  }

  Future<void> rearm() async {
    if (!_active) return;
    // Убеждаемся что нативный сервис работает
    try {
      final active = await _micChannel.invokeMethod<bool>('isActive') ?? false;
      if (!active) {
        await _micChannel.invokeMethod('start');
      }
    } catch (_) {}
  }

  Future<void> disarm() async {
    if (_stt.isListening) {
      try { await _stt.stop(); } catch (_) {}
    }
    _notifySttDone();
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

  // ─── Обработка speech_detected от нативного VAD ──────────────────

  /// Нативный VAD обнаружил речь → запускаем STT для распознавания
  Future<void> _onSpeechDetected() async {
    debugPrint('[WakeWord] 🎤 Native VAD → starting STT recognition');

    if (!_sttReady) {
      debugPrint('[WakeWord] STT not ready — re-initializing');
      try {
        _sttReady = await _stt.initialize(
          onError: _onSttError,
          onStatus: _onSttStatus,
        );
      } catch (e) {
        debugPrint('[WakeWord] STT re-init failed: $e');
        _notifySttDone();
        return;
      }
    }

    if (!_sttReady) {
      debugPrint('[WakeWord] STT still not ready — cannot recognize');
      _notifySttDone();
      return;
    }

    try {
      await _stt.listen(
        onResult: (result) {
          if (result.finalResult) {
            final words = result.recognizedWords.toLowerCase().trim();
            debugPrint('[WakeWord] STT result: "$words"');

            // Push в ring-buffer
            _recentWords.add(words);
            if (_recentWords.length > _ringBufferSize) {
              _recentWords.removeAt(0);
            }

            // Проверяем триггеры
            if (_checkTriggers()) {
              debugPrint('[WakeWord] 🎯 TRIGGERED!');
              _stt.stop();
              _active = false;
              _onWakeWord?.call();
              return;
            }

            // Не триггер — уведомляем нативный сервис возобновить AudioRecord
            _notifySttDone();
          }
        },
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        localeId: 'ru_RU',
        cancelOnError: false,
        listenMode: ListenMode.dictation,
        sampleRate: 44100,
      );
    } catch (e) {
      debugPrint('[WakeWord] STT listen failed: $e');
      _notifySttDone();
    }
  }

  /// Уведомить нативный сервис что STT закончил → возобновить AudioRecord
  void _notifySttDone() {
    try {
      _micChannel.invokeMethod('sttDone');
      debugPrint('[WakeWord] → Notified native: STT done, resume AudioRecord');
    } catch (e) {
      debugPrint('[WakeWord] sttDone failed: $e');
    }
  }

  // ─── Ring-buffer проверка триггеров ──────────────────────────────

  bool _checkTriggers() {
    for (final words in _recentWords) {
      for (final trigger in _triggers) {
        if (words.contains(trigger)) {
          _recentWords.clear();
          return true;
        }
      }
    }
    if (_recentWords.length >= _ringBufferSize) {
      _recentWords.removeRange(0, _recentWords.length - 1);
    }
    return false;
  }

  // ─── Triggers ────────────────────────────────────────────────────

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

  List<String> get currentTriggers => List.unmodifiable(_triggers);
  bool get isActive => _active;
}
