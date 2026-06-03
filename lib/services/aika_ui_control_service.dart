import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_service.dart';

/// Центральный сервис управления UI через AccessibilityService.
/// Все действия идут через MethodChannel → AikaAccessibilityService.kt
class AikaUiControlService {
  static const _ch = MethodChannel('com.aika.assistant/screen');
  static const _launcher = MethodChannel('com.aika.assistant/launcher');
  static const _messenger = MethodChannel('com.aika.assistant/messenger');
  static const _screen = MethodChannel('com.aika.assistant/screen');

  // ─────────────────────────────────────────────────────────────
  // ПРИЛОЖЕНИЯ
  // ─────────────────────────────────────────────────────────────

  /// Выйти из текущего приложения и открыть новое по имени/пакету.
  /// Айка сначала нажимает HOME, затем ищет пакет.
  static Future<String> openAppAndExit(String appNameOrPkg) async {
    try {
      // 1. Нажимаем HOME — выходим из текущего приложения
      await _ch.invokeMethod('pressHome');
      await Future.delayed(const Duration(milliseconds: 400));

      // 2. Открываем нужное приложение
      final result = await _launcher.invokeMethod('launchApp', {'package': appNameOrPkg});
      if (result == true) {
        return 'Открываю $appNameOrPkg 📱';
      } else {
        // Пробуем найти по имени через fuzzy search
        final found = await _launcher.invokeMethod('findAndLaunch', {'name': appNameOrPkg});
        return found == true
            ? 'Нашла и открываю $appNameOrPkg 📱'
            : 'Не нашла приложение: $appNameOrPkg';
      }
    } catch (e) {
      return 'Ошибка открытия: $e';
    }
  }

  /// Ввести текст в строку поиска текущего приложения.
  static Future<String> typeInSearch(String text) async {
    try {
      final result = await _ch.invokeMethod('typeInSearch', {'text': text});
      return result?.toString() ?? 'Ввела в поиск: $text';
    } catch (e) {
      return 'Ошибка ввода: $e';
    }
  }

  /// Нажать на элемент по тексту.
  static Future<String> clickText(String text) async {
    try {
      final result = await _ch.invokeMethod('clickByText', {'text': text});
      return result == true ? 'Нажала на "$text"' : 'Не нашла "$text" на экране';
    } catch (e) {
      return 'Ошибка нажатия: $e';
    }
  }

