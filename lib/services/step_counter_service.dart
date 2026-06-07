import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// StepCounterService — шагомер через акселерометр Android.
/// Адаптировано из openclaw-assistant MotionHandler (MIT).
///
/// Голосовые команды:
///   "сколько я прошёл шагов", "мои шаги", "шагомер"
class StepCounterService {
  static final StepCounterService _i = StepCounterService._();
  factory StepCounterService() => _i;
  StepCounterService._();

  static const _channel = MethodChannel('com.aika.assistant/sensors');

  int _sessionSteps = 0;
  int _baselineSteps = 0; // шаги в начале сессии (для delta)
  bool _initialized = false;
  StreamSubscription? _sub;

  // ──────────────────── ПУБЛИЧНЫЙ API ────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final steps = await _channel.invokeMethod<int>('getSteps');
      _baselineSteps = steps ?? 0;
      _initialized = true;
      debugPrint('[Steps] инициализирован. Baseline: $_baselineSteps');
    } catch (e) {
      debugPrint('[Steps] init error: $e');
    }
  }

  Future<int> getSteps() async {
    try {
      final total = await _channel.invokeMethod<int>('getSteps') ?? 0;
      return (total - _baselineSteps).clamp(0, 999999);
    } catch (e) {
      debugPrint('[Steps] getSteps error: $e');
      return _sessionSteps;
    }
  }

  void resetSession() {
    _sessionSteps = 0;
    _initialized = false;
    initialize();
  }

  // ──────────────────── ГОЛОСОВОЙ ПАРСЕР ────────────────────

  Future<String?> parseCommand(String input) async {
    final t = input.toLowerCase().trim();

    if (!_matches(t, ['шаг', 'прошёл', 'прошел', 'шагомер', 'активность', 'сколько ходил'])) {
      return null;
    }

    await initialize();
    final steps = await getSteps();

    if (steps == 0) return 'Шагомер пока не зафиксировал шагов в этой сессии.';

    final km = (steps * 0.00076).toStringAsFixed(2);
    final kcal = (steps * 0.04).round();
    return 'Сегодня ты прошла $steps шагов (~$km км, ~$kcal ккал) 🚶';
  }

  bool _matches(String text, List<String> triggers) =>
      triggers.any((tr) => text.contains(tr));
}
