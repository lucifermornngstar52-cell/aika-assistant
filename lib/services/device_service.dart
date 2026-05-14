import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:torch_light/torch_light.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class DeviceService {
  final Battery _battery = Battery();
  bool _flashlightOn = false;
  double _currentVolume = 0.5;

  DeviceService() {
    // Listen to volume changes to track current level
    VolumeController().listener((v) => _currentVolume = v);
    VolumeController().getVolume().then((v) => _currentVolume = v ?? 0.5);
  }

  Future<String?> parseAndExecute(String aiResponse) async {
    final regex = RegExp(r'\[ACTION:([^\]]+)\]');
    final match = regex.firstMatch(aiResponse);
    if (match == null) return null;
    final action = match.group(1)?.toLowerCase() ?? '';
    return await executeAction(action);
  }

  Future<String?> executeAction(String action) async {
    switch (action) {
      case 'open_youtube':
        return await _openApp('com.google.android.youtube', fallback: 'https://youtube.com');
      case 'open_telegram':
        return await _openApp('org.telegram.messenger', fallback: 'https://t.me');
      case 'open_tiktok':
        return await _openApp('com.zhiliaoapp.musically', fallback: 'https://tiktok.com');
      case 'open_chrome':
        return await _openApp('com.android.chrome', fallback: 'https://google.com');
      case 'open_spotify':
        return await _openApp('com.spotify.music', fallback: 'https://spotify.com');
      case 'open_settings':
        return await _openSettings();
      case 'flashlight_on':
        return await _toggleFlashlight(true);
      case 'flashlight_off':
        return await _toggleFlashlight(false);
      case 'flashlight_toggle':
        return await _toggleFlashlight(!_flashlightOn);
      case 'volume_up':
        return await _changeVolume(0.1);
      case 'volume_down':
        return await _changeVolume(-0.1);
      case 'volume_max':
        return await _setVolume(1.0);
      case 'volume_mute':
        return await _setVolume(0.0);
      case 'battery':
        return await _getBattery();
      case 'open_camera':
        return await _openCamera();
      default:
        if (action.startsWith('search_')) {
          final query = action.replaceFirst('search_', '').replaceAll('_', ' ');
          return await _searchWeb(query);
        }
        return null;
    }
  }

  Future<int> getBatteryLevel() async => await _battery.batteryLevel;

  Future<String> _getBattery() async {
    final level = await _battery.batteryLevel;
    return 'Заряд батареи: $level%';
  }

  Future<String> _openApp(String packageName, {String? fallback}) async {
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: packageName,
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      return 'Открываю приложение...';
    } catch (e) {
      if (fallback != null) {
        await launchUrl(Uri.parse(fallback), mode: LaunchMode.externalApplication);
        return 'Открываю в браузере...';
      }
      return 'Не могу открыть приложение';
    }
  }

  Future<String> _openSettings() async {
    try {
      const intent = AndroidIntent(
        action: 'android.settings.SETTINGS',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      return 'Открываю настройки';
    } catch (e) {
      return 'Не могу открыть настройки';
    }
  }

  Future<String> _openCamera() async {
    try {
      const intent = AndroidIntent(
        action: 'android.media.action.IMAGE_CAPTURE',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      return 'Открываю камеру';
    } catch (e) {
      return 'Камера недоступна';
    }
  }

  Future<String> _toggleFlashlight(bool on) async {
    try {
      if (on) {
        await TorchLight.enableTorch();
        _flashlightOn = true;
        return 'Фонарик включён 🔦';
      } else {
        await TorchLight.disableTorch();
        _flashlightOn = false;
        return 'Фонарик выключен';
      }
    } catch (e) {
      return 'Не могу управлять фонариком';
    }
  }

  Future<String> _changeVolume(double delta) async {
    try {
      final newVol = (_currentVolume + delta).clamp(0.0, 1.0);
      VolumeController().setVolume(newVol);
      _currentVolume = newVol;
      return 'Громкость изменена';
    } catch (e) {
      return 'Не могу изменить громкость';
    }
  }

  Future<String> _setVolume(double level) async {
    try {
      VolumeController().setVolume(level);
      _currentVolume = level;
      return level == 0 ? 'Звук выключен 🔇' : 'Громкость максимальная 🔊';
    } catch (e) {
      return 'Не могу изменить громкость';
    }
  }

  Future<String> _searchWeb(String query) async {
    final url = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(query)}');
    await launchUrl(url, mode: LaunchMode.externalApplication);
    return 'Ищу: $query';
  }

  void dispose() {
    VolumeController().removeListener();
  }
}
