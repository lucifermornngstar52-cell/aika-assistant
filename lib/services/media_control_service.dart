import 'package:flutter/services.dart';

/// Управление музыкой и медиа через MediaKey + Spotify DeepLink.
/// Работает с любым плеером на устройстве.
class MediaControlService {
  static const _ch = MethodChannel('com.aika.assistant/media');

  // ── Базовые медиа-команды (работают с любым плеером) ─────────────────

  static Future<void> playPause() async {
    try { await _ch.invokeMethod('playPause'); } catch (_) {}
  }

  static Future<void> next() async {
    try { await _ch.invokeMethod('next'); } catch (_) {}
  }

  static Future<void> prev() async {
    try { await _ch.invokeMethod('prev'); } catch (_) {}
  }

  static Future<void> play() async {
    try { await _ch.invokeMethod('play'); } catch (_) {}
  }

  static Future<void> pause() async {
    try { await _ch.invokeMethod('pause'); } catch (_) {}
  }

  // ── Spotify специфично ───────────────────────────────────────────────

  /// Открыть Spotify и воспроизвести по запросу (артист / трек / плейлист)
  static Future<void> spotifySearch(String query) async {
    try { await _ch.invokeMethod('launchSpotifyAndPlay', {'query': query}); } catch (_) {}
  }

  // ── Парсинг голосовой команды ────────────────────────────────────────

  /// Возвращает ответ если команда распознана, иначе null
  static Future<String?> tryHandleCommand(String text) async {
    final t = text.toLowerCase().trim();

    // Следующий трек
    if (_has(t, ['следующий трек', 'следующая песня', 'дальше', 'next track', 'skip'])) {
      await next();
      return 'Следующий трек ⏭️';
    }

    // Предыдущий
    if (_has(t, ['предыдущий трек', 'предыдущая песня', 'назад', 'prev track'])) {
      await prev();
      return 'Предыдущий трек ⏮️';
    }

    // Пауза
    if (_has(t, ['пауза', 'стоп музыка', 'stop music', 'pause', 'останови музыку', 'выключи музыку'])) {
      await pause();
      return 'Музыка на паузе ⏸️';
    }

    // Плей без уточнения
    if (_has(t, ['включи музыку', 'play music', 'воспроизведи', 'продолжи музыку', 'продолжай'])) {
      await play();
      return 'Играем! 🎵';
    }

    // Spotify с поиском — "включи [трек/артиста] в спотифай"
    final spotifyQuery = _extractSpotifyQuery(t);
    if (spotifyQuery != null) {
      await spotifySearch(spotifyQuery);
      return 'Ищу "$spotifyQuery" в Spotify 🎵';
    }

    // "включи мою музыку" / "включи плейлист"
    if (_has(t, ['включи спотифай', 'открой спотифай', 'запусти спотифай',
                 'включи spotify', 'open spotify'])) {
      await spotifySearch('');
      return 'Открываю Spotify 🎵';
    }

    return null;
  }

  static String? _extractSpotifyQuery(String t) {
    // "включи [артиста] в спотифай" / "поставь [трек] спотифай"
    final patterns = [
      RegExp(r'(?:включи|поставь|запусти|воспроизведи|play)\s+(.+?)\s+(?:в спотифай|в spotify|спотифай|spotify)'),
      RegExp(r'(?:спотифай|spotify)\s+(?:включи|поставь|запусти)\s+(.+)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(t);
      if (m != null) return m.group(1)?.trim();
    }
    return null;
  }

  static bool _has(String text, List<String> words) =>
      words.any((w) => text.contains(w));
}
