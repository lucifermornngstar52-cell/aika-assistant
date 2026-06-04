import 'aika_zone_watcher_service.dart';
import 'dart:async';
import 'screen_reader_service.dart';
import 'ai_service.dart';
import 'aika_self_learning_service.dart';

/// Помощник в играх.
/// Читает экран, даёт советы, нажимает кнопки по просьбе.
class AikaGameHelperService {
  static Timer? _watchTimer;
  static String? _currentGame;
  static void Function(String)? _onAlert;

  // ── Детектор ──────────────────────────────────────────────────────
  static bool isGameCommand(String text) {
    final t = text.toLowerCase();
    return t.contains('помоги в игре') ||
        t.contains('помощь в игре') ||
        t.contains('что делать в') ||
        t.contains('как построить') ||
        t.contains('как сделать в') ||
        t.contains('следи за') ||
        t.contains('смотри за') ||
        t.contains('наблюдай') ||
        t.contains('скажи когда') ||
        t.contains('стоп наблюдение') ||
        t.contains('стоп слежка') ||
        t.contains('нажми кнопку') ||
        t.contains('нажми на') && _isInGame() ||
        t.contains('кликни на') && _isInGame();
  }

  static bool _isInGame() => _currentGame != null;

  static void setCurrentGame(String? gameName) {
    _currentGame = gameName;
  }

  // ── Главный обработчик ────────────────────────────────────────────
  static Future<String> execute(String text, {
    required void Function(String) onAlert,
    String? currentApp,
  }) async {
    _onAlert = onAlert;
    final t = text.toLowerCase().trim();

    // Определяем игру из текущего приложения или из команды
    final game = _detectGame(currentApp ?? '') ?? _detectGameFromText(t);

    // ── Советы и помощь через AI ──────────────────────────────────
    if (t.contains('как построить') || t.contains('как сделать') ||
        t.contains('что делать') || t.contains('помоги в игре') ||
        t.contains('помощь в игре')) {
      return await _getGameAdvice(text, game);
    }

    // ── Наблюдение за экраном ─────────────────────────────────────
    if (t.contains('следи за') || t.contains('смотри за') ||
        t.contains('наблюдай') || t.contains('скажи когда')) {
      final instr = _extractWatchInstruction(text);
      return _startWatching(instr, onAlert);
    }

    // ── Стоп наблюдение ───────────────────────────────────────────
    if (t.contains('стоп') && (t.contains('наблюдени') || t.contains('слежк'))) {
      return _stopWatching();
    }

    // ── Нажать кнопку / UI взаимодействие ──────────────────────────
    if (t.contains('нажми на') || t.contains('нажми кнопку') || t.contains('кликни на')) {
      final target = _extractTarget(text, ['нажми на', 'нажми кнопку', 'кликни на']);
      if (target.isNotEmpty) {
        final ok = await ScreenReaderService.clickElement(target);
        return ok
            ? 'Нажала на "$target" ✓'
            : 'Не нашла "$target" на экране 🔍';
      }
    }

    return await _getGameAdvice(text, game);
  }

  // ── Советы через Gemini AI ────────────────────────────────────────
  static Future<String> _getGameAdvice(String question, String? game) async {
    try {
      // Читаем текст с экрана для контекста
      final screenText = await ScreenReaderService.getScreenText();

      final context = StringBuffer();
      if (game != null) context.write('Игра: $game. ');
      if (screenText != null && screenText.isNotEmpty) {
        context.write('На экране: ${screenText.substring(0, screenText.length.clamp(0, 300))}. ');
      }
      context.write(AikaSelfLearningService.buildContextSummary());

      final prompt =
          'Ты игровой помощник Айка. ${context.toString()} '
          'Вопрос игрока: "$question". '
          'Дай короткий конкретный совет на русском (1-3 предложения). '
          'Если это Майнкрафт — давай конкретные рецепты или шаги постройки.';

      final ai = AiService();
      final resp = await ai.sendMessage(prompt, history: []);
      return '🎮 $resp';
    } catch (e) {
      return 'Не смогла получить совет: $e';
    }
  }

