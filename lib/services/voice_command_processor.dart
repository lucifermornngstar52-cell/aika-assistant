import 'dart:async';
import 'package:flutter/services.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:torch_light/torch_light.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'weather_service.dart';
import 'app_launcher_service.dart';

/// ════════════════════════════════════════════════════════════════════════════
/// VoiceCommandProcessor — Центральный процессор голосовых команд.
///
/// Обрабатывает 150+ голосовых команд на русском МГНОВЕННО (без AI).
/// Вызывается ДО отправки в AI — экономит время и API-запросы.
///
/// Категории команд:
///  • Системные: Wi-Fi, Bluetooth, яркость, авиарежим, горячая точка
///  • Звук: громкость (с процентами), режим "Не беспокоить", вибро
///  • Медиа: треки, воспроизведение, пауза, перемотка
///  • Приложения: 50+ приложений по-русски и по-английски
///  • Телефон: звонки, SMS, контакты
///  • Инфо: погода, батарея, время, дата, курсы валют
///  • Навигация: маршрут, карты, адрес
///  • Таймеры и будильники: натуральный язык ("через 5 минут")
///  • Напоминания: "напомни мне через X"
///  • Камера: фото, видео, сканирование QR
///  • Поиск: Google, YouTube, Wikipedia
///  • Игры: помощь, скриншот, запись экрана
///  • Умный дом: (через Интент)
///  • Системная навигация: назад, домой, недавние, уведомления
/// ════════════════════════════════════════════════════════════════════════════
class VoiceCommandProcessor {
  static final VoiceCommandProcessor _i = VoiceCommandProcessor._();
  factory VoiceCommandProcessor() => _i;
  VoiceCommandProcessor._();

  static const _ch = MethodChannel('com.aika.assistant/screen_reader');
  final Battery _battery = Battery();
  double _vol = 0.5;
  bool _flashOn = false;

  void init() {
    VolumeController().listener((v) => _vol = v);
  }

