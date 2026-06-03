import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_service.dart';

/// Центральный сервис управления UI через AccessibilityService.
class AikaUiControlService {
  // Правильные каналы из MainActivity.kt
  static const _reader = MethodChannel('com.aika.assistant/screen_reader');
  static const _launcher = MethodChannel('com.aika.assistant/launcher');
  static const _messenger = MethodChannel('com.aika.assistant/messenger');
  static const _screen = MethodChannel('com.aika.assistant/screen');

  // ─────────────────────────────────────────────────────────────
  // ПРИЛОЖЕНИЯ
  // ─────────────────────────────────────────────────────────────

  /// Выйти из текущего приложения (HOME) и открыть новое по пакету или имени.
  static Future<String> openAppAndExit(String appNameOrPkg) async {
    try {
      await _reader.invokeMethod('pressHome');
      await Future.delayed(const Duration(milliseconds: 500));

      // Пробуем точный пакет
      bool? result = await _launcher.invokeMethod<bool>('launchApp', {'package': appNameOrPkg});
      if (result == true) return 'Открываю $appNameOrPkg 📱';

      // Fuzzy поиск по имени
      result = await _launcher.invokeMethod<bool>('findAndLaunch', {'name': appNameOrPkg});
      return result == true
          ? 'Нашла и открываю "$appNameOrPkg" 📱'
          : 'Не нашла приложение: "$appNameOrPkg"';
    } catch (e) {
      return 'Ошибка открытия: $e';
    }
  }

