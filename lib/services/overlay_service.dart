import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис управления 3D оверлеем.
/// Отправляет команды в AikaOverlayService через MethodChannel.
class OverlayService {
  static final OverlayService _i = OverlayService._();
  factory OverlayService() => _i;
  OverlayService._();

  static const _overlayChannel = MethodChannel('com.aika.assistant/overlay');
  static const _modelChannel   = MethodChannel('com.aika.assistant/live2d_overlay');

  // Настройки размера
  double _sizeDp   = 170.0;
  double _opacity  = 1.0;
  bool   _mirror   = false;
  String _side     = 'left'; // left / right
  bool   _musicPlaying = false;

  double get sizeDp   => _sizeDp;
  double get opacity  => _opacity;
  bool   get mirror   => _mirror;
  String get side     => _side;

  // ─── Инициализация ──────────────────────────────────────────────────
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _sizeDp  = prefs.getDouble('overlay_size')    ?? 170.0;
    _opacity = prefs.getDouble('overlay_opacity') ?? 1.0;
    _mirror  = prefs.getBool('overlay_mirror')    ?? false;
    _side    = prefs.getString('overlay_side')    ?? 'left';
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('overlay_size',    _sizeDp);
    await prefs.setDouble('overlay_opacity', _opacity);
    await prefs.setBool('overlay_mirror',    _mirror);
    await prefs.setString('overlay_side',    _side);
  }

  // ─── Разрешение и показ ─────────────────────────────────────────────
  Future<bool> hasPermission() async {
    try {
      return await _overlayChannel.invokeMethod('hasPermission') ?? false;
    } catch (_) { return false; }
  }

  Future<void> requestPermission() async {
    try { await _overlayChannel.invokeMethod('requestPermission'); } catch (_) {}
  }

  Future<void> show({String state = 'idle'}) async {
    try {
      await _overlayChannel.invokeMethod('showOverlay', {'state': state});
      await _sendConfig();
    } catch (_) {}
  }

  Future<void> hide() async {
    try { await _overlayChannel.invokeMethod('hideOverlay'); } catch (_) {}
  }

  // ─── Состояния модели ───────────────────────────────────────────────
  Future<void> setState(String state) async {
    try { await _overlayChannel.invokeMethod('updateOverlay', {'state': state}); } catch (_) {}
  }

  // Sync wrapper для вызова без await (публичный)
  void asyncState(String s) { setState(s); }

  Future<void> setIdle()      => setState('idle');
  Future<void> setListening() => setState('listening');
  Future<void> setThinking()  => setState('thinking');
  Future<void> setTalking()   => setState('talking');
  Future<void> setDance()     => setState('dance');
  Future<void> setGreeting()  => setState('greeting');

  // ─── Музыкальный режим ──────────────────────────────────────────────
  Future<void> setMusicPlaying(bool playing) async {
    _musicPlaying = playing;
    try {
      await _overlayChannel.invokeMethod('musicOverlay', {'playing': playing});
    } catch (_) {
      await setState(playing ? 'dance' : 'idle');
    }
  }

  bool get isMusicPlaying => _musicPlaying;

  // ─── Анимация напрямую ──────────────────────────────────────────────
  Future<void> playAnimation(String animName) async {
    try {
      await _overlayChannel.invokeMethod('animOverlay', {'anim': animName});
    } catch (_) {
      await _modelChannel.invokeMethod('playAnimation', animName);
    }
  }

  // ─── Конфиг: размер / прозрачность / сторона ────────────────────────
  Future<void> setSize(double dp) async {
    _sizeDp = dp.clamp(80.0, 350.0);
    await _savePrefs();
    await _sendConfig();
  }

  Future<void> setOpacity(double v) async {
    _opacity = v.clamp(0.2, 1.0);
    await _savePrefs();
    await _sendConfig();
  }

  Future<void> setSide(String side) async {
    _side = side;
    await _savePrefs();
    await _sendConfig();
  }

  Future<void> setMirror(bool v) async {
    _mirror = v;
    await _savePrefs();
    await _sendConfig();
  }

  Future<void> _sendConfig() async {
    try {
      // Обновляем WindowManager размер через overlay channel
      await _overlayChannel.invokeMethod('configOverlay', {
        'size': _sizeDp,
        'side': _side,
        'opacity': _opacity,
      });
      // Обновляем Flutter-сторону (зеркало, прозрачность)
      await _modelChannel.invokeMethod('setConfig', {
        'size':    _sizeDp,
        'opacity': _opacity,
        'mirror':  _mirror,
      });
    } catch (_) {}
  }
}
