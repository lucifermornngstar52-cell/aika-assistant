import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'personality_service.dart';

/// WakeWordService — МИНИМАЛЬНАЯ ЗАДЕРЖКА
/// Оптимизации:
/// - listenFor: 5s (было 10s) → быстрее рестарт цикла
/// - pauseFor: 1.5s (было 3s) → мгновенное обнаружение паузы
/// - partialResults: true → срабатывает на полуслове
/// - loop delay: 80ms (было 400ms) → почти нет паузы между сессиями
/// - немедленное срабатывание при первом partial match
class WakeWordService {
  static WakeWordService? _instance;
  factory WakeWordService() => _instance ??= WakeWordService._();
  WakeWordService._();

  SpeechToText? _stt;

  bool _active       = false;
  bool _paused       = false;
  bool _musicPlaying = false;
  bool _dialogOpen   = false;
  bool _loopRunning  = false;

  List<String> _triggers = ['айка', 'aika'];
  Function()? _onWakeWord;

  // ── Инициализация ─────────────────────────────────────────────────
  Future<void> initWithSharedStt(SpeechToText stt) async {
    _stt = stt;
    await updateTriggers(); // подгружаем триггеры сразу
    debugPrint('[WakeWord] ✅ инициализирован, триггеры: $_triggers');
  }

  Future<void> initialize() async {} // совместимость

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
    if (playing && !was) {
      _paused = true;
      _stt?.stop().catchError((_) {});
    } else if (!playing && was) {
      _paused = false;
      if (_active && !_loopRunning) _startLoop();
    }
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

  // ── ОСНОВНОЙ ЦИКЛ (минимальная задержка) ─────────────────────────
  void _startLoop() {
    if (_loopRunning) return;
    _loopRunning = true;
    _runLoop();
  }

  Future<void> _runLoop() async {
    debugPrint('[WakeWord] 🔄 цикл (низколатентный)');
    while (_active && _loopRunning) {
      if (_paused || _dialogOpen || _musicPlaying) {
        // Минимальная задержка ожидания — 80мс вместо 400мс
        await Future.delayed(const Duration(milliseconds: 80));
        continue;
      }

      final stt = _stt;
      if (stt == null || !stt.isAvailable) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      if (stt.isListening) {
        await Future.delayed(const Duration(milliseconds: 150));
        continue;
      }

      try {
        final detected = await _listenOnce(stt);
        if (detected && _active && !_paused && !_dialogOpen) {
          debugPrint('[WakeWord] ✅ СРАБОТАЛО!');
          _loopRunning = false;
          _onWakeWord?.call();
          return;
        }
      } catch (e) {
        debugPrint('[WakeWord] ошибка: $e');
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    _loopRunning = false;
  }

  /// Один раунд — УЛЬТРА БЫСТРЫЙ:
  /// listenFor 5с (было 10с), pauseFor 1.5с (было 3с)
  /// Срабатывает на ПЕРВОМ partial result совпадении
  Future<bool> _listenOnce(SpeechToText stt) async {
    final completer = Completer<bool>();
    bool triggered = false;

    stt.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase();
        if (text.isNotEmpty) {
          debugPrint('[WakeWord] 👂 "$text"');
        }

        if (_paused || _dialogOpen || _musicPlaying) return;

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

        // Финальный результат без совпадения
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(false);
        }
      },
      // ⬇ КЛЮЧЕВЫЕ ПАРАМЕТРЫ ЗАДЕРЖКИ ⬇
      listenFor: const Duration(seconds: 5),    // было 10s
      pauseFor: const Duration(milliseconds: 1500), // было 3s
      localeId: 'ru_RU',
      cancelOnError: false,
      partialResults: true,    // срабатываем до окончания слова
      onSoundLevelChange: null,
    );

    try {
      return await completer.future
          .timeout(const Duration(seconds: 7), onTimeout: () => false);
    } finally {
      if (!triggered && stt.isListening) {
        try { await stt.stop(); } catch (_) {}
      }
    }
  }

  bool get isListening => _active && !_paused && !_dialogOpen && !_musicPlaying;
  bool get isMusicPlaying => _musicPlaying;
  List<String> get currentTriggers => List.unmodifiable(_triggers);
}
