import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter/services.dart';

/// ═════════════════════════════════════════════════════════════════════
/// OpenAiRealtimeService — ПОСТОЯННЫЙ ЖИВОЙ РАЗГОВОР через OpenAI Realtime.
///
/// Пайплайн (аналог плана «фронтенд → бэкенд-мост → OpenAI», но без
/// сервера-моста: Flutter — не браузер, сам держит WebSocket с ключом,
/// как уже делает с Groq):
///
///   микрофон ──PCM 16бит 24кГц (чанками)──►  WebSocket  ──►  OpenAI
///   динамик ◄──PCM 16бит 24кГц (стримом)──  WebSocket  ◄──  OpenAI
///
///  • VAD серверный (turn_detection: server_vad) — Айка сама чувствует,
///    когда ты заговорил, и МГНОВЕННО замолкает (interrupt_response).
///  • Микрофон пишет и транслируется НЕПРЕРЫВНО всю сессию — никаких
///    «нажми чтобы говорить».
///  • Транскрипты летят в чат: и твои слова, и текст Айки.
///  • Прощание («пока») модель закрывает сама через функцию end_session.
/// ═════════════════════════════════════════════════════════════════════
class OpenAiRealtimeService {
  static final OpenAiRealtimeService _i = OpenAiRealtimeService._();
  factory OpenAiRealtimeService() => _i;
  OpenAiRealtimeService._();

  static const String _wsUrl =
      'wss://api.openai.com/v1/realtime?model=gpt-4o-mini-realtime-preview';

  // ── Колбэки (поставляет main_screen) ────────────────────────────────
  void Function(RealtimeState state)? onStateChanged;
  void Function(String userText)? onUserTranscript;
  void Function(String assistantText)? onAssistantText;
  /// Финальный текст реплики Айки (для чата и памяти).
  void Function(String assistantText)? onAssistantFinal;
  void Function()? onSessionEnd;
  void Function(String error)? onError;

  // ── Настройки ────────────────────────────────────────────────────────
  /// Тишина столько секунд → сессия закрывается (кроме речи Айки).
  int idleTimeoutSec = 60;
  String voice = 'shimmer'; // alloy | echo | shimmer

  RealtimeState _state = RealtimeState.idle;
  RealtimeState get state => _state;
  bool _active = false;
  bool get isActive => _active;

  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  /// Нативный PCM-конвейер: AudioRecord (микрофон) + AudioTrack (динамик).
  static const MethodChannel _pcmCh = MethodChannel('com.aika.assistant/pcm_stream');
  Timer? _idleTimer;
  String _apiKey = '';

  // ═══ ПУБЛИЧНОЕ API ═══════════════════════════════════════════════════

  /// Запуск realtime-сессии. Ключ OpenAI хранится в настройках (openai_key).
  Future<void> start({required String instructions}) async {
    if (_active) return;

    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('openai_key') ?? '';
    if (_apiKey.isEmpty) {
      onError?.call('Нет ключа OpenAI — впиши его в Настройках → Голос → Realtime');
      return;
    }

    _active = true;
    _setState(RealtimeState.connecting);
    debugPrint('[Realtime] 🔌 подключаюсь…');

    try {
      // ── 1. WebSocket к OpenAI (заголовки — как у сервера-моста) ──
      _ws = IOWebSocketChannel.connect(
        Uri.parse(_wsUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'OpenAI-Beta': 'realtime=v1',
        },
        protocols: const ['realtime'],
      );
      _wsSub = _ws!.stream.listen(
        _onServerEvent,
        onDone: () { if (_active) stop(); },
        onError: (e) {
          debugPrint('[Realtime] WS error: $e');
          onError?.call('Не удалось подключиться к OpenAI Realtime: $e');
          stop(notify: false);
        },
      );

      // Ждём session.created, затем настраиваем сессию
      _pendingInstructions = instructions;
      _armIdleTimer();
    } catch (e) {
      debugPrint('[Realtime] connect error: $e');
      onError?.call('Ошибка подключения: $e');
      _active = false;
      _setState(RealtimeState.idle);
    }
  }

  String _pendingInstructions = '';

  /// Принудительное закрытие.
  Future<void> stop({bool notify = true}) async {
    if (!_active) return;
    _active = false;
    _idleTimer?.cancel();
    try { await _pcmCh.invokeMethod('micStop'); } catch (_) {}
    try { await _pcmCh.invokeMethod('pcmStop'); } catch (_) {}
    try { await _ws?.sink.close(); } catch (_) {}
    try { await _wsSub?.cancel(); } catch (_) {}
    _ws = null;
    _setState(RealtimeState.idle);
    debugPrint('[Realtime] 🔴 сессия закрыта');
    if (notify) onSessionEnd?.call();
  }

  // ═══ НАСТРОЙКА СЕССИИ ПОСЛЕ session.created ══════════════════════════

