import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

/// Edge TTS — Microsoft Neural Voices
/// Стриминг: начинает воспроизводить сразу как получает первые чанки аудио
class EdgeTtsService extends ChangeNotifier {
  // ── Синглтон — один экземпляр на всё приложение ──────────────────────
  static EdgeTtsService? _instance;
  factory EdgeTtsService() => _instance ??= EdgeTtsService._internal();
  EdgeTtsService._internal();
  // ─────────────────────────────────────────────────────────────────────

  static const _defaultVoice = 'ru-RU-DariyaNeural';
  static const _trustedToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const _wsUrl =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';

  final FlutterTts _systemTts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();

  bool _isSpeaking = false;
  bool _edgeEnabled = true;
  String _voice = _defaultVoice;
  double _rate = 0.0;
  double _pitch = 5.0;

  // Персистентное WS соединение — переиспользуем между запросами
  WebSocket? _ws;
  bool _wsReady = false;
  Timer? _wsKeepalive;

  bool get isSpeaking => _isSpeaking;
  String get voice => _voice;

  static const List<Map<String, String>> voices = [
    {'id': 'ru-RU-DariyaNeural',   'label': '🌸 Дария (мягкий)'},
    {'id': 'ru-RU-SvetlanaNeural', 'label': '💼 Светлана (нейтральный)'},
    {'id': 'ru-RU-DmitryNeural',   'label': '👨 Дмитрий (мужской)'},
    {'id': 'ja-JP-NanamiNeural',   'label': '🌸 Nanami (аниме JP)'},
    {'id': 'ja-JP-AoiNeural',      'label': '✨ Aoi (аниме JP 2)'},
    {'id': 'zh-CN-XiaoxiaoNeural', 'label': '🐼 Xiaoxiao (аниме CN)'},
    {'id': 'en-US-JennyNeural',    'label': '🇺🇸 Jenny (EN)'},
    {'id': 'ko-KR-SunHiNeural',    'label': '🇰🇷 SunHi (KR)'},
  ];

  Future<void> initialize() async {
    await _systemTts.setLanguage('ru-RU');
    await _systemTts.setSpeechRate(0.85);
    await _systemTts.setVolume(1.0);
    await _systemTts.setPitch(1.15);
    _systemTts.setCompletionHandler(() { _isSpeaking = false; notifyListeners(); });
    _systemTts.setErrorHandler((_) { _isSpeaking = false; notifyListeners(); });
    _player.onPlayerComplete.listen((_) { _isSpeaking = false; notifyListeners(); });

    // Прогреваем соединение заранее
    _warmupConnection();
  }

  void setVoice(String voiceId) { _voice = voiceId; notifyListeners(); }
  void setRate(double rate) => _rate = rate;
  void setPitch(double pitch) => _pitch = pitch;

