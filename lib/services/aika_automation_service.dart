import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screen_reader_service.dart';
import 'app_launcher_service.dart';

/// Умная автоматизация — управляет экраном, обучается командам,
/// помогает в играх, делает скриншоты, ищет в приложениях.
class AikaAutomationService {
  static const _reader = MethodChannel('com.aika.assistant/screen_reader');

  static const _learnKey = 'aika_learned_commands_v2';
  static Map<String, String> _learnedCommands = {};

  static Timer? _gameWatchTimer;
  static void Function(String)? _onGameAlert;

  // ════════════════════════════════════════════════
  // САМООБУЧЕНИЕ
  // ════════════════════════════════════════════════

  static Future<void> loadLearned() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_learnKey);
    if (raw != null) {
      try {
        _learnedCommands = Map<String, String>.from(jsonDecode(raw));
      } catch (_) {}
    }
  }

  static Future<void> learn(String phrase, String action) async {
    _learnedCommands[phrase.toLowerCase().trim()] = action;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_learnKey, jsonEncode(_learnedCommands));
  }

  static String? recall(String text) {
    final t = text.toLowerCase().trim();
    for (final entry in _learnedCommands.entries) {
      if (t.contains(entry.key)) return entry.value;
    }
    return null;
  }

  // ════════════════════════════════════════════════
  // ДЕТЕКТОР
  // ════════════════════════════════════════════════

  static bool isAutomationCommand(String text) {
    final t = text.toLowerCase();
    return t.contains('введи в поиске') ||
        t.contains('найди в поиске') ||
        t.contains('поищи в') ||
        t.contains('введи в поиск') ||
        t.contains('скриншот') ||
        t.contains('сделай скрин') ||
        t.contains('сделай фото') ||
        t.contains('сфотографируй') ||
        t.contains('заблокируй телефон') ||
        t.contains('заблокируй экран') ||
        t.contains('выключи телефон') ||
        t.contains('выключи экран') ||
        t.contains('следи за') ||
        t.contains('наблюдай за') ||
        t.contains('стоп слежка') ||
        t.contains('прекрати следить') ||
        t.contains('стоп мониторинг') ||
        t.contains('запомни команду') ||
        t.contains('когда я говорю') ||
        (t.contains('открой') && t.contains('выйди'));
  }

  // ════════════════════════════════════════════════
  // ГЛАВНЫЙ ОБРАБОТЧИК
  // ════════════════════════════════════════════════

  static Future<String> execute(
    String text, {
    void Function(String)? onGameAlert,
  }) async {
    final t = text.toLowerCase().trim();
    _onGameAlert = onGameAlert;

    // Выученные команды
    final learned = recall(t);
    if (learned != null) return _executeLearnedAction(learned);

    // Самообучение
    if (t.contains('запомни команду') || t.contains('когда я говорю')) {
      return _handleLearnCommand(text);
    }

    // Скриншот
    if (t.contains('скриншот') || t.contains('сделай скрин')) {
      return await _takeScreenshot();
    }

    // Фото
    if (t.contains('сделай фото') || t.contains('сфотографируй')) {
      return await _takePhoto();
    }

    // Блокировка
    if (t.contains('заблокируй') || t.contains('выключи экран')) {
      return await _lockScreen();
    }

    // Выключение
    if (t.contains('выключи телефон')) {
      return await _powerMenu();
    }

    // Поиск в приложении: "введи в поиске Наруто"
    if (t.contains('введи в поиске') ||
        t.contains('найди в поиске') ||
        t.contains('поищи в')) {
      final idx = _firstIndex(t, ['введи в поиске', 'найди в поиске', 'поищи в']);
      if (idx >= 0) {
        final after = text.substring(idx);
        final spaceIdx = after.indexOf(' ');
        if (spaceIdx >= 0) {
          final query = after.substring(spaceIdx).trim();
          // Убираем "поиске " / "поиске" из начала если осталось
          final cleanQuery = query
              .replaceFirst(RegExp(r'^поиске?\s+', caseSensitive: false), '')
              .replaceFirst(RegExp(r'^в\s+', caseSensitive: false), '')
              .trim();
          return await _searchInCurrentApp(cleanQuery.isNotEmpty ? cleanQuery : query);
        }
      }
    }

    // Открыть приложение с выходом
    if (t.contains('открой') && t.contains('выйди')) {
      final appName = _extractAfter(text, ['открой', 'запусти'])
          .replaceAll(RegExp(r'\s+и\s+выйди.*', caseSensitive: false), '')
          .trim();
      if (appName.isNotEmpty) return await _openAppWithExit(appName);
    }

    // Игровой мониторинг
    if (t.contains('следи за') || t.contains('наблюдай за')) {
      final instr = _extractAfter(text, ['следи за', 'наблюдай за']).trim();
      return _startGameWatch(instr.isNotEmpty ? instr : 'экраном');
    }

    if (t.contains('стоп слежка') ||
        t.contains('прекрати следить') ||
        t.contains('стоп мониторинг')) {
      return _stopGameWatch();
    }

    return 'Не поняла команду. Попробуй ещё раз.';
  }

  // ════════════════════════════════════════════════
  // РЕАЛИЗАЦИИ
  // ════════════════════════════════════════════════

  static Future<String> _searchInCurrentApp(String query) async {
    try {
      await ScreenReaderService.clickElement('search');
      await Future.delayed(const Duration(milliseconds: 600));
      bool typed = await ScreenReaderService.typeText(query);
      if (!typed) {
        await ScreenReaderService.tapAt(540, 120);
        await Future.delayed(const Duration(milliseconds: 400));
        await ScreenReaderService.typeText(query);
      }
      await Future.delayed(const Duration(milliseconds: 500));
      await ScreenReaderService.pressEnter();
      return 'Ищу "$query" 🔍';
    } catch (e) {
      return 'Не смогла выполнить поиск';
    }
  }

  static Future<String> _openAppWithExit(String appName) async {
    await ScreenReaderService.pressHome();
    await Future.delayed(const Duration(milliseconds: 500));
    final result = await AppLauncherService.tryLaunch(appName);
    return result ?? 'Открываю $appName 📱';
  }

  static Future<String> _takeScreenshot() async {
    try {
      // GLOBAL_ACTION_TAKE_SCREENSHOT = 9
      await _reader.invokeMethod('performGlobalAction', {'action': 9});
      return 'Скриншот сделан 📸';
    } catch (_) {
      return 'Для скриншота нужен Android 9+';
    }
  }

  static Future<String> _takePhoto() async {
    try {
      await AppLauncherService.tryLaunch('камера');
      return 'Открываю камеру 📷';
    } catch (_) {
      return 'Не смогла открыть камеру';
    }
  }

  static Future<String> _lockScreen() async {
    try {
      // GLOBAL_ACTION_LOCK_SCREEN = 8
      await _reader.invokeMethod('performGlobalAction', {'action': 8});
      return 'Экран заблокирован 🔒';
    } catch (_) {
      return 'Не могу заблокировать — нужна Accessibility с DeviceAdmin';
    }
  }

  static Future<String> _powerMenu() async {
    try {
      // GLOBAL_ACTION_POWER_DIALOG = 12
      await _reader.invokeMethod('performGlobalAction', {'action': 12});
      return 'Открыла меню питания 🔌';
    } catch (_) {
      return 'Не могу открыть меню питания';
    }
  }

  // ════════════════════════════════════════════════
  // ИГРОВОЙ МОНИТОРИНГ
  // ════════════════════════════════════════════════

  static String _startGameWatch(String instruction) {
    _gameWatchTimer?.cancel();
    _gameWatchTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await _checkGameScreen(instruction);
    });
    return 'Слежу за "$instruction" 👁 Скажу если что-то важное';
  }

  static String _stopGameWatch() {
    _gameWatchTimer?.cancel();
    _gameWatchTimer = null;
    return 'Слежка остановлена ✓';
  }

  static Future<void> _checkGameScreen(String instruction) async {
    try {
      final screenText = await ScreenReaderService.getScreenText();
      if (screenText == null || screenText.isEmpty) return;

      final instr = instruction.toLowerCase();
      bool alert = false;
      String msg = '';

      if (instr.contains('враг') || instr.contains('красн') || instr.contains('danger')) {
        if (screenText.toLowerCase().contains('enemy') ||
            screenText.toLowerCase().contains('danger') ||
            screenText.toLowerCase().contains('alert')) {
          alert = true;
          msg = '⚠️ Вижу угрозу на экране! Осторожно';
        }
      }

      if (instr.contains('жизн') || instr.contains('hp') || instr.contains('здоровь')) {
        final hpMatch = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(screenText);
        if (hpMatch != null) {
          final cur = int.tryParse(hpMatch.group(1) ?? '') ?? 100;
          final max = int.tryParse(hpMatch.group(2) ?? '') ?? 100;
          if (max > 0 && cur / max < 0.3) {
            alert = true;
            msg = '❤️ Мало жизней! $cur/$max — будь осторожен!';
          }
        }
      }

      if (alert && _onGameAlert != null) {
        _onGameAlert!(msg);
      }
    } catch (_) {}
  }

  // ════════════════════════════════════════════════
  // САМООБУЧЕНИЕ
  // ════════════════════════════════════════════════

  static String _handleLearnCommand(String text) {
    // Ищем: "когда я говорю X делай Y"
    final words = text.toLowerCase().split('когда я говорю');
    if (words.length >= 2) {
      final rest = words[1].trim();
      final actions = ['делай', 'выполняй', 'открывай', 'запускай'];
      for (final a in actions) {
        if (rest.contains(a)) {
          final parts = rest.split(a);
          if (parts.length >= 2) {
            final phrase = parts[0].trim().replaceAll(RegExp(r'["\'']'), '');
            final action = parts[1].trim();
            if (phrase.isNotEmpty && action.isNotEmpty) {
              learn(phrase, action);
              return 'Запомнила! Когда скажешь "$phrase" — буду делать "$action" ✓';
            }
          }
        }
      }
    }
    return 'Скажи так: "когда я говорю [фраза] делай [действие]"';
  }

  static Future<String> _executeLearnedAction(String action) async {
    final a = action.toLowerCase();
    if (a.contains('открой') || a.contains('запусти')) {
      return await _openAppWithExit(action);
    }
    if (a.contains('скриншот')) return await _takeScreenshot();
    if (a.contains('заблокируй')) return await _lockScreen();
    return 'Выполняю: $action';
  }

  // ════════════════════════════════════════════════
  // УТИЛИТЫ
  // ════════════════════════════════════════════════

  static int _firstIndex(String text, List<String> keywords) {
    for (final k in keywords) {
      final idx = text.indexOf(k);
      if (idx >= 0) return idx + k.length;
    }
    return -1;
  }

  static String _extractAfter(String text, List<String> keywords) {
    final t = text.toLowerCase();
    for (final k in keywords) {
      final idx = t.indexOf(k);
      if (idx >= 0) return text.substring(idx + k.length);
    }
    return '';
  }

  static bool get isWatching => _gameWatchTimer != null;
}
