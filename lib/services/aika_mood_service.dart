import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'local_llm_service.dart';
import 'local_model_manager.dart';
import 'aika_log_service.dart';

/// Детект настроения пользователя по фронтальной камере.
///
/// Как это работает:
/// 1. Раз в [ttl] при отправке сообщения в фоне делается кадр фронталки
/// (низкое разрешение, превью не показывается).
/// 2. Кадр уходит в локальную VL-модель (Qwen3-VL), которая возвращает
/// ОДНО слово-эмоцию.
/// 3. Эмоция попадает в системный промпт — Айка подстраивает тон ответа.
///
/// Приватность: кадр живёт в памяти, на диск пишется временный файл,
/// который удаляется сразу после распознавания. Ничего не уходит в сеть 
/// работает только локальная модель, оффлайн.
class AikaMoodService {
 AikaMoodService._();
 static final AikaMoodService instance = AikaMoodService._();

 static const ttl = Duration(minutes: 3);

 /// Текущее настроение: '' — неизвестно, иначе слово-эмоция.
 final ValueNotifier<String> mood = ValueNotifier<String>('');

 DateTime _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);
 bool _busy = false;
 bool _permissionAsked = false;

 static const _emotions = <String>[
 'радость', 'грусть', 'усталость', 'злость',
 'спокойствие', 'сосредоточенность', 'удивление',
 ];

 /// Фоновое обновление, если прошло больше ttl. Не блокирует отправку.
 Future<void> refreshIfStale() async {
 if (_busy) return;
 if (DateTime.now().difference(_lastCheck) < ttl) return;
 await refresh();
 }

 /// Полная проверка: кадр фронталки → локальная VL-модель → эмоция.
 Future<void> refresh() async {
 if (_busy) return;
 _busy = true;
 try {
 final mgr = LocalModelManager.instance;
 if (!await mgr.moodCamEnabled) return;
 final visionModel = LocalModelManager.byId('qwen3_vision');
 if (visionModel == null ||!await mgr.isDownloaded(visionModel)) return;
 final engine = LocalLlmService.instance;
 if (!engine.isReady ||!engine.supportsVision) return;

 // Разрешение камеры: спрашиваем один раз, дальше не дёргаем.
 var status = await Permission.camera.status;
 if (!status.isGranted) {
 if (_permissionAsked) return;
 _permissionAsked = true;
 status = await Permission.camera.request();
 if (!status.isGranted) return;
 }

 final cameras = await availableCameras();
 if (cameras.isEmpty) return;
 CameraDescription front = cameras.first;
 for (final c in cameras) {
 if (c.lensDirection == CameraLensDirection.front) {
 front = c;
 break;
 }
 }
 final controller = CameraController(
 front,
 ResolutionPreset.low,
 enableAudio: false,
 imageFormatGroup: ImageFormatGroup.jpeg,
);
 await controller.initialize();
 // Даём камере секунду на экспозицию/баланс белого.
 await Future<void>.delayed(const Duration(milliseconds: 900));
 final shot = await controller.takePicture();
 await controller.dispose();

 final file = File(shot.path);
 Uint8List bytes = Uint8List(0);
 if (await file.exists()) bytes = await file.readAsBytes();
 try {
 if (await file.exists()) await file.delete();
 } catch (_) {}

 if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
 _lastCheck = DateTime.now();
 return;
 }

 final raw = await engine.chat(
 system: 'Ты детектор эмоций. Посмотри на человека на фото и ответь '
 'ровно одним словом из списка: радость, грусть, усталость, '
 'злость, спокойствие, сосредоточенность, удивление, нет. '
 'Если лица не видно — ответь «нет». Никаких других слов.',
 history: const <Map<String, String>>[],
 user: 'Какое эмоциональное состояние у человека на фото?',
 imageBytes: bytes,
 maxTokens: 8,
);
 final answer = raw.toLowerCase();
 for (final e in _emotions) {
 if (answer.contains(e)) {
 mood.value = e;
 debugPrint('[Mood] $e');
 break;
 }
 }
 _lastCheck = DateTime.now();
 } catch (e) {
 debugPrint('[Mood] failed: $e');
 _lastCheck = DateTime.now();
 } finally {
 _busy = false;
 }
 }

 /// Строка для промпта. Пустая — если настроение неизвестно.
 String get promptHint {
 final m = mood.value;
 if (m.isEmpty) return '';
 return 'Настроение пользователя сейчас (по камере): $m. '
 'Учитывай это в тоне ответа.';
 }
}
