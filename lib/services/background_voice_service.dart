import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BackgroundVoiceService — Flutter-сторона нативного AikaVoiceService.
///
/// Управляет нативным Android Foreground Service через MethodChannel.
/// Получает события wake word / rms / partial через EventChannel.
///
/// Как использовать:
///   final bg = BackgroundVoiceService();
///   await bg.initialize();
///   bg.onWakeWord = () { /* активировать диалог */ };
///   bg.onRms = (level) { /* обновить волну */ };
///   await bg.start();
class BackgroundVoiceService extends ChangeNotifier {
  static BackgroundVoiceService? _instance;
  factory BackgroundVoiceService() =>
      _instance ??= BackgroundVoiceService._internal();
  BackgroundVoiceService._internal();

  static const _methodChannel = MethodChannel('aika/voice_bg');
  static const _eventChannel  = EventChannel('aika/voice_events');

  StreamSubscription? _eventSub;
  bool _isRunning  = false;
  bool _isPaused   = false;
  double _rmsLevel = 0.0;
  String _lastPartial = '';

  // Callbacks
  VoidCallback?          onWakeWord;
  Function(double rms)?  onRms;
  Function(String text)? onPartial;
  VoidCallback?          onReady;

  bool   get isRunning   => _isRunning;
  bool   get isPaused    => _isPaused;
  double get rmsLevel    => _rmsLevel;
  String get lastPartial => _lastPartial;

  // ── Initialize ──────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    _eventSub?.cancel();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (e) => debugPrint('[BgVoice] event error: $e'),
    );
    debugPrint('[BgVoice] initialized');
  }

  // ── Start / Stop ────────────────────────────────────────────────────────────

  Future<void> start([List<String>? triggers]) async {
    final prefs = await SharedPreferences.getInstance();
    final effectiveTriggers = triggers ?? await _loadTriggers(prefs);
    try {
      await _methodChannel.invokeMethod('startVoiceBg', {
        'triggers': effectiveTriggers,
      });
      _isRunning = true;
      _isPaused  = false;
      debugPrint('[BgVoice] ▶ started, triggers=$effectiveTriggers');
      notifyListeners();
    } catch (e) {
      debugPrint('[BgVoice] start error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod('stopVoiceBg');
    } catch (e) {
      debugPrint('[BgVoice] stop error: $e');
    }
    _isRunning  = false;
    _isPaused   = false;
    _rmsLevel   = 0.0;
    _lastPartial = '';
    notifyListeners();
    debugPrint('[BgVoice] ■ stopped');
  }

  /// Пауза — пока Flutter STT слушает пользователя
  Future<void> pause() async {
    if (!_isRunning || _isPaused) return;
    try {
      await _methodChannel.invokeMethod('pauseVoiceBg');
    } catch (e) {
      debugPrint('[BgVoice] pause error: $e');
    }
    _isPaused = true;
    _rmsLevel = 0.0;
    notifyListeners();
    debugPrint('[BgVoice] ⏸ paused');
  }

  /// Возобновление после диалога
  Future<void> resume() async {
    if (!_isRunning || !_isPaused) return;
    try {
      await _methodChannel.invokeMethod('resumeVoiceBg');
    } catch (e) {
      debugPrint('[BgVoice] resume error: $e');
    }
    _isPaused = false;
    notifyListeners();
    debugPrint('[BgVoice] ▶ resumed');
  }

  /// Обновить триггеры без перезапуска
  Future<void> updateTriggers(List<String> triggers) async {
    try {
      await _methodChannel.invokeMethod('setVoiceTriggers', {
        'triggers': triggers,
      });
    } catch (e) {
      debugPrint('[BgVoice] setTriggers error: $e');
    }
  }

  // ── Event handler ───────────────────────────────────────────────────────────

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'] as String? ?? '';
    final data = event['data'] as String? ?? '';

    switch (type) {
      case 'wake_word':
        debugPrint('[BgVoice] ✅ wake word: $data');
        onWakeWord?.call();
        break;

      case 'rms':
        final rms = double.tryParse(data) ?? 0.0;
        _rmsLevel = rms;
        onRms?.call(rms);
        // Не notifyListeners() — слишком часто
        break;

      case 'partial':
        _lastPartial = data;
        onPartial?.call(data);
        break;

      case 'ready':
        onReady?.call();
        break;

      case 'error':
        debugPrint('[BgVoice] error from native: $data');
        break;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<List<String>> _loadTriggers(SharedPreferences prefs) async {
    final assistantName =
        (prefs.getString('assistant_name') ?? 'Aika').toLowerCase().trim();
    final customRaw = prefs.getString('custom_wake_word') ?? '';

    final triggers = <String>{'айка', 'aika', 'aivora', assistantName};

    if (customRaw.isNotEmpty) {
      for (final w in customRaw.split(',')) {
        final clean = w.trim().toLowerCase();
        if (clean.isNotEmpty) triggers.add(clean);
      }
    }
    return triggers.toList();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
