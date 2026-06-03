import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис самообучения Айки.
/// Запоминает последние действия, паттерны пользователя,
/// и помогает Айке давать точные реакции на контекст.
class AikaSelfLearningService {
  static const _actionsKey  = 'aika_recent_actions_v1';
  static const _patternsKey = 'aika_user_patterns_v1';
  static const _maxActions  = 50;

  // Последние N действий (app, команда, время)
  static List<Map<String, dynamic>> _recentActions = [];
  // Паттерны: {фраза -> действие, счётчик}
  static Map<String, Map<String, dynamic>> _patterns = {};

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_actionsKey);
      if (raw != null) {
        _recentActions = List<Map<String, dynamic>>.from(
          (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e))
        );
      }
      final rawP = prefs.getString(_patternsKey);
      if (rawP != null) {
        _patterns = Map<String, Map<String, dynamic>>.from(
          (jsonDecode(rawP) as Map).map(
            (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map))
          )
        );
      }
    } catch (_) {}
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_actionsKey, jsonEncode(_recentActions));
    await prefs.setString(_patternsKey, jsonEncode(_patterns));
  }

  // ── Запомнить действие ──────────────────────────────────────────────
  static Future<void> recordAction({
    required String type,     // 'app_open', 'command', 'search', 'message'
    required String value,    // название приложения, текст команды
    String? context,          // доп. контекст (экран, игра)
  }) async {
    _recentActions.insert(0, {
      'type': type,
      'value': value,
      'context': context ?? '',
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    if (_recentActions.length > _maxActions) {
      _recentActions = _recentActions.take(_maxActions).toList();
    }
    await _save();
  }

  // ── Обучение паттерну ───────────────────────────────────────────────
  static Future<void> learnPattern(String phrase, String action) async {
    final key = phrase.toLowerCase().trim();
    _patterns[key] = {
      'action': action,
      'count': ((_patterns[key]?['count'] as int?) ?? 0) + 1,
      'last': DateTime.now().millisecondsSinceEpoch,
    };
    await _save();
  }

  // ── Найти паттерн ───────────────────────────────────────────────────
  static String? findPattern(String text) {
    final t = text.toLowerCase().trim();
    // Точное вхождение
    for (final entry in _patterns.entries) {
      if (t.contains(entry.key)) return entry.value['action'] as String?;
    }
    return null;
  }

  // ── Последние открытые приложения ───────────────────────────────────
  static List<String> recentApps({int limit = 5}) {
    return _recentActions
        .where((a) => a['type'] == 'app_open')
        .map((a) => a['value'] as String)
        .toSet()
        .take(limit)
        .toList();
  }

  // ── Контекстная реакция на открытие приложения ──────────────────────
  /// Возвращает живую реплику Айки при открытии приложения
  static String? appOpenReaction(String packageName, String appLabel) {
    final pkg = packageName.toLowerCase();
    final label = appLabel.toLowerCase();

    // Мессенджеры
    if (pkg.contains('whatsapp') || pkg.contains('whatsapp')) {
      final reactions = [
        'WhatsApp открыт! Не забудь ответить на непрочитанные сообщения 💬',
        'О, ватсап! Кто-то ждёт ответа? 😏',
        'WhatsApp! Смотри не потеряй важное сообщение 📱',
      ];
      return reactions[DateTime.now().second % reactions.length];
    }
    if (pkg.contains('telegram')) {
      return 'Телеграм! Есть новые сообщения? ✈️';
    }
    if (pkg.contains('vkontakte') || pkg.contains('com.vk')) {
      return 'ВКонтакте открыт! Что новенького в ленте? 👀';
    }
    if (pkg.contains('instagram')) {
      return 'Инстаграм! Не зависни надолго 😄';
    }

    // Видео сервисы
    if (pkg.contains('vkvideo') || (pkg.contains('vk') && label.contains('video'))) {
      final q = ['Что сегодня смотрим? 🎬', 'Кино вечер начинается! 🍿', 'Что выбрал для просмотра? 👁'];
      return q[DateTime.now().second % q.length];
    }
    if (pkg.contains('youtube') || pkg.contains('vanced') || pkg.contains('revanced')) {
      final q = ['YouTube! Что сегодня смотрим? 🎬', 'Ютуб открыт! Чилл или учёба? 😄', 'Кино или ролики? 🍿'];
      return q[DateTime.now().second % q.length];
    }
    if (pkg.contains('netflix')) {
      return 'Нетфликс! Хорошего просмотра 🎬🍿';
    }
    if (pkg.contains('twitch')) {
      return 'Твитч! Кто стримит сегодня? 🎮';
    }

    // Игры
    if (pkg.contains('minecraft') || pkg.contains('mojang')) {
      return 'Майнкрафт! Что строим сегодня? 🏗️ Скажи если нужна помощь!';
    }
    if (pkg.contains('roblox')) {
      return 'Роблокс! Удачи в игре 🎮';
    }
    if (pkg.contains('pubg') || pkg.contains('battlegrounds')) {
      return 'PUBG! Слежу за тылами — скажи если нужна помощь 🎯';
    }
    if (pkg.contains('genshin') || pkg.contains('mihoyo') || pkg.contains('hoyoverse')) {
      return 'Геншин! Фарм или сюжет? ⚔️';
      }
    if (pkg.contains('game') || pkg.contains('games')) {
      return 'Игра запущена! Скажи "следи за экраном" если нужна помощь 🎮';
    }

    // Браузеры
    if (pkg.contains('chrome') || pkg.contains('firefox') || pkg.contains('browser') || pkg.contains('opera')) {
      return 'Браузер открыт! Скажи что найти — поищу для тебя 🔍';
    }

    // Музыка
    if (pkg.contains('spotify')) {
      return 'Спотифай! Хорошей музыки 🎵';
    }
    if (pkg.contains('vkmusic') || pkg.contains('zvuk') || pkg.contains('yandex.music')) {
      return 'Музыка! Расслабляемся или работаем? 🎶';
    }

    // Маркетплейсы
    if (pkg.contains('wildberries') || pkg.contains('ozon') || pkg.contains('aliexpress')) {
      return 'Шопинг! Что ищем? 🛍️';
    }

    // Банки
    if (pkg.contains('sberbank') || pkg.contains('tinkoff') || pkg.contains('kaspi') || pkg.contains('alfa')) {
      return 'Банковское приложение 💳';
    }

    // Запоминаем факт открытия
    recordAction(type: 'app_open', value: appLabel);
    return null; // нет специальной реплики — промолчим
  }

  // ── Сводка для AI промпта ────────────────────────────────────────────
  static String buildContextSummary() {
    if (_recentActions.isEmpty) return '';
    final apps = recentApps(limit: 3).join(', ');
    final lastCmd = _recentActions
        .where((a) => a['type'] == 'command')
        .take(3)
        .map((a) => a['value'])
        .join('; ');
    final buf = StringBuffer('[Контекст пользователя: ');
    if (apps.isNotEmpty) buf.write('недавние приложения: $apps. ');
    if (lastCmd.isNotEmpty) buf.write('последние команды: $lastCmd. ');
    buf.write(']');
    return buf.toString();
  }

  static List<Map<String, dynamic>> get recentActions => _recentActions;
  static Map<String, Map<String, dynamic>> get patterns => _patterns;
}
