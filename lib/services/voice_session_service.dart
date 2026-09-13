import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'speech_service.dart';

/// ═════════════════════════════════════════════════════════════════════
/// VoiceSessionService — ЖИВОЙ РАЗГОВОР (live dialog).
///
/// Архитектура (накинута поверх уже работающих STT и TTS):
///   wake word → [сессия] listening → thinking → speaking → listening → …
///   → тишина / «пока» / лимит → конец сессии → снова ждём wake word.
///
/// Ключевые свойства:
///  • Режим wake word и разговорный сеанс РАЗДЕЛЕНЫ: wake word disarm'ится
///    на время сессии, сессия владеет микрофоном, после конца — rearm.
///  • TTS замолкает МГНОВЕННО, если пользователь начинает говорить
///    (barge-in): микрофон слушает ПОВЕРХ речи Айки, эхо отфильтровывается.
///  • VAD по уровню звука: тишина N секунд в listening → сессия закрывается.
///  • Микрофон не держится бесконечно: STT живёт только внутри сессии.
/// ═════════════════════════════════════════════════════════════════════
class VoiceSessionService {
  static final VoiceSessionService _i = VoiceSessionService._();
  factory VoiceSessionService() => _i;
  VoiceSessionService._();

  /// Единый STT приложения (SpeechService — владелец, wake word — свой).
  SpeechToText get _stt => SpeechService().sharedStt;

  // ── Колбэки (поставляет main_screen) ────────────────────────────────
  /// AI-ответ на реплику. ОЗВУЧКУ НЕ ДЕЛАЕТ — только текст (или null).
  Future<String?> Function(String userText)? onTurn;
  /// Озвучить текст и дождаться окончания (или перебивания).
  Future<void> Function(String text)? onSpeak;
  /// МГНОВЕННО замолчать (все TTS-движки).
  Future<void> Function()? onStopSpeak;
  /// Смена состояния — для UI и оверлея.
  void Function(VoiceSessionState state)? onStateChanged;
  /// Сессия закрыта — время вернуть wake word.
  void Function()? onSessionEnd;

  // ── Настройки ────────────────────────────────────────────────────────
  /// Тишина столько секунд в listening → сессия закрывается.
  int silenceTimeoutSec = 8;
  /// Защита от вечного разговора.
  int maxTurns = 40;
  /// Порог уровня звука для VAD (0..~30, зависит от микрофона).
  double voiceLevelThreshold = 6.0;

  VoiceSessionState _state = VoiceSessionState.idle;
  VoiceSessionState get state => _state;
  bool _active = false;
  bool get isActive => _active;

  Timer? _silenceTimer;
  Timer? _healthTimer;
  int _turns = 0;
  bool _processing = false;

  /// Слова текущей реплики Айки — для фильтра эха при перебивании.
  Set<String> _echoWords = {};

  /// Фразы-прощания — сессия закрывается сразу.
  static const _farewells = [
    'пока', 'всё', 'все', 'хватит', 'стоп', 'отбой', 'до свидания',
    'закончим', 'закончить', 'прощай', 'бай', 'bye', 'гуд бай',
  ];

  // ═══ ПУБЛИЧНОЕ API ═══════════════════════════════════════════════════

  /// Вход в сессию. Вызывается ПОСЛЕ срабатывания wake word
  /// (wake word уже disarm'нут и отдал микрофон).
  Future<void> start({String? greeting}) async {
    if (_active) return;
    if (onTurn == null || onSpeak == null) {
      debugPrint('[VoiceSession] колбэки не настроены — старт отменён');
      return;
    }
    _active = true;
    _turns = 0;
    _processing = false;
    debugPrint('[VoiceSession] 🟢 сессия начата');
    _setState(VoiceSessionState.listening);
    _startHealthWatch();

    if (greeting != null && greeting.trim().isNotEmpty) {
      await _speakWithBargeIn(greeting);
      if (!_active) return; // перебили приветствие и сессия закрыта
    }
    await _ensureListening();
  }

