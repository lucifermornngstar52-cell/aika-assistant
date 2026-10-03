import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_model_manager.dart';

/// Оффлайн STT через нативный Vosk (Kotlin-часть: VoskHandler).
/// Модель скачивается с alphacephei.com и распаковывается нативно.
class LocalSttService {
 LocalSttService._();
 static final LocalSttService instance = LocalSttService._();

 static const _channel = MethodChannel('com.aika.assistant/vosk');
 static const _events = EventChannel('com.aika.assistant/vosk_events');

 StreamSubscription? _sub;
 bool _ready = false;
 bool _listening = false;
 String _lastWords = '';
 final _stateCtrl = StreamController<void>.broadcast();

 bool get isReady => _ready;
 bool get isListening => _listening;
 String get lastWords => _lastWords;
 Stream<void> get onStateChange => _stateCtrl.stream;

 /// Инициализация: если модель скачана — распаковываем (один раз) и грузим.
 Future<bool> ensureInitialized() async {
 if (_ready) return true;
 final mgr = LocalModelManager.instance;
 final model = LocalModelManager.byId('vosk_ru');
 if (model == null) return false;
 if (!await mgr.isDownloaded(model)) return false;
 final zipPath = await mgr.pathFor(model.files[0].fileName);
 final modelsDir = await mgr.dir();
 try {
 // Нативно: распаковать zip (если ещё не распакован) и загрузить модель.
 final modelPath = await _channel.invokeMethod<String>('init', {
 'zipPath': zipPath,
 'modelsDir': modelsDir,
 });
 if (modelPath == null || modelPath.isEmpty) {
 debugPrint('[Vosk] init вернул пустой путь');
 return false;
 }
 _ready = true;
 debugPrint('[Vosk] модель загружена: $modelPath');
 return true;
 } catch (e) {
 debugPrint('[Vosk] init failed: $e');
 return false;
 }
 }

 /// Начать слушать микрофон. [onResult] придёт финальные слова.
 Future<void> startListening({
 required void Function(String text) onResult,
 void Function(String partial)? onPartial,
 }) async {
 if (!_ready) return;
 if (_listening) await stopListening();
 _lastWords = '';
 _listening = true;
 _stateCtrl.add(null);
 _sub = _events.receiveBroadcastStream().listen((event) {
 if (event is! Map) return;
 final type = event['type'] as String??? '';
 final text = event['text'] as String??? '';
 if (type == 'partial') {
 _lastWords = text;
 onPartial?.call(text);
 _stateCtrl.add(null);
 } else if (type == 'result' || type == 'final') {
 _lastWords = text;
 _listening = false;
 _stateCtrl.add(null);
 _sub?.cancel();
 _sub = null;
 if (text.isNotEmpty) onResult(text);
 } else if (type == 'timeout' || type == 'error') {
 _listening = false;
 _stateCtrl.add(null);
 _sub?.cancel();
 _sub = null;
 }
 }, onError: (e) {
 debugPrint('[Vosk] stream error: $e');
 _listening = false;
 _stateCtrl.add(null);
 });
 try {
 await _channel.invokeMethod('start');
 } catch (e) {
 debugPrint('[Vosk] start failed: $e');
 _listening = false;
 _sub?.cancel();
 _sub = null;
 _stateCtrl.add(null);
 }
 }

 Future<void> stopListening() async {
 _sub?.cancel();
 _sub = null;
 if (_listening) {
 _listening = false;
 _stateCtrl.add(null);
 try {
 await _channel.invokeMethod('stop');
 } catch (_) {}
 }
 }

 Future<void> dispose() async {
 await stopListening();
 if (_ready) {
 try {
 await _channel.invokeMethod('unload');
 } catch (_) {}
 _ready = false;
 }
 }
}
