import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:torch_light/torch_light.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_launcher_service.dart';

class DeviceService {
  final Battery _battery = Battery();
  bool _flashlightOn = false;
  double _currentVolume = 0.5;

  DeviceService() {
    VolumeController().listener((v) {
      _currentVolume = v;
    });
  }

  void dispose() {
    VolumeController().removeListener();
  }

  Future<String?> parseAndExecute(String aiResponse) async {
    // Проверяем сначала фразовый запуск приложений (без AI)
    final appResult = await AppLauncherService.tryLaunch(aiResponse);
    if (appResult != null) return appResult;

    // Ищем ACTION теги
    final regex = RegExp(r'\[ACTION:([^\]]+)\]');
    final match = regex.firstMatch(aiResponse);
    if (match == null) return null;
    final action = match.group(1)?.toLowerCase() ?? '';
    return await executeAction(action);
  }

  Future<String?> executeAction(String action) async {
    // Динамический запуск любого приложения
    if (action.startsWith('launch_app_')) {
      final packageName = action.substring('launch_app_'.length);
      return await _launchApp(packageName);
    }

    switch (action) {
      case 'open_youtube':
        return await _launchApp('com.google.android.youtube');
      case 'open_telegram':
        return await _launchApp('org.telegram.messenger');
      case 'open_tiktok':
        return await _launchApp('com.zhiliaoapp.musically');
      case 'open_chrome':
        return await _launchApp('com.android.chrome');
      case 'open_spotify':
        return await _launchApp('com.spotify.music');
      case 'open_settings':
        final intent = AndroidIntent(action: 'android.settings.SETTINGS');
        await intent.launch();
        return 'Настройки открыты';
      case 'open_camera':
        final intent = AndroidIntent(
          action: 'android.media.action.STILL_IMAGE_CAMERA',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
        return 'Камера открыта';
      case 'flashlight_on':
        try {
          await TorchLight.enableTorch();
          _flashlightOn = true;
          return 'Фонарик включён';
        } catch (e) {
          return 'Не удалось включить фонарик';
        }
      case 'flashlight_off':
        try {
          await TorchLight.disableTorch();
          _flashlightOn = false;
          return 'Фонарик выключен';
        } catch (e) {
          return 'Не удалось выключить фонарик';
        }
      case 'flashlight_toggle':
        return _flashlightOn
            ? await executeAction('flashlight_off')
            : await executeAction('flashlight_on');
      case 'volume_up':
        VolumeController().setVolume(_currentVolume + 0.1 > 1 ? 1 : _currentVolume + 0.1);
        return 'Громкость увеличена';
      case 'volume_down':
        VolumeController().setVolume(_currentVolume - 0.1 < 0 ? 0 : _currentVolume - 0.1);
        return 'Громкость уменьшена';
      case 'volume_max':
        VolumeController().setVolume(1.0);
        return 'Максимальная громкость';
      case 'volume_mute':
        VolumeController().setVolume(0.0);
        return 'Звук выключен';
      case 'battery':
        final level = await _battery.batteryLevel;
        return 'Заряд батареи: $level%';
      default:
        if (action.startsWith('search_')) {
          final query = action.substring(7);
          await _launchUrl('https://google.com/search?q=$query');
          return 'Поиск: $query';
        }
        return null;
    }
  }

  Future<String> _launchApp(String packageName) async {
    try {
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
    } catch (e) {
      // Не установлено — идём в Play Store
      try {
        final store = AndroidIntent(
          action: 'android.intent.action.VIEW',
          data: 'market://details?id=$packageName',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await store.launch();
        return 'Приложение не найдено, открываю Play Store';
      } catch (_) {
        return 'Не удалось открыть приложение';
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
