import 'dart:io';

import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import '../services/local_llm_service.dart';
import '../services/local_model_manager.dart';
import '../services/local_stt_service.dart';

/// Экран «Локальные модели (Pro)»: скачивание моделей с прогрессом,
/// загрузка движка llama.cpp, переключатели локального режима.
class LocalModelsScreen extends StatefulWidget {
  const LocalModelsScreen({super.key});

  @override
  State<LocalModelsScreen> createState() => _LocalModelsScreenState();
}

class _LocalModelsScreenState extends State<LocalModelsScreen> {
  final mgr = LocalModelManager.instance;
  final engine = LocalLlmService.instance;
  final vosk = LocalSttService.instance;

  Map<String, bool> downloaded = {};
  bool localMode = false;
  bool localStt = false;
  bool visionMode = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    engine.addListener(_refresh);
    mgr.progress.addListener(_refresh);
    mgr.errors.addListener(_refresh);
  }

  @override
  void dispose() {
    engine.removeListener(_refresh);
    mgr.progress.removeListener(_refresh);
    mgr.errors.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final d = <String, bool>{};
    for (final m in LocalModelManager.catalog) {
      d[m.id] = await mgr.isDownloaded(m);
    }
    if (!mounted) return;
    setState(() {
      downloaded = d;
      localMode = _localModeOn;
      localStt = _localSttOn;
      visionMode = _visionOn;
    });
  }

  bool _localModeOn = false;
  bool _localSttOn = false;
  bool _visionOn = false;

  Future<void> _loadFlags() async {
    _localModeOn = await mgr.localModeEnabled;
    _localSttOn = await mgr.localSttEnabled;
    _visionOn = await mgr.visionModeEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧠 Локальные модели (Pro)'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _engineCard(),
          const SizedBox(height: 12),
          ...LocalModelManager.catalog.map(_modelCard),
          const SizedBox(height: 12),
          _settingsCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _engineCard() {
    return Card(
      color: Colors.blue.shade900.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.memory, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    engine.isReady
                        ? 'Движок: ${engine.loadedModelName}'
                        : engine.isLoading
                            ? 'Загрузка модели…'
                            : 'Движок не загружен',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            if (engine.isLoading ||
                (engine.status.isNotEmpty && engine.status != ''))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  engine.status,
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            if (engine.isReady)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  engine.supportsVision
                      ? 'Зрение: включено (видит фото)'
                      : 'Зрение: нет (только текст)',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: engine.isLoading ? null : _loadEngine,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Загрузить'),
                ),
                const SizedBox(width: 8),
                if (engine.isReady)
                  ElevatedButton.icon(
                    onPressed: () => engine.unload(),
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Выгрузить'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadEngine() async {
    final ok = await loadEngineFromManager();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Сначала скачай модель Qwen3'),
        backgroundColor: Colors.orange,
      ));
    }
  }

  Widget _modelCard(LocalModelInfo model) {
    final prog = mgr.progress.value[model.id];
    final err = mgr.errors.value[model.id];
    final isDownloading = prog != null && prog < 1.0;
    final done = downloaded[model.id] ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(model.icon,
                    style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(model.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                        model.description,
                        style: TextStyle(
                            fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (isDownloading) ...[
              LinearProgressIndicator(value: prog),
              const SizedBox(height: 6),
              Text('${(prog * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12)),
            ] else if (err != null)
              Text('Ошибка: $err',
                  style: TextStyle(fontSize: 12, color: Colors.redAccent)),
            Row(
              children: [
                if (!done)
                  ElevatedButton.icon(
                    onPressed: isDownloading
                        ? null
                        : () async {
                            await _loadFlags();
                            setState(() => localMode = localMode);
                            try {
                              await mgr.download(model);
                            } catch (_) {}
                            await _refresh();
                          },
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Скачать'),
                  )
                else
                  Chip(
                    label: const Text('Скачано ✓'),
                    backgroundColor: Colors.green.withOpacity(0.3),
                    labelStyle: const TextStyle(color: Colors.greenAccent),
                    side: BorderSide(color: Colors.green.withOpacity(0.5)),
                  ),
                const SizedBox(width: 8),
                if (done)
                  TextButton.icon(
                    onPressed: () async {
                      await mgr.delete(model);
                      if (model.kind == 'stt') {
                        await vosk.dispose();
                      }
                      await _refresh();
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Удалить'),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent),
                  ),
                if (isDownloading)
                  TextButton.icon(
                    onPressed: () => mgr.cancelDownload(model.id),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Отмена'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsCard() {
    final anyModel = downloaded['qwen3_text'] == true ||
        downloaded['qwen3_vision'] == true;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Локальный режим'),
            subtitle: const Text(
                'Айка думает на устройстве, без интернета. '
                'Если движок не загружен — отвечает через облако.'),
            value: localMode,
            onChanged: anyModel
                ? (v) async {
                    await mgr.setLocalModeEnabled(v);
                    // ФИКС «тумблер не переключается до перезапуска»:
                    // раньше флаг писался только в prefs, а AiService
                    // читал его один раз в main(). Теперь применяем
                    // мгновенно — следующая же фраза уйдёт в локальный
                    // движок (или в облако) без перезапуска приложения.
                    AiService.setLocalMode(v);
                    await _loadFlags();
                    setState(() => localMode = v);
                  }
                : null,
          ),
          SwitchListTile(
            title: const Text('Локальный STT (Vosk)'),
            subtitle: const Text(
                'Распознавание речи оффлайн вместо системного.'),
            value: localStt,
            onChanged: downloaded['vosk_ru'] == true
                ? (v) async {
                    await mgr.setLocalSttEnabled(v);
                    await _loadFlags();
                    setState(() => localStt = v);
                  }
                : null,
          ),
          SwitchListTile(
            title: const Text('Режим «Зрение»'),
            subtitle: const Text(
                'Загружать мультимодальную Qwen3-VL вместо текстовой. '
                'Требует больше оперативной памяти (~3 ГБ).'),
            value: visionMode,
            onChanged: downloaded['qwen3_vision'] == true
                ? (v) async {
                    await mgr.setVisionModeEnabled(v);
                    await _loadFlags();
                    setState(() => visionMode = v);
                    // ФИКС «не переключается до перезапуска»: если движок
                    // уже загружен — сразу меняем текст ↔ зрение на лету.
                    if (engine.isReady) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(v
                            ? 'Переключаю на Qwen3-VL (зрение)…'
                            : 'Переключаю на текстовую модель…'),
                        backgroundColor: Colors.cyan.shade900,
                      ));
                      await loadEngineFromManager();
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
