import 'gemini_computer_use_service.dart';
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
  static const _screenChannel = MethodChannel('com.aika.assistant/screen_reader');

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
      return 'Уведомления:\n' + notifs.take(5).map((n) => '• ${n['title'] ?? n['pkg'] ?? ''}: ${n['text'] ?? ''}').join('\n');
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

    // ── Gemini Vision: умный клик и описание экрана ────────────────────
    if (action == 'describe_screen') {
      return await GeminiComputerUseService.describeScreen();
    }

    if (action.startsWith('smart_tap:') || action.startsWith('smart_click:')) {
      final task = action.contains(':') ? action.split(':').skip(1).join(':').trim() : action;
      return await GeminiComputerUseService.executeTask(task);
    }

    if (action.startsWith('smart_do:')) {
      final task = action.split(':').skip(1).join(':').trim();
      return await GeminiComputerUseService.executeTask(task);
    }

    // ── Поиск в Google ───────────────────────────────────────────────────
    if (action.startsWith('maps_route_')) {
      final dest = Uri.encodeComponent(action.substring('maps_route_'.length).replaceAll('_', ' '));
      await _launchUrl('https://maps.google.com/maps?daddr=$dest');
      return 'Прокладываю маршрут 🗺';
    }
    if (action.startsWith('maps_search_')) {
      final place = Uri.encodeComponent(action.substring('maps_search_'.length).replaceAll('_', ' '));
      await _launchUrl('https://maps.google.com/maps?q=$place');
      return 'Ищу на карте 📍';
    }
    if (action.startsWith('youtube_search_')) {
      final q = Uri.encodeComponent(action.substring('youtube_search_'.length).replaceAll('_', ' '));
      await _launchUrl('https://www.youtube.com/results?search_query=$q');
      return 'Ищу на YouTube ▶️';
    }

    // ── Яркость ──────────────────────────────────────────────────────────
    if (action == 'brightness_max') {
      try { await _screenChannel.invokeMethod('setBrightness', {'value': 255}); return 'Максимальная яркость ☀️'; }
      catch (_) { await _openSettings('android.settings.DISPLAY_SETTINGS'); return 'Открываю настройки яркости'; }
    }
    if (action == 'brightness_min') {
      try { await _screenChannel.invokeMethod('setBrightness', {'value': 20}); return 'Минимальная яркость 🌑'; }
      catch (_) { await _openSettings('android.settings.DISPLAY_SETTINGS'); return 'Открываю настройки яркости'; }
    }
    if (action == 'brightness_50') {
      try { await _screenChannel.invokeMethod('setBrightness', {'value': 128}); return 'Яркость 50% ☀️'; }
      catch (_) { await _openSettings('android.settings.DISPLAY_SETTINGS'); return 'Открываю настройки яркости'; }
    }
    if (action == 'brightness_auto') {
      try { await _screenChannel.invokeMethod('setAutoBrightness'); return 'Автояркость включена ☀️'; }
      catch (_) { return 'Не удалось включить автояркость'; }
    }
    if (action.startsWith('brightness_')) {
      final val = int.tryParse(action.substring('brightness_'.length)) ?? 50;
      final raw = (val / 100 * 255).round().clamp(0, 255);
      try { await _screenChannel.invokeMethod('setBrightness', {'value': raw}); return 'Яркость $val% ☀️'; }
      catch (_) { return 'Не удалось установить яркость'; }
    }

    // ── Беспроводные сети ─────────────────────────────────────────────────
    if (action == 'open_wifi') {
      await _openSettings('android.settings.WIFI_SETTINGS');
      return 'Настройки Wi-Fi открыты 📶';
    }
    if (action == 'open_bluetooth') {
      await _openSettings('android.settings.BLUETOOTH_SETTINGS');
      return 'Настройки Bluetooth открыты 🔵';
    }
    if (action == 'open_airplane_mode') {
      await _openSettings('android.settings.AIRPLANE_MODE_SETTINGS');
      return 'Авиарежим — открываю настройки ✈️';
    }
    if (action == 'open_hotspot') {
      await _openSettings('android.settings.TETHER_SETTINGS');
      return 'Горячая точка — открываю настройки 📡';
    }
    if (action == 'open_dnd') {
      await _openSettings('android.settings.ZEN_MODE_SETTINGS');
      return 'Режим "Не беспокоить" — открываю настройки 🤫';
    }
    if (action == 'open_power_save') {
      await _openSettings('android.settings.BATTERY_SAVER_SETTINGS');
      return 'Экономия энергии — открываю настройки 🔋';
    }

    // ── Системные действия ────────────────────────────────────────────────
    if (action == 'lock_screen') {
      try { await _screenChannel.invokeMethod('performGlobalAction', {'action': 8}); return 'Экран заблокирован 🔒'; }
      catch (_) { return 'Для блокировки нужен Accessibility + Device Admin'; }
    }
    if (action == 'power_menu') {
      try { await _screenChannel.invokeMethod('performGlobalAction', {'action': 12}); return 'Меню питания 🔌'; }
      catch (_) { return 'Не удалось открыть меню питания'; }
    }
    if (action == 'close_app') {
      try { await _screenChannel.invokeMethod('closeCurrentApp'); return 'Закрываю приложение ✅'; }
      catch (_) { return 'Не удалось закрыть приложение'; }
    }
    if (action == 'open_dialer') {
      return await _launchPackage('com.google.android.dialer');
    }
    if (action == 'open_messages') {
      return await _launchPackage('com.google.android.apps.messaging');
    }
    if (action == 'open_clock') {
      return await _launchPackage('com.google.android.deskclock');
    }
    if (action == 'get_weather') {
      await _launchUrl('https://weather.com');
      return 'Открываю погоду 🌤';
    }

    // ── Громкость % ──────────────────────────────────────────────────────
    if (action.startsWith('volume_')) {
      final pctStr = action.substring('volume_'.length);
      final pct = int.tryParse(pctStr);
      if (pct != null) {
        VolumeController().setVolume(pct / 100);
        return 'Громкость $pct% 🔊';
      }
    }

    // ── Открытие новых приложений ─────────────────────────────────────────
    final extraApps = <String, String>{
      'open_drive':          'com.google.android.apps.docs',
      'open_photos':         'com.google.android.apps.photos',
      'open_play_store':     'com.android.vending',
      'open_viber':          'com.viber.voip',
      'open_skype':          'com.skype.raider',
      'open_firefox':        'org.mozilla.firefox',
      'open_opera':          'com.opera.browser',
      'open_twitch':         'tv.twitch.android.app',
      'open_tinder':         'com.tinder',
      'open_duolingo':       'com.duolingo',
      'open_uber':           'com.ubercab',
      'open_yandex_taxi':    'ru.yandex.taxi',
      'open_sber':           'ru.sberbankmobile',
      'open_tinkoff':        'com.idamob.tinkoff.android',
      'open_avito':          'ru.avito.android',
      'open_ozon':           'ru.ozon.app.android',
      'open_wildberries':    'com.wildberries.ru',
      'open_ok':             'ru.ok.android',
      'open_gosuslugi':      'ru.rostelekom.portal',
      'open_yandex_music':   'com.yandex.music',
      'open_yandex_browser': 'com.yandex.browser',
      'open_signal':         'org.thoughtcrime.securesms',
    };
    if (extraApps.containsKey(action)) {
      return await _launchPackage(extraApps[action]!);
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
        VolumeController().setVolume((_currentVolume + 0.15).clamp(0.0, 1.0));
        return 'Громкость увеличена 🔊';
      case 'volume_down':
        VolumeController().setVolume((_currentVolume - 0.15).clamp(0.0, 1.0));
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
      case 'music_play':
        final cmd = MusicControlService.parseCommand('play');
        if (cmd != null) await MusicControlService.send(cmd);
        return 'Включаю музыку 🎵';

      // ── Навигация ────────────────────────────────────────────────────
      case 'nav_back':
        try { await _screenChannel.invokeMethod('performBack'); } catch (_) {}
        return 'Назад ◀️';
      case 'nav_home':
        try { await _screenChannel.invokeMethod('pressHome'); } catch (_) {}
        return 'Главный экран 🏠';
      case 'nav_recents':
        try { await _screenChannel.invokeMethod('pressRecents'); } catch (_) {}
        return 'Недавние приложения';
      case 'nav_notifications':
        try { await _screenChannel.invokeMethod('openNotifications'); } catch (_) {}
        return 'Уведомления открыты';

      // ── Скриншот ─────────────────────────────────────────────────────
      case 'take_screenshot':
        try { await _screenChannel.invokeMethod('takeScreenshot'); return 'Скриншот сделан 📸'; }
        catch (_) { await _screenChannel.invokeMethod('performGlobalAction', {'action': 9}); return 'Скриншот 📸'; }

      default:
        return null;
    }
  }

  Future<void> _openSettings(String action) async {
    try {
      await AndroidIntent(action: action, flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
    } catch (_) {}
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
