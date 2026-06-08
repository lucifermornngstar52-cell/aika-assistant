import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'voice_command_parser.dart';
import 'voice_command_executor.dart';
import 'background_voice_service.dart';
import 'speech_service.dart';
import 'wake_word_service.dart';
import 'edge_tts_service.dart';

/// OfflineVoiceService — главный оркестратор голосового управления.
///
/// Связывает:
///   BackgroundVoiceService → обнаружил wake word
///   SpeechService          → слушает команду пользователя
///   VoiceCommandParser     → распознаёт намерение (офлайн, без AI)
///   VoiceCommandExecutor   → выполняет действие через Accessibility
///   EdgeTtsService         → произносит ответ
///
/// Режимы:
///   [CommandMode.voice]   — wake word → слушать → выполнить → ответить
///   [CommandMode.hybrid]  — если команда не распознана → передать в AI
///
/// Полностью офлайн когда CommandMode.voice.
class OfflineVoiceService extends ChangeNotifier {
  static OfflineVoiceService? _instance;
  factory OfflineVoiceService() => _instance ??= OfflineVoiceService._();
  OfflineVoiceService._();

  final _parser   = VoiceCommandParser();
  final _executor = VoiceCommandExecutor();
  final _bgVoice  = BackgroundVoiceService();
  final _speech   = SpeechService();
  final _tts      = EdgeTtsService();
  final _wake     = WakeWordService();

  bool _initialized = false;
  bool _isActive    = false; // слушаем команду сейчас
  bool _enabled     = true;  // включён ли вообще
  String _lastCommand = '';
  String _lastFeedback = '';

  // Callback: вызывается если команда не распознана (hybrid mode → AI)
  Future<void> Function(String text)? onFallbackToAi;
  // Callback: UI обновление
  VoidCallback? onStateChanged;
  Function(double level)? onSoundLevel;

  bool   get isActive      => _isActive;
  bool   get isEnabled     => _enabled;
  String get lastCommand   => _lastCommand;
  String get lastFeedback  => _lastFeedback;

  // ── Initialize ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _bgVoice.initialize();

    // Когда нативный сервис поймал wake word — начинаем слушать команду
    _bgVoice.onWakeWord = _onWakeWordDetected;
    _bgVoice.onRms = (level) => onSoundLevel?.call(level);

    debugPrint('[OfflineVoice] initialized');
  }

  // ── Start/Stop background listening ────────────────────────────────────────

  Future<void> startBackground() async {
    if (!_initialized) await initialize();
    final prefs = await SharedPreferences.getInstance();
    final triggers = await _loadTriggers(prefs);
    await _bgVoice.start(triggers);
    debugPrint('[OfflineVoice] ▶ background listening started');
    notifyListeners();
  }

  Future<void> stopBackground() async {
    await _bgVoice.stop();
    notifyListeners();
  }

  // ── Wake word detected → listen for command ─────────────────────────────────

  Future<void> _onWakeWordDetected() async {
    if (_isActive) return;

    // Пауза фонового прослушивания — берём микрофон
    await _bgVoice.pause();

    _isActive = true;
    onStateChanged?.call();
    notifyListeners();

    // Короткий звуковой сигнал готовности
    try { _speech; } catch (_) {}

    // Слушаем команду
    final completer = Completer<String>();
    await _speech.startListening(
      (text) {
        if (!completer.isCompleted && text.isNotEmpty) {
          completer.complete(text);
        }
      },
      onListeningStart: () => debugPrint('[OfflineVoice] 🎤 слушаю команду'),
    );

    String commandText = '';
    try {
      commandText = await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => '',
      );
    } catch (_) {}

    await _speech.stopListening();

    if (commandText.isNotEmpty) {
      await _handleCommand(commandText);
    }

    _isActive = false;
    onStateChanged?.call();
    notifyListeners();

    // Возобновляем фоновое прослушивание
    await Future.delayed(const Duration(milliseconds: 800));
    await _bgVoice.resume();
  }

  // ── Прямой вызов команды из UI (без wake word) ─────────────────────────────

  Future<String> processCommand(String text) async {
    return _handleCommand(text);
  }

  // ── Core: parse → execute → speak ──────────────────────────────────────────

  Future<String> _handleCommand(String text) async {
    _lastCommand = text;
    debugPrint('[OfflineVoice] 📝 команда: "$text"');

    final cmd = VoiceCommandParser.parse(text);
    debugPrint('[OfflineVoice] 🔍 intent: $cmd');

    String feedback = '';

    if (cmd != null) {
      // Офлайн исполнение
      feedback = await _executor.execute(cmd!);
    } else {
      // Команда не распознана
      feedback = '';
      debugPrint('[OfflineVoice] ❓ неизвестная команда — fallback');
      // Передаём в AI если есть обработчик
      if (onFallbackToAi != null) {
        await onFallbackToAi!(text);
        return '';
      }
    }

    // Произносим ответ
    if (feedback.isNotEmpty) {
      _lastFeedback = feedback;
      await _speak(feedback);
    }

    return feedback;
  }

  // ── TTS ────────────────────────────────────────────────────────────────────

  Future<void> _speak(String text) async {
    try {
      await _tts.speak(text);
    } catch (_) {
      await _speech.speak(text);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<List<String>> _loadTriggers(SharedPreferences prefs) async {
    final name = (prefs.getString('assistant_name') ?? 'Aika').toLowerCase();
    final custom = prefs.getString('custom_wake_word') ?? '';
    final triggers = <String>{'айка', 'aika', 'aivora', name};
    if (custom.isNotEmpty) {
      for (final w in custom.split(',')) {
        final c = w.trim().toLowerCase();
        if (c.isNotEmpty) triggers.add(c);
      }
    }
    return triggers.toList();
  }

  bool get isBackgroundActive => _bgVoice.isRunning;
  double get rmsLevel         => _bgVoice.rmsLevel;

  @override
  void dispose() {
    _bgVoice.dispose();
    super.dispose();
  }
}
