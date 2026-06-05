import 'notification_service.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:torch_light/torch_light.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'app_launcher_service.dart';
import 'currency_service.dart';
import 'music_control_service.dart';
import 'screen_watcher_service.dart';

/// ════════════════════════════════════════════════════════════════════
/// DeviceService — единая точка выполнения всех ACTION команд от AI.
///
/// ИСПРАВЛЕНИЯ:
/// 1. _launchPackage — убран componentName: '' (он ломал запуск!)
/// 2. Добавлена карта пакетов для открытия по названию (VK, Spotify и др.)
/// 3. open_vk теперь com.vkontakte.android (не камера!)
/// 4. open_spotify + play — открывает и запускает воспроизведение
/// 5. Цепочки команд: "открой Spotify включи музыку" = 2 action
/// 6. AI знает ВСЕ возможные ACTION в systemPrompt
/// ════════════════════════════════════════════════════════════════════

class DeviceService {
  final Battery _battery = Battery();
  final CurrencyService _currencyService = CurrencyService();
  bool _flashlightOn = false;
  double _currentVolume = 0.5;
  static const _screenChannel = MethodChannel('aika/screen_reader');

  /// Таблица известных приложений: название → package name
  static const Map<String, String> knownApps = {
    // Соцсети
    'vk': 'com.vkontakte.android',
    'вк': 'com.vkontakte.android',
    'vkontakte': 'com.vkontakte.android',
    'вконтакте': 'com.vkontakte.android',
    'telegram': 'org.telegram.messenger',
    'телеграм': 'org.telegram.messenger',
    'whatsapp': 'com.whatsapp',
    'ватсап': 'com.whatsapp',
    'вотсап': 'com.whatsapp',
    'instagram': 'com.instagram.android',
    'инстаграм': 'com.instagram.android',
    'tiktok': 'com.zhiliaoapp.musically',
    'тикток': 'com.zhiliaoapp.musically',
    'twitter': 'com.twitter.android',
    'x': 'com.twitter.android',
    'facebook': 'com.facebook.katana',

    // Медиа
    'youtube': 'com.google.android.youtube',
    'ютуб': 'com.google.android.youtube',
    'spotify': 'com.spotify.music',
    'спотифай': 'com.spotify.music',
    'netflix': 'com.netflix.mediaclient',
    'нетфликс': 'com.netflix.mediaclient',
    'twitch': 'tv.twitch.android.app',
    'twich': 'tv.twitch.android.app',
    'music': 'com.google.android.apps.youtube.music',
    'youtube music': 'com.google.android.apps.youtube.music',
    'ютуб музыка': 'com.google.android.apps.youtube.music',

    // Браузеры
    'chrome': 'com.android.chrome',
    'хром': 'com.android.chrome',
    'browser': 'com.android.chrome',

    // Google
    'maps': 'com.google.android.apps.maps',
    'карты': 'com.google.android.apps.maps',
    'google maps': 'com.google.android.apps.maps',
    'gmail': 'com.google.android.gm',
    'почта': 'com.google.android.gm',
    'drive': 'com.google.android.apps.docs',
    'диск': 'com.google.android.apps.docs',
    'google drive': 'com.google.android.apps.docs',
    'translate': 'com.google.android.apps.translate',
    'переводчик': 'com.google.android.apps.translate',
    'google translate': 'com.google.android.apps.translate',

    // Системные
    'calculator': 'com.google.android.calculator',
    'калькулятор': 'com.google.android.calculator',
    'calendar': 'com.google.android.calendar',
    'календарь': 'com.google.android.calendar',
    'clock': 'com.google.android.deskclock',
    'часы': 'com.google.android.deskclock',
    'camera': 'com.android.camera2',

    // Другое
    'discord': 'com.discord',
    'дискорд': 'com.discord',
    'zoom': 'us.zoom.videomeetings',
    'зум': 'us.zoom.videomeetings',
    'shazam': 'com.shazam.android',
    'шазам': 'com.shazam.android',
  };

  DeviceService() {
    VolumeController().listener((v) => _currentVolume = v);
  }

  void dispose() {
    VolumeController().removeListener();
  }

