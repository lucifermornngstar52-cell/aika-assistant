import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// WakeWordService — надёжный бесконечный цикл прослушивания.
/// Использует ОБЩИЙ SpeechToText от SpeechService (без конфликта за микрофон).
class WakeWordService {
  static WakeWordService? _instance;
  factory WakeWordService() => _instance ??= WakeWordService._();
  WakeWordService._();

  SpeechToText? _stt;

  bool _active        = false; // true пока сервис запущен глобально
  bool _paused        = false; // пауза во время речи ассистента
  bool _musicPlaying  = false; // мьют при медиа
  bool _dialogOpen    = false; // true пока идёт диалог с пользователем
  bool _loopRunning   = false; // защита от двойного запуска цикла

  List<String> _triggers = ['айка', 'aika'];
  Function()? _onWakeWord;

  // ─── Инициализация ──────────────────────────────────────────────────────────

  Future<void> initWithSharedStt(SpeechToText stt) async {
    _stt = stt;
    debugPrint('[WakeWord] инициализирован');
  }

  Future<void> initialize() async {} // совместимость

  // ─── Запуск/остановка ──────────────────────────────────────────────────────

  Future<void> startListening(Function() onWakeWordDetected) async {
    if (_active) return;
    if (_stt == null) {
      debugPrint('[WakeWord] ❌ STT не передан');
      return;
    }
    _onWakeWord = onWakeWordDetected;
    _active = true;
    _paused = false;
    _dialogOpen = false;
    debugPrint('[WakeWord] ▶ запущен');
    _startLoop();
  }

  Future<void> stop() async {
    _active = false;
    _paused = false;
    _loopRunning = false;
    debugPrint('[WakeWord] ■ остановлен');
    // НЕ останавливаем shared STT — им владеет SpeechService
  }

  // ─── Пауза/возобновление (вызывается из _speak) ────────────────────────────

  /// Пауза — ассистент говорит, не записываем
  Future<void> pause() async {
    if (_paused) return;
    _paused = true;
    debugPrint('[WakeWord] ⏸ пауза (ассистент говорит)');
    final stt = _stt;
    if (stt != null && stt.isListening) {
      try { await stt.stop(); } catch (_) {}
    }
  }

  /// Возобновление — ассистент замолчал
  Future<void> resume() async {
    if (!_active) return;
    _paused = false;
    debugPrint('[WakeWord] ▶ возобновление');
    // Перезапускаем цикл если он не идёт
    if (!_loopRunning) _startLoop();
  }

  // ─── Диалог открыт/закрыт ──────────────────────────────────────────────────

  /// Вызывается когда пользователь начал говорить (диалог активен)
  void setDialogOpen(bool open) {
    _dialogOpen = open;
    if (open) {
      debugPrint('[WakeWord] 💬 диалог открыт — wake word на паузе');
    } else {
      debugPrint('[WakeWord] ✅ диалог закрыт — возобновляем');
      if (_active && !_paused && !_loopRunning) _startLoop();
    }
  }

  // ─── Музыка ────────────────────────────────────────────────────────────────

  void setMusicPlaying(bool playing) {
    final was = _musicPlaying;
    _musicPlaying = playing;
    if (playing && !was) {
      debugPrint('[WakeWord] 🎵 медиа — микрофон выкл');
      _paused = true;
      final stt = _stt;
      if (stt != null && stt.isListening) stt.stop().catchError((_) {});
    } else if (!playing && was) {
      debugPrint('[WakeWord] 🎵 медиа стоп — микрофон вкл');
      _paused = false;
      if (_active && !_loopRunning) _startLoop();
    }
  }

  // ─── Обновление триггеров ──────────────────────────────────────────────────

  Future<void> updateTriggers([List<String>? triggers]) async {
    _triggers = (triggers != null && triggers.isNotEmpty)
        ? triggers
        : ['айка', 'aika'];
  }

  // ─── Основной цикл ─────────────────────────────────────────────────────────
  // Бесконечный цикл: слушать 12 сек → проверить триггер → снова слушать.
  // При паузе/диалоге — ждёт. При ошибке STT — переинициализирует.

  void _startLoop() {
    if (_loopRunning) return;
    _loopRunning = true;
    _runLoop();
  }

  Future<void> _runLoop() async {
    debugPrint('[WakeWord] 🔄 цикл запущен');
    while (_active && _loopRunning) {
      // Ждём пока не надо делать паузу
      if (_paused || _dialogOpen || _musicPlaying) {
        await Future.delayed(const Duration(milliseconds: 400));
        continue;
      }

      final stt = _stt;
      if (stt == null || !stt.isAvailable) {
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }

      // Если STT уже занят (основной диалог) — ждём
      if (stt.isListening) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      // Слушаем один раунд
      try {
        final detected = await _listenOnce(stt);
        if (detected && _active && !_paused && !_dialogOpen) {
          debugPrint('[WakeWord] ✅ триггер обнаружен!');
          _loopRunning = false; // цикл остановится — возобновит resume()
          _onWakeWord?.call();
          return;
        }
      } catch (e) {
        debugPrint('[WakeWord] ошибка: $e');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    _loopRunning = false;
    debugPrint('[WakeWord] 🔄 цикл завершён');
  }

  /// Один раунд прослушивания — возвращает true если триггер найден
  Future<bool> _listenOnce(SpeechToText stt) async {
    final completer = Completer<bool>();
    bool triggered = false;
    bool started = false;

    stt.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase();
        if (text.isNotEmpty) debugPrint('[WakeWord] слышу: $text');
        if (_paused || _dialogOpen || _musicPlaying) return;
        for (final t in _triggers) {
          if (text.contains(t)) {
            triggered = true;
            if (!completer.isCompleted) completer.complete(true);
            return;
          }
        }
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(false);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      localeId: 'ru_RU',
      cancelOnError: false,
      partialResults: true,
      onSoundLevelChange: null,
    );
    started = true;

    // Ждём результата или таймаут 12 сек
    try {
      return await completer.future
          .timeout(const Duration(seconds: 12), onTimeout: () => false);
    } finally {
      // Если STT ещё слушает после таймаута — остановим
      if (!triggered && stt.isListening) {
        try { await stt.stop(); } catch (_) {}
      }
    }
  }

  // ─── Геттеры ───────────────────────────────────────────────────────────────

  bool get isListening => _active && !_paused && !_dialogOpen && !_musicPlaying;
  bool get isMusicPlaying => _musicPlaying;
}