  // ── Наблюдение за экраном ─────────────────────────────────────────
  static String _startWatching(String instruction, void Function(String) onAlert) {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await _analyzeScreen(instruction);
    });
    return 'Наблюдаю за "$instruction" 👁 Скажу если что-то важное!';
  }

  static String _stopWatching() {
    _watchTimer?.cancel();
    _watchTimer = null;
    return 'Остановила наблюдение ✓';
  }

  static Future<void> _analyzeScreen(String instruction) async {
    try {
      final screenText = await ScreenReaderService.getScreenText();
      if (screenText == null || screenText.isEmpty) return;
      final t = instruction.toLowerCase();
      final s = screenText.toLowerCase();

      // Конкретные паттерны по инструкции
      bool alert = false;
      String msg = '';

      if (t.contains('враг') || t.contains('противник') || t.contains('enemy')) {
        if (s.contains('enemy') || s.contains('danger') || s.contains('alert') || s.contains('!')) {
          alert = true; msg = '⚠️ Враги рядом! Будь осторожен!';
        }
      }
      if (t.contains('жизн') || t.contains('hp') || t.contains('здоровь')) {
        // Ищем паттерн HP: XX/XX
        final m = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(screenText);
        if (m != null) {
          final cur = int.tryParse(m.group(1) ?? '') ?? 100;
          final max = int.tryParse(m.group(2) ?? '') ?? 100;
          if (max > 0 && cur / max < 0.25) {
            alert = true; msg = '❤️ Мало жизней ($cur/$max)! Лечись!';
          }
        }
      }
      if (t.contains('ресурс') || t.contains('материал') || t.contains('дерево') || t.contains('камень')) {
        if (s.contains('low') || s.contains('мало') || s.contains('0 ')) {
          alert = true; msg = '📦 Ресурсы на исходе!';
        }
      }
      if (t.contains('миникарт') || t.contains('карт')) {
        if (s.contains('red') || s.contains('enemy') || s.contains('danger')) {
          alert = true; msg = '🗺️ На карте активность! Смотри!';
        }
      }

      if (alert && _onAlert != null) _onAlert!(msg);
    } catch (_) {}
  }

  // ── Определение игры ──────────────────────────────────────────────
  static String? _detectGame(String pkg) {
    final p = pkg.toLowerCase();
    if (p.contains('minecraft') || p.contains('mojang')) return 'Minecraft';
    if (p.contains('roblox')) return 'Roblox';
    if (p.contains('pubg') || p.contains('battlegrounds')) return 'PUBG';
    if (p.contains('genshin')) return 'Genshin Impact';
    if (p.contains('clash')) return 'Clash';
    if (p.contains('brawl')) return 'Brawl Stars';
    return null;
  }

  static String? _detectGameFromText(String text) {
    if (text.contains('майнкрафт') || text.contains('minecraft')) return 'Minecraft';
    if (text.contains('пабг') || text.contains('pubg')) return 'PUBG';
    if (text.contains('геншин') || text.contains('genshin')) return 'Genshin Impact';
    if (text.contains('роблокс') || text.contains('roblox')) return 'Roblox';
    if (text.contains('бравл') || text.contains('brawl')) return 'Brawl Stars';
    return null;
  }

  static String _extractWatchInstruction(String text) {
    for (final kw in ['следи за', 'смотри за', 'наблюдай за', 'скажи когда']) {
      final t = text.toLowerCase();
      final idx = t.indexOf(kw);
      if (idx >= 0) return text.substring(idx + kw.length).trim();
    }
    return 'экраном';
  }

  static String _extractTarget(String text, List<String> keywords) {
    final t = text.toLowerCase();
    for (final k in keywords) {
      final idx = t.indexOf(k);
      if (idx >= 0) return text.substring(idx + k.length).trim();
    }
    return '';
  }

  static bool get isWatching => _watchTimer != null;
  static String? get currentGame => _currentGame;
}