  void _configureSession() {
    _send({
      'type': 'session.update',
      'session': {
        'instructions': _pendingInstructions,
        'voice': voice,
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'input_audio_transcription': {'model': 'whisper-1'},
        // Серверный VAD: сам чувствует речь, сам перебивает ответ Айки
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.5,
          'prefix_padding_ms': 300,
          'silence_duration_ms': 500,
          'create_response': true,    // после паузы — сразу отвечать
          'interrupt_response': true, // заговорил — Айка МГНОВЕННО молчит
        },
        'tools': [
          {
            'type': 'function',
            'name': 'end_session',
            'description':
                'Вызови, когда пользователь прощается (пока, до свидания) '
                'и явно хочет закончить разговор',
            'parameters': {
              'type': 'object',
              'properties': {},
            },
          }
        ],
        'tool_choice': 'auto',
      },
    });
  }

  // ═══ МИКРОФОН → OPENAI (PCM чанками) ════════════════════════════════

  Future<void> _startMic() async {
    try {
      // Чанки с нативного AudioRecord прилетают сюда
      _pcmCh.setMethodCallHandler((call) async {
        if (call.method == 'micData' && _active) {
          final data = call.arguments['data'] as List<int>?;
          if (data != null && data.isNotEmpty) {
            _send({
              'type': 'input_audio_buffer.append',
              'audio': base64Encode(data),
            });
          }
        }
      });
      final ok = await _pcmCh.invokeMethod(
          'micStart', {'sampleRate': 24000}) as bool? ?? false;
      if (!ok) {
        onError?.call('Нет доступа к микрофону');
        await stop(notify: false);
        return;
      }
      debugPrint('[Realtime] 🎤 микрофон стримит PCM 24кГц');
      _setState(RealtimeState.listening);
    } catch (e) {
      debugPrint('[Realtime] mic error: $e');
      onError?.call('Микрофон недоступен: $e');
      await stop(notify: false);
    }
  }


  // ═══ OPENAI → ДИНАМИК (стрим PCM) ════════════════════════════════════

  Future<void> _startPlayer() async {
    await _pcmCh.invokeMethod('pcmStart', {'sampleRate': 24000});
  }

  // ═══ СОБЫТИЯ СЕРВЕРА ═════════════════════════════════════════════════

  Future<void> _onServerEvent(dynamic raw) async {
    if (!_active) return;
    Map<String, dynamic> ev;
    try {
      ev = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) { return; }
    final type = ev['type'] as String? ?? '';

    switch (type) {
      // ── Сессия создана → настраиваем и включаем звук ──
      case 'session.created':
        _configureSession();
        _startPlayer().then((_) {
          if (_active) _startMic();
        });
        break;

      // ── Ты заговорил: сервер перебивает ответ Айки сам,
      //    мы выкидываем уже скачанный хвост из буфера плеера ──
      case 'input_audio_buffer.speech_started':
        _armIdleTimer();
        _setState(RealtimeState.listening);
        // сброс локального буфера, чтобы Айка замолчала МГНОВЕННО
        try {
          await _pcmCh.invokeMethod('pcmStop');
          await _pcmCh.invokeMethod('pcmStart', {'sampleRate': 24000});
        } catch (_) {}
        break;

      case 'input_audio_buffer.speech_stopped':
        _setState(RealtimeState.thinking);
        break;

      // ── Транскрипт твоей реплики → в чат ──
      case 'conversation.item.input_audio_transcription.completed':
        final text = (ev['transcript'] as String? ?? '').trim();
        if (text.isNotEmpty) onUserTranscript?.call(text);
        _armIdleTimer();
        break;

      // ── Речь Айки полетела ──
      case 'response.audio.delta':
        final b64 = ev['delta'] as String?;
        if (b64 != null && b64.isNotEmpty) {
          try {
            await _pcmCh.invokeMethod('pcmWrite', {'data': base64Decode(b64)});
          } catch (_) {}
        }
        _armIdleTimer();
        break;

      case 'response.output_audio_transcript.delta':
        _setState(RealtimeState.speaking);
        final d = ev['delta'] as String? ?? '';
        if (d.isNotEmpty) onAssistantText?.call(d);
        _armIdleTimer();
        break;

      // ── Финальный текст реплики Айки → в чат и память ──
      case 'response.output_audio_transcript.done':
        final text = (ev['transcript'] as String? ?? '').trim();
        if (text.isNotEmpty) onAssistantFinal?.call(text);
        break;

      // ── Айка вызывает end_session (ты попрощался) ──
      case 'response.function_call_arguments.done':
        final name = ev['name'] as String? ?? '';
        if (name == 'end_session') {
          debugPrint('[Realtime] модель закрыла сессию (прощание)');
          _send({'type': 'response.create', 'response': {
            'instructions': 'Попрощайся одним коротким предложением.',
          }});
          // даём ей 2 секунды сказать «пока» и закрываем
          Future.delayed(const Duration(seconds: 2), () => stop());
        }
        break;

      case 'error':
        final msg = ev['error'] is Map
            ? (ev['error']['message'] ?? 'неизвестная ошибка')
            : ev['error'];
        debugPrint('[Realtime] ⚠️ server error: $msg');
        onError?.call('OpenAI: $msg');
        break;
    }
  }

  void _send(Map<String, dynamic> data) {
    try { _ws?.sink.add(jsonEncode(data)); } catch (_) {}
  }

  // ═══ ТАЙМЕР БЕЗДЕЙСТВИЯ ═════════════════════════════════════════════

  void _armIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(Duration(seconds: idleTimeoutSec), () {
      debugPrint('[Realtime] тишина ${idleTimeoutSec}с — закрываю сессию');
      stop();
    });
  }

  void _setState(RealtimeState s) {
    if (_state == s) return;
    _state = s;
    debugPrint('[Realtime] → ${s.name}');
    onStateChanged?.call(s);
  }
}

enum RealtimeState { idle, connecting, listening, thinking, speaking }