  /// Ввести текст в активное поле.
  static Future<String> typeText(String text) async {
    try {
      final result = await _ch.invokeMethod('typeText', {'text': text});
      return result == true ? 'Ввела текст ✍️' : 'Не смогла ввести текст';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  /// Нажать кнопку назад.
  static Future<void> pressBack() async {
    try { await _ch.invokeMethod('pressBack'); } catch (_) {}
  }

  /// Нажать HOME.
  static Future<void> pressHome() async {
    try { await _ch.invokeMethod('pressHome'); } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  // СООБЩЕНИЯ
  // ─────────────────────────────────────────────────────────────

  /// Написать сообщение контакту через Accessibility.
  /// app = 'whatsapp'/'telegram'/'vk' и т.д.
  static Future<String> sendMessageToContact({
    required String app,
    required String contact,
    required String message,
  }) async {
    try {
      final result = await _messenger.invokeMethod('sendMessage', {
        'app': app,
        'contact': contact,
        'message': message,
      });
      return result?.toString() ?? 'Отправляю сообщение...';
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
      await _ch.invokeMethod('lockScreen');
      return 'Экран заблокирован 🔒';
    } catch (e) {
      return 'Ошибка блокировки: $e';
    }
  }

  /// Скриншот.
  static Future<String> takeScreenshot() async {
    try {
      final result = await _ch.invokeMethod('takeScreenshot');
      return result?.toString() ?? 'Скриншот сделан 📸';
    } catch (e) {
      return 'Ошибка скриншота: $e';
    }
  }

  /// Открыть камеру и сделать фото.
  static Future<String> takePhoto() async {
    try {
      final result = await _launcher.invokeMethod('launchCamera');
      return result == true ? 'Открываю камеру 📷' : 'Не смогла открыть камеру';
    } catch (e) {
      return 'Ошибка камеры: $e';
    }
  }

  /// Получить весь текст с текущего экрана.
  static Future<String> readScreen() async {
    try {
      final result = await _ch.invokeMethod('getScreenText');
      return result?.toString() ?? '';
    } catch (e) {
      return '';
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ИГРОВАЯ СЛЕЖКА ЗА ЭКРАНОМ
  // ─────────────────────────────────────────────────────────────

  static Timer? _watchTimer;
  static String _watchInstruction = '';
  static Function(String alert)? _onAlert;
  static int _watchIntervalSec = 4;

  /// Начать слежку за экраном по инструкции.
  /// Пример: "следи за миникартой, если красные точки — скажи"
  static Future<String> startScreenWatch({
    required String instruction,
    required Function(String) onAlert,
    int intervalSeconds = 4,
  }) async {
    _watchInstruction = instruction;
    _onAlert = onAlert;
    _watchIntervalSec = intervalSeconds;
    _watchTimer?.cancel();

    _watchTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) async {
      await _doWatchTick();
    });

    return 'Слежу за экраном 👁 Инструкция: "$instruction"';
  }

  static Future<void> _doWatchTick() async {
    try {
      // Делаем скриншот через Accessibility
      final imgData = await _ch.invokeMethod('getScreenshot');
      if (imgData == null) return;

      final String b64 = imgData is String ? imgData : base64Encode(imgData as List<int>);

      // Анализируем через GPT-4o Vision
      final ai = AiService();
      final prompt = 'Ты игровой ассистент Айка. '
          'Смотри на скриншот экрана и выполни инструкцию: "$_watchInstruction". '
          'Если нашла что-то важное — напиши КОРОТКО (1-2 предложения). '
          'Если ничего важного — ответь только словом "OK"';

      final resp = await ai.sendMessage(
        prompt,
        imageBase64: b64,
        imageMimeType: 'image/png',
      );

      if (resp.trim() != 'OK' && resp.trim().isNotEmpty) {
        _onAlert?.call(resp);
      }
    } catch (_) {}
  }

  /// Остановить слежку.
  static String stopScreenWatch() {
    _watchTimer?.cancel();
    _watchTimer = null;
    _watchInstruction = '';
    return 'Слежку остановила 👁‍🗨';
  }

  static bool get isWatching => _watchTimer != null;

  // ─────────────────────────────────────────────────────────────
  // САМООБУЧЕНИЕ — запись паттернов использования
  // ─────────────────────────────────────────────────────────────

  /// Записать действие в историю для самообучения.
  static Future<void> recordAction(String action, String context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'self_learn_actions';
      final existing = prefs.getStringList(key) ?? [];
      final entry = json.encode({
        'ts': DateTime.now().toIso8601String(),
        'action': action,
        'context': context,
      });
      existing.add(entry);
      // Храним последние 200 действий
      if (existing.length > 200) existing.removeRange(0, existing.length - 200);
      await prefs.setStringList(key, existing);
    } catch (_) {}
  }

  /// Получить паттерны использования для контекста AI.
  static Future<String> getLearningContext() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final actions = prefs.getStringList('self_learn_actions') ?? [];
      if (actions.isEmpty) return '';

      // Берём последние 20 действий
      final recent = actions.length > 20
          ? actions.sublist(actions.length - 20)
          : actions;

      final decoded = recent.map((e) {
        final m = json.decode(e) as Map;
        return '${m['action']}: ${m['context']}';
      }).join('
');

      return 'История действий пользователя:
$decoded';
    } catch (_) {
      return '';
    }
  }
}
