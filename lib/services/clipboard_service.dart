import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// ClipboardService — читаем и пишем системный буфер обмена.
/// Голосовые команды: "скопируй ...", "что в буфере", "вставь".
/// Адаптировано из openclaw-assistant ClipboardHandler (MIT).
class ClipboardService {
  static final ClipboardService _i = ClipboardService._();
  factory ClipboardService() => _i;
  ClipboardService._();

  static const _channel = MethodChannel('com.aika.assistant/screen_reader');

  // ──────────────── ПУБЛИЧНЫЙ API ────────────────

  /// Читает текущее содержимое буфера обмена
  Future<String?> read() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    } catch (e) {
      debugPrint('[Clipboard] read error: $e');
      return null;
    }
  }

  /// Записывает текст в буфер обмена
  Future<bool> write(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      debugPrint('[Clipboard] written: ${text.length} chars');
      return true;
    } catch (e) {
      debugPrint('[Clipboard] write error: $e');
      return false;
    }
  }

  /// Парсит голосовую команду, возвращает ответ ассистента
  Future<String?> parseCommand(String input) async {
    final t = input.toLowerCase().trim();

    // Читаем буфер
    if (_matches(t, ['что в буфере', 'что в clipboard', 'прочитай буфер',
                      'покажи буфер', 'что скопировано', 'что там в буфере'])) {
      final text = await read();
      if (text == null || text.isEmpty) return 'Буфер обмена пуст.';
      return 'В буфере: $text';
    }

    // Очищаем буфер
    if (_matches(t, ['очисти буфер', 'удали буфер', 'очистить буфер'])) {
      await write('');
      return 'Буфер очищен.';
    }

    // Копируем текст после ключевого слова
    for (final trigger in ['скопируй ', 'скопировать ', 'запиши в буфер ']) {
      if (t.contains(trigger)) {
        final idx = t.indexOf(trigger);
        final toCopy = input.substring(idx + trigger.length).trim();
        if (toCopy.isNotEmpty) {
          await write(toCopy);
          return 'Скопировала: $toCopy';
        }
      }
    }

    return null;
  }

  bool _matches(String text, List<String> triggers) =>
      triggers.any((tr) => text.contains(tr));
}
