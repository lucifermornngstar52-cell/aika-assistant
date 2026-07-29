import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'elevenlabs_tts_service.dart';

/// Edge TTS — Microsoft Neural Voices (стриминг через WebSocket)
/// Исправлено: _edgeEnabled не сбрасывается, автоматический реконнект.
class EdgeTtsService extends ChangeNotifier {
  static EdgeTtsService? _instance;
  factory EdgeTtsService() => _instance ??= EdgeTtsService._internal();
  EdgeTtsService._internal();

  static const _defaultVoice = 'ru-RU-DariyaNeural';
  static const _trustedToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const _wsUrl =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';

  final FlutterTts _systemTts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();

  bool _isSpeaking = false;
  // ФИКС: не отключаем EdgeTTS навсегда — при ошибке делаем реконнект и пробуем снова
  bool _edgeFailed = false;
  String _ttsEngine = 'edge'; // 'edge' | 'elevenlabs' | 'system'
  String get ttsEngine => _ttsEngine;
  void setTtsEngine(String engine) { _ttsEngine = engine; notifyListeners(); }
  String _voice = _defaultVoice;
  double _rate = 0.0;
  double _pitch = 0.0;

  WebSocket? _ws;
  bool _wsReady = false;
  Timer? _wsKeepalive;
  int _failCount = 0; // счётчик ошибок подряд
  static const _maxFails = 3; // после 3 ошибок — fallback на 30 сек

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
    await _initSystemTts();
    _player.onPlayerComplete.listen((_) { _isSpeaking = false; notifyListeners(); });
    _warmupConnection();
  }

  Future<void> _initSystemTts() async {
    await _systemTts.setLanguage('ru-RU');
    await _systemTts.setSpeechRate(0.85);
    await _systemTts.setVolume(1.0);
    await _systemTts.setPitch(1.15);
    _systemTts.setCompletionHandler(() { _isSpeaking = false; notifyListeners(); });
    _systemTts.setErrorHandler((_) { _isSpeaking = false; notifyListeners(); });
  }

  void setVoice(String voiceId) { _voice = voiceId; notifyListeners(); }
  void setRate(double rate) => _rate = rate;
  void setPitch(double pitch) => _pitch = pitch;

  Future<void> _loadEdgeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _rate = prefs.getDouble('edge_tts_rate') ?? 0.0;
      _pitch = prefs.getDouble('edge_tts_pitch') ?? 0.0;
      final voice = prefs.getString('edge_voice');
      if (voice != null && voice.isNotEmpty) _voice = voice;
      _ttsEngine = prefs.getString('tts_engine') ?? 'edge';
    } catch (_) {}
  }

  Future<void> _warmupConnection() async {
    try {
      await _connectWs();
      debugPrint('[EdgeTTS] ✅ WS прогрет');
    } catch (e) {
      debugPrint('[EdgeTTS] прогрев не удался: $e');
    }
  }

  Future<void> _connectWs() async {
    try { _ws?.close(); } catch (_) {}
    _ws = null;
    _wsReady = false;
    _wsKeepalive?.cancel();

    final connId = _genUuid();
    final uri = Uri.parse('$_wsUrl?TrustedClientToken=$_trustedToken&ConnectionId=$connId');

    _ws = await WebSocket.connect(uri.toString(), headers: {
      'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          'Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0',
    }).timeout(const Duration(seconds: 8));

    _wsReady = true;

    // Keepalive пинг каждые 20 сек
    _wsKeepalive = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_ws?.readyState == WebSocket.open) {
        try { _ws?.add(''); } catch (_) { _wsReady = false; }
      } else {
        _wsReady = false;
        _wsKeepalive?.cancel();
      }
    });

    _ws!.done.then((_) { _wsReady = false; });
  }

  Future<void> speak(String text) async {
    await _loadEdgeSettings();
    if (text.isEmpty) return;
    await stop();
    _isSpeaking = true;
    notifyListeners();

    // ── Переключение TTS движка ─────────────────────────────────────
    if (_ttsEngine == 'elevenlabs') {
      try {
        await ElevenLabsTtsService().speak(text);
        _failCount = 0;
        return;
      } catch (e) {
        debugPrint('[ElevenLabs] ошибка, fallback на EdgeTTS: $e');
        // Падаем на EdgeTTS если ElevenLabs не сработал
      }
    }

    // ФИКС: пробуем EdgeTTS если ошибок было меньше MAX
    final canUseEdge = _failCount < _maxFails;

    if (canUseEdge) {
      try {
        await _speakEdgeStreaming(text);
        _failCount = 0; // успех — сбрасываем счётчик
        return;
      } catch (e) {
        _failCount++;
        debugPrint('[EdgeTTS] ошибка $_failCount/$_maxFails: $e');
        if (_failCount >= _maxFails) {
          debugPrint('[EdgeTTS] переключаемся на системный TTS на 30 сек');
          // Через 30 сек автоматически пробуем снова
          Timer(const Duration(seconds: 30), () {
            _failCount = 0;
            _wsReady = false;
            _warmupConnection();
          });
        }
        _isSpeaking = true; // восстанавливаем для системного TTS
      }
    } else {
      debugPrint('[EdgeTTS] пауза — системный TTS');
    }

    // Системный TTS fallback
    await _speakSystem(text);
  }

  Future<void> _speakSystem(String text) async {
    final done = Completer<void>();
    _systemTts.setCompletionHandler(() {
      _isSpeaking = false; notifyListeners();
      if (!done.isCompleted) done.complete();
    });
    _systemTts.setErrorHandler((_) {
      _isSpeaking = false; notifyListeners();
      if (!done.isCompleted) done.complete();
    });
    try {
      await _systemTts.speak(text);
      await done.future.timeout(
        Duration(seconds: (text.length / 8).ceil() + 5),
        onTimeout: () { _isSpeaking = false; notifyListeners(); },
      );
    } catch (e) {
      debugPrint('[SystemTTS] error: $e');
      _isSpeaking = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try { await _player.stop(); } catch (_) {}
    try { await _systemTts.stop(); } catch (_) {}
    _isSpeaking = false;
    notifyListeners();
  }

  Future<void> _speakEdgeStreaming(String text) async {
    // Реконнект если WS не готов
    if (!_wsReady || _ws == null || _ws!.readyState != WebSocket.open) {
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

    _ws!.add(
      'X-Timestamp:$ts\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n'
      '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false",'
      '"wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}'
    );
    _ws!.add(
      'X-RequestId:$reqId\r\nContent-Type:application/ssml+xml\r\n'
      'X-Timestamp:$ts\r\nPath:ssml\r\n\r\n$ssml'
    );

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
          int start = 0;
          for (int i = 0; i < data.length - 3; i++) {
            if (data[i] == 0x0d && data[i+1] == 0x0a &&
                data[i+2] == 0x0d && data[i+3] == 0x0a) {
              start = i + 4; break;
            }
          }
          if (start < data.length) {
            final chunk = data.sublist(start);
            audioBytes.addAll(chunk);
            sink.add(chunk);
            if (!playbackStarted && audioBytes.length > 8192) {
              playbackStarted = true;
              await sink.flush();
              debugPrint('[EdgeTTS] ▶ стриминг (${audioBytes.length}b)');
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

    if (!playbackStarted && audioBytes.isNotEmpty) {
      try { await sink.close(); } catch (_) {}
      await _player.play(DeviceFileSource(filePath));
      playbackStarted = true;
    }

    if (playbackStarted) {
      final playDone = Completer<void>();
      late StreamSubscription playSub;
      playSub = _player.onPlayerComplete.listen((_) {
        if (!playDone.isCompleted) playDone.complete();
        playSub.cancel();
      });
      final secs = (text.length / 8).ceil() + 5;
      await playDone.future.timeout(Duration(seconds: secs), onTimeout: () {});
    }

    _isSpeaking = false;
    notifyListeners();

    // Прогреваем следующее соединение
    Future.delayed(const Duration(milliseconds: 500), _warmupConnection);
  }

  String _genUuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  String _timestamp() {
    final d = DateTime.now().toUtc();
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${days[d.weekday-1]}, ${d.day.toString().padLeft(2,'0')} '
        '${months[d.month-1]} ${d.year} '
        '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}:${d.second.toString().padLeft(2,'0')} GMT';
  }

  String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  @override
  void dispose() {
    _wsKeepalive?.cancel();
    try { _ws?.close(); } catch (_) {}
    _player.dispose();
    _systemTts.stop();
    super.dispose();
  }
}