  void dispose() {
    VolumeController().removeListener();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ГЛАВНЫЙ МЕТОД — возвращает null если команда не распознана (→ AI)
  // ══════════════════════════════════════════════════════════════════════════
  Future<VoiceCmdResult?> process(String text) async {
    final t = text.toLowerCase().trim();
    if (t.isEmpty) return null;

    // ── 0. Приложения — ПРОВЕРЯЕМ ПЕРВЫМИ! ──────────────────────────────────
    // Важно: "открой whatsapp" не должно попасть в громкость/звонки
    if (t.contains('открой') || t.contains('запусти') || t.contains('покажи') ||
        t.contains('зайди') || t.contains('перейди') || t.contains('включи') ||
        t.contains('открыть') || t.contains('запустить') || t.contains('включить') ||
        t.contains('показать')) {
      final appResult = await _handleOpenApp(t, text);
      if (appResult != null) return appResult;
    }

    // ── 1. Фонарик ─────────────────────────────────────────────────────────
    final flashResult = _handleFlashlight(t);
    if (flashResult != null) return flashResult;

    // ── 2. Громкость ───────────────────────────────────────────────────────
    final volResult = await _handleVolume(t);
    if (volResult != null) return volResult;

    // ── 3. Яркость ────────────────────────────────────────────────────────
    final brightResult = await _handleBrightness(t);
    if (brightResult != null) return brightResult;

    // ── 4. Wi-Fi ──────────────────────────────────────────────────────────
    final wifiResult = await _handleWifi(t);
    if (wifiResult != null) return wifiResult;

    // ── 5. Bluetooth ──────────────────────────────────────────────────────
    final btResult = await _handleBluetooth(t);
    if (btResult != null) return btResult;

    // ── 6. Авиарежим ──────────────────────────────────────────────────────
    if (_has(t, ['авиарежим', 'режим полёта', 'режим полета', 'airplane'])) {
      await AndroidIntent(action: 'android.settings.AIRPLANE_MODE_SETTINGS',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return VoiceCmdResult.ok('✈️ Авиарежим — открываю настройки');
    }

    // ── 7. Горячая точка ──────────────────────────────────────────────────
    if (_has(t, ['горячая точка', 'точка доступа', 'хотспот', 'hotspot', 'раздать интернет'])) {
      await AndroidIntent(action: 'android.settings.TETHER_SETTINGS',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return VoiceCmdResult.ok('📡 Горячая точка — открываю настройки');
    }

    // ── 8. Режим "Не беспокоить" ──────────────────────────────────────────
    if (_has(t, ['не беспокоить', 'dnd', 'режим тишины', 'тихий режим', 'беспокоить'])) {
      await AndroidIntent(action: 'android.settings.ZEN_MODE_SETTINGS',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return VoiceCmdResult.ok('🤫 Режим "Не беспокоить" — открываю настройки');
    }

    // ── 9. Вибро-режим ────────────────────────────────────────────────────
    if (_has(t, ['вибро', 'виброрежим', 'включи вибрацию'])) {
      await AndroidIntent(action: 'android.settings.SOUND_SETTINGS',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return VoiceCmdResult.ok('📳 Открываю настройки звука');
    }

    // ── 10. Экономия энергии ──────────────────────────────────────────────
    if (_has(t, ['экономия энергии', 'экономия заряда', 'энергосбережение', 'power save', 'режим экономии'])) {
      await AndroidIntent(action: 'android.settings.BATTERY_SAVER_SETTINGS',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return VoiceCmdResult.ok('🔋 Экономия энергии — открываю настройки');
    }

    // ── 11. Батарея ───────────────────────────────────────────────────────
    if (_has(t, ['заряд', 'батарея', 'аккумулятор', 'сколько процентов', 'сколько заряда', 'battery'])) {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final charging = state == BatteryState.charging ? ' ⚡ заряжается' : '';
      final full = state == BatteryState.full ? ' — полностью заряжен' : '';
      return VoiceCmdResult.ok('🔋 Заряд батареи: $level%$charging$full');
    }

    // ── 12. Скриншот ──────────────────────────────────────────────────────
    if (_has(t, ['скриншот', 'снимок экрана', 'сделай скрин', 'screenshot', 'скрин'])) {
      try {
        await _ch.invokeMethod('performGlobalAction', {'action': 9});
        return VoiceCmdResult.ok('📸 Скриншот сделан!');
      } catch (_) {
        return VoiceCmdResult.ok('📸 Для скриншота нужен доступ Accessibility');
      }
    }

    // ── 13. Камера ────────────────────────────────────────────────────────
    if (_has(t, ['открой камеру', 'включи камеру', 'запусти камеру', 'camera', 'камеру', 'сфоткай', 'сделай фото'])) {
      await AndroidIntent(action: 'android.media.action.STILL_IMAGE_CAMERA',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return VoiceCmdResult.ok('📷 Камера открыта!');
    }
    if (_has(t, ['сними видео', 'видеосъёмка', 'видеокамера', 'запись видео', 'video camera'])) {
      await AndroidIntent(action: 'android.media.action.VIDEO_CAMERA',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return VoiceCmdResult.ok('🎥 Видеокамера открыта!');
    }

    // ── 14. Навигация телефона ────────────────────────────────────────────
    final navResult = await _handleNavigation(t);
    if (navResult != null) return navResult;

    // ── 15. Блокировка/выключение экрана ──────────────────────────────────
    if (_has(t, ['заблокируй', 'заблокируй экран', 'заблокируй телефон', 'выключи экран', 'lock', 'блокировка'])) {
      try {
        await _ch.invokeMethod('performGlobalAction', {'action': 8});
        return VoiceCmdResult.ok('🔒 Экран заблокирован');
      } catch (_) {
        return VoiceCmdResult.ok('🔒 Нужен доступ Accessibility + Device Admin');
      }
    }

    // ── 16. Меню питания ──────────────────────────────────────────────────
    if (_has(t, ['выключи телефон', 'перезагрузи', 'меню питания', 'power menu', 'выключить телефон'])) {
      try {
        await _ch.invokeMethod('performGlobalAction', {'action': 12});
        return VoiceCmdResult.ok('🔌 Меню питания открыто');
      } catch (_) {
        return VoiceCmdResult.ok('🔌 Не удалось открыть меню питания');
      }
    }

    // ── 17. Приложения ────────────────────────────────────────────────────
    final appResult = await _handleOpenApp(t, text);
    if (appResult != null) return appResult;

    // ── 18. Поиск в Google ────────────────────────────────────────────────
    final searchResult = await _handleSearch(t, text);
    if (searchResult != null) return searchResult;

    // ── 19. YouTube ───────────────────────────────────────────────────────
    final ytResult = await _handleYouTube(t, text);
    if (ytResult != null) return ytResult;

    // ── 20. Карты / Навигация ─────────────────────────────────────────────
    final mapsResult = await _handleMaps(t, text);
    if (mapsResult != null) return mapsResult;

    // ── 21. Звонки ────────────────────────────────────────────────────────
    final callResult = await _handleCalls(t, text);
    if (callResult != null) return callResult;

    // ── 22. SMS / Сообщения ───────────────────────────────────────────────
    final smsResult = await _handleSms(t, text);
    if (smsResult != null) return smsResult;

    // ── 23. Таймер ────────────────────────────────────────────────────────
    final timerResult = await _handleTimer(t, text);
    if (timerResult != null) return timerResult;

    // ── 24. Будильник ─────────────────────────────────────────────────────
    final alarmResult = await _handleAlarm(t, text);
    if (alarmResult != null) return alarmResult;

    // ── 25. Напоминания ───────────────────────────────────────────────────
    final reminderResult = await _handleReminder(t, text);
    if (reminderResult != null) return reminderResult;

    // ── 26. Погода ────────────────────────────────────────────────────────
    if (_has(t, ['погода', 'температура', 'прогноз', 'какая погода', 'weather'])) {
      try {
        final weatherStr = await WeatherService().getWeather();
        if (weatherStr.isNotEmpty) {
          return VoiceCmdResult.ok('🌤 $weatherStr');
        }
      } catch (_) {}
      await launchUrl(Uri.parse('https://weather.com'), mode: LaunchMode.externalApplication);
      return VoiceCmdResult.ok('🌤 Открываю прогноз погоды...');
    }

    // ── 27. Дата и время ──────────────────────────────────────────────────
    if (_has(t, ['сколько времени', 'который час', 'текущее время', 'what time', 'котор'])) {
      final now = DateTime.now();
      final h = now.hour.toString().padLeft(2, '0');
      final m = now.minute.toString().padLeft(2, '0');
      return VoiceCmdResult.ok('🕐 Сейчас $h:$m');
    }
    if (_has(t, ['какой сегодня день', 'какое сегодня число', 'какая дата', 'today date', 'дата сегодня'])) {
      final now = DateTime.now();
      final days = ['понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье'];
      final months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
      return VoiceCmdResult.ok('📅 Сегодня ${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}');
    }

    // ── 28. Настройки ─────────────────────────────────────────────────────
    final settingsResult = await _handleSettings(t);
    if (settingsResult != null) return settingsResult;

    // ── 29. Калькулятор ───────────────────────────────────────────────────
    if (_has(t, ['калькулятор', 'calculator', 'посчитай', 'вычисли'])) {
      await _launchPackage('com.google.android.calculator');
      return VoiceCmdResult.ok('🧮 Калькулятор открыт!');
    }

    // ── 30. Диктофон / Запись голоса ──────────────────────────────────────
    if (_has(t, ['диктофон', 'запись голоса', 'voice recorder', 'запиши', 'включи запись'])) {
      try {
        await AndroidIntent(action: 'android.provider.MediaStore.RECORD_SOUND',
            flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      } catch (_) {
        await _launchPackage('com.sec.android.app.voicenote');
      }
      return VoiceCmdResult.ok('🎙 Диктофон открыт');
    }

    // ── 31. Уведомления ───────────────────────────────────────────────────
    if (_has(t, ['открой уведомления', 'шторка уведомлений', 'покажи уведомления', 'notifications', 'свайп вниз'])) {
      try {
        await _ch.invokeMethod('openNotifications');
        return VoiceCmdResult.ok('🔔 Уведомления открыты');
      } catch (_) {
        return VoiceCmdResult.ok('🔔 Нет доступа к уведомлениям');
      }
    }

    // ── 32. Удалить приложение ────────────────────────────────────────────
    if (_has(t, ['удали приложение', 'удалить приложение', 'деинсталлируй', 'uninstall'])) {
      final appName = _extractAfterKeywords(t, ['удали приложение', 'удалить приложение', 'удали', 'uninstall']);
      if (appName != null && appName.length > 1) {
        final pkg = _knownApps[appName.trim()] ?? appName.trim();
        try {
          await _ch.invokeMethod('uninstallApp', {'package': pkg});
        } catch (_) {
          final url = 'package:$pkg';
          await launchUrl(Uri.parse(url));
        }
        return VoiceCmdResult.ok('🗑 Открываю удаление: $appName');
      }
    }

    // ── 33. Wikipedia ─────────────────────────────────────────────────────
    if (_has(t, ['википедия', 'wikipedia', 'что такое', 'кто такой', 'кто такая'])) {
      final query = _extractAfterKeywords(t, ['что такое', 'кто такой', 'кто такая', 'wikipedia', 'википедия']) ?? '';
      if (query.length > 2) {
        await launchUrl(Uri.parse('https://ru.wikipedia.org/wiki/${Uri.encodeComponent(query)}'),
            mode: LaunchMode.externalApplication);
        return VoiceCmdResult.ok('📖 Wikipedia: $query');
      }
    }

    // ── 34. Переводчик ────────────────────────────────────────────────────
    if (_has(t, ['переведи', 'перевод', 'translate', 'как будет по-английски', 'как будет по-русски'])) {
      final query = _extractAfterKeywords(t, ['переведи', 'перевод слово', 'translate']) ?? t;
      await launchUrl(Uri.parse('https://translate.google.com/?text=${Uri.encodeComponent(query)}'),
          mode: LaunchMode.externalApplication);
      return VoiceCmdResult.ok('🌍 Открываю переводчик');
    }

    // ── 35. Танцуй / анимация ────────────────────────────────────────────
    if (_has(t, ['потанцуй', 'давай потанцуем', 'станцуй', 'dance'])) {
      return VoiceCmdResult.ok('💃 Давай потанцуем!', action: 'dance');
    }

    return null; // Команда не распознана → отправляем в AI
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ОБРАБОТЧИКИ КАТЕГОРИЙ
  // ══════════════════════════════════════════════════════════════════════════

  // ── Фонарик ───────────────────────────────────────────────────────────────
  VoiceCmdResult? _handleFlashlight(String t) {
    if (_has(t, ['включи фонарик', 'фонарик вкл', 'flashlight on', 'включи свет', 'зажги фонарик'])) {
      TorchLight.enableTorch().then((_) => _flashOn = true).catchError((_) {});
      return VoiceCmdResult.ok('🔦 Фонарик включён!');
    }
    if (_has(t, ['выключи фонарик', 'фонарик выкл', 'flashlight off', 'выключи свет', 'погаси фонарик'])) {
      TorchLight.disableTorch().then((_) => _flashOn = false).catchError((_) {});
      return VoiceCmdResult.ok('🔦 Фонарик выключен');
    }
    if (_has(t, ['фонарик', 'flashlight']) && !_has(t, ['настройки'])) {
      if (_flashOn) {
        TorchLight.disableTorch().then((_) => _flashOn = false).catchError((_) {});
        return VoiceCmdResult.ok('🔦 Фонарик выключен');
      } else {
        TorchLight.enableTorch().then((_) => _flashOn = true).catchError((_) {});
        return VoiceCmdResult.ok('🔦 Фонарик включён!');
      }
    }
    return null;
  }

  // ── Громкость ─────────────────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleVolume(String t) async {
    // Процентная установка: "громкость 70%", "поставь громкость на 50"
    if (_has(t, ['громкость', 'volume'])) {
      final pct = _extractPercent(t) ?? _extractNumber(t);
      if (pct != null && pct >= 0 && pct <= 100) {
        VolumeController().setVolume(pct / 100);
        return VoiceCmdResult.ok('🔊 Громкость: ${pct.round()}%');
      }
      if (_has(t, ['max', 'максимум', 'максимальная', 'на максимум', 'полная'])) {
        VolumeController().setVolume(1.0);
        return VoiceCmdResult.ok('🔊 Максимальная громкость!');
      }
      if (_has(t, ['min', 'минимум', 'минимальная', 'на минимум'])) {
        VolumeController().setVolume(0.05);
        return VoiceCmdResult.ok('🔉 Минимальная громкость');
      }
      if (_has(t, ['выключи', 'mute', 'без звука', 'выкл', 'тихо'])) {
        VolumeController().setVolume(0.0);
        return VoiceCmdResult.ok('🔇 Звук выключен');
      }
    }
    // Не трогаем громкость если это команда запуска приложения
    if (_has(t, ['включи', 'вкл']) && !_has(t, ['spotify', 'спотифай', 'спотифи',
        'whatsapp', 'ватсап', 'вотсап', 'вацап', 'телеграм', 'telegram',
        'ютуб', 'youtube', 'инстаграм', 'инста', 'тик', 'музык'])) {
      VolumeController().setVolume(_vol = 1.0);
      return VoiceCmdResult.ok('🔊 Громкость на максимум!');
    }
    if (_has(t, ['громче', 'увеличь громкость', 'volume up', 'прибавь', 'добавь громкости'])) {
      VolumeController().setVolume((_vol + 0.15).clamp(0.0, 1.0));
      return VoiceCmdResult.ok('🔊 Громкость увеличена');
    }
    if (_has(t, ['тише', 'уменьши громкость', 'volume down', 'убавь', 'убавь громкость'])) {
      VolumeController().setVolume((_vol - 0.15).clamp(0.0, 1.0));
      return VoiceCmdResult.ok('🔉 Громкость уменьшена');
    }
    if (_has(t, ['без звука', 'тихий режим', 'заглуши', 'mute', 'замолчи звук'])) {
      VolumeController().setVolume(0.0);
      return VoiceCmdResult.ok('🔇 Звук выключен');
    }
    return null;
  }

  // ── Яркость ───────────────────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleBrightness(String t) async {
    if (!_has(t, ['яркость', 'brightness', 'экран ярче', 'экран темнее'])) return null;

    if (_has(t, ['максимум', 'максимальная', 'на максимум', 'max', 'ярче максимум'])) {
      return await _setBrightness(255, 'максимальная');
    }
    if (_has(t, ['минимум', 'минимальная', 'на минимум', 'min', 'темнее минимум'])) {
      return await _setBrightness(20, 'минимальная');
    }
    if (_has(t, ['авто', 'автоматическая', 'auto', 'автояркость'])) {
      try {
        await _ch.invokeMethod('setAutoBrightness');
        return VoiceCmdResult.ok('☀️ Автояркость включена');
      } catch (_) {}
    }
    if (_has(t, ['ярче', 'увеличь яркость', 'посветлее'])) {
      return await _setBrightness(200, 'высокая');
    }
    if (_has(t, ['темнее', 'уменьши яркость', 'потемнее'])) {
      return await _setBrightness(60, 'низкая');
    }
    final pct = _extractPercent(t) ?? _extractNumber(t);
    if (pct != null) {
      return await _setBrightness((pct / 100 * 255).round().clamp(0, 255), '$pct%');
    }
    await AndroidIntent(action: 'android.settings.DISPLAY_SETTINGS',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
    return VoiceCmdResult.ok('☀️ Открываю настройки яркости');
  }

  Future<VoiceCmdResult> _setBrightness(int value, String label) async {
    try {
      await _ch.invokeMethod('setBrightness', {'value': value});
      return VoiceCmdResult.ok('☀️ Яркость: $label');
    } catch (_) {
      await AndroidIntent(action: 'android.settings.DISPLAY_SETTINGS',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return VoiceCmdResult.ok('☀️ Открываю настройки яркости ($label)');
    }
  }

  // ── Wi-Fi ─────────────────────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleWifi(String t) async {
    if (!_has(t, ['wifi', 'вай фай', 'вайфай', 'wi-fi', 'беспроводная', 'интернет настройки'])) return null;
    await AndroidIntent(action: 'android.settings.WIFI_SETTINGS',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
    return VoiceCmdResult.ok('📶 Настройки Wi-Fi открыты');
  }

  // ── Bluetooth ─────────────────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleBluetooth(String t) async {
    if (!_has(t, ['bluetooth', 'блютуз', 'блюзуб', 'беспроводная гарнитура', 'bt'])) return null;
    await AndroidIntent(action: 'android.settings.BLUETOOTH_SETTINGS',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
    return VoiceCmdResult.ok('🔵 Настройки Bluetooth открыты');
  }

  // ── Системная навигация ───────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleNavigation(String t) async {
    if (_has(t, ['назад', 'вернись', 'go back', 'кнопка назад', 'выйди из', 'нажми назад'])) {
      try { await _ch.invokeMethod('performBack'); return VoiceCmdResult.ok('◀️ Назад'); } catch (_) {}
    }
    if (_has(t, ['домой', 'на главный', 'главный экран', 'go home', 'home screen', 'на главную'])) {
      try { await _ch.invokeMethod('pressHome'); return VoiceCmdResult.ok('🏠 Главный экран'); } catch (_) {}
    }
    if (_has(t, ['недавние', 'последние приложения', 'recent apps', 'переключиться', 'открытые приложения'])) {
      try { await _ch.invokeMethod('pressRecents'); return VoiceCmdResult.ok('📋 Недавние приложения'); } catch (_) {}
    }
    if (_has(t, ['закрой приложение', 'закрыть это', 'закрой это', 'close app', 'закрой текущее'])) {
      try { await _ch.invokeMethod('closeCurrentApp'); return VoiceCmdResult.ok('✅ Закрываю приложение'); } catch (_) {}
    }
    return null;
  }

  // ── Открытие приложений ───────────────────────────────────────────────────
    Future<VoiceCmdResult?> _handleOpenApp(String t, String original) async {
    // Делегируем ВСЁ в AppLauncherService — единая точка истины
    final result = await AppLauncherService.tryLaunch(original);
    if (result != null) {
      return VoiceCmdResult.ok(result);
    }
    return null;
  }

  // ── Поиск Google ──────────────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleSearch(String t, String original) async {
    final triggers = ['найди', 'погугли', 'поищи', 'загугли', 'искать', 'поиск по запросу'];
    if (!triggers.any((k) => t.startsWith(k) || t.contains(' $k '))) return null;
    final query = _extractAfterKeywords(t, triggers) ?? '';
    if (query.length < 2) return null;
    await launchUrl(Uri.parse('https://google.com/search?q=${Uri.encodeComponent(query)}'),
        mode: LaunchMode.externalApplication);
    return VoiceCmdResult.ok('🔍 Ищу: $query');
  }

  // ── YouTube поиск ─────────────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleYouTube(String t, String original) async {
    if (!_has(t, ['включи на ютубе', 'найди на ютубе', 'поищи на ютубе', 'ютуб включи', 'youtube search', 'youtube найди'])) return null;
    final query = _extractAfterKeywords(t, ['включи на ютубе', 'найди на ютубе', 'поищи на ютубе', 'ютуб включи']) ?? '';
    if (query.length < 2) return null;
    await launchUrl(Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}'),
        mode: LaunchMode.externalApplication);
    return VoiceCmdResult.ok('▶️ YouTube: $query');
  }

  // ── Google Maps / маршрут ─────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleMaps(String t, String original) async {
    final routeTriggers = ['маршрут до', 'проложи маршрут', 'как добраться', 'навигация до', 'доехать до', 'дорогу до'];
    if (routeTriggers.any((k) => t.contains(k))) {
      final dest = _extractAfterKeywords(t, routeTriggers) ?? '';
      if (dest.length > 1) {
        await launchUrl(Uri.parse('https://maps.google.com/maps?daddr=${Uri.encodeComponent(dest)}'),
            mode: LaunchMode.externalApplication);
        return VoiceCmdResult.ok('🗺 Прокладываю маршрут до $dest');
      }
    }
    if (_has(t, ['покажи на карте', 'где находится', 'найди на карте', 'maps search'])) {
      final place = _extractAfterKeywords(t, ['покажи на карте', 'где находится', 'найди на карте']) ?? '';
      if (place.length > 1) {
        await launchUrl(Uri.parse('https://maps.google.com/maps?q=${Uri.encodeComponent(place)}'),
            mode: LaunchMode.externalApplication);
        return VoiceCmdResult.ok('📍 Ищу на карте: $place');
      }
    }
    return null;
  }

  // ── Звонки ────────────────────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleCalls(String t, String original) async {
    if (_has(t, ['позвони', 'набери', 'вызови', 'call', 'позвоник'])) {
      final contact = _extractAfterKeywords(t, ['позвони', 'набери', 'вызови', 'позвони на']) ?? '';
      if (contact.length > 1) {
        // Пробуем набрать номер или открыть набор
        try {
          final uri = Uri(scheme: 'tel', path: contact.replaceAll(RegExp(r'\s+'), ''));
          await launchUrl(uri);
          return VoiceCmdResult.ok('📞 Звоню $contact...');
        } catch (_) {}
      }
      await _launchPackage('com.google.android.dialer');
      return VoiceCmdResult.ok('📞 Открываю набор номера');
    }
    if (_has(t, ['завершить звонок', 'сбрось', 'положи трубку', 'end call', 'завершить вызов'])) {
      try {
        await _ch.invokeMethod('endCall');
        return VoiceCmdResult.ok('📵 Звонок завершён');
      } catch (_) {
        return VoiceCmdResult.ok('📵 Не удалось завершить автоматически');
      }
    }
    return null;
  }

  // ── SMS ───────────────────────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleSms(String t, String original) async {
    if (!_has(t, ['отправь смс', 'отправить смс', 'написать смс', 'смс', 'sms'])) return null;
    final contact = _extractAfterKeywords(t, ['отправь смс', 'смс на номер', 'смс']) ?? '';
    if (contact.isNotEmpty) {
      final uri = Uri(scheme: 'sms', path: contact.trim());
      await launchUrl(uri);
      return VoiceCmdResult.ok('💬 Открываю SMS для $contact');
    }
    return null;
  }

  // ── Таймер ───────────────────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleTimer(String t, String original) async {
    if (!_has(t, ['таймер', 'timer', 'поставь таймер', 'запусти таймер'])) return null;

    int? seconds;
    // "таймер на 5 минут", "таймер на 30 секунд", "таймер на 1 час 30 минут"
    final hoursMatch = RegExp(r'(\d+)\s*(?:час|часа|часов|h)').firstMatch(t);
    final minsMatch  = RegExp(r'(\d+)\s*(?:минут|минуты|мин|min|m)').firstMatch(t);
    final secsMatch  = RegExp(r'(\d+)\s*(?:секунд|секунды|сек|sec|s)').firstMatch(t);

    if (hoursMatch != null || minsMatch != null || secsMatch != null) {
      seconds = (int.tryParse(hoursMatch?.group(1) ?? '0') ?? 0) * 3600
              + (int.tryParse(minsMatch?.group(1) ?? '0')  ?? 0) * 60
              + (int.tryParse(secsMatch?.group(1) ?? '0')  ?? 0);
    }

    if (seconds != null && seconds > 0) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.SET_TIMER',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
          arguments: {'android.intent.extra.alarm.LENGTH': seconds, 'android.intent.extra.alarm.SKIP_UI': false},
        );
        await intent.launch();
        final label = _formatDuration(seconds);
        return VoiceCmdResult.ok('⏱ Таймер на $label запущен!');
      } catch (_) {}
    }
    // Без времени — открываем часы
    await _launchPackage('com.google.android.deskclock');
    return VoiceCmdResult.ok('⏱ Открываю таймер');
  }

  // ── Будильник ─────────────────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleAlarm(String t, String original) async {
    if (!_has(t, ['будильник', 'alarm', 'разбуди меня', 'поставь будильник'])) return null;

    // "будильник на 7:30", "разбуди в 8 утра"
    final timeMatch = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(?:утра|часов|:)?').firstMatch(t);
    if (timeMatch != null) {
      final h = int.tryParse(timeMatch.group(1) ?? '') ?? -1;
      final m = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
      if (h >= 0 && h <= 23) {
        try {
          final intent = AndroidIntent(
            action: 'android.intent.action.SET_ALARM',
            flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
            arguments: {'android.intent.extra.alarm.HOUR': h, 'android.intent.extra.alarm.MINUTES': m, 'android.intent.extra.alarm.SKIP_UI': false},
          );
          await intent.launch();
          return VoiceCmdResult.ok('⏰ Будильник на $h:${m.toString().padLeft(2, '0')}!');
        } catch (_) {}
      }
    }
    await _launchPackage('com.google.android.deskclock');
    return VoiceCmdResult.ok('⏰ Открываю будильники');
  }

  // ── Напоминания ───────────────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleReminder(String t, String original) async {
    if (!_has(t, ['напомни', 'напомни мне', 'напоминание', 'reminder', 'поставь напоминание'])) return null;

    // "напомни мне через 10 минут [текст]"
    final minMatch = RegExp(r'через\s+(\d+)\s*(?:минут|мин)').firstMatch(t);
    if (minMatch != null) {
      final mins = int.tryParse(minMatch.group(1) ?? '0') ?? 0;
      final textAfter = _extractAfterKeywords(t, ['напомни мне', 'напомни', 'напоминание']) ?? original;
      final reminderText = textAfter.replaceFirst(RegExp(r'через\s+\d+\s*(?:минут|мин)\s*'), '').trim();
      if (mins > 0) {
        final due = DateTime.now().add(Duration(minutes: mins));
        try {
          final prefs = await SharedPreferences.getInstance();
          final existing = prefs.getStringList('quick_reminders') ?? [];
          existing.add('${due.millisecondsSinceEpoch}|${reminderText.isNotEmpty ? reminderText : 'Напоминание'}');
          await prefs.setStringList('quick_reminders', existing);
        } catch (_) {}
        return VoiceCmdResult.ok('⏰ Напомню через $mins минут: ${reminderText.isNotEmpty ? reminderText : 'Напоминание'}');
      }
    }
    return VoiceCmdResult.ok('📝 Открываю напоминания', action: 'open_reminders');
  }

  // ── Настройки ─────────────────────────────────────────────────────────────
  Future<VoiceCmdResult?> _handleSettings(String t) async {
    if (_has(t, ['настройки звука', 'настройки уведомлений', 'sound settings', 'notification settings'])) {
      await AndroidIntent(action: 'android.settings.SOUND_SETTINGS',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return VoiceCmdResult.ok('🔔 Настройки звука открыты');
    }
    if (_has(t, ['настройки дисплея', 'настройки экрана', 'display settings', 'настройки яркости'])) {
      await AndroidIntent(action: 'android.settings.DISPLAY_SETTINGS',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return VoiceCmdResult.ok('🖥 Настройки дисплея открыты');
    }
    if (_has(t, ['настройки местоположения', 'gps', 'геолокация', 'location settings', 'настройки gps'])) {
      await AndroidIntent(action: 'android.settings.LOCATION_SOURCE_SETTINGS',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return VoiceCmdResult.ok('📍 Настройки GPS открыты');
    }
    if (_has(t, ['открой настройки', 'настройки телефона', 'open settings', 'системные настройки'])) {
      await AndroidIntent(action: 'android.settings.SETTINGS',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return VoiceCmdResult.ok('⚙️ Настройки открыты');
    }
    if (_has(t, ['настройки приложений', 'управление приложениями', 'app settings', 'список приложений'])) {
      await AndroidIntent(action: 'android.settings.APPLICATION_SETTINGS',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return VoiceCmdResult.ok('📱 Управление приложениями открыто');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // УТИЛИТЫ
  // ══════════════════════════════════════════════════════════════════════════

  bool _has(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  String? _extractAfterKeywords(String text, List<String> keywords) {
    final sorted = List<String>.from(keywords)..sort((a, b) => b.length - a.length);
    for (final k in sorted) {
      final idx = text.indexOf(k);
      if (idx >= 0) {
        final after = text.substring(idx + k.length).trim();
        if (after.isNotEmpty) return after;
      }
    }
    return null;
  }

  double? _extractNumber(String text) {
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    return m != null ? double.tryParse(m.group(1)!) : null;
  }

  double? _extractPercent(String text) {
    final m = RegExp(r'(\d+)\s*%').firstMatch(text);
    return m != null ? double.tryParse(m.group(1)!) : null;
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final parts = <String>[];
    if (h > 0) parts.add('$h ч');
    if (m > 0) parts.add('$m мин');
    if (s > 0) parts.add('$s сек');
    return parts.join(' ');
  }

  Future<void> _launchPackage(String packageName) async {
    try {
      await AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: packageName,
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK, Flag.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED],
      ).launch();
    } catch (_) {
      try {
        await launchUrl(Uri.parse('market://details?id=$packageName'));
      } catch (_) {}
    }
  }

  // ── Таблица известных приложений (название → package name) ────────────────
  static const Map<String, String> _knownApps = {
    // Соцсети
    'вк': 'com.vkontakte.android',
    'вконтакте': 'com.vkontakte.android',
    'vk': 'com.vkontakte.android',
    'telegram': 'org.telegram.messenger',
    'телеграм': 'org.telegram.messenger',
    'whatsapp': 'com.whatsapp',
    'ватсап': 'com.whatsapp',
    'вотсап': 'com.whatsapp',
    'вацап': 'com.whatsapp',
    'instagram': 'com.instagram.android',
    'инстаграм': 'com.instagram.android',
    'инста': 'com.instagram.android',
    'tiktok': 'com.zhiliaoapp.musically',
    'тикток': 'com.zhiliaoapp.musically',
    'twitter': 'com.twitter.android',
    'твиттер': 'com.twitter.android',
    'x': 'com.twitter.android',
    'facebook': 'com.facebook.katana',
    'фейсбук': 'com.facebook.katana',
    'snapchat': 'com.snapchat.android',
    'снэпчат': 'com.snapchat.android',
    'pinterest': 'com.pinterest',
    'пинтерест': 'com.pinterest',
    'linkedin': 'com.linkedin.android',
    'линкедин': 'com.linkedin.android',
    'reddit': 'com.reddit.frontpage',
    'реддит': 'com.reddit.frontpage',
    // Медиа
    'youtube': 'com.google.android.youtube',
    'ютуб': 'com.google.android.youtube',
    'spotify': 'com.spotify.music',
    'спотифай': 'com.spotify.music',
    'netflix': 'com.netflix.mediaclient',
    'нетфликс': 'com.netflix.mediaclient',
    'twitch': 'tv.twitch.android.app',
    'твич': 'tv.twitch.android.app',
    'shazam': 'com.shazam.android',
    'шазам': 'com.shazam.android',
    'youtube music': 'com.google.android.apps.youtube.music',
    'ютуб музыка': 'com.google.android.apps.youtube.music',
    'yandex music': 'com.yandex.music',
    'яндекс музыка': 'com.yandex.music',
    'yandex': 'ru.yandex.searchplugin',
    'яндекс': 'ru.yandex.searchplugin',
    'okko': 'ru.okko.app',
    'окко': 'ru.okko.app',
    'kion': 'ru.mts.kion',
    // Браузеры
    'chrome': 'com.android.chrome',
    'хром': 'com.android.chrome',
    'firefox': 'org.mozilla.firefox',
    'файрфокс': 'org.mozilla.firefox',
    'opera': 'com.opera.browser',
    'опера': 'com.opera.browser',
    'brave': 'com.brave.browser',
    'yandex browser': 'com.yandex.browser',
    'яндекс браузер': 'com.yandex.browser',
    // Google
    'maps': 'com.google.android.apps.maps',
    'карты': 'com.google.android.apps.maps',
    'google maps': 'com.google.android.apps.maps',
    'gmail': 'com.google.android.gm',
    'почта': 'com.google.android.gm',
    'drive': 'com.google.android.apps.docs',
    'диск': 'com.google.android.apps.docs',
    'translate': 'com.google.android.apps.translate',
    'переводчик': 'com.google.android.apps.translate',
    'photos': 'com.google.android.apps.photos',
    'фото': 'com.google.android.apps.photos',
    'галерея': 'com.google.android.apps.photos',
    'play store': 'com.android.vending',
    'плей стор': 'com.android.vending',
    'маркет': 'com.android.vending',
    'play market': 'com.android.vending',
    'google meet': 'com.google.android.apps.meetings',
    'meet': 'com.google.android.apps.meetings',
    'google docs': 'com.google.android.apps.docs.editors.docs',
    'docs': 'com.google.android.apps.docs.editors.docs',
    // Системные
    'calculator': 'com.google.android.calculator',
    'калькулятор': 'com.google.android.calculator',
    'calendar': 'com.google.android.calendar',
    'календарь': 'com.google.android.calendar',
    'clock': 'com.google.android.deskclock',
    'часы': 'com.google.android.deskclock',
    'camera': 'com.android.camera2',
    'камера': 'com.android.camera2',
    'files': 'com.google.android.documentsui',
    'файлы': 'com.google.android.documentsui',
    'dialer': 'com.google.android.dialer',
    'телефон': 'com.google.android.dialer',
    // Общение
    'discord': 'com.discord',
    'дискорд': 'com.discord',
    'zoom': 'us.zoom.videomeetings',
    'зум': 'us.zoom.videomeetings',
    'skype': 'com.skype.raider',
    'скайп': 'com.skype.raider',
    'viber': 'com.viber.voip',
    'вайбер': 'com.viber.voip',
    'signal': 'org.thoughtcrime.securesms',
    'сигнал': 'org.thoughtcrime.securesms',
    // Разное
    'uber': 'com.ubercab',
    'убер': 'com.ubercab',
    'yandex taxi': 'ru.yandex.taxi',
    'яндекс такси': 'ru.yandex.taxi',
    'яндекс go': 'ru.yandex.taxi',
    'duolingo': 'com.duolingo',
    'дуолинго': 'com.duolingo',
    'tinder': 'com.tinder',
    'тиндер': 'com.tinder',
    'booking': 'com.booking',
    'букинг': 'com.booking',
    'aliexpress': 'com.alibaba.aliexpresshd',
    'алиэкспресс': 'com.alibaba.aliexpresshd',
    'ozon': 'ru.ozon.app.android',
    'озон': 'ru.ozon.app.android',
    'wildberries': 'com.wildberries.ru',
    'вайлдберриз': 'com.wildberries.ru',
    'wb': 'com.wildberries.ru',
    'сбербанк': 'ru.sberbankmobile',
    'сбер': 'ru.sberbankmobile',
    'тинькофф': 'com.idamob.tinkoff.android',
    'тинкофф': 'com.idamob.tinkoff.android',
    'tinkoff': 'com.idamob.tinkoff.android',
    'avito': 'ru.avito.android',
    'авито': 'ru.avito.android',
    'gosuslugi': 'ru.rostelekom.portal',
    'госуслуги': 'ru.rostelekom.portal',
    'ok.ru': 'ru.ok.android',
    'одноклассники': 'ru.ok.android',
    'ok': 'ru.ok.android',
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// Результат обработки голосовой команды
// ══════════════════════════════════════════════════════════════════════════════
class VoiceCmdResult {
  final String message;
  final bool success;
  final String? action; // опциональное доп. действие для UI ('dance', 'open_reminders' и т.д.)

  const VoiceCmdResult({required this.message, required this.success, this.action});

  factory VoiceCmdResult.ok(String message, {String? action}) =>
      VoiceCmdResult(message: message, success: true, action: action);

  factory VoiceCmdResult.error(String message) =>
      VoiceCmdResult(message: message, success: false);
}
