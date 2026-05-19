import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:torch_light/torch_light.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_launcher_service.dart';
import 'currency_service.dart';
import 'screen_watcher_service.dart';

class DeviceService {
  final Battery _battery = Battery();
  final CurrencyService _currencyService = CurrencyService();
  bool _flashlightOn = false;
  double _currentVolume = 0.5;

  DeviceService() {
    VolumeController().listener((v) => _currentVolume = v);
  }

  void dispose() {
    VolumeController().removeListener();
  }

  Future<String?> parseAndExecute(String aiResponse) async {
    // Ищем ACTION теги
    final regex = RegExp(r'\[ACTION:([^\]]+)\]');
    final match = regex.firstMatch(aiResponse);
    if (match == null) return null;
    final action = match.group(1)?.toLowerCase().trim() ?? '';
    return await executeAction(action);
  }

  Future<String?> executeAction(String action) async {
    // Запуск любого приложения по package name
    if (action.startsWith('launch_app_')) {
      final pkg = action.substring('launch_app_'.length);
      return await _launchPackage(pkg);
    }

    // Курсы валют
    if (action.startsWith('currency_')) {
      final code = action.substring('currency_'.length).toUpperCase();
      if (code == 'ALL') return await _currencyService.getRatesText();
      return await _currencyService.getSingleRate(code);
    }

    // Поиск
    if (action.startsWith('search_')) {
      final query = Uri.encodeComponent(action.substring(7));
      await _launchUrl('https://google.com/search?q=$query');
      return 'Поиск запущен';
    }

    switch (action) {
      // ── Приложения ────────────────────────────────────────────
      case 'open_youtube':
        return await _launchPackage('com.google.android.youtube');
      case 'open_telegram':
        return await _launchPackage('org.telegram.messenger');
      case 'open_tiktok':
        return await _launchPackage('com.zhiliaoapp.musically');
      case 'open_chrome':
        return await _launchPackage('com.android.chrome');
      case 'open_spotify':
        return await _launchPackage('com.spotify.music');
      case 'open_whatsapp':
        return await _launchPackage('com.whatsapp');
      case 'open_instagram':
        return await _launchPackage('com.instagram.android');
      case 'open_vk':
        return await _launchPackage('com.vkontakte.android');
      case 'open_maps':
        return await _launchPackage('com.google.android.apps.maps');
      case 'open_settings':
        await AndroidIntent(action: 'android.settings.SETTINGS',
            flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
        return 'Настройки открыты';
      case 'open_camera':
        await AndroidIntent(
          action: 'android.media.action.STILL_IMAGE_CAMERA',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        ).launch();
        return 'Камера открыта';

      // ── Фонарик ───────────────────────────────────────────────
      case 'flashlight_on':
        try { await TorchLight.enableTorch(); _flashlightOn = true; return 'Фонарик включён'; }
        catch (_) { return 'Не удалось включить фонарик'; }
      case 'flashlight_off':
        try { await TorchLight.disableTorch(); _flashlightOn = false; return 'Фонарик выключен'; }
        catch (_) { return 'Не удалось выключить фонарик'; }
      case 'flashlight_toggle':
        return _flashlightOn
            ? await executeAction('flashlight_off')
            : await executeAction('flashlight_on');

      // ── Громкость ─────────────────────────────────────────────
      case 'volume_up':
        VolumeController().setVolume((_currentVolume + 0.15).clamp(0.0, 1.0));
        return 'Громкость увеличена';
      case 'volume_down':
        VolumeController().setVolume((_currentVolume - 0.15).clamp(0.0, 1.0));
        return 'Громкость уменьшена';
      case 'volume_max':
        VolumeController().setVolume(1.0);
        return 'Максимальная громкость';
      case 'volume_mute':
        VolumeController().setVolume(0.0);
        return 'Звук выключен';

      // ── Батарея ───────────────────────────────────────────────
      case 'battery':
        final level = await _battery.batteryLevel;
        return 'Заряд батареи: $level%';

      // ── Экран ─────────────────────────────────────────────────
      case 'what_on_screen':
      case 'screen_info':
        final info = ScreenWatcherService.getCurrentAppInfo();
        if (info == null) return 'Не вижу что на экране — включи доступность для Айки';
        return 'Сейчас на экране: ${info['label']} (${info['package']})';

      default:
        return null;
    }
  }

  /// Запуск приложения по package name через Launcher intent
  Future<String> _launchPackage(String packageName) async {
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: packageName,
        componentName: '',   // пустой — система найдёт главную Activity
        flags: [
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
        ],
      );
      await intent.launch();
      return 'Открываю';
    } catch (_) {
      // Fallback — открываем Play Store
      try {
        await _launchUrl('market://details?id=$packageName');
        return 'Приложение не найдено, открываю Play Store';
      } catch (_) {
        try {
          await _launchUrl('https://play.google.com/store/apps/details?id=$packageName');
          return 'Открываю Play Store';
        } catch (_) {
          return 'Не удалось открыть приложение';
        }
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
