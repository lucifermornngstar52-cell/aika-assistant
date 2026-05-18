import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Постоянное фоновое прослушивание — как Google Assistant.
/// Триггер динамически читается из SharedPreferences (имя ассистента).
class WakeWordService {
  bool _isRunning = false;
  SpeechToText? _sharedStt;
  Timer? _watchdogTimer;
  Function()? onWakeWord;

  // Базовые fallback-триггеры если имя не задано
  static const List<String> _defaultTriggers = [
    'айка', 'aika', 'aica', 'эйка', 'ayka',
  ];

  List<String> _currentTriggers = List.from(_defaultTriggers);

  /// Обновить триггеры на основе текущего имени ассистента
  Future<void> updateTriggers() async {
    final prefs = await SharedPreferences.getInstance();
    final name = (prefs.getString('assistant_name') ?? 'Aika').trim();
    final nameLower = name.toLowerCase();

    final triggers = <String>{};
    triggers.add(nameLower);

    // Транслитерация кириллицы → латиница и обратно
    triggers.addAll(_translitVariants(nameLower));

    // Всегда оставляем дефолтные как запасные
    triggers.addAll(_defaultTriggers);

    _currentTriggers = triggers.toList();
    debugPrint('[WakeWord] триггеры обновлены: $_currentTriggers');
  }

  List<String> _translitVariants(String name) {
    final result = <String>[];

    // Кириллица → латиница (упрощённо)
    final cyrToLat = {
      'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd',
      'е': 'e', 'ё': 'yo', 'ж': 'zh', 'з': 'z', 'и': 'i',
      'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
      'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't',
      'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch',
      'ш': 'sh', 'щ': 'sch', 'ъ': '', 'ы': 'y', 'ь': '',
      'э': 'e', 'ю': 'yu', 'я': 'ya',
    };

    // Латиница → кириллица (упрощённо)
    final latToCyr = {
      'a': 'а', 'b': 'б', 'v': 'в', 'g': 'г', 'd': 'д',
      'e': 'е', 'z': 'з', 'i': 'и', 'y': 'й', 'k': 'к',
      'l': 'л', 'm': 'м', 'n': 'н', 'o': 'о', 'p': 'п',
      'r': 'р', 's': 'с', 't': 'т', 'u': 'у', 'f': 'ф',
    };

    // Если имя кириллическое — добавляем транслит
    final hasCyrillic = name.runes.any((r) => r >= 0x0400 && r <= 0x04FF);
    if (hasCyrillic) {
      final lat = name.split('').map((c) => cyrToLat[c] ?? c).join();
      if (lat.isNotEmpty) result.add(lat);
    }

    // Если имя латинское — добавляем кириллицу
    final hasLatin = name.runes.any((r) => (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A));
    if (hasLatin) {
      final cyr = name.split('').map((c) => latToCyr[c] ?? c).join();
      if (cyr.isNotEmpty) result.add(cyr);
    }

    return result;
  }

  Future<void> initialize() async {
    await updateTriggers();
    debugPrint('[WakeWord] ready — ждёт shared STT');
  }

  void initWithSharedStt(SpeechToText stt) {
    _sharedStt = stt;
    debugPrint('[WakeWord] shared STT подключён');
  }

  Future<void> startListening(Function() callback) async {
    if (_sharedStt == null || !_sharedStt!.isAvailable || _isRunning) return;
    onWakeWord = callback;
    _isRunning = true;
    await updateTriggers(); // Обновляем триггеры перед стартом
    debugPrint('[WakeWord] фоновое прослушивание запущено');
    await _startContinuousListen();
    _startWatchdog();
  }

  Future<void> _startContinuousListen() async {
    if (!_isRunning || _sharedStt == null) return;
    if (!_sharedStt!.isAvailable) return;
    if (_sharedStt!.isListening) return;

    try {
      await _sharedStt!.listen(
        localeId: 'ru-RU',
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 30),
        onResult: (result) {
          if (!_isRunning) return;
          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;
          debugPrint('[WakeWord] слышу: $words');
          if (_currentTriggers.any((t) => words.contains(t))) {
            debugPrint('[WakeWord] ✅ Wake word: $words');
            onWakeWord?.call();
          }
        },
        listenMode: ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('[WakeWord] ошибка listen: $e');
    }

    if (_isRunning) {
      await Future.delayed(const Duration(milliseconds: 300));
      _startContinuousListen();
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!_isRunning) return;
      if (_sharedStt == null || !_sharedStt!.isAvailable) return;
      if (!_sharedStt!.isListening) {
        debugPrint('[WakeWord] watchdog: перезапуск...');
        _startContinuousListen();
      }
    });
  }

  Future<void> stop() async {
    _isRunning = false;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    debugPrint('[WakeWord] остановлено');
  }

  bool get isRunning => _isRunning;
}
