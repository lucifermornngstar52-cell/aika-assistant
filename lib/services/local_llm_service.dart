import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

import 'local_model_manager.dart';

/// Локальный LLM-движок Pro-версии: llama.cpp внутри приложения.
/// Один активный движок: текст (Qwen3-1.7B) или зрение (Qwen3-VL-2B + mmproj).
class LocalLlmService extends ChangeNotifier {
 LocalLlmService._();
 static final LocalLlmService instance = LocalLlmService._();

 LlamaEngine? _engine;
 bool _loading = false;
 bool _ready = false;
 String _status = '';
 String _loadedModelName = '';

 bool get isLoading => _loading;
 bool get isReady => _ready;
 String get status => _status;
 String get loadedModelName => _loadedModelName;
 bool get supportsVision => _engine?.supportsVision?? false;

 /// Загружает модель. [mmprojPath] — мультимодальный проектор для зрения.
 Future<bool> load({
 required String modelPath,
 required String modelLabel,
 String? mmprojPath,
 int ctx = 4096,
 }) async {
 if (_loading) return false;
 await unload();
 _loading = true;
 _ready = false;
 _status = 'Загружаю модель $modelLabel…';
 notifyListeners();
 try {
 // ФИКС ПАМЯТИ (VL-модели): Qwen3-VL с динамическим разрешением может
 // выдать тысячи токенов на одну фотографию — контекст 4096 не
 // выдерживал, и движок падал по памяти. Решение:
 // • KV-кэш квантован в q8_0 (в 2 раза меньше RAM при малой потере);
 // • лимит образа: imageMin/imageMax токенов (64..512);
 // • меньшие батчи префилла под VL;
 // • warmup — надёжный первый токен после загрузки.
 final isVision = mmprojPath!= null;
 _engine = await LlamaEngine.spawn(
 modelParams: ModelParams(path: modelPath, gpuLayers: 0),
 contextParams: isVision
? const ContextParams(
 nCtx: 4096,
 nThreads: 0,
 nBatch: 1024,
 nUbatch: 256,
 typeK: KvCacheType.q8_0,
 typeV: KvCacheType.q8_0,
)
: const ContextParams(nCtx: 4096, nThreads: 0),
 multimodalParams: mmprojPath == null
? null
: MultimodalParams(
 mmprojPath: mmprojPath,
 imageMinTokens: 64,
 imageMaxTokens: 512,
 warmup: true,
),
);
 _ready = true;
 _loadedModelName = modelLabel;
 _status = _engine!.supportsVision
? 'Готово: $modelLabel (+зрение)'
: 'Готово: $modelLabel';
 debugPrint('[LocalLLM] $status, vision=${_engine!.supportsVision}');
 } catch (e) {
 _engine = null;
 _ready = false;
 _status = 'Ошибка загрузки: $e';
 debugPrint('[LocalLLM] load failed: $e');
 } finally {
 _loading = false;
 notifyListeners();
 }
 return _ready;
 }

 Future<void> unload() async {
 final e = _engine;
 _engine = null;
 _ready = false;
 if (!_loading) {
 _status = '';
 _loadedModelName = '';
 }
 if (e!= null &&!e.isDisposed) {
 try {
 await e.dispose();
 } catch (err) {
 debugPrint('[LocalLLM] dispose error: $err');
 }
 }
 notifyListeners();
 }

 // Маркеры блока размышлений Qwen3.
 static final String _thinkOpen = '<' + 'think' + '>';
 static final String _thinkClose = '<' + '/think' + '>';

 /// Фильтр размышлений Qwen3: наружу идёт только чистый ответ.
 static String _stripThink(String text) {
 var s = text;
 // если шаблон не съел мягкий переключатель — убираем хвост
 s = s.replaceAll('/no_think', '').trim();
 final open = s.indexOf(_thinkOpen);
 if (open >= 0) {
 final close = s.indexOf(_thinkClose, open);
 if (close >= 0) {
 s = s.replaceRange(open, close + _thinkClose.length, '');
 } else {
 s = s.substring(0, open);
 }
 }
 return s.trim();
 }

 /// Диалог с локальной моделью. [history] — [{'role','content'},…].
 /// [imageBytes] — фото, если движок мультимодальный.
 Future<String> chat({
 required String system,
 required List<Map<String, String>> history,
 required String user,
 Uint8List? imageBytes,
 int maxTokens = 512,
 }) async {
 final engine = _engine;
 if (engine == null || _loading) {
 throw StateError('Локальная модель не загружена');
 }
 final chat = await engine.createChat();
 try {
 if (system.isNotEmpty) chat.addSystem(system);
 for (final m in history) {
 final role = m['role']?? '';
 final content = m['content']?? '';
 if (content.isEmpty) continue;
 if (role == 'user') {
 chat.addUser(content);
 } else if (role == 'assistant') {
 chat.addAssistant(content);
 }
 }
 final media = (imageBytes!= null && engine.supportsVision)
? <LlamaMedia>[LlamaMedia.imageBytes(imageBytes)]
: const <LlamaMedia>[];
 chat.addUser(user, media: media);

 final full = StringBuffer();
 await for (final ev in chat.generate(
 maxTokens: maxTokens,
 sampler: const SamplerParams(temperature: 0.7, topP: 0.8),
)) {
 if (ev is TokenEvent) full.write(ev.text);
 }
 return _stripThink(full.toString());
 } finally {
 try {
 await chat.dispose();
 } catch (_) {}
 }
 }
}

/// Загружает подходящий движок по скачанным моделям и настройкам.
Future<bool> loadEngineFromManager() async {
 final mgr = LocalModelManager.instance;
 final vision = await mgr.visionModeEnabled;
 final visionModel = LocalModelManager.byId('qwen3_vision');
 final textModel4b = LocalModelManager.byId('qwen3_4b_text');
 final textModel = LocalModelManager.byId('qwen3_text');
 if (vision && visionModel!= null && await mgr.isDownloaded(visionModel)) {
 final modelPath =
 await mgr.pathFor(visionModel.files[0].fileName);
 final mmprojPath =
 await mgr.pathFor(visionModel.files[1].fileName);
 return LocalLlmService.instance.load(
 modelPath: modelPath,
 mmprojPath: mmprojPath,
 modelLabel: 'Qwen3-VL-2B',
);
 }
 // Текстовый движок: приоритет у 4B (лучше держит персону), 1.7B — запасная.
 if (textModel4b!= null && await mgr.isDownloaded(textModel4b)) {
 final modelPath = await mgr.pathFor(textModel4b.files[0].fileName);
 return LocalLlmService.instance.load(
 modelPath: modelPath,
 modelLabel: 'Qwen3-4B',
);
 }
 if (textModel!= null && await mgr.isDownloaded(textModel)) {
 final modelPath = await mgr.pathFor(textModel.files[0].fileName);
 return LocalLlmService.instance.load(
 modelPath: modelPath,
 modelLabel: 'Qwen3-1.7B',
);
 }
 return false;
}