  /// Открыть приложение по имени (без выхода из текущего).
  static Future<String> launchApp(String appNameOrPkg) async {
    try {
      bool? r = await _launcher.invokeMethod<bool>('launchApp', {'package': appNameOrPkg});
      if (r == true) return 'Открываю $appNameOrPkg 📱';
      r = await _launcher.invokeMethod<bool>('findAndLaunch', {'name': appNameOrPkg});
      return r == true ? 'Открываю "$appNameOrPkg" 📱' : 'Приложение не найдено: "$appNameOrPkg"';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  /// Получить список установленных приложений.
  static Future<List<Map<String, String>>> getInstalledApps() async {
    try {
      final raw = await _launcher.invokeMethod<List>('getInstalledApps');
      return raw?.map((e) => Map<String, String>.from(e as Map)).toList() ?? [];
    } catch (_) {
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ВВОД И НАЖАТИЯ
  // ─────────────────────────────────────────────────────────────

  /// Ввести текст в строку поиска.
  static Future<String> typeInSearch(String text) async {
    try {
      await _reader.invokeMethod('typeInSearch', {'text': text});
      return 'Ввела в поиск: "$text" 🔍';
    } catch (e) {
      return 'Ошибка ввода: $e';
    }
  }

  /// Нажать на элемент по тексту.
  static Future<String> clickText(String text) async {
    try {
      final r = await _reader.invokeMethod<bool>('clickElement', {'text': text});
      return r == true ? 'Нажала на "$text" 👆' : 'Не нашла "$text" на экране';
    } catch (e) {
      return 'Ошибка нажатия: $e';
    }
  }

  /// Нажать по точным координатам.
  static Future<void> tapAt(double x, double y) async {
    try { await _reader.invokeMethod('tapAt', {'x': x, 'y': y}); } catch (_) {}
  }

  /// Свайп.
  static Future<void> swipe(double x1, double y1, double x2, double y2, {int durationMs = 300}) async {
    try {
      await _reader.invokeMethod('swipe', {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'duration': durationMs});
    } catch (_) {}
  }

  /// Ввести текст в активное поле.
  static Future<String> typeText(String text) async {
    try {
      final r = await _reader.invokeMethod<bool>('typeInField', {'text': text});
      return r == true ? 'Ввела: "$text" ✍️' : 'Не смогла ввести текст';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  /// Нажать Enter/Отправить.
  static Future<void> pressEnter() async {
    try { await _reader.invokeMethod('pressEnter'); } catch (_) {}
  }

  /// Нажать назад.
  static Future<void> pressBack() async {
    try { await _reader.invokeMethod('pressBack'); } catch (_) {}
  }

  /// Нажать HOME.
  static Future<void> pressHome() async {
    try { await _reader.invokeMethod('pressHome'); } catch (_) {}
  }

  /// Скролл вниз/вверх.
  static Future<void> scroll(String direction) async {
    try { await _reader.invokeMethod('scroll', {'direction': direction}); } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  // СООБЩЕНИЯ
  // ─────────────────────────────────────────────────────────────

  /// Написать сообщение контакту через Accessibility.
  static Future<String> sendMessageToContact({
    required String app,
    required String contact,
    required String message,
  }) async {
    try {
      final r = await _messenger.invokeMethod('sendMessage', {
        'app': app,
        'contact': contact,
        'message': message,
      });
      return r?.toString() ?? 'Отправляю "$message" для $contact...';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  // ─────────────────────────────────────────────────────────────
  // СИСТЕМНЫЕ ДЕЙСТВИЯ
  // ─────────────────────────────────────────────────────────────

  /// Заблокировать экран.
  static Future<String> lockScreen() async {
    try {
      await _reader.invokeMethod('lockScreen');
      return 'Экран заблокирован 🔒';
    } catch (e) {
      return 'Ошибка блокировки: $e';
    }
  }

  /// Скриншот (сохраняется в галерею через Accessibility).
  static Future<String> takeScreenshot() async {
    try {
      await _reader.invokeMethod('takeScreenshot');
      return 'Скриншот сделан 📸';
    } catch (e) {
      return 'Ошибка скриншота: $e';
    }
  }

  /// Открыть камеру.
  static Future<String> takePhoto() async {
    try {
      final r = await _launcher.invokeMethod<bool>('launchCamera');
      return r == true ? 'Открываю камеру 📷' : 'Не смогла открыть камеру';
    } catch (e) {
      return 'Ошибка камеры: $e';
    }
  }

  /// Читать весь текст с экрана.
  static Future<String> readScreen() async {
    try {
      final r = await _reader.invokeMethod<String>('getScreenText');
      return r ?? '';
    } catch (e) {
      return '';
    }
  }

  /// Открыть Power Dialog (выключение).
  static Future<void> powerDialog() async {
    try { await _reader.invokeMethod('powerDialog'); } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  // ИГРОВАЯ СЛЕЖКА ЗА ЭКРАНОМ
  // ─────────────────────────────────────────────────────────────

  static Timer? _watchTimer;
  static String _watchInstruction = '';
  static Function(String)? _onAlert;

  /// Начать слежку за экраном.
  /// Пример: "следи за миникартой, если красные точки — скажи"
  static Future<String> startScreenWatch({
    required String instruction,
    required Function(String) onAlert,
    int intervalSeconds = 4,
  }) async {
    _watchInstruction = instruction;
    _onAlert = onAlert;
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) async {
      await _doWatchTick();
    });
    return 'Слежу 👁 Инструкция: "$instruction"';
  }

  static Future<void> _doWatchTick() async {
    try {
      // Читаем текст экрана
      final screenText = await readScreen();
      if (screenText.isEmpty) return;

      final ai = AiService();
      final prompt =
          'Ты игровой ассистент Айка. '
          'Текст с экрана пользователя:\n$screenText\n\n'
          'Инструкция: "$_watchInstruction". '
          'Если нашла что-то важное — напиши КОРОТКО (1-2 предложения). '
          'Если ничего важного — ответь только "OK".';

      final resp = await ai.sendMessage(prompt);
      if (resp.trim() != 'OK' && resp.trim().isNotEmpty) {
        _onAlert?.call(resp);
      }
    } catch (_) {}
  }

  /// Остановить слежку.
  static String stopScreenWatch() {
    _watchTimer?.cancel();
    _watchTimer = null;
    return 'Слежку остановила 👁‍🗨';
  }

  static bool get isWatching => _watchTimer != null;

  // ─────────────────────────────────────────────────────────────
  // САМООБУЧЕНИЕ
  // ─────────────────────────────────────────────────────────────

  /// Записать действие в историю самообучения.
  static Future<void> recordAction(String action, String context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList('self_learn_actions') ?? [];
      existing.add(json.encode({
        'ts': DateTime.now().toIso8601String(),
        'action': action,
        'context': context,
      }));
      if (existing.length > 200) existing.removeRange(0, existing.length - 200);
      await prefs.setStringList('self_learn_actions', existing);
    } catch (_) {}
  }

  /// Получить историю для контекста AI (последние 20 действий).
  static Future<String> getLearningContext() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final actions = prefs.getStringList('self_learn_actions') ?? [];
      if (actions.isEmpty) return '';
      final recent = actions.length > 20 ? actions.sublist(actions.length - 20) : actions;
      return 'История действий:\n' + recent.map((e) {
        final m = json.decode(e) as Map;
        return '\${m['action']}: \${m['context']}';
      }).join('\n');
    } catch (_) {
      return '';
    }
  }
}
