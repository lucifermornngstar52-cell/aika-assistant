import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Центральный лог Айки.
///
/// Каждая функция пишет сюда свои шаги — и всё видно в приложении
/// на экране «Логи». Заодно перехватывает debugPrint, поэтому все
/// старые debugPrint-сообщения тоже попадают в просмотрщик.
class AikaLogService {
  AikaLogService._();
  static final AikaLogService instance = AikaLogService._();

  /// Максимум строк в памяти (ринг-буфер).
  static const _maxMemory = 1500;
  /// Максимум строк, хранящихся в файле.
  static const _maxFile = 4000;

  final _entries = <LogEntry>[];
  final _listeners = <void Function(List<LogEntry>)>{};

  bool _paused = false;
  bool get paused => _paused;
  set paused(bool v) => _paused = v;

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void addListener(void Function(List<LogEntry>) l) => _listeners.add(l);
  void removeListener(void Function(List<LogEntry>) l) => _listeners.remove(l);

  void _notify() {
    if (_paused) return;
    _notifyListeners(List.unmodifiable(_entries));
  }

  void _notifyListeners(List<LogEntry> snapshot) {
    for (final l in _listeners.toList()) {
      try {
        l(snapshot);
      } catch (_) {}
    }
  }

  /// Главная функция: пишем лог.
  static void log(String tag, String message, {LogLevel level = LogLevel.info}) {
    instance._add(LogEntry(
      time: DateTime.now(),
      tag: tag,
      message: message,
      level: level,
    ));
  }

  static void error(String tag, Object error, [StackTrace? st]) {
    instance._add(LogEntry(
      time: DateTime.now(),
      tag: tag,
      message: '$error${st != null ? '\n$st' : ''}',
      level: LogLevel.error,
    ));
  }

  static void debug(String tag, String message) =>
      log(tag, message, level: LogLevel.debug);

  void _add(LogEntry e) {
    _entries.add(e);
    if (_entries.length > _maxMemory) {
      _entries.removeRange(0, _entries.length - _maxMemory);
    }
    _notify();
    _appendToFile(e);
  }

  void clear() {
    _entries.clear();
    _notifyListeners([]);
    _writeFile(const []);
  }

  // ── Файл ───────────────────────────────────────────────────────────

  File? _file;
  Future<File> _logFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    return _file = File('${dir.path}/aika_log.txt');
  }

  Future<void> _appendToFile(LogEntry e) async {
    try {
      final f = await _logFile();
      final line = '${e.fileLine}\n';
      final size = await f.length();
      if (size > 400 * 1024) {
        // ротация: держим хвост
        final lines = await f.readAsLines();
        await f.writeAsString(lines
            .skip(lines.length - _maxFile ~/ 2)
            .join('\n'));
      }
      await f.writeAsString(line, mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> _writeFile(List<LogEntry> list) async {
    try {
      final f = await _logFile();
      await f.writeAsString(list.map((e) => e.fileLine).join('\n'));
    } catch (_) {}
  }

  /// Полный экспорт в файл — возвращает путь.
  Future<String> export() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/aika_log_export.txt');
    await f.writeAsString(
      'Aika log — экспорт ${DateTime.now()}\n'
      'Всего строк: ${_entries.length}\n\n'
      + _entries.map((e) => e.fileLine).join('\n'),
    );
    return f.path;
  }

  /// Нативный logcat (Kotlin) — последние [lines] строк.
  static Future<String> getLogcat({int lines = 800}) async {
    try {
      const ch = MethodChannel('com.aika.assistant/screen_reader');
      final res = await ch.invokeMethod('getLogcat', {'lines': lines});
      return res as String? ?? '(пусто)';
    } catch (e) {
      return 'Не удалось прочитать logcat: $e';
    }
  }
}

enum LogLevel { debug, info, warn, error }

class LogEntry {
  final DateTime time;
  final String tag;
  final String message;
  final LogLevel level;
  const LogEntry({
    required this.time,
    required this.tag,
    required this.message,
    required this.level,
  });

  String get levelStr => switch (level) {
        LogLevel.debug => 'DBG',
        LogLevel.info => 'INF',
        LogLevel.warn => 'WRN',
        LogLevel.error => 'ERR',
      };

  String get fileLine =>
      '${time.toIso8601String()} [$levelStr] [$tag] ${message.replaceAll('\n', ' ⏎ ')}';
}
