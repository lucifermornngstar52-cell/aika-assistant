import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/aika_log_service.dart';
import '../theme/app_theme.dart';

/// Просмотр логов всего приложения.
/// Вкладка «Приложение» — живой лог всех функций Айки,
/// вкладка «Logcat» — нативные логи (Kotlin, Android).
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();

  List<LogEntry> _entries = [];
  bool _autoScroll = true;
  LogLevel? _levelFilter;
  String _logcat = '';
  bool _logcatLoading = false;

  @override
  void initState() {
    super.initState();
    _entries = AikaLogService.instance.entries;
    AikaLogService.instance.addListener(_onLog);
    _tabs.addListener(() {
      if (_tabs.index == 1 && _logcat.isEmpty) _loadLogcat();
    });
  }

  void _onLog(List<LogEntry> entries) {
    if (!mounted) return;
    setState(() => _entries = entries);
    if (_autoScroll && _scroll.hasClients) {
      scheduleMicrotask(() {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    AikaLogService.instance.removeListener(_onLog);
    _tabs.dispose();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadLogcat() async {
    setState(() => _logcatLoading = true);
    final text = await AikaLogService.getLogcat(lines: 1000);
    if (mounted) setState(() { _logcat = text; _logcatLoading = false; });
  }

  List<LogEntry> get _filtered {
    final q = _searchCtrl.text.toLowerCase();
    return _entries
        .where((e) =>
            (_levelFilter == null || e.level == _levelFilter) &&
            (q.isEmpty ||
                e.message.toLowerCase().contains(q) ||
                e.tag.toLowerCase().contains(q)))
        .toList();
  }

  Future<void> _export() async {
    final path = await AikaLogService.instance.export();
    await Clipboard.setData(ClipboardData(text: path));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Лог сохранён: $path (путь скопирован)'),
        backgroundColor: AikaTheme.surface,
      ));
    }
  }

  Color _levelColor(LogLevel l) => switch (l) {
        LogLevel.debug => AikaTheme.textSecondary,
        LogLevel.info => AikaTheme.accent,
        LogLevel.warn => Colors.orange.shade300,
        LogLevel.error => Colors.red.shade300,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: AikaTheme.surface,
        title: const Text('📜 Логи приложения'),
        actions: [
          IconButton(
            icon: Icon(_autoScroll ? Icons.arrow_downward : Icons.pause,
                size: 20),
            tooltip: _autoScroll ? 'Автоскролл вкл' : 'Автоскролл выкл',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined, size: 20),
            tooltip: 'Экспорт в файл',
            onPressed: _export,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Очистить',
            onPressed: () {
              AikaLogService.instance.clear();
              setState(() => _entries = []);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AikaTheme.accent,
          labelColor: AikaTheme.textPrimary,
          unselectedLabelColor: AikaTheme.textSecondary,
          tabs: const [
            Tab(text: 'Приложение'),
            Tab(text: 'Logcat'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Поиск + фильтры ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                        color: AikaTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Поиск по логам…',
                      hintStyle: TextStyle(
                          color: AikaTheme.textSecondary, fontSize: 13),
                      filled: true,
                      fillColor: AikaTheme.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                for (final l in LogLevel.values)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ChoiceChip(
                      label: Text(l.name.toUpperCase(),
                          style: TextStyle(
                              fontSize: 10,
                              color: _levelFilter == l
                                  ? Colors.black
                                  : AikaTheme.textPrimary)),
                      selected: _levelFilter == l,
                      selectedColor: AikaTheme.accent,
                      backgroundColor: AikaTheme.surface,
                      onSelected: (_) => setState(() =>
                          _levelFilter = _levelFilter == l ? null : l),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                // ── Вкладка 1: лог приложения ──
                _filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Лог пуст — поговори с Айкой и возвращайся',
                          style: TextStyle(
                              color: AikaTheme.textSecondary, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _filtered.length,
                        itemBuilder: (c, i) {
                          final e = _filtered[i];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text:
                                      '${e.time.hour.toString().padLeft(2, '0')}:'
                                      '${e.time.minute.toString().padLeft(2, '0')}:'
                                      '${e.time.second.toString().padLeft(2, '0')} ',
                                  style: TextStyle(
                                      color: AikaTheme.textSecondary,
                                      fontSize: 10.5,
                                      fontFamily: 'monospace'),
                                ),
                                TextSpan(
                                  text: '${e.levelStr} ',
                                  style: TextStyle(
                                      color: _levelColor(e.level),
                                      fontSize: 10.5,
                                      fontFamily: 'monospace'),
                                ),
                                TextSpan(
                                  text: '[${e.tag}] ',
                                  style: TextStyle(
                                      color: AikaTheme.accent,
                                      fontSize: 10.5,
                                      fontFamily: 'monospace'),
                                ),
                                TextSpan(
                                  text: e.message,
                                  style: TextStyle(
                                      color: _levelColor(e.level),
                                      fontSize: 10.5,
                                      fontFamily: 'monospace'),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),

                // ── Вкладка 2: logcat ──
                _logcatLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AikaTheme.accent),
                      )
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                Text(
                                  'Последние строки системного лога',
                                  style: TextStyle(
                                      color: AikaTheme.textSecondary,
                                      fontSize: 12),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: _loadLogcat,
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Обновить',
                                      style: TextStyle(fontSize: 12)),
                                  style: TextButton.styleFrom(
                                      foregroundColor: AikaTheme.accent),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Container(
                              color: Colors.black,
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  _logcat.isEmpty ? '(пусто)' : _logcat,
                                  style: const TextStyle(
                                    color: AikaTheme.textPrimary,
                                    fontSize: 10.5,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
