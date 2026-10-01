import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/logs_screen.dart';
import '../services/aika_log_service.dart';
import '../theme/app_theme.dart';

/// Плавающая кнопка логов: маленький пузырь поверх интерфейса.
/// Тап — мини-окно с последними строками лога + «Скопировать».
/// Можно перетаскивать за кнопку, чтобы не мешала.
class FloatingLogsButton extends StatefulWidget {
  const FloatingLogsButton({super.key});

  @override
  State<FloatingLogsButton> createState() => _FloatingLogsButtonState();
}

class _FloatingLogsButtonState extends State<FloatingLogsButton> {
  Offset _offset = const Offset(12, 120);
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // держим кнопку внутри экрана
    final dx = _offset.dx.clamp(0.0, size.width - 56);
    final dy = _offset.dy.clamp(0.0, size.height - 220);

    return Positioned(
      right: dx,
      top: dy,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _dragging = true),
        onPanEnd: (_) => setState(() => _dragging = false),
        onPanUpdate: (d) => setState(() {
          _offset = Offset(
            (_offset.dx - d.delta.dx).clamp(0.0, size.width - 56),
            (_offset.dy + d.delta.dy).clamp(0.0, size.height - 220),
          );
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AikaTheme.surface.withOpacity(_dragging ? 0.95 : 0.75),
            border: Border.all(color: AikaTheme.accent.withOpacity(0.7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: _showLogsWindow,
            icon: const Icon(Icons.terminal, size: 22, color: AikaTheme.accent),
          ),
        ),
      ),
    );
  }

  void _showLogsWindow() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AikaTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      isScrollControlled: true,
      builder: (_) => const _LogsMiniWindow(),
    );
  }
}

/// Мини-окно с логами: читаем, копируем, открываем полный экран.
class _LogsMiniWindow extends StatefulWidget {
  const _LogsMiniWindow();

  @override
  State<_LogsMiniWindow> createState() => _LogsMiniWindowState();
}

class _LogsMiniWindowState extends State<_LogsMiniWindow> {
  List<LogEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _entries = AikaLogService.instance.entries;
    AikaLogService.instance.addListener(_onLog);
  }

  @override
  void dispose() {
    AikaLogService.instance.removeListener(_onLog);
    super.dispose();
  }

  void _onLog(List<LogEntry> e) {
    if (mounted) setState(() => _entries = e);
  }

  String get _allText {
    // последние 300 строк — в буфер копирования
    final tail = _entries.length > 300 ? _entries.sublist(_entries.length - 300) : _entries;
    return tail.map((e) => e.fileLine).join('\n');
  }

  Future<void> _copy() async {
    final text = _allText;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Логи скопированы — вставляй в чат'),
        backgroundColor: AikaTheme.surface,
        duration: Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tail = _entries.length > 150 ? _entries.sublist(_entries.length - 150) : _entries;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (c, scrollController) => Column(
        children: [
          // ── Шапка ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 18, color: AikaTheme.accent),
                const SizedBox(width: 8),
                Text(
                  '📜 Логи (${_entries.length})',
                  style: const TextStyle(
                    color: AikaTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.content_copy, size: 20),
                  tooltip: 'Скопировать',
                  color: AikaTheme.accent,
                  onPressed: _copy,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Очистить',
                  color: AikaTheme.textSecondary,
                  onPressed: () {
                    AikaLogService.instance.clear();
                    setState(() => _entries = []);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.open_in_full, size: 18),
                  tooltip: 'Полный экран',
                  color: AikaTheme.textSecondary,
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LogsScreen()),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: AikaTheme.textSecondary,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // ── Лог ──
          Expanded(
            child: tail.isEmpty
                ? Center(
                    child: Text(
                      'Лог пуст — поговори с Айкой',
                      style: TextStyle(color: AikaTheme.textSecondary, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: tail.length,
                    itemBuilder: (c, i) {
                      final e = tail[i];
                      final color = switch (e.level) {
                        LogLevel.error => Colors.red.shade300,
                        LogLevel.warn => Colors.orange.shade300,
                        LogLevel.info => AikaTheme.textPrimary,
                        LogLevel.debug => AikaTheme.textSecondary,
                      };
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: SelectableText(
                          '${e.time.hour.toString().padLeft(2, '0')}:'
                          '${e.time.minute.toString().padLeft(2, '0')}:'
                          '${e.time.second.toString().padLeft(2, '0')} '
                          '[${e.tag}] ${e.message}',
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // ── Кнопка «Скопировать» внизу, крупная ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.content_copy, size: 18),
                  label: const Text('Скопировать последние 300 строк'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AikaTheme.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