  /// Принудительное закрытие сессии (уход с экрана, ручной стоп).
  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    _silenceTimer?.cancel();
    _healthTimer?.cancel();
    _echoWords = {};
    try { await _stt.stop(); } catch (_) {}
    try { await onStopSpeak?.call(); } catch (_) {}
    _setState(VoiceSessionState.idle);
    debugPrint('[VoiceSession] 🔴 сессия завершена');
    onSessionEnd?.call();
  }

  // ═══ СЛУШАНИЕ ════════════════════════════════════════════════════════

  Future<void> _ensureListening() async {
    if (!_active) return;
    _setState(VoiceSessionState.listening);
    _armSilenceTimer();
    if (_stt.isListening) return; // уже слушаем (после barge-in / речи)
    await _startStt();
  }

  Future<void> _startStt() async {
    if (!_active || _stt.isListening) return;
    try {
      await _stt.listen(
        onResult: _onSttResult,
        onSoundLevelChange: (level) {
          if (level > voiceLevelThreshold) _bumpActivity();
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        localeId: 'ru_RU',
        cancelOnError: false,
        partialResults: true,
      );
    } catch (e) {
      debugPrint('[VoiceSession] listen error: $e');
      await Future.delayed(const Duration(milliseconds: 600));
      if (_active) _startStt();
    }
  }

  void _onSttResult(dynamic result) {
    if (!_active) return;
    final raw = (result.recognizedWords as String? ?? '').trim();
    final isFinal = result.finalResult as bool? ?? false;
    if (raw.isNotEmpty) _bumpActivity();

    // ── Во время речи Айки: ловим ПЕРЕБИВАНИЕ ──
    if (_state == VoiceSessionState.speaking && raw.isNotEmpty) {
      if (_looksLikeBargeIn(raw)) {
        debugPrint('[VoiceSession] 🗣 перебили: "$raw"');
        try { onStopSpeak?.call(); } catch (_) {}
        _setState(VoiceSessionState.listening);
        _armSilenceTimer();
        // STT уже слушает — реплика пользователя придёт сюда же.
        // Финал обработается ниже как обычная реплика.
      }
      if (!isFinal) return;
      // Финал во время речи: если это эхо — игнорируем и слушаем дальше.
      if (_isEcho(raw)) return;
      _handleUtterance(raw);
      return;
    }

    if (!isFinal) return;

    // ── Финал в listening ──
    if (raw.isEmpty) {
      // Пустой финал (тишина) — перезапускаем прослушивание.
      Future.delayed(const Duration(milliseconds: 400), () {
        if (_active && !_stt.isListening) _startStt();
      });
      return;
    }
    _silenceTimer?.cancel();
    _handleUtterance(raw);
  }

  // ═══ ЭХО И ПЕРЕБИВАНИЕ ═══════════════════════════════════════════════

  /// Похоже ли услышанное на перебивание (а не на эхо собственной речи).
  bool _looksLikeBargeIn(String raw) {
    final words = _normalizeWords(raw);
    if (words.length < 2) return false; // одиночное слово — ждём подтверждения
    if (_echoWords.isEmpty) return true; // нечего фильтровать — значит, перебили
    // Есть слова, которых НЕ было в реплике Айки — это живой человек.
    return words.any((w) => !_echoWords.contains(w) && w.length > 2);
  }

  /// Вся ли реплика — эхо от динамика.
  bool _isEcho(String raw) {
    if (_echoWords.isEmpty) return false;
    final words = _normalizeWords(raw);
    if (words.isEmpty) return true;
    return words.every((w) => _echoWords.contains(w));
  }

  Set<String> _normalizeWords(String text) {
    final clean = text.toLowerCase().replaceAll(RegExp(r'[^\wа-яё\s]'), ' ');
    return clean.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
  }

  // ═══ ЦИКЛ РАЗГОВОРА ══════════════════════════════════════════════════

  Future<void> _handleUtterance(String rawText) async {
    if (!_active || _processing) return;
    _processing = true;
    _echoWords = {};

    try {
      // ── Прощание → закрываем сессию ──
      final lower = rawText.toLowerCase().replaceAll(
          RegExp(r'[^\wа-яё\s]'), ' ').trim();
      final words = lower.split(RegExp(r'\s+'));
      if (words.length <= 3 && words.isNotEmpty &&
          _farewells.contains(words.first)) {
        debugPrint('[VoiceSession] прощание: "$rawText"');
        _setState(VoiceSessionState.speaking);
        try { await onSpeak?.call('Пока! Позови, если понадоблюсь.'); }
        catch (_) {}
        await stop();
        return;
      }

      // ── Думаем ──
      _setState(VoiceSessionState.thinking);
      _silenceTimer?.cancel();
      try { await _stt.stop(); } catch (_) {} // микрофон свободен, пока думаем
      final reply = await onTurn?.call(rawText);
      if (!_active) return;
      if (reply == null || reply.trim().isEmpty) {
        await _ensureListening();
        return;
      }

      // ── Говорим (с возможностью перебить) ──
      _turns++;
      await _speakWithBargeIn(reply);
      if (!_active) return; // перебили и закрыли
      if (_turns >= maxTurns) {
        debugPrint('[VoiceSession] лимит реплик ($maxTurns)');
        await stop();
        return;
      }
      await _ensureListening();
    } catch (e) {
      debugPrint('[VoiceSession] turn error: $e');
      if (_active) await _ensureListening();
    } finally {
      _processing = false;
    }
  }

  Future<void> _speakWithBargeIn(String text) async {
    if (!_active) return;
    _echoWords = _normalizeWords(text); // фильтр эха для перебивания
    _setState(VoiceSessionState.speaking);
    _silenceTimer?.cancel();

    // Микрофон слушает ПОВЕРХ речи Айки — чтобы поймать перебивание сразу.
    if (!_stt.isListening) await _startStt();
    if (!_active) return;

    try {
      await onSpeak!.call(text);
    } catch (e) {
      debugPrint('[VoiceSession] speak error: $e');
    }
    if (!_active) return;

    // Речь закончилась (или её перебили) — микрофон уже жив,
    // просто возвращаемся в ожидание реплики.
    _echoWords = {};
    _setState(VoiceSessionState.listening);
    _armSilenceTimer();
    if (!_stt.isListening) await _startStt();
  }

  // ═══ VAD / ТАЙМЕРЫ ═══════════════════════════════════════════════════

  void _bumpActivity() {
    // Только в listening тишина — повод закрыться;
    // в speaking молчание — нормальная часть речи Айки.
    if (_active && _state == VoiceSessionState.listening) {
      _armSilenceTimer();
    }
  }

  void _armSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(Duration(seconds: silenceTimeoutSec), () {
      debugPrint('[VoiceSession] тишина ${silenceTimeoutSec}с — закрываю сессию');
      stop();
    });
  }

  /// Надзиратель: если STT тихо умер (не слушает, а должен) — поднимаем.
  void _startHealthWatch() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_active) return;
      if (!_stt.isListening &&
          _state != VoiceSessionState.thinking &&
          !_processing) {
        debugPrint('[VoiceSession] watchdog: STT не слушает — перезапуск');
        _startStt();
      }
    });
  }

  void _setState(VoiceSessionState s) {
    if (_state == s) return;
    _state = s;
    debugPrint('[VoiceSession] → ${s.name}');
    onStateChanged?.call(s);
  }
}

enum VoiceSessionState { idle, listening, thinking, speaking }
