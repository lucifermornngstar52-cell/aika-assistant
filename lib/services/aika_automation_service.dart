import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screen_reader_service.dart';
import 'app_launcher_service.dart';

/// Умная автоматизация — управляет экраном, обучается командам,
/// помогает в играх, делает скриншоты, ищет в приложениях.
class AikaAutomationService {
  static const _reader  = MethodChannel('com.aika.assistant/screen_reader');
  static const _phone   = MethodChannel('aika/phone_control');
  static const _camera  = MethodChannel('com.aika.assistant/camera');

  static const _learnKey = 'aika_learned_commands_v2';
  static Map<String, String> _learnedCommands = {}; // фраза → действие

  static Timer? _gameWatchTimer;
  static String? _gameWatchInstruction; // "следи за минискартой"
  static void Function(String)? _onGameAlert;

  // ═══════════════════════════════════════════════════════
  // САМООБУЧЕНИЕ
  // ═══════════════════════════════════════════════════════

  static Future<void> loadLearned() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_learnKey);
    if (raw != null) {
      try { _learnedCommands = Map<String, String>.from(jsonDecode(raw)); }
      catch (_) {}
    }
  }

  /// Запомнить новую команду
  static Future<void> learn(String phrase, String action) async {
    _learnedCommands[phrase.toLowerCase().trim()] = action;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_learnKey, jsonEncode(_learnedCommands));
  }

  /// Проверить — знает ли уже эту команду
  static String? recall(String text) {
    final t = text.toLowerCase().trim();
    for (final entry in _learnedCommands.entries) {
      if (t.contains(entry.key)) return entry.value;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════
  // ДЕТЕКТОР КОМАНДЫ
  // ═══════════════════════════════════════════════════════

  static bool isAutomationCommand(String text) {
    final t = text.toLowerCase();
    return
      // Поиск в приложении
      t.contains('введи в поиске') || t.contains('найди в поиске') ||
      t.contains('поищи в') || t.contains('введи в поиск') ||
      // Скриншот
      t.contains('скриншот') || t.contains('сделай скрин') || t.contains('screenshot') ||
      // Фото
      t.contains('сделай фото') || t.contains('сфотографируй') || t.contains('снимок') ||
      // Блокировка / выключение
      t.contains('заблокируй телефон') || t.contains('заблокируй экран') ||
      t.contains('выключи телефон') || t.contains('выключи экран') ||
      t.contains('lock screen') ||
      // Игровой мониторинг
      t.contains('следи за') || t.contains('мониторь') || t.contains('наблюдай за') ||
      t.contains('стоп слежка') || t.contains('прекрати следить') ||
      // Открытие с выходом
      (t.contains('открой') && (t.contains('выйди') || t.contains('выйти') || t.contains('сначала'))) ||
      // Написать контакту — умный поиск
      t.contains('найди контакт') || t.contains('напиши контакту') ||
      // Самообучение
      t.contains('запомни команду') || t.contains('научись') || t.contains('когда я говорю');
  }

  // ═══════════════════════════════════════════════════════
  // ГЛАВНЫЙ ОБРАБОТЧИК
  // ═══════════════════════════════════════════════════════

  static Future<String> execute(String text,
      {void Function(String)? onGameAlert}) async {
    final t = text.toLowerCase().trim();

    // Проверяем выученные команды
    final learned = recall(t);
    if (learned != null) {
      return await _executeLearnedAction(learned);
    }

    // ── Самообучение ───────────────────────────────────────────────
    if (t.contains('запомни команду') || t.contains('когда я говорю')) {
      return _handleLearnCommand(text);
    }

    // ── Скриншот ───────────────────────────────────────────────────
    if (t.contains('скриншот') || t.contains('сделай скрин') || t.contains('screenshot')) {
      return await _takeScreenshot();
    }

    // ── Фото ───────────────────────────────────────────────────────
    if (t.contains('сделай фото') || t.contains('сфотографируй') || t.contains('снимок')) {
      return await _takePhoto();
    }

    // ── Блокировка экрана ──────────────────────────────────────────
    if (t.contains('заблокируй') || t.contains('lock screen') || t.contains('выключи экран')) {
      return await _lockScreen();
    }

    // ── Выключить телефон ──────────────────────────────────────────
    if (t.contains('выключи телефон') || t.contains('shutdown') || t.contains('перезагрузи')) {
      return await _powerMenu();
    }

    // ── Поиск в текущем приложении ────────────────────────────────
    // "введи в поиске Наруто" / "найди в поиске атака титанов"
    final searchMatch = RegExp(
      r'(?:введи в поиске|найди в поиске|поищи)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (searchMatch != null) {
      final query = searchMatch.group(1)?.trim() ?? '';
      return await _searchInCurrentApp(query);
    }

    // ── Открыть приложение с выходом из текущего ──────────────────
    // "открой VK Видео" / "открой ютуб и выйди отсюда"
    final openMatch = RegExp(
      r'(?:открой|запусти|перейди в)\s+(.+?)(?:\s+(?:и\s+)?(?:выйди|сначала выйди|выйти))?\$',
      caseSensitive: false,
    ).firstMatch(text);
    if (openMatch != null) {
      final appName = openMatch.group(1)?.trim() ?? '';
      return await _openAppWithExit(appName);
    }

    // ── Игровой мониторинг ────────────────────────────────────────
    if (t.contains('следи за') || t.contains('наблюдай за') || t.contains('мониторь')) {
      final instrMatch = RegExp(r'(?:следи за|наблюдай за|мониторь)\s+(.+)', caseSensitive: false)
          .firstMatch(text);
      final instr = instrMatch?.group(1)?.trim() ?? 'экраном';
      _onGameAlert = onGameAlert;
      return _startGameWatch(instr);
    }

    if (t.contains('стоп слежка') || t.contains('прекрати следить') || t.contains('стоп мониторинг')) {
      return _stopGameWatch();
    }

    return 'Не поняла команду. Попробуй ещё раз.';
  }

  // ═══════════════════════════════════════════════════════
  // РЕАЛИЗАЦИИ
  // ═══════════════════════════════════════════════════════

  /// Поиск в текущем открытом приложении
  static Future<String> _searchInCurrentApp(String query) async {
    try {
      // 1. Ищем кнопку поиска (лупа / иконка)
      final clickedSearch = await ScreenReaderService.clickElement('search')
        || await ScreenReaderService.clickElement('поиск')
        || await ScreenReaderService.clickElement('Search');

      await Future.delayed(const Duration(milliseconds: 700));

      // 2. Вводим текст
      final typed = await ScreenReaderService.typeText(query);
      if (!typed) {
        // Fallback: ищем поле EditText и вводим
        await ScreenReaderService.tapAt(540, 120); // верх экрана — обычно там поиск
        await Future.delayed(const Duration(milliseconds: 400));
        await ScreenReaderService.typeText(query);
      }

      // 3. Нажимаем Enter
      await Future.delayed(const Duration(milliseconds: 500));
      await ScreenReaderService.pressEnter();

      return 'Ищу "$query" 🔍';
    } catch (e) {
      return 'Не смогла выполнить поиск: $e';
    }
  }

  /// Открыть приложение, предварительно выйдя из текущего (Home → запуск)
  static Future<String> _openAppWithExit(String appName) async {
    try {
      // Сначала идём на главный экран
      await ScreenReaderService.pressHome();
      await Future.delayed(const Duration(milliseconds: 500));
      // Затем запускаем нужное приложение
      final result = await AppLauncherService.tryLaunch(appName);
      return result ?? 'Открываю $appName 📱';
    } catch (e) {
      return 'Ошибка при открытии: $e';
    }
  }

  /// Скриншот через Accessibility (нет root — используем системный диалог)
  static Future<String> _takeScreenshot() async {
    try {
      await _reader.invokeMethod('takeScreenshot');
      return 'Скриншот сделан 📸';
    } catch (_) {
      // Fallback: комбинация клавиш через Accessibility
      try {
        await _reader.invokeMethod('performGlobalAction', {'action': 9}); // GLOBAL_ACTION_TAKE_SCREENSHOT
        return 'Скриншот сделан 📸';
      } catch (e) {
        return 'Нужен Android 9+ для скриншота через Accessibility';
      }
    }
  }

  /// Фото через камеру
  static Future<String> _takePhoto() async {
    try {
      await _camera.invokeMethod('takePhoto');
      return 'Фото сделано 📷';
    } catch (_) {
      // Открываем камеру как fallback
      await AppLauncherService.tryLaunch('открой камеру');
      return 'Открываю камеру 📷';
    }
  }

  /// Заблокировать экран
  static Future<String> _lockScreen() async {
    try {
      await _reader.invokeMethod('lockScreen');
      return 'Экран заблокирован 🔒';
    } catch (e) {
      return 'Не могу заблокировать: нужна Accessibility с правами DeviceAdmin';
    }
  }

  /// Меню питания (выключение)
  static Future<String> _powerMenu() async {
    try {
      await _reader.invokeMethod('performGlobalAction', {'action': 12}); // GLOBAL_ACTION_POWER_DIALOG
      return 'Открыла меню питания 🔌';
    } catch (e) {
      return 'Не могу открыть меню питания';
    }
  }

  // ═══════════════════════════════════════════════════════
  // ИГРОВОЙ МОНИТОРИНГ
  // ═══════════════════════════════════════════════════════

  /// Начать следить за экраном в игре
  static String _startGameWatch(String instruction) {
    _gameWatchInstruction = instruction;
    _gameWatchTimer?.cancel();

    // Читаем экран каждые 3 секунды
    _gameWatchTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _checkGameScreen(instruction);
    });

    return 'Слежу за "$instruction" 👁️ Сообщу если что-то важное';
  }

  static String _stopGameWatch() {
    _gameWatchTimer?.cancel();
    _gameWatchTimer = null;
    _gameWatchInstruction = null;
    return 'Слежка остановлена ✓';
  }

  static Future<void> _checkGameScreen(String instruction) async {
    try {
      final screenText = await ScreenReaderService.getScreenText();
      if (screenText == null || screenText.isEmpty) return;

      final instr = instruction.toLowerCase();

      // Паттерны для распространённых игровых событий
      bool shouldAlert = false;
      String alertMsg = '';

      if (instr.contains('миникарт') || instr.contains('враг') || instr.contains('красн')) {
        // Ищем текстовые признаки врагов (зависит от игры)
        if (screenText.toLowerCase().contains('enemy') ||
            screenText.toLowerCase().contains('danger') ||
            screenText.toLowerCase().contains('alert')) {
          shouldAlert = true;
          alertMsg = '⚠️ Вижу активность на экране! Будь осторожен';
        }
      }

      if (instr.contains('жизн') || instr.contains('hp') || instr.contains('здоровь')) {
        final hpMatch = RegExp(r'(\d+)\s*[/\\]\s*(\d+)').firstMatch(screenText);
        if (hpMatch != null) {
          final cur = int.tryParse(hpMatch.group(1) ?? '') ?? 100;
          final max = int.tryParse(hpMatch.group(2) ?? '') ?? 100;
          if (max > 0 && cur / max < 0.3) {
            shouldAlert = true;
            alertMsg = '❤️ Мало жизней! $cur/$max — осторожнее!';
          }
        }
      }

      if (instr.contains('уровень') || instr.contains('level up')) {
        if (screenText.toLowerCase().contains('level up') ||
            screenText.toLowerCase().contains('уровень')) {
          shouldAlert = true;
          alertMsg = '🎉 Новый уровень!';
        }
      }

      if (shouldAlert && _onGameAlert != null) {
        _onGameAlert!(alertMsg);
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════
  // САМООБУЧЕНИЕ
  // ═══════════════════════════════════════════════════════

  static String _handleLearnCommand(String text) {
    // "запомни команду: когда я говорю X делай Y"
    final m = RegExp(
      r'(?:запомни|научись).+?когда я говорю\s+(.+?)\s+(?:делай|выполняй|открывай)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(text);

    if (m != null) {
      final phrase = m.group(1)?.trim() ?? '';
      final action = m.group(2)?.trim() ?? '';
      if (phrase.isNotEmpty && action.isNotEmpty) {
        learn(phrase, action);
        return 'Запомнила! Когда скажешь "$phrase" — буду делать "$action" ✓';
      }
    }

    return 'Скажи так: "запомни команду: когда я говорю [фраза] делай [действие]"';
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

  static bool get isWatching => _gameWatchTimer != null;
  static String? get watchInstruction => _gameWatchInstruction;
}
