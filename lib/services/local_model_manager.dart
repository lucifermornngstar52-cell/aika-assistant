import 'dart:async';

import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Каталог и менеджер загрузки локальных моделей Pro-версии.
/// Модели не зашиты в APK — пользователь скачивает их сам с прогрессом.
class LocalModelFile {
  final String url;
  final String fileName;
  const LocalModelFile({required this.url, required this.fileName});
}

class LocalModelInfo {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String kind; // 'text' | 'vision' | 'stt'
  final List<LocalModelFile> files;
  const LocalModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.kind,
    required this.files,
  });
}

class LocalModelManager {
  LocalModelManager._();
  static final LocalModelManager instance = LocalModelManager._();

  static const catalog = <LocalModelInfo>[
    LocalModelInfo(
      id: 'qwen3_text',
      name: 'Qwen3-1.7B — текст (Pro)',
      description:
          'Локальная языковая модель для диалога, вопросов и команд. '
          'GGUF Q4_K_M, ~1.1 ГБ. Работает полностью оффлайн.',
      icon: '🧠',
      kind: 'text',
      files: [
        LocalModelFile(
          url: 'https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
          fileName: 'Qwen3-1.7B-Q4_K_M.gguf',
        ),
      ],
    ),
    LocalModelInfo(
      id: 'qwen3_4b_text',
      name: 'Qwen3-4B — текст (Pro+)',
      description:
          'Более умная локальная модель: заметно лучше держит персону и '
          'системный промпт, чем 1.7B. GGUF Q4_K_M, ~2.5 ГБ. '
          'Рекомендуется при 8+ ГБ оперативной памяти.',
      icon: '🧠',
      kind: 'text',
      files: [
        LocalModelFile(
          url: 'https://huggingface.co/ggml-org/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
          fileName: 'Qwen3-4B-Q4_K_M.gguf',
        ),
      ],
    ),
    LocalModelInfo(
      id: 'qwen3_vision',
      name: 'Qwen3-VL-2B — зрение (Pro)',
      description:
          'Мультимодальная модель: видит и описывает фотографии прямо на '
          'устройстве. GGUF Q4_K_M + mmproj-проектор, ~1.4 ГБ суммарно.',
      icon: '👁️',
      kind: 'vision',
      files: [
        LocalModelFile(
          url: 'https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/resolve/main/Qwen3VL-2B-Instruct-Q4_K_M.gguf',
          fileName: 'Qwen3VL-2B-Instruct-Q4_K_M.gguf',
        ),
        LocalModelFile(
          url: 'https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf',
          fileName: 'mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf',
        ),
      ],
    ),
    LocalModelInfo(
      id: 'vosk_ru',
      name: 'Vosk — распознавание речи (Pro)',
      description:
          'Оффлайн STT для русского языка. Модель small-ru, ~45 МБ. '
          'Голос превращается в текст без интернета.',
      icon: '🎙️',
      kind: 'stt',
      files: [
        LocalModelFile(
          url: 'https://alphacephei.com/vosk/models/vosk-model-small-ru-0.22.zip',
          fileName: 'vosk-model-small-ru-0.22.zip',
        ),
      ],
    ),
  ];