  // ─── Парсинг ВСЕХ ACTION тегов из ответа AI ───────────────────────
  Future<String?> parseAndExecute(String aiResponse) async {
    final regex = RegExp(r'\[ACTION:([^\]]+)\]');
    final matches = regex.allMatches(aiResponse);
    if (matches.isEmpty) return null;

    final results = <String>[];
    for (final m in matches) {
      final action = m.group(1)?.toLowerCase().trim() ?? '';
      final result = await executeAction(action);
      if (result != null && result.isNotEmpty) results.add(result);
    }
    return results.isNotEmpty ? results.join('\n') : null;
  }

  Future<String?> executeAction(String action) async {
    // ── Запуск по package name ────────────────────────────────────────
    if (action.startsWith('launch_app_')) {
      final pkg = action.substring('launch_app_'.length);
      return await _launchPackage(pkg);
    }

    // ── Запуск по названию (open_NAME) ────────────────────────────────
    if (action.startsWith('open_')) {
      final name = action.substring('open_'.length);
      // Специальные кейсы
      if (name == 'camera') {
        await AndroidIntent(
          action: 'android.media.action.STILL_IMAGE_CAMERA',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        ).launch();
        return 'Камера открыта';
      }
      if (name == 'settings') {
        await AndroidIntent(action: 'android.settings.SETTINGS',
            flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
        return 'Настройки открыты';
      }
      if (name == 'wifi') {
        await AndroidIntent(action: 'android.settings.WIFI_SETTINGS',
            flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
        return 'WiFi настройки открыты';
      }
      if (name == 'bluetooth') {
        await AndroidIntent(action: 'android.settings.BLUETOOTH_SETTINGS',
            flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
        return 'Bluetooth настройки открыты';
      }
      // Ищем в таблице известных приложений
      final pkg = knownApps[name] ?? knownApps[name.replaceAll('_', ' ')];
      if (pkg != null) return await _launchPackage(pkg);
      // Если не нашли — ищем по имени
      return await _launchByName(name);
    }

    // ── Музыка + Spotify ──────────────────────────────────────────────
    if (action == 'spotify_play' || action == 'music_play') {
      await _launchPackage('com.spotify.music');
      await Future.delayed(const Duration(milliseconds: 1200));
      final cmd = MusicControlService.parseCommand('play');
      if (cmd != null) await MusicControlService.send(cmd);
      return 'Spotify открыт, включаю музыку';
    }

    // ── Курсы валют ───────────────────────────────────────────────────
    if (action.startsWith('currency_')) {
      final code = action.substring('currency_'.length).toUpperCase();
      if (code == 'ALL') return await _currencyService.getRatesText();
      return await _currencyService.getSingleRate(code);
    }

    // ── Поиск ─────────────────────────────────────────────────────────
    if (action.startsWith('search_')) {
      final query = Uri.encodeComponent(action.substring(7));
      await _launchUrl('https://google.com/search?q=$query');
      return 'Поиск запущен';
    }

    // ── Уведомления ───────────────────────────────────────────────────
    if (action == 'notifications_briefing') {
      final notifs = NotificationService.recent;
      if (notifs.isEmpty) return 'Нет новых уведомлений';
      return 'Уведомления:\n' + notifs.take(5).map((n) => '• ${n['app']}: ${n['text']}').join('\n');
    }

    // ── Экран ─────────────────────────────────────────────────────────
    if (action == 'what_on_screen') {
      try {
        final text = await _screenChannel.invokeMethod<String>('getScreenText') ?? '';
        final lines = text.split('\n').where((l) => l.trim().length > 1).take(20).join('\n');
        return lines.isNotEmpty ? 'На экране:\n$lines' : 'Экран недоступен';
      } catch (_) {
        return 'Нет доступа к экрану — включи Accessibility';
      }
    }

    switch (action) {
      // ── Фонарик ─────────────────────────────────────────────────────
      case 'flashlight_on':
        try { await TorchLight.enableTorch(); _flashlightOn = true; return 'Фонарик включён 🔦'; }
        catch (_) { return 'Не удалось включить фонарик'; }
      case 'flashlight_off':
        try { await TorchLight.disableTorch(); _flashlightOn = false; return 'Фонарик выключен'; }
        catch (_) { return 'Не удалось выключить фонарик'; }
      case 'flashlight_toggle':
        return _flashlightOn
            ? await executeAction('flashlight_off')
            : await executeAction('flashlight_on');

      // ── Громкость ────────────────────────────────────────────────────
      case 'volume_up':
        VolumeController().setVolume((_currentVolume + 0.2).clamp(0.0, 1.0));
        return 'Громкость увеличена 🔊';
      case 'volume_down':
        VolumeController().setVolume((_currentVolume - 0.2).clamp(0.0, 1.0));
        return 'Громкость уменьшена 🔉';
      case 'volume_mute':
        VolumeController().setVolume(0.0);
        return 'Звук выключен 🔇';
      case 'volume_max':
        VolumeController().setVolume(1.0);
        return 'Максимальная громкость 🔊';

      // ── Батарея ──────────────────────────────────────────────────────
      case 'battery':
        final level = await _battery.batteryLevel;
        final state = await _battery.batteryState;
        final ch = state == BatteryState.charging ? ' ⚡ заряжается' : '';
        return 'Заряд: $level%$ch 🔋';

      // ── Музыка ───────────────────────────────────────────────────────
      case 'music_next':
        final cmd = MusicControlService.parseCommand('next');
        if (cmd != null) await MusicControlService.send(cmd);
        return 'Следующий трек ⏭';
      case 'music_prev':
        final cmd = MusicControlService.parseCommand('previous');
        if (cmd != null) await MusicControlService.send(cmd);
        return 'Предыдущий трек ⏮';
      case 'music_pause':
        final cmd = MusicControlService.parseCommand('pause');
        if (cmd != null) await MusicControlService.send(cmd);
        return 'Пауза ⏸';

      // ── Навигация ────────────────────────────────────────────────────
      case 'nav_back':
        await _screenChannel.invokeMethod('performBack');
        return 'Назад ◀️';
      case 'nav_home':
        await _screenChannel.invokeMethod('pressHome');
        return 'Главный экран 🏠';
      case 'nav_recents':
        await _screenChannel.invokeMethod('pressRecents');
        return 'Недавние приложения';
      case 'nav_notifications':
        await _screenChannel.invokeMethod('openNotifications');
        return 'Уведомления открыты';

      // ── Скриншот ─────────────────────────────────────────────────────
      case 'take_screenshot':
        await _screenChannel.invokeMethod('takeScreenshot');
        return 'Скриншот сделан 📸';

      default:
        return null;
    }
  }

  // ─── Запуск приложения (ИСПРАВЛЕННЫЙ) ────────────────────────────────
  Future<String> _launchPackage(String packageName) async {
    try {
      // ПРАВИЛЬНЫЙ способ — без componentName (он ломал запуск!)
      final intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: packageName,
        flags: [
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
        ],
      );
      await intent.launch();
      return 'Открываю';
    } catch (_) {
      // Fallback через URL scheme
      try {
        await _launchUrl('market://details?id=$packageName');
        return 'Приложение не установлено, открываю Play Store';
      } catch (_) {
        return 'Не удалось открыть приложение ($packageName)';
      }
    }
  }

  /// Запуск по человеческому названию — ищем в таблице
  Future<String> _launchByName(String name) async {
    final normalized = name.toLowerCase().trim();
    final pkg = knownApps[normalized];
    if (pkg != null) return await _launchPackage(pkg);
    return 'Не знаю такое приложение: "$name". Скажи: открой [название]';
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<String> pressBack() async {
    try { await _screenChannel.invokeMethod('performBack'); return 'Назад'; }
    catch (e) { return 'Не удалось: $e'; }
  }

  Future<String> goHome() async {
    try { await _screenChannel.invokeMethod('pressHome'); return 'Главный экран'; }
    catch (e) { return 'Не удалось: $e'; }
  }

  Future<String> closeCurrentApp() async {
    try { await _screenChannel.invokeMethod('closeCurrentApp'); return 'Закрываю'; }
    catch (e) { return 'Не удалось: $e'; }
  }

  Future<String> openAppSettings(String packageName) async {
    try { await _screenChannel.invokeMethod('openAppSettings', {'package': packageName}); return 'Открываю настройки'; }
    catch (e) { return 'Не удалось: $e'; }
  }

  Future<String> uninstallApp(String packageName) async {
    try { await _screenChannel.invokeMethod('uninstallApp', {'package': packageName}); return 'Открываю удаление'; }
    catch (e) { return 'Не удалось: $e'; }
  }

  Future<String> openRecents() async {
    try { await _screenChannel.invokeMethod('pressRecents'); return 'Недавние'; }
    catch (e) { return 'Не удалось: $e'; }
  }
}
