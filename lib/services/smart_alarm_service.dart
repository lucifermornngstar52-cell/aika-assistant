import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Умный будильник — будит с погодой, мотивацией, и уникальным сообщением каждый день.
class SmartAlarmService {
  static const _keyAlarms      = 'smart_alarms_v2';
  static const _keyCity        = 'alarm_city';
  static const _owmKey         = '30b398816f9dc8ec92454b67c2172c31';

  static final _rng = Random();
  static Timer? _ticker;
  static final _notif = FlutterLocalNotificationsPlugin();
  static final Set<String> _firedToday = {};

  /// Callback: будильник сработал — передаём текст для озвучки
  static Future<void> Function(String text)? onAlarmFired;

  static Future<void> initialize() async {
    const settings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(const InitializationSettings(android: settings));
    _startTicker();
  }

  static void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _checkAlarms());

    // Сбрасываем _firedToday в полночь
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    Timer(midnight.difference(now), () {
      _firedToday.clear();
      _startTicker();
    });
  }

  static Future<void> _checkAlarms() async {
    final alarms = await getAlarms();
    final now = DateTime.now();
    for (final alarm in alarms) {
      if (!alarm['enabled']) continue;
      final h = alarm['hour'] as int;
      final m = alarm['minute'] as int;
      final id = alarm['id'] as String;
      final firedKey = '$id-${now.year}${now.month}${now.day}';

      if (h == now.hour && m == now.minute && !_firedToday.contains(firedKey)) {
        _firedToday.add(firedKey);
        await _fireSmartAlarm(alarm, now);
      }
    }
  }

  static Future<void> _fireSmartAlarm(Map alarm, DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final personality = prefs.getString('aika_personality') ?? 'miya';
    final city = prefs.getString(_keyCity) ?? '';

    // Получаем погоду параллельно с генерацией сообщения
    String weatherPart = '';
    try {
      final resolvedCity = city.isNotEmpty ? city : await _cityByIp();
      final url = 'https://api.openweathermap.org/data/2.5/weather'
          '?q=${Uri.encodeComponent(resolvedCity)}&appid=$_owmKey&units=metric&lang=ru';
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final temp = (data['main']?['temp'] as num?)?.round() ?? 0;
        final desc = (data['weather'] as List?)?.first['description'] ?? '';
        final feelsLike = (data['main']?['feels_like'] as num?)?.round() ?? temp;
        weatherPart = _buildWeatherAdvice(temp, feelsLike, desc);
      }
    } catch (_) {}

    // Главное пробудительное сообщение
    final wakePart = _getWakeMessage(personality, now.hour, now.weekday);

    // Мотивация дня
    final motivePart = _getDailyMotivation(now.weekday);

    // Метка будильника
    final label = (alarm['label'] as String?) ?? '';
    final labelPart = label.isNotEmpty ? '\n📌 $label' : '';

    // Собираем финальное сообщение
    final parts = <String>[wakePart];
    if (weatherPart.isNotEmpty) parts.add(weatherPart);
    parts.add(motivePart);
    final fullMsg = parts.join('\n\n') + labelPart;

    // Уведомление
    await _notif.show(
      alarm['id'].hashCode,
      '⏰ Доброе утро! Айка здесь',
      fullMsg.length > 200 ? '${fullMsg.substring(0, 197)}...' : fullMsg,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'aika_smart_alarm', 'Умный будильник',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          playSound: true,
        ),
      ),
    );

    // Озвучиваем
    onAlarmFired?.call(fullMsg);
  }

  static String _buildWeatherAdvice(int temp, int feelsLike, String desc) {
    String advice = '';
    if (temp <= 0) {
      advice = 'Сегодня мороз — оденься потеплее! 🧥';
    } else if (temp <= 10) {
      advice = 'Прохладно — куртка пригодится 🧤';
    } else if (temp <= 18) {
      advice = 'Свежо, лёгкая кофта не помешает 😊';
    } else if (temp <= 26) {
      advice = 'Отличная погода! Можно идти налегке ☀️';
    } else {
      advice = 'Жарко! Не забудь воду 💧';
    }

    if (desc.contains('дожд') || desc.contains('ливен')) {
      advice += ' Возьми зонт ☂️';
    } else if (desc.contains('снег')) {
      advice += ' Осторожно — снег на дороге ❄️';
    }

    return '🌤 Погода: $temp°C, $desc. $advice';
  }

  static String _getWakeMessage(String personality, int hour, int weekday) {
    final isWeekend = weekday >= 6;
    switch (personality) {
      case 'tsundere':
        return isWeekend
            ? ['Вставай уже! Я... я не из-за тебя разбудила, просто так! 😤',
               'Ладно, просыпайся. И не думай что мне не всё равно! 🙄'][_rng.nextInt(2)]
            : ['Подъём! Не смей опять засыпать! 😠',
               'Эй! Вставай!! Я два раза повторять не буду! 💢'][_rng.nextInt(2)];
      case 'cold':
        return 'Время пробуждения. Рекомендую встать немедленно.';
      case 'gabimaru':
        return ['Подъём, боец! Слабых здесь нет! ⚔️',
               'Утро — время тренировки! Вставай! 🔥'][_rng.nextInt(2)];
      case 'sensei':
        return ['Доброе утро. Новый день — новая мудрость 🌅',
               'Пробуждение — малое рождение. Встречай день с благодарностью 🌸'][_rng.nextInt(2)];
      default:
        return isWeekend
            ? ['Доброе утро~! Я скучала! ☀️✨',
               'Хэй, соня! Просыпайся, я жду~ 🌸',
               'Доброе утро! Выходной — давай проведём его весело! 💕'][_rng.nextInt(3)]
            : ['Доброе утро! Вставай, я уже скучаю~ 💕',
               'Хэй-хэй! Новый день! Я здесь~ 🌺',
               'Просыпайся! Сегодня будет отличный день, обещаю! ✨'][_rng.nextInt(3)];
    }
  }

  static String _getDailyMotivation(int weekday) {
    switch (weekday) {
      case 1: return '📅 Понедельник — старт новой недели. Заряжайся энергией!';
      case 2: return '💡 Вторник — хороший день для сложных задач. Мозг в форме!';
      case 3: return '⚡ Среда — середина пути. Держи темп!';
      case 4: return '🚀 Четверг — финишная прямая! Ещё немного!';
      case 5: return '🎉 Пятница! Почти выходные — давай дожмём!';
      case 6: return '😎 Суббота — твой день. Делай что любишь!';
      case 7: return '🌿 Воскресенье — перезагрузка. Отдыхай и набирайся сил!';
      default: return '✨ Каждый день — новый шанс!';
    }
  }

  static Future<String> _cityByIp() async {
    try {
      final resp = await http
          .get(Uri.parse('http://ip-api.com/json/?fields=city'))
          .timeout(const Duration(seconds: 5));
      return jsonDecode(resp.body)['city'] ?? 'Almaty';
    } catch (_) { return 'Almaty'; }
  }

  // ── CRUD ────────────────────────────────────────────────────────

  static Future<List<Map>> getAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyAlarms) ?? [];
    return raw.map<Map>((s) => jsonDecode(s) as Map).toList();
  }

  static Future<Map> addAlarm(int hour, int minute, {String label = '', List<int> days = const []}) async {
    final alarm = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'hour': hour,
      'minute': minute,
      'label': label,
      'enabled': true,
      'days': days, // 1-7, пусто = каждый день
    };
    final prefs = await SharedPreferences.getInstance();
    final list = await getAlarms();
    list.add(alarm);
    await prefs.setStringList(_keyAlarms, list.map((a) => jsonEncode(a)).toList());
    return alarm;
  }

  static Future<void> toggleAlarm(String id, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAlarms();
    final idx = list.indexWhere((a) => a['id'] == id);
    if (idx >= 0) {
      list[idx] = {...list[idx], 'enabled': enabled};
      await prefs.setStringList(_keyAlarms, list.map((a) => jsonEncode(a)).toList());
    }
  }

  static Future<void> deleteAlarm(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAlarms();
    list.removeWhere((a) => a['id'] == id);
    await prefs.setStringList(_keyAlarms, list.map((a) => jsonEncode(a)).toList());
  }

  static Future<void> deleteAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAlarms);
  }

  // ── Voice parsing ────────────────────────────────────────────────

  static Future<String?> tryParseCommand(String text) async {
    final t = text.toLowerCase();
    if (!(t.contains('будильник') || t.contains('разбуди') || t.contains('подними') || t.contains('буди'))) {
      return null;
    }

    if (t.contains('удали') || t.contains('убери') || t.contains('отмени все')) {
      await deleteAll();
      return 'Все умные будильники удалены! 🗑';
    }

    if (t.contains('список') || t.contains('покажи') || t.contains('какие')) {
      final alarms = await getAlarms();
      if (alarms.isEmpty) return 'Умных будильников нет. Скажи "поставь умный будильник на 7:30"';
      final buf = StringBuffer('⏰ Умные будильники:\n');
      for (final a in alarms) {
        final h = (a['hour'] as int).toString().padLeft(2, '0');
        final m = (a['minute'] as int).toString().padLeft(2, '0');
        final on = a['enabled'] ? '✅' : '❌';
        final lbl = (a['label'] as String).isNotEmpty ? ' — ${a['label']}' : '';
        buf.writeln('$on $h:$m$lbl');
      }
      buf.writeln('\n(С погодой и мотивацией каждый день!)');
      return buf.toString().trim();
    }

    final time = _parseTime(t);
    if (time == null) return 'Не понял время. Например: "поставь умный будильник на 7:30"';

    final label = _extractLabel(t);
    final alarm = await addAlarm(time[0], time[1], label: label);
    final hStr = time[0].toString().padLeft(2, '0');
    final mStr = time[1].toString().padLeft(2, '0');

    final now = DateTime.now();
    final fireAt = DateTime(now.year, now.month, now.day, time[0], time[1]);
    final diff = fireAt.isAfter(now) ? fireAt.difference(now) : fireAt.add(const Duration(days: 1)).difference(now);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final leftStr = h > 0 ? 'через $h ч $m мин' : 'через $m мин';

    return '⏰ Умный будильник на $hStr:$mStr поставлен!\n\n'
        'Разбужу $leftStr — скажу погоду, мотивацию и доброе утро 🌅';
  }

  static List<int>? _parseTime(String t) {
    final re = RegExp(r'(\d{1,2})[:\.](\d{2})');
    final m = re.firstMatch(t);
    if (m != null) {
      final h = int.parse(m.group(1)!);
      final min = int.parse(m.group(2)!);
      if (h < 24 && min < 60) return [h, min];
    }
    final re2 = RegExp(r'(?:в|на)\s+(\d{1,2})(?:\s*(утра|утром|вечера|вечером|ночи|дня))?');
    final m2 = re2.firstMatch(t);
    if (m2 != null) {
      int h = int.parse(m2.group(1)!);
      final period = m2.group(2) ?? '';
      if ((period.contains('вечер') || period.contains('ночи') || period.contains('дня')) && h < 12) h += 12;
      if (h < 24) return [h, 0];
    }
    return null;
  }

  static String _extractLabel(String t) {
    if (t.contains('работ')) return 'Работа';
    if (t.contains('тренировк') || t.contains('спортзал')) return 'Тренировка';
    if (t.contains('встреч')) return 'Встреча';
    if (t.contains('школ') || t.contains('учёб') || t.contains('уроки')) return 'Учёба';
    if (t.contains('врач')) return 'Врач';
    return '';
  }

  static void dispose() => _ticker?.cancel();
}
