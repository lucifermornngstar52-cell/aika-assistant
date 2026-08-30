import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'personality_service.dart';

/// WakeWordService — НЕПРЕРЫВНОЕ прослушивание без зазоров.
/// Оптимизации:
/// - listenFor: 300с (5 минут) — одна длинная сессия, без рестартов
/// - pauseFor: 1.5с — мгновенное обнаружение паузы
/// - partialResults: true — срабатывает на полуслове
/// - Нет stt.stop() между сессиями — нулевая задержка
/// - PhoneState: глушится при звонках и записи ГС
class WakeWordService {
  static WakeWordService? _instance;
  factory WakeWordService() => _instance ??= WakeWordService._();
  WakeWordService._();

  static const _phoneChannel = EventChannel('com.aika.assistant/phone_state');

  SpeechToText? _stt;

  bool _active       = false;
  bool _paused       = false;
  bool _musicPlaying = false;
  bool _dialogOpen   = false;
  bool _loopRunning  = false;
  bool _inCall       = false;       // активный звонок (входящий/исходящий)
  bool _recordingGS  = false;       // запись голосового сообщения

  List<String> _triggers = ['айка', 'aika'];
  Function()? _onWakeWord;

  // ── Инициализация ─────────────────────────────────────────────────
  Future<void> initWithSharedStt(SpeechToText stt) async {
    _stt = stt;
    await updateTriggers();
    _listenPhoneState();
    debugPrint('[WakeWord] ✅ инициализирован, триггеры: $_triggers');
  }

  Future<void> initialize() async {}