  static LocalModelInfo? byId(String id) {
    for (final m in catalog) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Прогресс загрузки: id модели → 0..1. Отсутствие ключа — не качается.
  final ValueNotifier<Map<String, double>> progress =
      ValueNotifier<Map<String, double>>({});

  final ValueNotifier<Map<String, String>> errors =
      ValueNotifier<Map<String, String>>({});

  String _dir = '';
  final Map<String, bool> _cancels = {};

  Future<String> dir() async {
    if (_dir.isEmpty) {
      final base = await getApplicationSupportDirectory();
      _dir = '${base.path}/models';
      await Directory(_dir).create(recursive: true);
    }
    return _dir;
  }

  Future<String> pathFor(String fileName) async =>
      '${await dir()}/$fileName';

  Future<bool> isDownloaded(LocalModelInfo model) async {
    final d = await dir();
    for (final f in model.files) {
      final file = File('$d/${f.fileName}');
      if (!await file.exists()) return false;
      // 4 КБ почти наверняка означает битую/недокачанную загрузку.
      if (await file.length() < 4096) return false;
    }
    return true;
  }

  Future<bool> anyDownloaded() async {
    for (final m in catalog) {
      if (await isDownloaded(m)) return true;
    }
    return false;
  }

  Future<void> download(LocalModelInfo model) async {
    if (model.kind == 'stt') {
      // Vosk: zip качаем сами (прогресс), распаковывает нативная часть.
      await _downloadFile(model, model.files.first);
      return;
    }
    for (final f in model.files) {
      await _downloadFile(model, f);
    }
  }

  Future<void> _downloadFile(LocalModelInfo model, LocalModelFile f) async {
    final target = await pathFor(f.fileName);
    final tmp = '$target.part';
    _cancels[model.id] = false;
    final p = Map<String, double>.of(progress.value);
    p[model.id] = 0.0;
    progress.value = p;
    final errs = Map<String, String>.of(errors.value)..remove(model.id);
    errors.value = errs;
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(f.url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode} для ${f.fileName}');
      }
      final total = res.contentLength > 0
          ? res.contentLength.toDouble()
          : 0.0;
      var done = 0.0;
      final sink = File(tmp).openWrite();
      try {
        await for (final chunk in res) {
          if (_cancels[model.id] ?? false) {
            throw const HttpException('cancelled');
          }
          sink.add(chunk);
          done += chunk.length;
          final cur = Map<String, double>.of(progress.value);
          cur[model.id] = total > 0 ? done / total : done / (1024 * 1024) / 100;
          progress.value = cur;
        }
      } finally {
        await sink.close();
        client.close();
      }
      final downloaded = File(tmp);
      if (await downloaded.length() < 4096) {
        throw const HttpException('Файл скачался пустым');
      }
      await downloaded.rename(target);
      final cur = Map<String, double>.of(progress.value);
      cur[model.id] = 1.0;
      progress.value = cur;
    } catch (e) {
      final f2 = File(tmp);
      if (await f2.exists()) await f2.delete();
      final cur = Map<String, double>.of(progress.value)..remove(model.id);
      progress.value = cur;
      if ('$e'.contains('cancelled')) {
        return;
      }
      final errs = Map<String, String>.of(errors.value)
        ..[model.id] = '$e';
      errors.value = errs;
      rethrow;
    } finally {
      _cancels.remove(model.id);
    }
  }

  void cancelDownload(String id) => _cancels[id] = true;

  Future<void> delete(LocalModelInfo model) async {
    final d = await dir();
    for (final f in model.files) {
      final file = File('$d/${f.fileName}');
      if (await file.exists()) await file.delete();
      final part = File('$d/${f.fileName}.part');
      if (await part.exists()) await part.delete();
    }
    if (model.kind == 'stt') {
      // распакованная папка модели
      for (final f in model.files) {
        final name = f.fileName.replaceAll('.zip', '');
        final dir = Directory('$d/$name');
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    }
  }

  // ── Настройки-флаги ────────────────────────────────────────────────────

  Future<bool> _getFlag(String key, {bool def = false}) async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(key) ?? def;
  }

  Future<void> _setFlag(String key, bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(key, v);
  }

  Future<bool> get localModeEnabled async =>
      _getFlag('local_ai_mode');
  Future<void> setLocalModeEnabled(bool v) => _setFlag('local_ai_mode', v);

  Future<bool> get localSttEnabled async =>
      _getFlag('local_stt_mode');
  Future<void> setLocalSttEnabled(bool v) => _setFlag('local_stt_mode', v);

  Future<bool> get visionModeEnabled async =>
      _getFlag('local_vision_mode');
  Future<void> setVisionModeEnabled(bool v) => _setFlag('local_vision_mode', v);

  /// Детект настроения по фронтальной камере (по умолчанию включён).
  Future<bool> get moodCamEnabled async =>
      _getFlag('mood_cam_enabled', def: true);
  Future<void> setMoodCamEnabled(bool v) => _setFlag('mood_cam_enabled', v);
}
