import 'package:flutter/services.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:torch_light/torch_light.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:battery_plus/battery_plus.dart';

/// Полное голосовое управление телефоном
/// Все команды парсятся из натурального текста пользователя
class PhoneControlService {
  static final PhoneControlService _i = PhoneControlService._();
  factory PhoneControlService() => _i;
  PhoneControlService._();

  static const _channel = MethodChannel('aika/phone_control');
  final Battery _battery = Battery();
  double _vol = 0.5;

  void init() {
    VolumeController().listener((v) => _vol = v);
  }

  void dispose() {
    VolumeController().removeListener();
  }

  // ══════════════════════════════════════════════════════════════
  // ГЛАВНЫЙ ПАРСЕР — принимает любую голосовую команду
  // ══════════════════════════════════════════════════════════════
  Future<PhoneCommandResult?> parseCommand(String text) async {
    final t = text.toLowerCase().trim();

    // ── ЗВОНКИ ────────────────────────────────────────────────
    if (_matches(t, ['позвони', 'набери', 'вызови', 'call', 'звонок'])) {
      final name = _extractContact(t, ['позвони', 'набери', 'вызови', 'call']);
      if (name != null) return await _makeCall(name);
    }
    if (_matches(t, ['завершить звонок', 'сбрось', 'положи трубку', 'end call'])) {
      return await _endCall();
    }
    if (_matches(t, ['принять звонок', 'ответить', 'answer'])) {
      return await _answerCall();
    }

    // ── SMS / СООБЩЕНИЯ ───────────────────────────────────────
    if (_matches(t, ['отправь смс', 'напиши смс', 'смс', 'send sms', 'написать сообщение'])) {
      final contact = _extractContact(t, ['отправь смс', 'напиши смс', 'смс для', 'смс']);
      final msg = _extractAfter(t, ['текст:', 'сообщение:', 'напиши:', 'написать:']);
      return await _sendSms(contact ?? '', msg ?? text);
    }

    // ── WIFI ──────────────────────────────────────────────────
    if (_matches(t, ['включи wifi', 'включи вай фай', 'turn on wifi', 'wifi on'])) {
      return await _openWifiSettings();
    }
    if (_matches(t, ['настройки wifi', 'wifi настройки', 'подключиться к wifi'])) {
      return await _openWifiSettings();
    }

    // ── BLUETOOTH ─────────────────────────────────────────────
    if (_matches(t, ['включи bluetooth', 'включи блютуз', 'turn on bluetooth'])) {
      return await _toggleBluetooth(true);
    }
    if (_matches(t, ['выключи bluetooth', 'выключи блютуз', 'turn off bluetooth'])) {
      return await _toggleBluetooth(false);
    }
    if (_matches(t, ['bluetooth настройки', 'настройки bluetooth', 'блютуз'])) {
      return await _openBluetoothSettings();
    }

    // ── ЯРКОСТЬ ───────────────────────────────────────────────
    if (_matches(t, ['яркость максимум', 'яркость на максимум', 'максимальная яркость', 'brightness max'])) {
      return await _setBrightness(255);
    }
    if (_matches(t, ['яркость минимум', 'яркость на минимум', 'минимальная яркость', 'brightness min'])) {
      return await _setBrightness(20);
    }
    if (_matches(t, ['яркость', 'brightness'])) {
      final val = _extractNumber(t);
      if (val != null) return await _setBrightness((val * 2.55).round().clamp(0, 255));
    }
    if (_matches(t, ['авто яркость', 'автояркость', 'auto brightness'])) {
      return await _setAutoBrightness();
    }

    // ── АВИАРЕЖИМ ─────────────────────────────────────────────
    if (_matches(t, ['авиарежим', 'режим полета', 'airplane mode', 'режим в самолете'])) {
      return await _openAirplaneMode();
    }

    // ── ГРОМКОСТЬ ─────────────────────────────────────────────
    if (_matches(t, ['громкость на максимум', 'максимальная громкость', 'volume max'])) {
      VolumeController().setVolume(1.0);
      return PhoneCommandResult.ok('🔊 Максимальная громкость');
    }
    if (_matches(t, ['без звука', 'тихий режим', 'заглуши', 'mute', 'volume mute'])) {
      VolumeController().setVolume(0.0);
      return PhoneCommandResult.ok('🔇 Звук выключен');
    }
    if (_matches(t, ['громче', 'увеличь громкость', 'volume up'])) {
      VolumeController().setVolume((_vol + 0.2).clamp(0.0, 1.0));
      return PhoneCommandResult.ok('🔊 Громкость увеличена');
    }
    if (_matches(t, ['тише', 'уменьши громкость', 'volume down'])) {
      VolumeController().setVolume((_vol - 0.2).clamp(0.0, 1.0));
      return PhoneCommandResult.ok('🔉 Громкость уменьшена');
    }

    // ── ФОНАРИК ───────────────────────────────────────────────
    if (_matches(t, ['включи фонарик', 'фонарик вкл', 'flashlight on', 'включи свет'])) {
      try { await TorchLight.enableTorch(); return PhoneCommandResult.ok('🔦 Фонарик включён'); }
      catch (e) { return PhoneCommandResult.error('Не могу включить фонарик'); }
    }
    if (_matches(t, ['выключи фонарик', 'фонарик выкл', 'flashlight off'])) {
      try { await TorchLight.disableTorch(); return PhoneCommandResult.ok('🔦 Фонарик выключен'); }
      catch (e) { return PhoneCommandResult.error('Не могу выключить фонарик'); }
    }

    // ── БАТАРЕЯ ───────────────────────────────────────────────
    if (_matches(t, ['заряд', 'батарея', 'сколько процентов', 'battery'])) {
      final level = await _battery.batteryLevel;
      final status = await _battery.batteryState;
      final charging = status == BatteryState.charging ? ' (заряжается ⚡)' : '';
      return PhoneCommandResult.ok('🔋 Заряд: $level%$charging');
    }

    // ── СКРИНШОТ ──────────────────────────────────────────────
    if (_matches(t, ['сделай скриншот', 'скриншот', 'screenshot', 'снимок экрана'])) {
      return await _takeScreenshot();
    }

    // ── НАСТРОЙКИ ─────────────────────────────────────────────
    if (_matches(t, ['открой настройки', 'настройки телефона', 'open settings'])) {
      await AndroidIntent(action: 'android.settings.SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return PhoneCommandResult.ok('⚙️ Настройки открыты');
    }
    if (_matches(t, ['настройки звука', 'настройки уведомлений', 'notification settings'])) {
      await AndroidIntent(action: 'android.settings.SOUND_SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return PhoneCommandResult.ok('🔔 Настройки звука открыты');
    }
    if (_matches(t, ['настройки дисплея', 'настройки экрана', 'display settings'])) {
      await AndroidIntent(action: 'android.settings.DISPLAY_SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return PhoneCommandResult.ok('🖥 Настройки дисплея открыты');
    }
    if (_matches(t, ['настройки местоположения', 'gps', 'геолокация', 'location settings'])) {
      await AndroidIntent(action: 'android.settings.LOCATION_SOURCE_SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return PhoneCommandResult.ok('📍 Настройки геолокации открыты');
    }
    if (_matches(t, ['управление приложениями', 'список приложений', 'app settings'])) {
      await AndroidIntent(action: 'android.settings.APPLICATION_SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return PhoneCommandResult.ok('📱 Список приложений открыт');
    }

    // ── КАМЕРА ────────────────────────────────────────────────
    if (_matches(t, ['открой камеру', 'включи камеру', 'сфотографируй', 'camera'])) {
      await AndroidIntent(action: 'android.media.action.STILL_IMAGE_CAMERA', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return PhoneCommandResult.ok('📷 Камера открыта');
    }
    if (_matches(t, ['видео', 'сними видео', 'включи видеокамеру'])) {
      await AndroidIntent(action: 'android.media.action.VIDEO_CAMERA', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return PhoneCommandResult.ok('🎥 Видеокамера открыта');
    }

    // ── ТАЙМЕР / БУДИЛЬНИК ────────────────────────────────────
    if (_matches(t, ['поставь таймер', 'таймер на', 'timer'])) {
      final minutes = _extractNumber(t);
      if (minutes != null) return await _setTimer(minutes.round());
    }
    if (_matches(t, ['поставь будильник', 'разбуди меня', 'alarm', 'будильник на'])) {
      final hour = _extractTime(t);
      if (hour != null) return await _setAlarm(hour.$1, hour.$2);
    }

    // ── ПОИСК ─────────────────────────────────────────────────
    if (_matches(t, ['найди', 'погугли', 'поищи', 'google', 'search'])) {
      final query = _extractAfter(t, ['найди', 'погугли', 'поищи', 'поиск']);
      if (query != null) {
        final url = 'https://google.com/search?q=${Uri.encodeComponent(query)}';
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return PhoneCommandResult.ok('🔍 Ищу: $query');
      }
    }

    // ── НАВИГАЦИЯ ─────────────────────────────────────────────
    if (_matches(t, ['проложи маршрут', 'навигация до', 'как добраться до', 'маршрут до'])) {
      final dest = _extractAfter(t, ['проложи маршрут до', 'навигация до', 'маршрут до', 'добраться до']);
      if (dest != null) {
        final url = 'https://maps.google.com/maps?daddr=${Uri.encodeComponent(dest)}';
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return PhoneCommandResult.ok('🗺 Прокладываю маршрут до $dest');
      }
    }

    // ── КАЛЬКУЛЯТОР ───────────────────────────────────────────
    if (_matches(t, ['открой калькулятор', 'калькулятор', 'calculator'])) {
      await _launchPackage('com.google.android.calculator');
      return PhoneCommandResult.ok('🧮 Калькулятор открыт');
    }

    // ── ЗАПИСЬ ГОЛОСА ─────────────────────────────────────────
    if (_matches(t, ['запись голоса', 'включи диктофон', 'диктофон', 'voice recorder'])) {
      await AndroidIntent(action: 'android.provider.MediaStore.RECORD_SOUND', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return PhoneCommandResult.ok('🎙 Диктофон открыт');
    }

    // ── ЭКРАННОЕ ВРЕМЯ / ДО НЕ БЕСПОКОИТЬ ────────────────────
    if (_matches(t, ['не беспокоить', 'режим тишины', 'do not disturb', 'dnd'])) {
      await AndroidIntent(action: 'android.settings.ZEN_MODE_SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return PhoneCommandResult.ok('🤫 Настройки "Не беспокоить" открыты');
    }

    // ── ПЕРЕЗАГРУЗКА / ВЫКЛЮЧЕНИЕ ─────────────────────────────
    if (_matches(t, ['перезагрузи телефон', 'reboot', 'restart'])) {
      return PhoneCommandResult.ok('⚠️ Перезагрузка требует root. Открываю меню питания...',
          action: 'power_dialog');
    }

    return null; // Команда не распознана — отправляем в AI
  }

  // ══════════════════════════════════════════════════════════════
  // РЕАЛИЗАЦИИ КОМАНД
  // ══════════════════════════════════════════════════════════════

  Future<PhoneCommandResult> _makeCall(String contact) async {
    try {
      final uri = Uri(scheme: 'tel', path: contact);
      await launchUrl(uri);
      return PhoneCommandResult.ok('📞 Звоню $contact...');
    } catch (e) {
      return PhoneCommandResult.error('Не могу совершить звонок');
    }
  }

  Future<PhoneCommandResult> _endCall() async {
    try {
      await _channel.invokeMethod('endCall');
      return PhoneCommandResult.ok('📵 Звонок завершён');
    } catch (_) {
      return PhoneCommandResult.error('Не удалось завершить звонок — нужно разрешение ANSWER_PHONE_CALLS');
    }
  }

  Future<PhoneCommandResult> _answerCall() async {
    try {
      await _channel.invokeMethod('answerCall');
      return PhoneCommandResult.ok('📞 Принимаю звонок');
    } catch (_) {
      return PhoneCommandResult.error('Не удалось принять звонок автоматически');
    }
  }

  Future<PhoneCommandResult> _sendSms(String contact, String message) async {
    try {
      final uri = Uri(scheme: 'sms', path: contact, queryParameters: {'body': message});
      await launchUrl(uri);
      return PhoneCommandResult.ok('💬 Открываю SMS для $contact');
    } catch (e) {
      return PhoneCommandResult.error('Не могу открыть SMS');
    }
  }

  Future<PhoneCommandResult> _setBrightness(int value) async {
    try {
      await _channel.invokeMethod('setBrightness', {'value': value});
      return PhoneCommandResult.ok('☀️ Яркость: ${(value / 2.55).round()}%');
    } catch (_) {
      await AndroidIntent(action: 'android.settings.DISPLAY_SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return PhoneCommandResult.ok('☀️ Открываю настройки яркости');
    }
  }

  Future<PhoneCommandResult> _setAutoBrightness() async {
    try {
      await _channel.invokeMethod('setAutoBrightness');
      return PhoneCommandResult.ok('☀️ Авто-яркость включена');
    } catch (_) {
      return PhoneCommandResult.error('Не могу установить авто-яркость');
    }
  }

  Future<PhoneCommandResult> _openWifiSettings() async {
    await AndroidIntent(action: 'android.settings.WIFI_SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
    return PhoneCommandResult.ok('📶 Настройки WiFi открыты');
  }

  Future<PhoneCommandResult> _toggleBluetooth(bool enable) async {
    await AndroidIntent(action: 'android.settings.BLUETOOTH_SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
    return PhoneCommandResult.ok(enable ? '🔵 Настройки Bluetooth открыты' : '🔵 Настройки Bluetooth открыты');
  }

  Future<PhoneCommandResult> _openBluetoothSettings() async {
    await AndroidIntent(action: 'android.settings.BLUETOOTH_SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
    return PhoneCommandResult.ok('🔵 Bluetooth настройки открыты');
  }

  Future<PhoneCommandResult> _openAirplaneMode() async {
    await AndroidIntent(action: 'android.settings.AIRPLANE_MODE_SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
    return PhoneCommandResult.ok('✈️ Настройки авиарежима открыты');
  }

  Future<PhoneCommandResult> _setTimer(int minutes) async {
    final intent = AndroidIntent(
      action: 'android.intent.action.SET_TIMER',
      arguments: {
        'android.intent.extra.alarm.LENGTH': minutes * 60,
        'android.intent.extra.alarm.SKIP_UI': false,
        'android.intent.extra.alarm.MESSAGE': 'Таймер от Айки',
      },
      flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    await intent.launch();
    return PhoneCommandResult.ok('⏱ Таймер на $minutes мин установлен');
  }

  Future<PhoneCommandResult> _setAlarm(int hour, int minute) async {
    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: {
        'android.intent.extra.alarm.HOUR': hour,
        'android.intent.extra.alarm.MINUTES': minute,
        'android.intent.extra.alarm.SKIP_UI': false,
        'android.intent.extra.alarm.MESSAGE': 'Будильник от Айки',
      },
      flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    await intent.launch();
    return PhoneCommandResult.ok('⏰ Будильник на ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} установлен');
  }

  Future<PhoneCommandResult> _takeScreenshot() async {
    try {
      await _channel.invokeMethod('takeScreenshot');
      return PhoneCommandResult.ok('📸 Скриншот сохранён');
    } catch (_) {
      return PhoneCommandResult.error('Нужно разрешение Accessibility для скриншота');
    }
  }

  Future<void> _launchPackage(String pkg) async {
    try {
      await AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: pkg,
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════
  // ХЕЛПЕРЫ ПАРСИНГА
  // ══════════════════════════════════════════════════════════════

  bool _matches(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  String? _extractContact(String text, List<String> prefixes) {
    for (final p in prefixes) {
      final idx = text.indexOf(p);
      if (idx != -1) {
        var rest = text.substring(idx + p.length).trim();
        rest = rest.replaceAll(RegExp(r'\b(пожалуйста|please|срочно)\b'), '').trim();
        if (rest.isNotEmpty) return rest.split(' ').take(3).join(' ');
      }
    }
    return null;
  }

  String? _extractAfter(String text, List<String> prefixes) {
    for (final p in prefixes) {
      final idx = text.indexOf(p);
      if (idx != -1) {
        final rest = text.substring(idx + p.length).trim();
        if (rest.isNotEmpty) return rest;
      }
    }
    return null;
  }

  double? _extractNumber(String text) {
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    return m != null ? double.tryParse(m.group(1)!) : null;
  }

  (int, int)? _extractTime(String text) {
    final m = RegExp(r'(\d{1,2})[:\s]?(\d{2})?').firstMatch(text);
    if (m != null) {
      final h = int.tryParse(m.group(1)!) ?? 0;
      final min = int.tryParse(m.group(2) ?? '0') ?? 0;
      return (h.clamp(0, 23), min.clamp(0, 59));
    }
    return null;
  }
}

class PhoneCommandResult {
  final String message;
  final bool success;
  final String? action;

  PhoneCommandResult.ok(this.message, {this.action}) : success = true;
  PhoneCommandResult.error(this.message) : success = false, action = null;
}