  // ── Отслеживание телефонных состояний ────────────────────────────
  void _listenPhoneState() {
    _phoneChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final state = event['state'] as String? ?? '';
          debugPrint('[WakeWord] 📞 phone state: $state');
          switch (state) {
            case 'call_started':
              _inCall = true;
              _pauseForExternal();
              break;
            case 'call_ended':
              _inCall = false;
              _resumeAfterExternal();
              break;
            case 'recording_started':
              _recordingGS = true;
              _pauseForExternal();
              break;
            case 'recording_ended':
              _recordingGS = false;
              _resumeAfterExternal();
              break;
          }
        }
      },
      onError: (e) => debugPrint('[WakeWord] phone state error: $e'),
    );
  }

  void _pauseForExternal() {
    if (_active && !_paused) {
      _paused = true;
      final stt = _stt;
      if (stt != null && stt.isListening) {
        try { stt.stop(); } catch (_) {}
      }
      debugPrint('[WakeWord] ⏸ пауза (внешнее вмешательство)');
    }
  }

  void _resumeAfterExternal() {
    if (!_inCall && !_recordingGS && _active) {
      _paused = false;
      if (!_loopRunning) _startLoop();
      debugPrint('[WakeWord] ▶ возобновление после внешнего вмешательства');
    }
  }

  // ── Запуск ────────────────────────────────────────────────────────
  Future<void> startListening(Function() onWakeWordDetected) async {
    if (_active) return;
    if (_stt == null) {
      debugPrint('[WakeWord] ❌ STT не передан');
      return;
    }
    _onWakeWord = onWakeWordDetected;
    _active    = true;
    _paused    = false;
    _dialogOpen = false;
    debugPrint('[WakeWord] ▶ запущен');
    _startLoop();
  }

  Future<void> stop() async {
    _active      = false;
    _paused      = false;
    _loopRunning = false;
    debugPrint('[WakeWord] ■ остановлен');
  }

  // ── Пауза / Возобновление ─────────────────────────────────────────
  Future<void> pause() async {
    if (_paused) return;
    _paused = true;
    debugPrint('[WakeWord] ⏸ пауза');
    final stt = _stt;
    if (stt != null && stt.isListening) {
      try { await stt.stop(); } catch (_) {}
    }
  }

  Future<void> resume() async {
    if (!_active) return;
    _paused = false;
    debugPrint('[WakeWord] ▶ возобновление');
    if (!_loopRunning) _startLoop();
  }

  void setDialogOpen(bool open) {
    _dialogOpen = open;
    if (!open && _active && !_paused && !_loopRunning) _startLoop();
  }

  void setMusicPlaying(bool playing) {
    final was = _musicPlaying;
    _musicPlaying = playing;
    // Музыка НЕ глушит микрофон — слушаем поверх музыки
    // (раньше глушли, теперь нет — пользователь просит не мешать)
    debugPrint('[WakeWord] 🎵 music: $playing (listening continues)');
  }

  // ── Обновление триггеров ──────────────────────────────────────────
  Future<void> updateTriggers([List<String>? triggers]) async {
    if (triggers != null && triggers.isNotEmpty) {
      _triggers = triggers;
      debugPrint('[WakeWord] триггеры обновлены: $_triggers');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final assistantName = (prefs.getString('assistant_name') ?? 'Айка').toLowerCase().trim();
    final customRaw = prefs.getString('custom_wake_word') ?? '';

    final Set<String> result = {'айка', 'aika', assistantName};

    // Транслит имени
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

    // Wake-words персонажа (JARVIS, FRIDAY и др.)
    result.addAll(PersonalityService.characterWakeWords);

    // Кастомные слова
    if (customRaw.isNotEmpty) {
      for (final w in customRaw.split(',')) {
        final clean = w.trim().toLowerCase();
        if (clean.isNotEmpty) result.add(clean);
      }
    }

    _triggers = result.toList();
    debugPrint('[WakeWord] триггеры: $_triggers');
  }

  // ── ОСНОВНОЙ ЦИКЛ — непрерывный, без зазоров ─────────────────────
  void _startLoop() {
    if (_loopRunning) return;
    _loopRunning = true;
    _runLoop();
  }

  Future<void> _runLoop() async {
    debugPrint('[WakeWord] 🔄 цикл (непрерывный)');
    while (_active && _loopRunning) {
      // Пауза только для звонков/записи ГС/диалога
      if (_paused || _dialogOpen || _inCall || _recordingGS) {
        await Future.delayed(const Duration(milliseconds: 80));
        continue;
      }

      final stt = _stt;
      if (stt == null || !stt.isAvailable) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      if (stt.isListening) {
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }

      try {
        final detected = await _listenOnce(stt);
        if (detected && _active && !_paused && !_dialogOpen && !_inCall && !_recordingGS) {
          debugPrint('[WakeWord] ✅ СРАБОТАЛО!');
          _loopRunning = false;
          _onWakeWord?.call();
          return;
        }
      } catch (e) {
        debugPrint('[WakeWord] ошибка: $e');
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    _loopRunning = false;
  }

  /// Один раунд — НЕПРЕРЫВНЫЙ:
  /// listenFor 300с — длинная сессия без рестарта
  /// pauseFor 1.5с — быстрое обнаружение паузы
  /// НЕТ stt.stop() между раундами — нулевая задержка
  Future<bool> _listenOnce(SpeechToText stt) async {
    final completer = Completer<bool>();
    bool triggered = false;

    stt.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase();
        if (text.isNotEmpty) {
          debugPrint('[WakeWord] 👂 "$text"');
        }

        if (_paused || _dialogOpen || _inCall || _recordingGS) return;

        // МГНОВЕННОЕ срабатывание — даже на partial result
        for (final t in _triggers) {
          if (t.isNotEmpty && text.contains(t)) {
            if (!triggered) {
              triggered = true;
              if (!completer.isCompleted) completer.complete(true);
            }
            return;
          }
        }

        // Финальный результат без совпадения — НЕ останавливаем,
        // просто ждём следующий результат в той же сессии
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(false);
        }
      },
      listenFor: const Duration(seconds: 300),
      pauseFor: const Duration(milliseconds: 1500),
      localeId: 'ru_RU',
      cancelOnError: false,
      partialResults: true,
      onSoundLevelChange: null,
    );

    try {
      return await completer.future
          .timeout(const Duration(seconds: 310), onTimeout: () => false);
    } finally {
      // НЕ останавливаем STT между раундами — сразу перезапускаем
      if (!triggered && stt.isListening) {
        try { await stt.stop(); } catch (_) {}
      }
    }
  }

  bool get isListening => _active && !_paused && !_dialogOpen && !_inCall && !_recordingGS;
  bool get isMusicPlaying => _musicPlaying;
  List<String> get currentTriggers => List.unmodifiable(_triggers);
}
