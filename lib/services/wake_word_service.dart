import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Постоянное фоновое прослушивание.
/// Автоматически приостанавливается когда играет музыка —
/// чтобы не перебивать аудио захватом микрофона.
class WakeWordService {
  bool _isRunning = false;
  bool _isPaused = false; // пауза из-за музыки
  SpeechToText? _sharedStt;
  Timer? _watchdogTimer;
  Function()? onWakeWord;

  static const List<String> _defaultTriggers = [
    'айка', 'aika', 'aica', 'эйка', 'ayka',
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
      'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd',
      'е': 'e', 'ё': 'yo', 'ж': 'zh', 'з': 'z', 'и': 'i',
      'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
      'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't',
      'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch',
      'ш': 'sh', 'щ': 'sch', 'ъ': '', 'ы': 'y', 'ь': '',
      'э': 'e', 'ю': 'yu', 'я': 'ya',
    };
    final latToCyr = {
      'a': 'а', 'b': 'б', 'v': 'в', 'g': 'г', 'd': 'д',
      'e': 'е', 'z': 'з', 'i': 'и', 'y': 'й', 'k': 'к',
      'l': 'л', 'm': 'м', 'n': 'н', 'o': 'о', 'p': 'п',
      'r': 'р', 's': 'с', 't': 'т', 'u': 'у', 'f': 'ф',
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
    debugPrint('[WakeWord] готов');
  }

  void initWithSharedStt(SpeechToText stt) {
    _sharedStt = stt;
    debugPrint('[WakeWord] shared STT подключён');
  }

  Future<void> startListening(Function() callback) async {
    if (_sharedStt == null || !_sharedStt!.isAvailable || _isRunning) return;
    onWakeWord = callback;
    _isRunning = true;
    _isPaused = false;
    await updateTriggers();
    debugPrint('[WakeWord] запущен');
    await _startContinuousListen();
    _startWatchdog();
  }

  /// Приостановить прослушивание (музыка играет)
  Future<void> pauseForMusic() async {
    if (!_isRunning || _isPaused) return;
    _isPaused = true;
    if (_sharedStt != null && _sharedStt!.isListening) {
      await _sharedStt!.stop();
    }
    debugPrint('[WakeWord] ⏸ пауза — играет музыка');
  }

  /// Возобновить прослушивание (музыка остановилась)
  Future<void> resumeAfterMusic() async {
    if (!_isRunning || !_isPaused) return;
    _isPaused = false;
    debugPrint('[WakeWord] ▶ возобновляем прослушивание');
    await Future.delayed(const Duration(milliseconds: 500));
    await _startContinuousListen();
  }

  Future<void> _startContinuousListen() async {
    if (!_isRunning || _isPaused || _sharedStt == null) return;
    if (!_sharedStt!.isAvailable) return;
    if (_sharedStt!.isListening) return;

    try {
      await _sharedStt!.listen(
        localeId: 'ru-RU',
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 30),
        onResult: (result) {
          if (!_isRunning || _isPaused) return;
          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;
          debugPrint('[WakeWord] слышу: $words');
          if (_currentTriggers.any((t) => words.contains(t))) {
            debugPrint('[WakeWord] ✅ Wake word!');
            onWakeWord?.call();
          }
        },
        listenMode: ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('[WakeWord] ошибка: $e');
    }

    if (_isRunning && !_isPaused) {
      await Future.delayed(const Duration(milliseconds: 300));
      _startContinuousListen();
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_isRunning || _isPaused) return;
      if (_sharedStt == null || !_sharedStt!.isAvailable) return;
      if (!_sharedStt!.isListening) {
        debugPrint('[WakeWord] watchdog: перезапуск...');
        _startContinuousListen();
      }
    });
  }

  Future<void> stop() async {
    _isRunning = false;
    _isPaused = false;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    debugPrint('[WakeWord] остановлен');
  }
}