  /// Load rate and pitch from SharedPreferences (called automatically before each speak)
  Future<void> _loadEdgeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _rate = prefs.getDouble('edge_tts_rate') ?? 0.0;
      _pitch = prefs.getDouble('edge_tts_pitch') ?? 0.0;
      final voice = prefs.getString('edge_voice');
      if (voice != null && voice.isNotEmpty) _voice = voice;
    } catch (_) {}
  }

  /// Прогрев WS соединения — вызывается при инициализации
  Future<void> _warmupConnection() async {
    try {
      await _connectWs();
      debugPrint('[EdgeTTS] ✅ WS соединение прогрето');
    } catch (e) {
      debugPrint('[EdgeTTS] Прогрев не удался: $e');
    }
  }

  Future<void> _connectWs() async {
    _ws?.close();
    _ws = null;
    _wsReady = false;

    final connId = _genUuid();
    final uri = Uri.parse('$_wsUrl?TrustedClientToken=$_trustedToken&ConnectionId=$connId');
    _ws = await WebSocket.connect(uri.toString(), headers: {
      'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          'Chrome/91.0.4472.77 Safari/537.36 Edg/91.0.864.41',
    }).timeout(const Duration(seconds: 8));

    _wsReady = true;

    // Keepalive — пинг каждые 25 сек чтобы соединение не закрылось
    _wsKeepalive?.cancel();
    _wsKeepalive = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_ws?.readyState == WebSocket.open) {
        _ws?.add('');
      } else {
        _wsReady = false;
        _wsKeepalive?.cancel();
      }
    });

    // Если сервер закрыл — сбрасываем флаг
    _ws!.done.then((_) { _wsReady = false; });
  }

  Future<void> speak(String text) async {
    await _loadEdgeSettings();
    if (text.isEmpty) return;
    await stop();
    _isSpeaking = true;
    notifyListeners();

    if (_edgeEnabled) {
      try {
        await _speakEdgeStreaming(text);
        // _isSpeaking уже сброшен внутри _speakEdgeStreaming
        return;
      } catch (e) {
        debugPrint('[EdgeTTS] ошибка: $e → системный TTS');
        _edgeEnabled = false;
        _isSpeaking = true;
      }
    }

    // Системный TTS — ждём завершения
    final sysDone = Completer<void>();
    _systemTts.setCompletionHandler(() {
      _isSpeaking = false;
      notifyListeners();
      if (!sysDone.isCompleted) sysDone.complete();
    });
    _systemTts.setErrorHandler((_) {
      _isSpeaking = false;
      notifyListeners();
      if (!sysDone.isCompleted) sysDone.complete();
    });
    await _systemTts.speak(text);
    await sysDone.future.timeout(
      Duration(seconds: (text.length / 8).ceil() + 5),
      onTimeout: () { _isSpeaking = false; notifyListeners(); },
    );
  }

  Future<void> stop() async {
    await _player.stop();
    await _systemTts.stop();
    _isSpeaking = false;
    notifyListeners();
  }

  /// Стриминговое воспроизведение — начинает играть сразу как получает первые байты
  Future<void> _speakEdgeStreaming(String text) async {
    // Переиспользуем существующее соединение или создаём новое
    if (!_wsReady || _ws?.readyState != WebSocket.open) {
      await _connectWs();
    }

    final reqId = _genUuid();
    final ts = _timestamp();
    final rateStr = _rate >= 0 ? '+${_rate.toInt()}%' : '${_rate.toInt()}%';
    final pitchStr = _pitch >= 0 ? '+${_pitch.toInt()}Hz' : '${_pitch.toInt()}Hz';

    final ssml =
        '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="ru-RU">'
        '<voice name="$_voice">'
        '<prosody rate="$rateStr" pitch="$pitchStr">${_escapeXml(text)}</prosody>'
        '</voice></speak>';

    // Отправляем конфиг
    _ws!.add(
      'X-Timestamp:$ts\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n'
      '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false",'
      '"wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}'
    );

    // Отправляем SSML
    _ws!.add(
      'X-RequestId:$reqId\r\nContent-Type:application/ssml+xml\r\n'
      'X-Timestamp:$ts\r\nPath:ssml\r\n\r\n$ssml'
    );

    // Собираем аудио байты — стриминг
    final audioBytes = <int>[];
    final done = Completer<void>();
    bool playbackStarted = false;

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/aika_tts_${reqId.substring(0, 8)}.mp3';
    final file = File(filePath);
    final sink = file.openWrite();

    StreamSubscription? sub;
    sub = _ws!.listen(
      (data) async {
        if (data is List<int>) {
          // Парсим бинарный фрейм — пропускаем заголовок
          int start = 0;
          for (int i = 0; i < data.length - 3; i++) {
            if (data[i] == 0x0d && data[i + 1] == 0x0a &&
                data[i + 2] == 0x0d && data[i + 3] == 0x0a) {
              start = i + 4;
              break;
            }
          }
          if (start < data.length) {
            final chunk = data.sublist(start);
            audioBytes.addAll(chunk);
            sink.add(chunk);

            // Начинаем воспроизведение сразу после первых ~8KB (~0.25 сек аудио)
            if (!playbackStarted && audioBytes.length > 8192) {
              playbackStarted = true;
              await sink.flush();
              debugPrint('[EdgeTTS] ▶ стриминг старт (${audioBytes.length} bytes)');
              await _player.play(DeviceFileSource(filePath));
            }
          }
        } else if (data is String && data.contains('Path:turn.end')) {
          await sink.flush();
          await sink.close();
          if (!done.isCompleted) done.complete();
          sub?.cancel();
        }
      },
      onDone: () { if (!done.isCompleted) done.complete(); sub?.cancel(); },
      onError: (e) { if (!done.isCompleted) done.completeError(e); sub?.cancel(); },
      cancelOnError: true,
    );

    await done.future.timeout(const Duration(seconds: 15));

    // Если аудио маленькое — не успело запуститься стримингом
    if (!playbackStarted && audioBytes.isNotEmpty) {
      await sink.close();
      await _player.play(DeviceFileSource(filePath));
      playbackStarted = true;
    }

    // ── ФИКС: ждём завершения воспроизведения ──────────────────────────
    // speak() не должен возвращаться пока плеер играет — иначе isSpeaking
    // сбрасывается раньше времени и wake word стартует поверх речи
    if (playbackStarted) {
      final playDone = Completer<void>();
      late StreamSubscription playSub;
      playSub = _player.onPlayerComplete.listen((_) {
        if (!playDone.isCompleted) playDone.complete();
        playSub.cancel();
      });
      // Таймаут: длина текста / 8 символов в секунду + 5 сек запас
      final timeoutSec = (text.length / 8).ceil() + 5;
      await playDone.future.timeout(Duration(seconds: timeoutSec), onTimeout: () {});
    }

    _isSpeaking = false;
    notifyListeners();

    // После завершения — прогреваем новое соединение для следующего запроса
    Future.delayed(const Duration(milliseconds: 300), _warmupConnection);
  }

  // ── Утилиты ─────────────────────────────────────────────────────────────
  String _genUuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  String _timestamp() {
    final d = DateTime.now().toUtc();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${days[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')} '
        '${months[d.month - 1]} ${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')} GMT';
  }

  String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  @override
  void dispose() {
    _wsKeepalive?.cancel();
    _ws?.close();
    _player.dispose();
    _systemTts.stop();
    super.dispose();
  }
}

