import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Постоянное фоновое прослушивание wake word.
/// Использует ОТДЕЛЬНЫЙ экземпляр STT (не тот что для команд).
/// Автоматически перезапускается через watchdog каждые 15 сек.
/// Приостанавливается пока играет музыка — чтобы не мешать аудио.
class WakeWordService {
  // Отдельный STT — не делим с SpeechService!
  final SpeechToText _stt = SpeechToText();

  bool _initialized = false;
  bool _isRunning = false;
  bool _isPaused = false;
  Timer? _watchdogTimer;
  Timer? _restartTimer;
  Function()? onWakeWord;

  static const _channel = MethodChannel('aika/wake_word');

  static const List<String> _defaultTriggers = [
    'айка', 'aika', 'aica', 'эйка', 'ayka', 'ай ка', 'ай-ка',
  ];

  List<String> _currentTriggers = List.from(_defaultTriggers);

  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;

  Future<void> updateTriggers() async {
    final prefs = await SharedPreferences.getInstance();
    final name = (prefs.getString('assistant_name') ?? 'Aika').trim();
    final nameLower = name.toLowerCase();

    final triggers = <String>{};
    triggers.add(nameLower);
    triggers.addAll(_translitVariants(nameLower));
    triggers.addAll(_defaultTriggers);

    _currentTriggers = triggers.toList();
    debugPrint('[WakeWord] триггеры: $_currentTriggers');
  }

  List<String> _translitVariants(String name) {
    final result = <String>[];
    final cyrToLat = {
      'а': 'a','б': 'b','в': 'v','г': 'g','д': 'd',
      'е': 'e','ё': 'yo','ж': 'zh','з': 'z','и': 'i',
      'й': 'y','к': 'k','л': 'l','м': 'm','н': 'n',
      'о': 'o','п': 'p','р': 'r','с': 's','т': 't',
      'у': 'u','ф': 'f','х': 'kh','ц': 'ts','ч': 'ch',
      'ш': 'sh','щ': 'sch','ъ': '','ы': 'y','ь': '',
      'э': 'e','ю': 'yu','я': 'ya',
    };
    final latToCyr = {
      'a': 'а','b': 'б','v': 'в','g': 'г','d': 'д',
      'e': 'е','z': 'з','i': 'и','y': 'й','k': 'к',
      'l': 'л','m': 'м','n': 'н','o': 'о','p': 'п',
      'r': 'р','s': 'с','t': 'т','u': 'у','f': 'ф',
    };

    final hasCyrillic = name.runes.any((r) => r >= 0x0400 && r <= 0x04FF);
    if (hasCyrillic) {
      final lat = name.split('').map((c) => cyrToLat[c] ?? c).join();
      if (lat.isNotEmpty) result.add(lat);
    }
    final hasLatin = name.runes.any((r) => (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A));
    if (hasLatin) {
      final cyr = name.split('').map((c) => latToCyr[c] ?? c).join();
      if (cyr.isNotEmpty) result.add(cyr);
    }
    return result;
  }

  Future<void> initialize() async {
    await updateTriggers();
    _initialized = await _stt.initialize(
      onError: (e) {
        debugPrint('[WakeWord] STT error: $e');
        // Перезапуск при ошибке
        if (_isRunning && !_isPaused) {
          _scheduleRestart(const Duration(seconds: 2));
        }
      },
      onStatus: (status) {
        debugPrint('[WakeWord] STT status: $status');
        if ((status == 'done' || status == 'notListening') &&
            _isRunning && !_isPaused) {
          _scheduleRestart(const Duration(milliseconds: 500));
        }
      },
    );
    debugPrint('[WakeWord] initialized: $_initialized');
  }

  // Совместимость со старым кодом — больше не нужен но не ломаем API
  void initWithSharedStt(SpeechToText stt) {
    debugPrint('[WakeWord] initWithSharedStt вызван — используем собственный STT');
  }

  Future<void> startListening(Function() callback) async {
    if (!_initialized) await initialize();
    if (!_initialized || _isRunning) return;
    onWakeWord = callback;
    _isRunning = true;
    _isPaused = false;
    await updateTriggers();
    debugPrint('[WakeWord] ▶ запускаем постоянное прослушивание');
    await _startLoop();
    _startWatchdog();
  }

  Future<void> pauseForMusic() async {
    if (!_isRunning || _isPaused) return;
    _isPaused = true;
    _restartTimer?.cancel();
    if (_stt.isListening) await _stt.stop();
    debugPrint('[WakeWord] ⏸ пауза — играет музыка');
  }

  Future<void> resumeAfterMusic() async {
    if (!_isRunning || !_isPaused) return;
    _isPaused = false;
    debugPrint('[WakeWord] ▶ возобновляем прослушивание');
    await Future.delayed(const Duration(milliseconds: 800));
    await _startLoop();
  }

  void _scheduleRestart(Duration delay) {
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () async {
      if (_isRunning && !_isPaused) await _startLoop();
    });
  }

  Future<void> _startLoop() async {
    if (!_isRunning || _isPaused || !_initialized) return;
    if (_stt.isListening) return;

    try {
      await _stt.listen(
        localeId: 'ru-RU',
        listenFor: const Duration(minutes: 10),
        pauseFor: const Duration(seconds: 60),
        onResult: (result) {
          if (!_isRunning || _isPaused) return;
          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;
          debugPrint('[WakeWord] слышу: "$words"');
          if (_currentTriggers.any((t) => words.contains(t))) {
            debugPrint('[WakeWord] ✅ Wake word! Вызываю callback');
            onWakeWord?.call();
          }
        },
        listenMode: ListenMode.dictation,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[WakeWord] ошибка listen: $e');
      _scheduleRestart(const Duration(seconds: 3));
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_isRunning || _isPaused) return;
      if (!_stt.isListening) {
        debugPrint('[WakeWord] 🐕 watchdog: микрофон не активен — перезапуск');
        _startLoop();
      } else {
        debugPrint('[WakeWord] 🐕 watchdog: ОК, слушаю');
      }
    });
  }

  Future<void> stop() async {
    _isRunning = false;
    _isPaused = false;
    _watchdogTimer?.cancel();
    _restartTimer?.cancel();
    _watchdogTimer = null;
    _restartTimer = null;
    if (_stt.isListening) await _stt.stop();
    debugPrint('[WakeWord] ⏹ остановлен');
  }
}
