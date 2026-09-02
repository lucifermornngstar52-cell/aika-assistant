import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'ai_service.dart';

/// Предустановленные зоны экрана (в процентах от размера экрана).
/// Можно использовать голосом: "следи за миникартой"
class ScreenZone {
  final String name;
  final double xPct;   // левый край, 0.0–1.0
  final double yPct;   // верхний край
  final double wPct;   // ширина
  final double hPct;   // высота

  const ScreenZone({
    required this.name,
    required this.xPct,
    required this.yPct,
    required this.wPct,
    required this.hPct,
  });

  // Стандартные зоны для игр
  static const minimap = ScreenZone(name: 'миникарта', xPct: 0.0, yPct: 0.0, wPct: 0.25, hPct: 0.25);
  static const topBar  = ScreenZone(name: 'верхняя панель', xPct: 0.0, yPct: 0.0, wPct: 1.0, hPct: 0.1);
  static const health  = ScreenZone(name: 'здоровье', xPct: 0.0, yPct: 0.85, wPct: 0.4, hPct: 0.15);
  static const center  = ScreenZone(name: 'центр', xPct: 0.25, yPct: 0.25, wPct: 0.5, hPct: 0.5);
  static const full    = ScreenZone(name: 'весь экран', xPct: 0.0, yPct: 0.0, wPct: 1.0, hPct: 1.0);

  /// Распознать зону по голосовой команде
  static ScreenZone fromVoice(String text) {
    final t = text.toLowerCase();
    if (t.contains('миникарт') || t.contains('карт')) return minimap;
    if (t.contains('здоровь') || t.contains('hp') || t.contains('жизн')) return health;
    if (t.contains('верх') || t.contains('сверху') || t.contains('статус')) return topBar;
    if (t.contains('центр') || t.contains('середин')) return center;
    return full;
  }
}

/// Сервис слежки за конкретной зоной экрана.
/// Использует PixelCopy (через Kotlin) для захвата + Groq gpt-oss-120b Vision для анализа.
class AikaZoneWatcherService {
  static const _reader = MethodChannel('com.aika.assistant/screen_reader');

  static Timer? _timer;
  static ScreenZone? _zone;
  static String _instruction = '';
  static Function(String)? _onAlert;
  static int _intervalSec = 4;
  static DateTime? _lastAlert;
  static const _alertCooldown = Duration(seconds: 10);

  // ─── Запуск слежки ────────────────────────────────────────────

  /// Запустить слежку за зоной.
  /// [voiceCommand] — фраза пользователя, например «следи за миникартой, красные точки»
  static Future<String> startFromVoice({
    required String voiceCommand,
    required Function(String alert) onAlert,
    int intervalSeconds = 4,
  }) async {
    final zone = ScreenZone.fromVoice(voiceCommand);
    return start(
      zone: zone,
      instruction: voiceCommand,
      onAlert: onAlert,
      intervalSeconds: intervalSeconds,
    );
  }

  /// Запустить слежку за конкретной зоной с инструкцией.
  static Future<String> start({
    required ScreenZone zone,
    required String instruction,
    required Function(String) onAlert,
    int intervalSeconds = 4,
  }) async {
    stop();
    _zone = zone;
    _instruction = instruction;
    _onAlert = onAlert;
    _intervalSec = intervalSeconds;

    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) async {
      await _tick();
    });

    return 'Слежу за зоной "${zone.name}" 👁 Скажу если что-то важное.';
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _zone = null;
    _instruction = '';
  }

  static bool get isActive => _timer != null;
  static String get zoneName => _zone?.name ?? '';

  // ─── Один тик наблюдения ─────────────────────────────────────

  static Future<void> _tick() async {
    try {
      // 1. Захватываем скриншот через PixelCopy
      final b64Full = await _reader.invokeMethod<String>(
        'captureScreenBase64',
        {'quality': 55},
      );
      if (b64Full == null || b64Full.isEmpty) return;

      // 2. Кропаем зону через dart:ui
      final zone = _zone!;
      final croppedB64 = await _cropZone(b64Full, zone);
      if (croppedB64 == null) return;

      // 3. Анализируем через Groq gpt-oss-120b Vision
      final ai = AiService();
      final prompt =
          'Ты игровой ассистент Айка. Смотришь на зону экрана: "${zone.name}". '
          'Инструкция пользователя: "$_instruction". '
          'Если видишь что-то важное по инструкции — напиши коротко (1-2 предложения) на русском. '
          'Если ничего важного — ответь только словом OK.';

      final resp = await ai.sendMessage(
        prompt,
        imageBase64: croppedB64,
        imageMimeType: 'image/jpeg',
      );

      final trimmed = resp.trim();
      if (trimmed == 'OK' || trimmed.isEmpty) return;

      // Антиспам — не чаще раз в 10 секунд
      final now = DateTime.now();
      if (_lastAlert != null && now.difference(_lastAlert!) < _alertCooldown) return;
      _lastAlert = now;

      _onAlert?.call('👁 ${zone.name}: $trimmed');
    } catch (_) {}
  }

  // ─── Кроп зоны из base64 изображения ─────────────────────────

  static Future<String?> _cropZone(String b64, ScreenZone zone) async {
    try {
      final bytes = base64Decode(b64);
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      final frame = await codec.getNextFrame();
      final img = frame.image;

      final w = img.width.toDouble();
      final h = img.height.toDouble();

      final srcRect = ui.Rect.fromLTWH(
        zone.xPct * w,
        zone.yPct * h,
        zone.wPct * w,
        zone.hPct * h,
      );

      // Рисуем кроп в PictureRecorder
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, srcRect.width, srcRect.height));
      canvas.drawImageRect(
        img,
        srcRect,
        ui.Rect.fromLTWH(0, 0, srcRect.width, srcRect.height),
        ui.Paint(),
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(srcRect.width.toInt(), srcRect.height.toInt());

      final byteData = await cropped.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;

      // Конвертируем RGBA → JPEG через простой PNG encode
      final pngData = await _rgbaToJpeg(cropped);
      if (pngData == null) return null;

      return base64Encode(pngData);
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>?> _rgbaToJpeg(ui.Image image) async {
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List().toList();
    } catch (_) {
      return null;
    }
  }
}
