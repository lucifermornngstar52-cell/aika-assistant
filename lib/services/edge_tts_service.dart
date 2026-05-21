import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

/// Edge TTS — Microsoft Neural Voices
/// Голос: ru-RU-DariyaNeural (нежный женский)
class EdgeTtsService extends ChangeNotifier {
  static const _defaultVoice  = 'ru-RU-DariyaNeural';
  static const _trustedToken  = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const _wsUrl =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';

  final FlutterTts _systemTts = FlutterTts();
  final AudioPlayer _player   = AudioPlayer();

  bool _isSpeaking   = false;
  bool _edgeEnabled  = true;
  String _voice      = _defaultVoice;
  double _rate       = 0.0;   // в процентах: 0 = норма, +20 = быстрее
  double _pitch      = 5.0;   // в процентах

  bool   get isSpeaking => _isSpeaking;
  String get voice      => _voice;

  /// Доступные голоса
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
    // Системный TTS как fallback
    await _systemTts.setLanguage('ru-RU');
    await _systemTts.setSpeechRate(0.85);
    await _systemTts.setVolume(1.0);
    await _systemTts.setPitch(1.15);
    _systemTts.setCompletionHandler(() { _isSpeaking = false; notifyListeners(); });
    _systemTts.setErrorHandler((_)    { _isSpeaking = false; notifyListeners(); });

    _player.onPlayerComplete.listen((_) { _isSpeaking = false; notifyListeners(); });
  }

  void setVoice(String voiceId) {
    _voice = voiceId;
    notifyListeners();
  }

  void setRate(double rate) => _rate = rate;
  void setPitch(double pitch) => _pitch = pitch;

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await stop();

    _isSpeaking = true;
    notifyListeners();

    if (_edgeEnabled) {
      try {
        await _speakEdge(text);
        return;
      } catch (e) {
        debugPrint('[EdgeTTS] ошибка: $e → системный TTS');
        _edgeEnabled = false;
        _isSpeaking = true;
      }
    }

    await _systemTts.speak(text);
  }

  Future<void> stop() async {
    await _player.stop();
    await _systemTts.stop();
    _isSpeaking = false;
    notifyListeners();
  }

  // ── Edge TTS via WebSocket ──────────────────────────────────────────────
  Future<void> _speakEdge(String text) async {
    final reqId = _genUuid();
    final ts    = _timestamp();
    final rateStr  = _rate >= 0 ? '+${_rate.toInt()}%' : '${_rate.toInt()}%';
    final pitchStr = _pitch >= 0 ? '+${_pitch.toInt()}Hz' : '${_pitch.toInt()}Hz';

    final ssml = '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="ru-RU">'
        '<voice name="$_voice">'
        '<prosody rate="$rateStr" pitch="$pitchStr">${_escapeXml(text)}</prosody>'
        '</voice></speak>';

    final uri = Uri.parse('$_wsUrl?TrustedClientToken=$_trustedToken&ConnectionId=$reqId');
    final ws  = await WebSocket.connect(uri.toString(), headers: {
      'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          'Chrome/91.0.4472.77 Safari/537.36 Edg/91.0.864.41',
    }).timeout(const Duration(seconds: 10));

    // Config
    ws.add('X-Timestamp:$ts\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false",'
        '"wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}');

    // SSML
    ws.add('X-RequestId:$reqId\r\nContent-Type:application/ssml+xml\r\n'
        'X-Timestamp:$ts\r\nPath:ssml\r\n\r\n$ssml');

    final audioBytes = <int>[];
    final done = Completer<void>();

    ws.listen((data) {
      if (data is List<int>) {
        // Бинарный фрейм — ищем конец заголовка (двойной \r\n)
        int start = 0;
        for (int i = 0; i < data.length - 1; i++) {
          if (data[i] == 0x0d && data[i+1] == 0x0a &&
              i+3 < data.length && data[i+2] == 0x0d && data[i+3] == 0x0a) {
            start = i + 4;
            break;
          }
        }
        if (start < data.length) audioBytes.addAll(data.sublist(start));
      } else if (data is String && data.contains('Path:turn.end')) {
        if (!done.isCompleted) done.complete();
      }
    }, onDone: () { if (!done.isCompleted) done.complete(); },
       onError: (e) { if (!done.isCompleted) done.completeError(e); });

    await done.future.timeout(const Duration(seconds: 20));
    await ws.close();

    if (audioBytes.isEmpty) throw Exception('пустой аудио ответ');

    // Сохраняем MP3 и воспроизводим
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/aika_tts_${reqId.substring(0,8)}.mp3');
    await file.writeAsBytes(audioBytes);
    debugPrint('[EdgeTTS] ✅ ${file.lengthSync()} bytes → ${file.path}');

    await _player.play(DeviceFileSource(file.path));
  }

  // ── Утилиты ─────────────────────────────────────────────────────────────
  String _genUuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    return b.map((x) => x.toRadixString(16).padLeft(2,'0')).join();
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
    _player.dispose();
    _systemTts.stop();
    super.dispose();
  }
}
