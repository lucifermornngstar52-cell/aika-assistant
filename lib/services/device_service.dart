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
    VolumeController().listener((v) {
      _currentVolume = v;
    });
  }

  void dispose() {
    VolumeController().removeListener();
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
        await _launchUrl('https://youtube.com');
        return 'YouTube открыт';
      case 'open_telegram':
        await _launchUrl('https://telegram.org');
        return 'Telegram открыт';
      case 'open_tiktok':
        await _launchUrl('https://tiktok.com');
        return 'TikTok открыт';
      case 'open_chrome':
        await _launchUrl('https://google.com');
        return 'Chrome открыт';
      case 'open_spotify':
        await _launchUrl('https://open.spotify.com');
        return 'Spotify открыт';
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

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
